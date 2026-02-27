import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path_provider/path_provider.dart';
import '../engine/PixelEngine.dart';

void _log(String tag, String msg) {
  debugPrint('[COLOR_APP][$tag] $msg');
}

class _SessionSnapshot {
  final int imageIndex;
  final int selectedColorValue;
  final int fillCount;
  final int rawWidth;
  final int rawHeight;
  final Uint8List? rawFillBytes;
  final List<Uint8List?> undoStack;

  const _SessionSnapshot({
    required this.imageIndex,
    required this.selectedColorValue,
    required this.fillCount,
    required this.rawWidth,
    required this.rawHeight,
    required this.rawFillBytes,
    required this.undoStack,
  });
}

class _ImageSessionState {
  final Uint8List? rawFillBytes;
  final int fillCount;
  final int rawWidth;
  final int rawHeight;
  final List<Uint8List?> undoStack;

  const _ImageSessionState({
    required this.rawFillBytes,
    required this.fillCount,
    required this.rawWidth,
    required this.rawHeight,
    required this.undoStack,
  });
}

class _SessionMetaSnapshot {
  final int currentImageIndex;
  final int selectedColorValue;

  const _SessionMetaSnapshot({
    required this.currentImageIndex,
    required this.selectedColorValue,
  });
}

class BasicScreen extends StatefulWidget {
  const BasicScreen({super.key});

  @override
  State<BasicScreen> createState() => _BasicScreenState();
}

class _BasicScreenState extends State<BasicScreen> with WidgetsBindingObserver {
  static const String _sessionNamespace = 'coloring_book_session_v1';
  final PixelEngine pixelEngine = PixelEngine();
  final TransformationController _transformationController =
      TransformationController();

  ui.Image? _uiImage;
  Uint8List? _rawFillBytes;

  int _rawWidth = 0;
  int _rawHeight = 0;

  final List<Uint8List?> _undoStack = <Uint8List?>[];
  static const int _maxUndoSteps = 20;

  int _fillCount = 0;
  Color selectedColor = const Color(0xFFFFC107);
  bool isProcessing = false;
  int currentImageIndex = 0;
  bool _engineReady = false;
  bool _showStartupLoader = true;
  int _imageLoadSeq = 0;
  bool _isPersisting = false;
  final Map<int, _SessionSnapshot> _pendingImageSnapshots =
      <int, _SessionSnapshot>{};
  _SessionMetaSnapshot? _pendingSessionMeta;
  Directory _sessionDirectory = Directory.systemTemp;
  Timer? _autosaveTimer;
  static const Duration _autosaveDebounce = Duration(milliseconds: 350);
  final Map<int, _ImageSessionState> _imageStateCache =
      <int, _ImageSessionState>{};

  Size _containerSize = Size.zero;
  double _cachedScaleFit = 1.0;
  double _cachedFitOffsetX = 0.0;
  double _cachedFitOffsetY = 0.0;

  int _activePointers = 0;
  Offset? _pointerDownPosition;
  int _pointerDownTimeMs = 0;
  bool _pointerDragged = false;
  static const double _tapMoveThreshold = 10.0;
  static const int _tapMaxDurationMs = 250;

  int _to8Bit(double channel) {
    final int scaled = (channel * 255.0).round();
    if (scaled < 0) return 0;
    if (scaled > 255) return 255;
    return scaled;
  }

  final List<Color> colorHistory = <Color>[
    const Color(0xFFF44336),
    const Color(0xFFE91E63),
    const Color(0xFF9C27B0),
    const Color(0xFF2196F3),
    const Color(0xFF00BCD4),
    const Color(0xFF4CAF50),
    const Color(0xFFFFEB3B),
    const Color(0xFFFF9800),
    const Color(0xFF795548),
    const Color(0xFF000000),
    const Color(0xFF9E9E9E),
    const Color(0xFFFFFFFF),
  ];

  final List<String> testImages = <String>[
    'assets/images/doremon.png',
    'assets/images/shinchan.png',
    'assets/images/mandala.png',
    'assets/images/smilie.png',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_prepareStorageAndInit());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    unawaited(_scheduleSessionSave());
    _uiImage?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _requestAutosave(immediate: true);
    }
  }

  Future<void> _prepareStorageAndInit() async {
    try {
      final Directory appSupportDir = await getApplicationSupportDirectory();
      final Directory sessionDir = Directory(
        '${appSupportDir.path}${Platform.pathSeparator}$_sessionNamespace',
      );
      if (!await sessionDir.exists()) {
        await sessionDir.create(recursive: true);
      }
      _sessionDirectory = sessionDir;
    } catch (e) {
      _log('STORAGE_INIT', 'ERROR: $e');
      _sessionDirectory = Directory.systemTemp;
    }

    await _migrateLegacySessionIfNeeded();
    await _initWithRestore();
  }

  Future<void> _migrateLegacySessionIfNeeded() async {
    try {
      final File newSessionMeta = _sessionMetaFile;
      if (await newSessionMeta.exists()) return;

      final Directory legacyDir = Directory.systemTemp;
      final List<FileSystemEntity> legacyFiles = await legacyDir
          .list()
          .toList();
      final String prefix = _sessionNamespace;
      bool copiedAny = false;

      for (final FileSystemEntity entity in legacyFiles) {
        if (entity is! File) continue;

        final String fileName = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : '';
        if (!fileName.startsWith(prefix)) continue;

        final File target = File(
          '${_sessionDirectory.path}${Platform.pathSeparator}$fileName',
        );
        if (await target.exists()) continue;
        await entity.copy(target.path);
        copiedAny = true;
      }

      if (copiedAny) {
        _log('STORAGE_MIGRATION', 'Migrated legacy session files from temp.');
      }
    } catch (e) {
      _log('STORAGE_MIGRATION', 'ERROR: $e');
    }
  }

  File get _sessionMetaFile => File(
    '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.json',
  );

  File _imageMetaFile(int imageIndex) => File(
    '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.image_$imageIndex.json',
  );

  File _imageRawFile(int imageIndex) => File(
    '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.image_$imageIndex.raw',
  );

  File _imageUndoRawFile(int imageIndex, int undoIndex) => File(
    '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.image_${imageIndex}_undo_$undoIndex.raw',
  );

  File _preparedMetaFile(int imageIndex) => File(
    '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.prepared_$imageIndex.json',
  );

  File _preparedRawFile(int imageIndex) => File(
    '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.prepared_$imageIndex.raw',
  );

  File _preparedMaskFile(int imageIndex) => File(
    '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.prepared_$imageIndex.mask',
  );

  Future<Map<String, Object>?> _readPreparedImageCache(
    int imageIndex,
    String assetPath,
    int assetByteLength,
  ) async {
    try {
      final File metaFile = _preparedMetaFile(imageIndex);
      final File rawFile = _preparedRawFile(imageIndex);
      final File maskFile = _preparedMaskFile(imageIndex);

      if (!await metaFile.exists() ||
          !await rawFile.exists() ||
          !await maskFile.exists()) {
        return null;
      }

      final String text = await metaFile.readAsString();
      final Map<String, dynamic> meta =
          jsonDecode(text) as Map<String, dynamic>;
      if (meta['version'] != 1) return null;
      if (meta['assetPath'] != assetPath) return null;
      if (meta['assetByteLength'] != assetByteLength) return null;

      final int width = (meta['width'] is int) ? meta['width'] as int : 0;
      final int height = (meta['height'] is int) ? meta['height'] as int : 0;
      if (width <= 0 || height <= 0) return null;

      final Uint8List raw = await rawFile.readAsBytes();
      final Uint8List borderMask = await maskFile.readAsBytes();
      final int pixelCount = width * height;
      if (raw.lengthInBytes != pixelCount * 4 ||
          borderMask.lengthInBytes != pixelCount) {
        return null;
      }

      return <String, Object>{
        'width': width,
        'height': height,
        'raw': raw,
        'borderMask': borderMask,
      };
    } catch (e) {
      _log('PREPARED_CACHE_READ', 'ERROR: $e');
      return null;
    }
  }

  Future<void> _writePreparedImageCache(
    int imageIndex,
    String assetPath,
    int assetByteLength,
    Map<String, Object> prepared,
  ) async {
    try {
      final int width = prepared['width'] as int;
      final int height = prepared['height'] as int;
      final Uint8List raw = prepared['raw'] as Uint8List;
      final Uint8List borderMask = prepared['borderMask'] as Uint8List;
      if (width <= 0 ||
          height <= 0 ||
          raw.isEmpty ||
          borderMask.isEmpty ||
          raw.lengthInBytes != width * height * 4 ||
          borderMask.lengthInBytes != width * height) {
        return;
      }

      await _preparedRawFile(imageIndex).writeAsBytes(raw, flush: true);
      await _preparedMaskFile(imageIndex).writeAsBytes(borderMask, flush: true);
      final Map<String, dynamic> meta = <String, dynamic>{
        'version': 1,
        'assetPath': assetPath,
        'assetByteLength': assetByteLength,
        'width': width,
        'height': height,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await _preparedMetaFile(
        imageIndex,
      ).writeAsString(jsonEncode(meta), flush: true);
    } catch (e) {
      _log('PREPARED_CACHE_WRITE', 'ERROR: $e');
    }
  }

  Future<Map<String, Object>> _loadOrPrepareImageData(
    int imageIndex,
    String assetPath,
    Uint8List bytes,
  ) async {
    final int byteLength = bytes.lengthInBytes;
    final Map<String, Object>? cached = await _readPreparedImageCache(
      imageIndex,
      assetPath,
      byteLength,
    );
    if (cached != null) {
      return cached;
    }

    final Map<String, Object> generated = await compute(
      PixelEngine.decodeAndPrepare,
      bytes,
    );
    unawaited(
      _writePreparedImageCache(imageIndex, assetPath, byteLength, generated),
    );
    return generated;
  }

  Future<void> _initWithRestore() async {
    await _restoreSessionIfAvailable();
    await loadImage();
  }

  Future<bool> _restoreSessionIfAvailable() async {
    try {
      if (!await _sessionMetaFile.exists()) return false;

      final String text = await _sessionMetaFile.readAsString();
      final Map<String, dynamic> meta =
          jsonDecode(text) as Map<String, dynamic>;

      final int restoredIndex = (meta['currentImageIndex'] is int)
          ? meta['currentImageIndex'] as int
          : 0;
      if (restoredIndex < 0 || restoredIndex >= testImages.length) return false;

      currentImageIndex = restoredIndex;

      if (meta['selectedColor'] is int) {
        selectedColor = Color(meta['selectedColor'] as int);
      }
      return true;
    } catch (e) {
      _log('RESTORE', 'ERROR: $e');
      return false;
    }
  }

  _SessionSnapshot _captureSessionSnapshot() {
    return _SessionSnapshot(
      imageIndex: currentImageIndex,
      selectedColorValue: selectedColor.toARGB32(),
      fillCount: _fillCount,
      rawWidth: _rawWidth,
      rawHeight: _rawHeight,
      rawFillBytes: _rawFillBytes,
      undoStack: List<Uint8List?>.from(_undoStack),
    );
  }

  _SessionMetaSnapshot _captureSessionMetaSnapshot() {
    return _SessionMetaSnapshot(
      currentImageIndex: currentImageIndex,
      selectedColorValue: selectedColor.toARGB32(),
    );
  }

  void _enqueueAutosaveSnapshot() {
    final _SessionSnapshot imageSnapshot = _captureSessionSnapshot();
    if (imageSnapshot.rawWidth > 0 && imageSnapshot.rawHeight > 0) {
      _pendingImageSnapshots[imageSnapshot.imageIndex] = imageSnapshot;
    }
    _pendingSessionMeta = _captureSessionMetaSnapshot();
  }

  void _requestAutosave({bool immediate = false}) {
    if (immediate) {
      _autosaveTimer?.cancel();
      unawaited(_scheduleSessionSave());
      return;
    }

    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDebounce, () {
      unawaited(_scheduleSessionSave());
    });
  }

  Future<void> _scheduleSessionSave() async {
    _enqueueAutosaveSnapshot();
    if (_isPersisting) return;

    _isPersisting = true;
    try {
      while (true) {
        while (_pendingImageSnapshots.isNotEmpty) {
          final int imageIndex = _pendingImageSnapshots.keys.first;
          final _SessionSnapshot snapshot = _pendingImageSnapshots.remove(
            imageIndex,
          )!;
          await _persistImageSnapshot(snapshot);
        }

        final _SessionMetaSnapshot? sessionMeta = _pendingSessionMeta;
        _pendingSessionMeta = null;
        if (sessionMeta != null) {
          await _persistSessionMetaSnapshot(sessionMeta);
        }

        if (_pendingImageSnapshots.isEmpty && _pendingSessionMeta == null) {
          break;
        }
      }
    } finally {
      _isPersisting = false;
    }
  }

  Future<void> _persistImageSnapshot(_SessionSnapshot snapshot) async {
    try {
      if (snapshot.rawWidth <= 0 || snapshot.rawHeight <= 0) return;

      final File imageMetaFile = _imageMetaFile(snapshot.imageIndex);
      final File imageRawFile = _imageRawFile(snapshot.imageIndex);

      _imageStateCache[snapshot.imageIndex] = _ImageSessionState(
        rawFillBytes: snapshot.rawFillBytes,
        fillCount: snapshot.fillCount,
        rawWidth: snapshot.rawWidth,
        rawHeight: snapshot.rawHeight,
        undoStack: List<Uint8List?>.from(snapshot.undoStack),
      );

      if (snapshot.rawFillBytes != null) {
        await imageRawFile.writeAsBytes(snapshot.rawFillBytes!, flush: true);
      } else if (await imageRawFile.exists()) {
        await imageRawFile.delete();
      }

      for (int i = 0; i < _maxUndoSteps; i++) {
        final File undoFile = _imageUndoRawFile(snapshot.imageIndex, i);
        if (await undoFile.exists()) {
          await undoFile.delete();
        }
      }

      final List<int> undoKinds = <int>[];
      for (int i = 0; i < snapshot.undoStack.length; i++) {
        final Uint8List? entry = snapshot.undoStack[i];
        if (entry == null) {
          undoKinds.add(0);
          continue;
        }
        undoKinds.add(1);
        await _imageUndoRawFile(
          snapshot.imageIndex,
          i,
        ).writeAsBytes(entry, flush: true);
      }

      final Map<String, dynamic> imageMeta = <String, dynamic>{
        'version': 1,
        'imageIndex': snapshot.imageIndex,
        'fillCount': snapshot.fillCount,
        'hasRawFill': snapshot.rawFillBytes != null,
        'rawWidth': snapshot.rawWidth,
        'rawHeight': snapshot.rawHeight,
        'undoKinds': undoKinds,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await imageMetaFile.writeAsString(jsonEncode(imageMeta), flush: true);
    } catch (e) {
      _log('AUTOSAVE_IMAGE', 'ERROR: $e');
    }
  }

  Future<void> _persistSessionMetaSnapshot(
    _SessionMetaSnapshot snapshot,
  ) async {
    try {
      final Map<String, dynamic> sessionMeta = <String, dynamic>{
        'version': 1,
        'currentImageIndex': snapshot.currentImageIndex,
        'selectedColor': snapshot.selectedColorValue,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await _sessionMetaFile.writeAsString(
        jsonEncode(sessionMeta),
        flush: true,
      );
    } catch (e) {
      _log('AUTOSAVE_META', 'ERROR: $e');
    }
  }

  Future<ui.Image?> _buildCurrentImageFromSavedState() async {
    final _ImageSessionState? cached = _imageStateCache[currentImageIndex];
    if (cached != null &&
        cached.rawWidth == _rawWidth &&
        cached.rawHeight == _rawHeight) {
      _fillCount = cached.fillCount;
      _rawFillBytes = cached.rawFillBytes;
      _undoStack
        ..clear()
        ..addAll(cached.undoStack);
      if (_rawFillBytes != null) {
        pixelEngine.updateFromRawBytes(_rawFillBytes!, _rawWidth, _rawHeight);
        return _rawRgbaToUiImage(_rawFillBytes!, _rawWidth, _rawHeight);
      }
      return null;
    }

    final File imageMetaFile = _imageMetaFile(currentImageIndex);
    if (await imageMetaFile.exists()) {
      try {
        final String text = await imageMetaFile.readAsString();
        final Map<String, dynamic> meta =
            jsonDecode(text) as Map<String, dynamic>;

        _fillCount = (meta['fillCount'] is int) ? meta['fillCount'] as int : 0;
        final bool hasRawFill = meta['hasRawFill'] == true;
        final int savedWidth = (meta['rawWidth'] is int)
            ? meta['rawWidth'] as int
            : _rawWidth;
        final int savedHeight = (meta['rawHeight'] is int)
            ? meta['rawHeight'] as int
            : _rawHeight;
        final List<int> undoKinds = (meta['undoKinds'] is List)
            ? (meta['undoKinds'] as List)
                  .map((dynamic e) => (e is int) ? e : -1)
                  .toList()
            : <int>[];

        final List<Uint8List?> restoredUndo = <Uint8List?>[];
        for (int i = 0; i < undoKinds.length; i++) {
          final int kind = undoKinds[i];
          if (kind == 0) {
            restoredUndo.add(null);
            continue;
          }
          if (kind == 1) {
            final File undoFile = _imageUndoRawFile(currentImageIndex, i);
            if (!await undoFile.exists()) continue;
            final Uint8List rawUndo = await undoFile.readAsBytes();
            if (rawUndo.lengthInBytes == _rawWidth * _rawHeight * 4) {
              restoredUndo.add(rawUndo);
            }
          }
        }
        _undoStack
          ..clear()
          ..addAll(restoredUndo);

        if (hasRawFill &&
            savedWidth == _rawWidth &&
            savedHeight == _rawHeight) {
          final File imageRawFile = _imageRawFile(currentImageIndex);
          if (await imageRawFile.exists()) {
            final Uint8List raw = await imageRawFile.readAsBytes();
            final int expectedLen = _rawWidth * _rawHeight * 4;
            if (raw.lengthInBytes == expectedLen) {
              _rawFillBytes = raw;
              pixelEngine.updateFromRawBytes(
                _rawFillBytes!,
                _rawWidth,
                _rawHeight,
              );
              _imageStateCache[currentImageIndex] = _ImageSessionState(
                rawFillBytes: _rawFillBytes,
                fillCount: _fillCount,
                rawWidth: _rawWidth,
                rawHeight: _rawHeight,
                undoStack: List<Uint8List?>.from(_undoStack),
              );
              return _rawRgbaToUiImage(_rawFillBytes!, _rawWidth, _rawHeight);
            }
          }
        }
      } catch (e) {
        _log('RESTORE_IMAGE', 'ERROR: $e');
      }
    }

    _rawFillBytes = null;
    _fillCount = 0;
    _imageStateCache[currentImageIndex] = _ImageSessionState(
      rawFillBytes: null,
      fillCount: 0,
      rawWidth: _rawWidth,
      rawHeight: _rawHeight,
      undoStack: <Uint8List?>[],
    );
    _undoStack.clear();
    return null;
  }

  Future<void> loadImage({bool restoreSavedState = true}) async {
    final int loadSeq = ++_imageLoadSeq;
    final int imageIndexAtLoad = currentImageIndex;
    final String assetPathAtLoad = testImages[imageIndexAtLoad];
    if (mounted) {
      setState(() {
        _engineReady = false;
      });
    }

    try {
      final ByteData data = await rootBundle.load(assetPathAtLoad);
      if (!mounted || loadSeq != _imageLoadSeq) return;
      final Uint8List bytes = data.buffer.asUint8List();

      // Start light preview decode and heavy pixel preparation in parallel.
      final Future<ui.Image> previewFuture = _decodeToUiImage(bytes);
      final Future<Map<String, Object>> preparedFuture =
          _loadOrPrepareImageData(imageIndexAtLoad, assetPathAtLoad, bytes);

      final ui.Image preview = await previewFuture;
      if (!mounted || loadSeq != _imageLoadSeq) {
        preview.dispose();
        return;
      }

      final ui.Image? oldPreview = _uiImage;
      setState(() {
        _uiImage = preview;
        _rawWidth = preview.width;
        _rawHeight = preview.height;
        _transformationController.value = Matrix4.identity();
        _showStartupLoader = false;
      });
      oldPreview?.dispose();
      _updateFitCache();

      final Map<String, Object> prepared = await preparedFuture;
      if (!mounted || loadSeq != _imageLoadSeq) return;

      pixelEngine.applyPreparedImage(prepared);
      if (!pixelEngine.isLoaded) {
        throw StateError('Failed to decode image: $assetPathAtLoad');
      }

      _rawWidth = pixelEngine.imageWidth;
      _rawHeight = pixelEngine.imageHeight;
      _undoStack.clear();

      final ui.Image? loaded = restoreSavedState
          ? await _buildCurrentImageFromSavedState()
          : null;
      if (!mounted || loadSeq != _imageLoadSeq) {
        loaded?.dispose();
        return;
      }

      if (!restoreSavedState) {
        _rawFillBytes = null;
        _fillCount = 0;
        _undoStack.clear();
        _imageStateCache[currentImageIndex] = _ImageSessionState(
          rawFillBytes: null,
          fillCount: 0,
          rawWidth: _rawWidth,
          rawHeight: _rawHeight,
          undoStack: <Uint8List?>[],
        );
      }

      if (loaded != null) {
        final ui.Image? oldImage = _uiImage;
        setState(() {
          _uiImage = loaded;
          _transformationController.value = Matrix4.identity();
        });
        oldImage?.dispose();
        _updateFitCache();
      }

      if (mounted && loadSeq == _imageLoadSeq) {
        setState(() {
          _engineReady = true;
        });
      }
    } catch (e) {
      _log('LOAD', 'ERROR: $e');
      if (mounted && loadSeq == _imageLoadSeq) {
        setState(() {
          _engineReady = false;
          _showStartupLoader = false;
        });
      }
    }
  }

  Future<ui.Image> _decodeToUiImage(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<ui.Image> _rawRgbaToUiImage(
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
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }

  void _updateFitCache() {
    if (_containerSize == Size.zero || _uiImage == null) return;
    final double imgW = _rawWidth.toDouble();
    final double imgH = _rawHeight.toDouble();
    final double viewW = _containerSize.width;
    final double viewH = _containerSize.height;
    _cachedScaleFit = (viewW / imgW < viewH / imgH)
        ? viewW / imgW
        : viewH / imgH;
    _cachedFitOffsetX = (viewW - imgW * _cachedScaleFit) / 2.0;
    _cachedFitOffsetY = (viewH - imgH * _cachedScaleFit) / 2.0;
  }

  void showPicker() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Pick a Custom Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: selectedColor,
            onColorChanged: (Color c) => setState(() => selectedColor = c),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers == 1) {
      _pointerDownPosition = event.localPosition;
      _pointerDownTimeMs = DateTime.now().millisecondsSinceEpoch;
      _pointerDragged = false;
    } else {
      _pointerDownPosition = null;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerDownPosition != null && !_pointerDragged) {
      if ((event.localPosition - _pointerDownPosition!).distance >
          _tapMoveThreshold) {
        _pointerDragged = true;
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    if (_pointerDownPosition != null &&
        !_pointerDragged &&
        _activePointers == 0) {
      final int elapsed =
          DateTime.now().millisecondsSinceEpoch - _pointerDownTimeMs;
      if (elapsed <= _tapMaxDurationMs) {
        handleTap(_pointerDownPosition!);
      }
    }
    if (_activePointers == 0) {
      _pointerDownPosition = null;
      _pointerDragged = false;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    if (_activePointers == 0) {
      _pointerDownPosition = null;
      _pointerDragged = false;
    }
  }

  Future<void> handleTap(Offset localOffset) async {
    if (_uiImage == null || isProcessing || !_engineReady) return;

    final Offset scene = _transformationController.toScene(localOffset);
    final int pixelX = ((scene.dx - _cachedFitOffsetX) / _cachedScaleFit)
        .floor();
    final int pixelY = ((scene.dy - _cachedFitOffsetY) / _cachedScaleFit)
        .floor();

    if (pixelX < 0 ||
        pixelX >= _rawWidth ||
        pixelY < 0 ||
        pixelY >= _rawHeight) {
      return;
    }

    setState(() {
      isProcessing = true;
    });

    try {
      _fillCount++;
      final int thisFill = _fillCount;

      // Each fill produces a new buffer, so the previous one is safe to reuse
      // as an undo snapshot without cloning.
      final Uint8List? snapshot = _rawFillBytes;

      if (_undoStack.length >= _maxUndoSteps) {
        if (_undoStack[0] == null) {
          _log(
            'FILL#$thisFill',
            'Stack full. Protecting original. Removing index 1.',
          );
          _undoStack.removeAt(1);
        } else {
          _log('FILL#$thisFill', 'Stack full. Removing oldest.');
          _undoStack.removeAt(0);
        }
      }
      _undoStack.add(snapshot);

      final Uint8List baseRaw = _rawFillBytes ?? pixelEngine.originalRawRgba;

      final Uint8List rawResult = await compute(
        PixelEngine.processFloodFill,
        FloodFillRequest(
          rawRgbaBytes: baseRaw,
          borderMask: pixelEngine.borderMask,
          x: pixelX,
          y: pixelY,
          width: _rawWidth,
          height: _rawHeight,
          fillR: _to8Bit(selectedColor.r),
          fillG: _to8Bit(selectedColor.g),
          fillB: _to8Bit(selectedColor.b),
        ),
      );

      _rawFillBytes = rawResult;
      pixelEngine.updateFromRawBytes(rawResult, _rawWidth, _rawHeight);
      _imageStateCache[currentImageIndex] = _ImageSessionState(
        rawFillBytes: _rawFillBytes,
        fillCount: _fillCount,
        rawWidth: _rawWidth,
        rawHeight: _rawHeight,
        undoStack: List<Uint8List?>.from(_undoStack),
      );

      final ui.Image newUiImage = await _rawRgbaToUiImage(
        rawResult,
        _rawWidth,
        _rawHeight,
      );
      if (!mounted) {
        newUiImage.dispose();
        return;
      }

      final ui.Image? oldImage = _uiImage;
      setState(() {
        _uiImage = newUiImage;
        isProcessing = false;
      });
      oldImage?.dispose();
      _requestAutosave();
    } catch (e) {
      _log('FILL', 'ERROR: $e');
      if (mounted) {
        setState(() => isProcessing = false);
      }
    }
  }

  Future<void> _undo() async {
    if (_undoStack.isEmpty || isProcessing || !_engineReady) return;

    setState(() => isProcessing = true);
    try {
      final Uint8List? snapshot = _undoStack.removeLast();
      if (_fillCount > 0) _fillCount--;

      ui.Image restoredImage;
      if (snapshot == null) {
        final Uint8List originalRaw = pixelEngine.originalRawRgba;
        _rawFillBytes = null;
        pixelEngine.updateFromRawBytes(originalRaw, _rawWidth, _rawHeight);
        restoredImage = await _rawRgbaToUiImage(
          originalRaw,
          _rawWidth,
          _rawHeight,
        );
      } else {
        _rawFillBytes = snapshot;
        pixelEngine.updateFromRawBytes(snapshot, _rawWidth, _rawHeight);
        restoredImage = await _rawRgbaToUiImage(
          snapshot,
          _rawWidth,
          _rawHeight,
        );
      }

      _imageStateCache[currentImageIndex] = _ImageSessionState(
        rawFillBytes: _rawFillBytes,
        fillCount: _fillCount,
        rawWidth: _rawWidth,
        rawHeight: _rawHeight,
        undoStack: List<Uint8List?>.from(_undoStack),
      );

      if (!mounted) {
        restoredImage.dispose();
        return;
      }

      final ui.Image? oldImage = _uiImage;
      setState(() {
        _uiImage = restoredImage;
        isProcessing = false;
      });
      oldImage?.dispose();
      _requestAutosave();
    } catch (e) {
      _log('UNDO', 'ERROR: $e');
      if (mounted) {
        setState(() => isProcessing = false);
      }
    }
  }

  Future<void> _refreshCurrentImage() async {
    if (isProcessing) return;
    try {
      final File metaFile = _imageMetaFile(currentImageIndex);
      final File rawFile = _imageRawFile(currentImageIndex);
      if (await metaFile.exists()) await metaFile.delete();
      if (await rawFile.exists()) await rawFile.delete();
      for (int i = 0; i < _maxUndoSteps; i++) {
        final File undoFile = _imageUndoRawFile(currentImageIndex, i);
        if (await undoFile.exists()) {
          await undoFile.delete();
        }
      }
      _imageStateCache.remove(currentImageIndex);
    } catch (e) {
      _log('REFRESH', 'ERROR: $e');
    }
    await loadImage(restoreSavedState: false);
    _requestAutosave(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_uiImage == null && _showStartupLoader) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        body: SafeArea(child: Center(child: _buildStartupLoader())),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Coloring Book',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: isProcessing
            ? const Padding(
                padding: EdgeInsets.all(15),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        actions: <Widget>[
          IconButton(
            icon: Icon(
              Icons.undo,
              color: (_undoStack.isNotEmpty && !isProcessing && _engineReady)
                  ? Colors.black
                  : Colors.grey.shade300,
            ),
            onPressed: (_undoStack.isNotEmpty && !isProcessing && _engineReady)
                ? _undo
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: (isProcessing || !_engineReady)
                ? null
                : _refreshCurrentImage,
          ),
          IconButton(
            icon: Icon(Icons.colorize, color: selectedColor),
            onPressed: _engineReady ? showPicker : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: _uiImage == null
                        ? const Center(child: CircularProgressIndicator())
                        : LayoutBuilder(
                            builder:
                                (
                                  BuildContext context,
                                  BoxConstraints constraints,
                                ) {
                                  final Size newSize = Size(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  );
                                  if (_containerSize != newSize) {
                                    _containerSize = newSize;
                                    _updateFitCache();
                                  }
                                  return Listener(
                                    onPointerDown: _onPointerDown,
                                    onPointerMove: _onPointerMove,
                                    onPointerUp: _onPointerUp,
                                    onPointerCancel: _onPointerCancel,
                                    child: InteractiveViewer(
                                      transformationController:
                                          _transformationController,
                                      panEnabled: true,
                                      minScale: 1.0,
                                      maxScale: 10.0,
                                      child: SizedBox(
                                        width: constraints.maxWidth,
                                        height: constraints.maxHeight,
                                        child: Center(
                                          child: RawImage(
                                            image: _uiImage,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                          ),
                  ),
                ),
              ),
            ),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _navBtn(Icons.arrow_back_ios, () => _changeImage(-1)),
                const Text(
                  'PALETTE',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                _navBtn(Icons.arrow_forward_ios, () => _changeImage(1)),
              ],
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 55,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemCount: colorHistory.length,
              itemBuilder: (BuildContext context, int i) =>
                  _buildColorCircle(colorHistory[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartupLoader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Icon(Icons.palette_outlined, size: 34),
        ),
        const SizedBox(height: 18),
        const Text(
          'Loading Coloring Book...',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 14),
        const SizedBox(
          width: 150,
          child: LinearProgressIndicator(
            minHeight: 4,
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
        ),
      ],
    );
  }

  Widget _buildColorCircle(Color color) {
    final bool isSelected = selectedColor == color;

    // 1. CALCULATE BRIGHTNESS
    // computeLuminance() returns a value from 0.0 (Black) to 1.0 (White)
    final double luminance = color.computeLuminance();

    // 2. DEFINE CONTRAST COLORS
    // If luminance is > 0.5, it means the color is "Light"
    final Color selectedBorderColor = luminance < 0.5
        ? Colors.white
        : Colors.black;

    // This variable determines the color of the Icon
    final Color checkColor = selectedBorderColor;

    return GestureDetector(
      onTap: () => setState(() => selectedColor = color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: isSelected ? 52 : 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          // Remove Shadow (Glow effect removed)
          boxShadow: null,
          border: Border.all(
            // Logic: Black if not selected, high-contrast if selected.
            color: isSelected ? selectedBorderColor : Colors.black,
            width: isSelected ? 2.0 : 2.5,
          ),
        ),
        child: isSelected
            ? Icon(Icons.check, color: checkColor, size: 20)
            : null,
      ),
    );
  }

  void _changeImage(int delta) {
    _requestAutosave(immediate: true);
    setState(() {
      currentImageIndex =
          (currentImageIndex + delta + testImages.length) % testImages.length;
    });
    loadImage();
  }

  Widget _navBtn(IconData icon, VoidCallback tap) {
    return IconButton(icon: Icon(icon, size: 18), onPressed: tap);
  }
}
