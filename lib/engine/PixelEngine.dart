import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;

class FloodFillRequest {
  final Uint8List rawRgbaBytes;
  final Uint8List borderMask;
  final Uint8List? replacementRawRgba;
  final int x;
  final int y;
  final int width;
  final int height;
  final int fillR;
  final int fillG;
  final int fillB;

  const FloodFillRequest({
    required this.rawRgbaBytes,
    required this.borderMask,
    this.replacementRawRgba,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.fillR,
    required this.fillG,
    required this.fillB,
  });
}

class FillPercentageRequest {
  final Uint8List currentRawRgba;
  final Uint8List originalRawRgba;
  final Uint8List borderMask;

  const FillPercentageRequest({
    required this.currentRawRgba,
    required this.originalRawRgba,
    required this.borderMask,
  });
}

class _FloodFillResult {
  final Uint8List raw;
  final bool changed;

  const _FloodFillResult({required this.raw, required this.changed});
}

class _RegionData {
  final int width;
  final int height;
  final Uint32List regionMap;
  final List<Uint32List> regionPixels;

  const _RegionData({
    required this.width,
    required this.height,
    required this.regionMap,
    required this.regionPixels,
  });
}

class _FloodFillWorkspace {
  Int32List _stack = Int32List(0);
  Uint32List _visitedWords = Uint32List(0);
  Int32List _dirtyVisitedWords = Int32List(0);
  int _stackLength = 0;
  int _dirtyVisitedWordCount = 0;

  void prepare(int pixelCount) {
    if (_stack.length < pixelCount) {
      _stack = Int32List(pixelCount);
    }

    final int visitedWordCount = (pixelCount + 31) >> 5;
    if (_visitedWords.length < visitedWordCount) {
      _visitedWords = Uint32List(visitedWordCount);
    }
    if (_dirtyVisitedWords.length < visitedWordCount) {
      _dirtyVisitedWords = Int32List(visitedWordCount);
    }

    _stackLength = 0;
    _dirtyVisitedWordCount = 0;
  }

  bool get hasEntries => _stackLength > 0;

  void push(int index) {
    _stack[_stackLength++] = index;
  }

  int pop() {
    return _stack[--_stackLength];
  }

  bool isVisited(int index) {
    final int wordIndex = index >> 5;
    final int bitMask = 1 << (index & 31);
    return (_visitedWords[wordIndex] & bitMask) != 0;
  }

  bool markVisited(int index) {
    final int wordIndex = index >> 5;
    final int bitMask = 1 << (index & 31);
    final int currentWord = _visitedWords[wordIndex];
    if ((currentWord & bitMask) != 0) {
      return false;
    }
    if (currentWord == 0) {
      _dirtyVisitedWords[_dirtyVisitedWordCount++] = wordIndex;
    }
    _visitedWords[wordIndex] = currentWord | bitMask;
    return true;
  }

  void clear() {
    for (int i = 0; i < _dirtyVisitedWordCount; i++) {
      _visitedWords[_dirtyVisitedWords[i]] = 0;
    }
    _stackLength = 0;
    _dirtyVisitedWordCount = 0;
  }
}

class PixelEngine {
  static const int _tolerance = 35;
  static const int _borderThreshold = 60;
  static const int _whiteThreshold = 245;
  static const int _maxRegionCacheEntries = 16;
  static const int _eagerRegionBuildMaxPixels = 3000000;

  static final LinkedHashMap<Uint8List, _RegionData> _regionDataCache =
      LinkedHashMap<Uint8List, _RegionData>.identity();

  final _FloodFillWorkspace _floodFillWorkspace = _FloodFillWorkspace();

  bool _isLoaded = false;
  int _width = 0;
  int _height = 0;
  Uint8List _originalRawRgba = Uint8List(0);
  Uint8List _currentRawRgba = Uint8List(0);
  Uint8List _borderMask = Uint8List(0);
  Uint32List _regionMap = Uint32List(0);
  List<Uint32List> _regionPixels = const <Uint32List>[];
  Uint32List _connectivityMaskWords = Uint32List(0);
  Int32List _connectivityMaskDirtyWords = Int32List(0);
  int _connectivityMaskDirtyWordCount = 0;
  _RegionData? _regionData;
  int _regionBuildGeneration = 0;

  bool get isLoaded => _isLoaded;
  int get imageWidth => _width;
  int get imageHeight => _height;
  Uint8List get borderMask => _borderMask;
  Uint8List get originalRawRgba => _originalRawRgba;
  bool get hasRegionData => _regionMap.isNotEmpty;

  int regionIdAtPixelIndex(int pixelIndex) {
    if (pixelIndex < 0 || pixelIndex >= _regionMap.length) {
      return 0;
    }
    return _regionMap[pixelIndex];
  }

  Uint32List? regionPixelsAtPixelIndex(int pixelIndex) {
    final int regionId = regionIdAtPixelIndex(pixelIndex);
    if (regionId <= 0 || regionId > _regionPixels.length) {
      return null;
    }
    return _regionPixels[regionId - 1];
  }

  bool prepareConnectivityMask(int startPixelIndex) {
    final int pixelCount = _width * _height;
    if (!_isLoaded ||
        pixelCount <= 0 ||
        startPixelIndex < 0 ||
        startPixelIndex >= pixelCount ||
        _borderMask.lengthInBytes < pixelCount ||
        _borderMask[startPixelIndex] == 1) {
      clearConnectivityMask();
      return false;
    }

    _prepareConnectivityMaskWords(pixelCount);
    _floodFillWorkspace.prepare(pixelCount);
    _floodFillWorkspace.markVisited(startPixelIndex);
    _floodFillWorkspace.push(startPixelIndex);

    try {
      while (_floodFillWorkspace.hasEntries) {
        final int seedIndex = _floodFillWorkspace.pop();
        final int rowStart = (seedIndex ~/ _width) * _width;
        final int rowEnd = rowStart + _width - 1;
        int left = seedIndex;
        int right = seedIndex;

        while (left > rowStart &&
            _canVisitConnectivityPixel(
              left - 1,
              borderMask: _borderMask,
              workspace: _floodFillWorkspace,
            )) {
          left--;
          _floodFillWorkspace.markVisited(left);
        }

        while (right < rowEnd &&
            _canVisitConnectivityPixel(
              right + 1,
              borderMask: _borderMask,
              workspace: _floodFillWorkspace,
            )) {
          right++;
          _floodFillWorkspace.markVisited(right);
        }

        for (int idx = left; idx <= right; idx++) {
          _markConnectivityMask(idx);
        }

        final int leftX = left - rowStart;
        final int rightX = right - rowStart;
        final int currentY = seedIndex ~/ _width;
        if (currentY > 0) {
          _enqueueConnectivityNeighborSeeds(
            rowY: currentY - 1,
            leftX: leftX,
            rightX: rightX,
            width: _width,
            borderMask: _borderMask,
            workspace: _floodFillWorkspace,
          );
        }
        if (currentY + 1 < _height) {
          _enqueueConnectivityNeighborSeeds(
            rowY: currentY + 1,
            leftX: leftX,
            rightX: rightX,
            width: _width,
            borderMask: _borderMask,
            workspace: _floodFillWorkspace,
          );
        }
      }
    } finally {
      _floodFillWorkspace.clear();
    }

    return true;
  }

  bool connectivityMaskContains(int pixelIndex) {
    if (pixelIndex < 0 || pixelIndex >= _width * _height) {
      return false;
    }
    final int wordIndex = pixelIndex >> 5;
    if (wordIndex >= _connectivityMaskWords.length) {
      return false;
    }
    final int bitMask = 1 << (pixelIndex & 31);
    return (_connectivityMaskWords[wordIndex] & bitMask) != 0;
  }

  void clearConnectivityMask() {
    for (int i = 0; i < _connectivityMaskDirtyWordCount; i++) {
      _connectivityMaskWords[_connectivityMaskDirtyWords[i]] = 0;
    }
    _connectivityMaskDirtyWordCount = 0;
  }

  static Map<String, Object> decodeAndPrepare(Uint8List bytes) {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return <String, Object>{
        'width': 0,
        'height': 0,
        'raw': Uint8List(0),
        'borderMask': Uint8List(0),
        'regionData': _RegionData(
          width: 0,
          height: 0,
          regionMap: Uint32List(0),
          regionPixels: <Uint32List>[],
        ),
      };
    }

    final int width = decoded.width;
    final int height = decoded.height;
    final Uint8List raw = Uint8List.fromList(decoded.getBytes());
    final int len = width * height;
    final Uint8List borderMask = Uint8List(len);

    for (int i = 0, bi = 0; i < len; i++, bi += 4) {
      if (raw[bi] < _borderThreshold &&
          raw[bi + 1] < _borderThreshold &&
          raw[bi + 2] < _borderThreshold) {
        borderMask[i] = 1;
      }
    }

    final Map<String, Object> prepared = <String, Object>{
      'width': width,
      'height': height,
      'raw': raw,
      'borderMask': borderMask,
    };
    if (_shouldBuildRegionDataEagerly(len)) {
      prepared['regionData'] = _buildRegionData(
        width: width,
        height: height,
        borderMask: borderMask,
      );
    }
    return prepared;
  }

  void applyPreparedImage(Map<String, Object> prepared) {
    final int width = prepared['width'] as int;
    final int height = prepared['height'] as int;
    final Uint8List raw = prepared['raw'] as Uint8List;
    final Uint8List borderMask = prepared['borderMask'] as Uint8List;
    final _RegionData? regionData = prepared['regionData'] as _RegionData?;

    _unregisterRegionData(_borderMask);
    _regionBuildGeneration++;

    if (width <= 0 || height <= 0 || raw.isEmpty || borderMask.isEmpty) {
      _isLoaded = false;
      _width = 0;
      _height = 0;
      _originalRawRgba = Uint8List(0);
      _currentRawRgba = Uint8List(0);
      _borderMask = Uint8List(0);
      _regionMap = Uint32List(0);
      _regionPixels = const <Uint32List>[];
      clearConnectivityMask();
      _regionData = null;
      return;
    }

    clearConnectivityMask();
    _width = width;
    _height = height;
    _originalRawRgba = raw;
    _currentRawRgba = _originalRawRgba;
    _borderMask = borderMask;
    _applyRegionData(regionData);
    if (_regionData == null) {
      _scheduleRegionDataBuild(
        width: width,
        height: height,
        borderMask: borderMask,
        generation: _regionBuildGeneration,
      );
    }
    _isLoaded = true;
  }

  void loadImage(Uint8List bytes) {
    applyPreparedImage(decodeAndPrepare(bytes));
  }

  void updateFromRawBytes(Uint8List rawRgba, int width, int height) {
    _width = width;
    _height = height;
    _currentRawRgba = rawRgba;
    _isLoaded = true;
  }

  Map<String, Object> processFloodFillToMapLocal(FloodFillRequest request) {
    final _FloodFillResult result = _processFloodFillInternal(
      request,
      regionData: _activeRegionData,
      workspace: _floodFillWorkspace,
    );
    return <String, Object>{'raw': result.raw, 'changed': result.changed};
  }

  static Uint8List processFloodFill(FloodFillRequest request) {
    return _processFloodFillInternal(request).raw;
  }

  _RegionData? get _activeRegionData {
    final _RegionData? data = _regionData;
    if (data == null ||
        _regionMap.length != _width * _height ||
        (_regionPixels.isEmpty && _regionMap.isNotEmpty)) {
      return null;
    }
    return data;
  }

  void _applyRegionData(_RegionData? regionData) {
    if (regionData == null ||
        !_isRegionDataValid(
          regionData,
          width: _width,
          height: _height,
        )) {
      _regionMap = Uint32List(0);
      _regionPixels = const <Uint32List>[];
      _regionData = null;
      return;
    }
    _regionMap = regionData.regionMap;
    _regionPixels = regionData.regionPixels;
    _regionData = regionData;
    _registerRegionData(_borderMask, regionData);
  }

  void _scheduleRegionDataBuild({
    required int width,
    required int height,
    required Uint8List borderMask,
    required int generation,
  }) {
    final int pixelCount = width * height;
    if (pixelCount <= 0 || borderMask.lengthInBytes < pixelCount) {
      return;
    }

    final TransferableTypedData borderMaskTransfer =
        TransferableTypedData.fromList(<TypedData>[borderMask]);
    unawaited(
      Isolate.run<_RegionData>(
        () {
          final Uint8List isolateBorderMask = borderMaskTransfer
              .materialize()
              .asUint8List();
          return _buildRegionData(
            width: width,
            height: height,
            borderMask: isolateBorderMask,
          );
        },
      ).then((final _RegionData regionData) {
        if (_regionBuildGeneration != generation ||
            !identical(_borderMask, borderMask) ||
            _width != width ||
            _height != height) {
          return;
        }
        _applyRegionData(regionData);
      }).catchError((Object _) {}),
    );
  }

  static bool _shouldBuildRegionDataEagerly(int pixelCount) {
    return pixelCount > 0 && pixelCount <= _eagerRegionBuildMaxPixels;
  }

  static bool _isRegionDataValid(
    _RegionData regionData, {
    required int width,
    required int height,
  }) {
    final int pixelCount = width * height;
    return width > 0 &&
        height > 0 &&
        regionData.width == width &&
        regionData.height == height &&
        regionData.regionMap.length == pixelCount;
  }

  static _FloodFillResult _processFloodFillInternal(
    FloodFillRequest request, {
    _RegionData? regionData,
    _FloodFillWorkspace? workspace,
  }) {
    final _RegionData? resolvedRegionData =
        regionData ?? _lookupRegionData(request.borderMask);
    final _FloodFillResult? regionResult = _tryRegionFill(
      request,
      resolvedRegionData,
    );
    if (regionResult != null) {
      return regionResult;
    }

    return _processScanlineFloodFill(request, workspace: workspace);
  }

  static _FloodFillResult _processScanlineFloodFill(
    FloodFillRequest request, {
    _FloodFillWorkspace? workspace,
  }) {
    final int w = request.width;
    final int h = request.height;
    if (w <= 0 || h <= 0) {
      return _FloodFillResult(raw: request.rawRgbaBytes, changed: false);
    }

    final int len = w * h;
    if (request.rawRgbaBytes.lengthInBytes < len * 4 ||
        request.borderMask.lengthInBytes < len) {
      return _FloodFillResult(raw: request.rawRgbaBytes, changed: false);
    }

    final Uint8List input = request.rawRgbaBytes;
    final Uint8List borderMask = request.borderMask;

    int startX = request.x;
    int startY = request.y;

    bool isBorder(int px, int py) {
      if (px < 0 || px >= w || py < 0 || py >= h) return true;
      return borderMask[(py * w) + px] == 1;
    }

    if (isBorder(startX, startY)) {
      bool found = false;
      outer:
      for (int i = -2; i <= 2; i++) {
        for (int j = -2; j <= 2; j++) {
          if (!isBorder(startX + i, startY + j)) {
            startX += i;
            startY += j;
            found = true;
            break outer;
          }
        }
      }
      if (!found) {
        return _FloodFillResult(raw: request.rawRgbaBytes, changed: false);
      }
    }

    final int startPixelBase = ((startY * w) + startX) << 2;
    final int sR = input[startPixelBase];
    final int sG = input[startPixelBase + 1];
    final int sB = input[startPixelBase + 2];

    final int fR = request.fillR;
    final int fG = request.fillG;
    final int fB = request.fillB;
    final Uint8List? replacementRaw = request.replacementRawRgba;
    final bool useReplacementRaw =
        replacementRaw != null && replacementRaw.lengthInBytes >= len * 4;
    final int targetR = useReplacementRaw ? replacementRaw[startPixelBase] : fR;
    final int targetG =
        useReplacementRaw ? replacementRaw[startPixelBase + 1] : fG;
    final int targetB =
        useReplacementRaw ? replacementRaw[startPixelBase + 2] : fB;

    if ((sR - targetR).abs() <= _tolerance &&
        (sG - targetG).abs() <= _tolerance &&
        (sB - targetB).abs() <= _tolerance) {
      return _FloodFillResult(raw: request.rawRgbaBytes, changed: false);
    }

    final Uint8List output = Uint8List.fromList(input);
    final _FloodFillWorkspace fillWorkspace = workspace ?? _FloodFillWorkspace();
    fillWorkspace.prepare(len);

    final int startIndex = (startY * w) + startX;
    fillWorkspace.markVisited(startIndex);
    fillWorkspace.push(startIndex);

    try {
      while (fillWorkspace.hasEntries) {
        final int seedIndex = fillWorkspace.pop();
        final int rowStart = (seedIndex ~/ w) * w;
        final int rowEnd = rowStart + w - 1;
        int left = seedIndex;
        int right = seedIndex;

        while (left > rowStart &&
            _canVisitPixel(
              left - 1,
              input: input,
              borderMask: borderMask,
              workspace: fillWorkspace,
              sourceR: sR,
              sourceG: sG,
              sourceB: sB,
            )) {
          left--;
          fillWorkspace.markVisited(left);
        }

        while (right < rowEnd &&
            _canVisitPixel(
              right + 1,
              input: input,
              borderMask: borderMask,
              workspace: fillWorkspace,
              sourceR: sR,
              sourceG: sG,
              sourceB: sB,
            )) {
          right++;
          fillWorkspace.markVisited(right);
        }

        for (int idx = left; idx <= right; idx++) {
          final int byteBase = idx << 2;
          if (useReplacementRaw) {
            output[byteBase] = replacementRaw[byteBase];
            output[byteBase + 1] = replacementRaw[byteBase + 1];
            output[byteBase + 2] = replacementRaw[byteBase + 2];
            output[byteBase + 3] = replacementRaw[byteBase + 3];
          } else {
            output[byteBase] = fR;
            output[byteBase + 1] = fG;
            output[byteBase + 2] = fB;
            output[byteBase + 3] = 255;
          }
        }

        final int leftX = left - rowStart;
        final int rightX = right - rowStart;
        final int currentY = seedIndex ~/ w;
        if (currentY > 0) {
          _enqueueNeighborSeeds(
            rowY: currentY - 1,
            leftX: leftX,
            rightX: rightX,
            width: w,
            input: input,
            borderMask: borderMask,
            workspace: fillWorkspace,
            sourceR: sR,
            sourceG: sG,
            sourceB: sB,
          );
        }
        if (currentY + 1 < h) {
          _enqueueNeighborSeeds(
            rowY: currentY + 1,
            leftX: leftX,
            rightX: rightX,
            width: w,
            input: input,
            borderMask: borderMask,
            workspace: fillWorkspace,
            sourceR: sR,
            sourceG: sG,
            sourceB: sB,
          );
        }
      }
    } finally {
      fillWorkspace.clear();
    }

    return _FloodFillResult(raw: output, changed: true);
  }

  static _FloodFillResult? _tryRegionFill(
    FloodFillRequest request,
    _RegionData? regionData,
  ) {
    if (regionData == null ||
        regionData.width != request.width ||
        regionData.height != request.height) {
      return null;
    }

    final int w = request.width;
    final int h = request.height;
    final int len = w * h;
    if (request.rawRgbaBytes.lengthInBytes < len * 4 ||
        request.borderMask.lengthInBytes < len ||
        regionData.regionMap.length != len) {
      return null;
    }

    int startX = request.x;
    int startY = request.y;
    final Uint8List borderMask = request.borderMask;

    bool isBorder(int px, int py) {
      if (px < 0 || px >= w || py < 0 || py >= h) return true;
      return borderMask[(py * w) + px] == 1;
    }

    if (isBorder(startX, startY)) {
      bool found = false;
      outer:
      for (int i = -2; i <= 2; i++) {
        for (int j = -2; j <= 2; j++) {
          if (!isBorder(startX + i, startY + j)) {
            startX += i;
            startY += j;
            found = true;
            break outer;
          }
        }
      }
      if (!found) {
        return _FloodFillResult(raw: request.rawRgbaBytes, changed: false);
      }
    }

    final int startIndex = (startY * w) + startX;
    final int regionId = regionData.regionMap[startIndex];
    if (regionId == 0 || regionId > regionData.regionPixels.length) {
      return null;
    }

    final Uint8List input = request.rawRgbaBytes;
    final int startPixelBase = startIndex << 2;
    final int sR = input[startPixelBase];
    final int sG = input[startPixelBase + 1];
    final int sB = input[startPixelBase + 2];
    final int fR = request.fillR;
    final int fG = request.fillG;
    final int fB = request.fillB;
    final Uint8List? replacementRaw = request.replacementRawRgba;
    final bool useReplacementRaw =
        replacementRaw != null && replacementRaw.lengthInBytes >= len * 4;
    final int targetR = useReplacementRaw ? replacementRaw[startPixelBase] : fR;
    final int targetG =
        useReplacementRaw ? replacementRaw[startPixelBase + 1] : fG;
    final int targetB =
        useReplacementRaw ? replacementRaw[startPixelBase + 2] : fB;

    if ((sR - targetR).abs() <= _tolerance &&
        (sG - targetG).abs() <= _tolerance &&
        (sB - targetB).abs() <= _tolerance) {
      return _FloodFillResult(raw: request.rawRgbaBytes, changed: false);
    }

    final Uint32List pixels = regionData.regionPixels[regionId - 1];
    if (pixels.isEmpty) {
      return null;
    }

    final Uint8List output = Uint8List.fromList(input);
    for (int i = 0; i < pixels.length; i++) {
      final int byteBase = pixels[i] << 2;
      if (useReplacementRaw) {
        output[byteBase] = replacementRaw[byteBase];
        output[byteBase + 1] = replacementRaw[byteBase + 1];
        output[byteBase + 2] = replacementRaw[byteBase + 2];
        output[byteBase + 3] = replacementRaw[byteBase + 3];
      } else {
        output[byteBase] = fR;
        output[byteBase + 1] = fG;
        output[byteBase + 2] = fB;
        output[byteBase + 3] = 255;
      }
    }

    return _FloodFillResult(raw: output, changed: true);
  }

  static _RegionData _buildRegionData({
    required int width,
    required int height,
    required Uint8List borderMask,
  }) {
    final int len = width * height;
    if (width <= 0 || height <= 0 || borderMask.lengthInBytes < len) {
      return _RegionData(
        width: width,
        height: height,
        regionMap: Uint32List(0),
        regionPixels: const <Uint32List>[],
      );
    }

    final Uint32List regionMap = Uint32List(len);
    final Int32List queue = Int32List(len);
    final List<Uint32List> regionPixels = <Uint32List>[];
    int nextRegionId = 1;

    for (int start = 0; start < len; start++) {
      if (borderMask[start] == 1 || regionMap[start] != 0) {
        continue;
      }

      final List<int> pixels = <int>[];
      int head = 0;
      int tail = 0;
      queue[tail++] = start;
      regionMap[start] = nextRegionId;

      while (head < tail) {
        final int index = queue[head++];
        pixels.add(index);

        final int px = index % width;
        final int py = index ~/ width;

        if (px + 1 < width) {
          final int neighbor = index + 1;
          if (borderMask[neighbor] == 0 && regionMap[neighbor] == 0) {
            regionMap[neighbor] = nextRegionId;
            queue[tail++] = neighbor;
          }
        }
        if (px - 1 >= 0) {
          final int neighbor = index - 1;
          if (borderMask[neighbor] == 0 && regionMap[neighbor] == 0) {
            regionMap[neighbor] = nextRegionId;
            queue[tail++] = neighbor;
          }
        }
        if (py + 1 < height) {
          final int neighbor = index + width;
          if (borderMask[neighbor] == 0 && regionMap[neighbor] == 0) {
            regionMap[neighbor] = nextRegionId;
            queue[tail++] = neighbor;
          }
        }
        if (py - 1 >= 0) {
          final int neighbor = index - width;
          if (borderMask[neighbor] == 0 && regionMap[neighbor] == 0) {
            regionMap[neighbor] = nextRegionId;
            queue[tail++] = neighbor;
          }
        }
      }

      regionPixels.add(Uint32List.fromList(pixels));
      nextRegionId++;
    }

    return _RegionData(
      width: width,
      height: height,
      regionMap: regionMap,
      regionPixels: regionPixels,
    );
  }

  static void _registerRegionData(Uint8List borderMask, _RegionData regionData) {
    if (borderMask.isEmpty || regionData.regionMap.isEmpty) {
      return;
    }
    _regionDataCache.remove(borderMask);
    _regionDataCache[borderMask] = regionData;
    while (_regionDataCache.length > _maxRegionCacheEntries) {
      _regionDataCache.remove(_regionDataCache.keys.first);
    }
  }

  static void _unregisterRegionData(Uint8List borderMask) {
    if (borderMask.isEmpty) return;
    _regionDataCache.remove(borderMask);
  }

  static _RegionData? _lookupRegionData(Uint8List borderMask) {
    if (borderMask.isEmpty) return null;
    return _regionDataCache[borderMask];
  }

  static bool _canVisitPixel(
    int pixelIndex, {
    required Uint8List input,
    required Uint8List borderMask,
    required _FloodFillWorkspace workspace,
    required int sourceR,
    required int sourceG,
    required int sourceB,
  }) {
    if (workspace.isVisited(pixelIndex) || borderMask[pixelIndex] == 1) {
      return false;
    }
    final int byteBase = pixelIndex << 2;
    return (input[byteBase] - sourceR).abs() <= _tolerance &&
        (input[byteBase + 1] - sourceG).abs() <= _tolerance &&
        (input[byteBase + 2] - sourceB).abs() <= _tolerance;
  }

  static void _enqueueNeighborSeeds({
    required int rowY,
    required int leftX,
    required int rightX,
    required int width,
    required Uint8List input,
    required Uint8List borderMask,
    required _FloodFillWorkspace workspace,
    required int sourceR,
    required int sourceG,
    required int sourceB,
  }) {
    final int rowStart = rowY * width;
    int x = leftX;

    while (x <= rightX) {
      final int candidateIndex = rowStart + x;
      if (_canVisitPixel(
        candidateIndex,
        input: input,
        borderMask: borderMask,
        workspace: workspace,
        sourceR: sourceR,
        sourceG: sourceG,
        sourceB: sourceB,
      )) {
        workspace.markVisited(candidateIndex);
        workspace.push(candidateIndex);
        x++;
        while (x <= rightX) {
          final int skipIndex = rowStart + x;
          if (borderMask[skipIndex] == 1) {
            break;
          }
          final int byteBase = skipIndex << 2;
          if ((input[byteBase] - sourceR).abs() > _tolerance ||
              (input[byteBase + 1] - sourceG).abs() > _tolerance ||
              (input[byteBase + 2] - sourceB).abs() > _tolerance) {
            break;
          }
          x++;
        }
        continue;
      }
      x++;
    }
  }

  static bool _canVisitConnectivityPixel(
    int pixelIndex, {
    required Uint8List borderMask,
    required _FloodFillWorkspace workspace,
  }) {
    return !workspace.isVisited(pixelIndex) && borderMask[pixelIndex] == 0;
  }

  static void _enqueueConnectivityNeighborSeeds({
    required int rowY,
    required int leftX,
    required int rightX,
    required int width,
    required Uint8List borderMask,
    required _FloodFillWorkspace workspace,
  }) {
    final int rowStart = rowY * width;
    int x = leftX;

    while (x <= rightX) {
      final int candidateIndex = rowStart + x;
      if (_canVisitConnectivityPixel(
        candidateIndex,
        borderMask: borderMask,
        workspace: workspace,
      )) {
        workspace.markVisited(candidateIndex);
        workspace.push(candidateIndex);
        x++;
        while (x <= rightX) {
          final int skipIndex = rowStart + x;
          if (borderMask[skipIndex] == 1) {
            break;
          }
          x++;
        }
        continue;
      }
      x++;
    }
  }

  static Map<String, Object> processFloodFillToMap(FloodFillRequest request) {
    final _FloodFillResult result = _processFloodFillInternal(request);
    return <String, Object>{'raw': result.raw, 'changed': result.changed};
  }

  Uint8List exportImage() {
    if (!_isLoaded || _width == 0 || _height == 0 || _currentRawRgba.isEmpty) {
      return Uint8List(0);
    }
    final img.Image image = img.Image.fromBytes(
      _width,
      _height,
      _currentRawRgba,
    );
    return Uint8List.fromList(img.encodePng(image));
  }

  static double computeFillPercentage(FillPercentageRequest request) {
    // Backwards-compatible API returning a 0-100 percentage (double).
    // Use [computeProgressPercent] when you need the exact UI percent.
    return computeProgressPercent(request).toDouble();
  }

  /// Computes the exact integer progress percentage (0-100) used by the UI.
  ///
  /// This intentionally matches the progress logic used on-canvas so gallery
  /// cards and saved metadata can show the same value.
  static int computeProgressPercent(FillPercentageRequest request) {
    final Uint8List currentRaw = request.currentRawRgba;
    final Uint8List original = request.originalRawRgba;
    final Uint8List borderMaskLocal = request.borderMask;

    if (currentRaw.lengthInBytes != original.lengthInBytes) {
      return 0;
    }
    if (borderMaskLocal.isEmpty) return 0;

    int fillablePixels = 0;
    int paintedPixels = 0;
    int whiteFillablePixels = 0;
    int unpaintedWhitePixels = 0;

    for (int i = 0, bi = 0; i < borderMaskLocal.length; i++, bi += 4) {
      if (borderMaskLocal[i] == 1) continue;

      // Ignore transparent/non-opaque pixels (common for background areas in
      // PNG assets). Counting these makes progress stick below 100% even when
      // all visible regions have been filled.
      if (original[bi + 3] != 255) continue;
      fillablePixels++;

      final bool isOriginalWhiteish =
          original[bi] >= _whiteThreshold &&
          original[bi + 1] >= _whiteThreshold &&
          original[bi + 2] >= _whiteThreshold;
      if (isOriginalWhiteish) {
        whiteFillablePixels++;
      }

      final bool changed = currentRaw[bi] != original[bi] ||
          currentRaw[bi + 1] != original[bi + 1] ||
          currentRaw[bi + 2] != original[bi + 2];

      if (changed) {
        paintedPixels++;
      } else if (isOriginalWhiteish) {
        unpaintedWhitePixels++;
      }
    }

    if (fillablePixels == 0) return 0;

    int percent = ((paintedPixels * 100) / fillablePixels).round().clamp(0, 100);
    if (whiteFillablePixels > 0 && percent >= 99) {
      // Snap to 100% when only a tiny number of originally-white pixels remain.
      int allowedRemainingWhitePixels = (whiteFillablePixels * 2) ~/ 1000; // 0.2%
      if (allowedRemainingWhitePixels < 64) allowedRemainingWhitePixels = 64;
      if (allowedRemainingWhitePixels > 4096) {
        allowedRemainingWhitePixels = 4096;
      }
      if (unpaintedWhitePixels <= allowedRemainingWhitePixels) {
        return 100;
      }
    }

    return percent;
  }

  void _prepareConnectivityMaskWords(int pixelCount) {
    final int wordCount = (pixelCount + 31) >> 5;
    if (_connectivityMaskWords.length < wordCount) {
      _connectivityMaskWords = Uint32List(wordCount);
    }
    if (_connectivityMaskDirtyWords.length < wordCount) {
      _connectivityMaskDirtyWords = Int32List(wordCount);
    }
    clearConnectivityMask();
  }

  void _markConnectivityMask(int pixelIndex) {
    final int wordIndex = pixelIndex >> 5;
    final int bitMask = 1 << (pixelIndex & 31);
    final int currentWord = _connectivityMaskWords[wordIndex];
    if ((currentWord & bitMask) != 0) {
      return;
    }
    if (currentWord == 0) {
      _connectivityMaskDirtyWords[_connectivityMaskDirtyWordCount++] =
          wordIndex;
    }
    _connectivityMaskWords[wordIndex] = currentWord | bitMask;
  }

  double getFillPercentage(Uint8List currentRaw) {
    return computeFillPercentage(
      FillPercentageRequest(
        currentRawRgba: currentRaw,
        originalRawRgba: originalRawRgba,
        borderMask: borderMask,
      ),
    );
  }

  Future<Uint8List?> getEncodedPng(
  Uint8List rgba,
  int width,
  int height,
) async {

  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
    rgba,
  );
  final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );

  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    image = frame.image;

    final ByteData? pngBytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    return pngBytes?.buffer.asUint8List();
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

  Future<Uint8List> getPngBytes() async {
    final completer = Completer<ui.Image>();
    // 1. Convert raw pixels to a UI Image
    ui.decodeImageFromPixels(
      _currentRawRgba,
      _width,
      _height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) => completer.complete(img),
    );

    final ui.Image image = await completer.future;
    // 2. Convert UI Image to PNG format bytes
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    return byteData!.buffer.asUint8List();
  }
}
