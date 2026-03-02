import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../../engine/PixelEngine.dart';

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

class _SessionMetaSnapshot {
  final int currentImageIndex;
  final int selectedColorValue;

  const _SessionMetaSnapshot({
    required this.currentImageIndex,
    required this.selectedColorValue,
  });
}

class BasicScreenController extends ChangeNotifier {
  final String _sessionNamespace = 'coloring_book_session_v1';
  final String _sessionMetaKey = 'session_meta';
  final String _imageMetaKeyPrefix = 'image_meta_';
  final String _preparedMetaKeyPrefix = 'prepared_meta_';
  final String _metaBoxSuffix = '_metadata_box';

  final PixelEngine pixelEngine = PixelEngine();
  final TransformationController transformationController =
      TransformationController();

  ui.Image? _uiImage;
  Uint8List? _rawFillBytes;

  int _rawWidth = 0;
  int _rawHeight = 0;

  final List<Uint8List?> _undoStack = <Uint8List?>[];
  final int _maxUndoSteps = 20;

  int _fillCount = 0;
  Color _selectedColor = const Color(0xFFFFC107);
  bool _isProcessing = false;
  int _currentImageIndex = 0;
  bool _engineReady = false;
  bool _showStartupLoader = true;
  bool _showImageTransitionLoader = false;
  int _imageLoadSeq = 0;
  bool _isImageLoading = false;
  int _queuedImageDelta = 0;
  bool _isPersisting = false;
  final Map<int, _SessionSnapshot> _pendingImageSnapshots =
      <int, _SessionSnapshot>{};
  _SessionMetaSnapshot? _pendingSessionMeta;
  Directory _sessionDirectory = Directory.current;
  Box<dynamic>? _sessionMetaBox;
  bool _storageReady = false;
  Timer? _autosaveTimer;
  final Duration _autosaveDebounce = const Duration(milliseconds: 350);

  Size _containerSize = Size.zero;
  double _cachedScaleFit = 1.0;
  double _cachedFitOffsetX = 0.0;
  double _cachedFitOffsetY = 0.0;

  int _activePointers = 0;
  Offset? _pointerDownPosition;
  int _pointerDownTimeMs = 0;
  bool _pointerDragged = false;
  final double _tapMoveThreshold = 10.0;
  final int _tapMaxDurationMs = 250;
  final double _swipeMinDistance = 64.0;
  final double _swipeMaxCrossAxis = 42.0;
  final int _swipeMaxDurationMs = 450;

  bool _disposed = false;

  final List<Color> _colorHistory = <Color>[
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

  final List<String> _testImages = <String>[
    'assets/images/doremon.png',
    'assets/images/shinchan.png',
    'assets/images/mandala.png',
    'assets/images/smilie.png',
  ];

  ui.Image? get uiImage => _uiImage;
  Color get selectedColor => _selectedColor;
  bool get isProcessing => _isProcessing;
  bool get engineReady => _engineReady;
  bool get showStartupLoader => _showStartupLoader;
  bool get showImageTransitionLoader => _showImageTransitionLoader;
  List<Color> get colorHistory => _colorHistory;
  bool get canUndo => _undoStack.isNotEmpty && !_isProcessing && _engineReady;
  bool get canRefresh => !_isProcessing && _engineReady;
  bool get canPickColor => _engineReady;

  void init() {
    unawaited(_prepareStorageAndInit());
  }

  void onAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _requestAutosave(immediate: true);
    }
  }

  void onViewportSizeChanged(Size newSize) {
    if (_containerSize != newSize) {
      _containerSize = newSize;
      _updateFitCache();
    }
  }

  void selectColor(Color color) {
    _selectedColor = color;
    _notify();
  }

  Future<void> showPicker(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Pick a Custom Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _selectedColor,
            onColorChanged: (Color c) {
              _selectedColor = c;
              _notify();
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void onPointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers == 1) {
      _pointerDownPosition = event.localPosition;
      _pointerDownTimeMs = DateTime.now().millisecondsSinceEpoch;
      _pointerDragged = false;
    } else {
      _pointerDownPosition = null;
    }
  }

  void onPointerMove(PointerMoveEvent event) {
    if (_pointerDownPosition != null && !_pointerDragged) {
      if ((event.localPosition - _pointerDownPosition!).distance >
          _tapMoveThreshold) {
        _pointerDragged = true;
      }
    }
  }

  void onPointerUp(PointerUpEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    if (_pointerDownPosition != null && _activePointers == 0) {
      final int elapsed =
          DateTime.now().millisecondsSinceEpoch - _pointerDownTimeMs;
      final Offset delta = event.localPosition - _pointerDownPosition!;
      final bool isHorizontalSwipe =
          _isSwipeNavigationAllowed() &&
          elapsed <= _swipeMaxDurationMs &&
          delta.dx.abs() >= _swipeMinDistance &&
          delta.dy.abs() <= _swipeMaxCrossAxis;

      if (isHorizontalSwipe) {
        changeImage(delta.dx < 0 ? 1 : -1);
      } else if (!_pointerDragged && elapsed <= _tapMaxDurationMs) {
        unawaited(handleTap(_pointerDownPosition!));
      }
    }
    if (_activePointers == 0) {
      _pointerDownPosition = null;
      _pointerDragged = false;
    }
  }

  void onPointerCancel(PointerCancelEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    if (_activePointers == 0) {
      _pointerDownPosition = null;
      _pointerDragged = false;
    }
  }

  void changeImage(int delta) {
    if (delta == 0) return;
    if (_isImageLoading) {
      _queuedImageDelta += delta;
      return;
    }
    _applyImageChange(delta);
  }

  Future<void> undo() async {
    if (_undoStack.isEmpty || _isProcessing || !_engineReady) return;

    _isProcessing = true;
    _notify();
    try {
      final Uint8List? snapshot = _undoStack.removeLast();
      if (_fillCount > 0) _fillCount--;

      ui.Image restoredImage;
      if (snapshot == null) {
        final Uint8List originalRaw = pixelEngine.originalRawRgba;
        _rawFillBytes = null;
        pixelEngine.updateFromRawBytes(originalRaw, _rawWidth, _rawHeight);
        restoredImage = await _rawRgbaToUiImage(originalRaw, _rawWidth, _rawHeight);
      } else {
        _rawFillBytes = snapshot;
        pixelEngine.updateFromRawBytes(snapshot, _rawWidth, _rawHeight);
        restoredImage = await _rawRgbaToUiImage(snapshot, _rawWidth, _rawHeight);
      }

      if (_disposed) {
        restoredImage.dispose();
        return;
      }

      _replaceUiImage(restoredImage);
      _isProcessing = false;
      _notify();
      _requestAutosave();
    } catch (e) {
      _log('UNDO', 'ERROR: $e');
      _isProcessing = false;
      _notify();
    }
  }

  Future<void> refreshCurrentImage() async {
    if (_isProcessing) return;
    try {
      if (_storageReady) {
        final File rawFile = _imageRawFile(_currentImageIndex);
        if (_sessionMetaBox != null) {
          await _sessionMetaBox!.delete(_imageMetaKey(_currentImageIndex));
        }
        if (await rawFile.exists()) await rawFile.delete();
        for (int i = 0; i < _maxUndoSteps; i++) {
          final File undoFile = _imageUndoRawFile(_currentImageIndex, i);
          if (await undoFile.exists()) {
            await undoFile.delete();
          }
        }
      }
    } catch (e) {
      _log('REFRESH', 'ERROR: $e');
    }
    await loadImage(restoreSavedState: false);
    _requestAutosave(immediate: true);
  }

  Future<void> handleTap(Offset localOffset) async {
    if (_uiImage == null || _isProcessing || !_engineReady) return;

    final Offset scene = transformationController.toScene(localOffset);
    final int pixelX = ((scene.dx - _cachedFitOffsetX) / _cachedScaleFit).floor();
    final int pixelY = ((scene.dy - _cachedFitOffsetY) / _cachedScaleFit).floor();

    if (pixelX < 0 || pixelX >= _rawWidth || pixelY < 0 || pixelY >= _rawHeight) {
      return;
    }

    _isProcessing = true;
    _notify();

    try {
      _fillCount++;
      final int thisFill = _fillCount;

      final Uint8List? snapshot = _rawFillBytes;

      if (_undoStack.length >= _maxUndoSteps) {
        if (_undoStack[0] == null) {
          _log('FILL#$thisFill', 'Stack full. Protecting original. Removing index 1.');
          _undoStack.removeAt(1);
        } else {
          _log('FILL#$thisFill', 'Stack full. Removing oldest.');
          _undoStack.removeAt(0);
        }
      }
      _undoStack.add(snapshot);

      final Uint8List baseRaw = _rawFillBytes ?? pixelEngine.originalRawRgba;

      final Uint8List rawResult = PixelEngine.processFloodFill(
        FloodFillRequest(
          rawRgbaBytes: baseRaw,
          borderMask: pixelEngine.borderMask,
          x: pixelX,
          y: pixelY,
          width: _rawWidth,
          height: _rawHeight,
          fillR: _to8Bit(_selectedColor.r),
          fillG: _to8Bit(_selectedColor.g),
          fillB: _to8Bit(_selectedColor.b),
        ),
      );

      _rawFillBytes = rawResult;
      pixelEngine.updateFromRawBytes(rawResult, _rawWidth, _rawHeight);

      final ui.Image newUiImage = await _rawRgbaToUiImage(
        rawResult,
        _rawWidth,
        _rawHeight,
      );
      if (_disposed) {
        newUiImage.dispose();
        return;
      }

      _replaceUiImage(newUiImage);
      _isProcessing = false;
      _notify();
      _requestAutosave();
    } catch (e) {
      _log('FILL', 'ERROR: $e');
      _isProcessing = false;
      _notify();
    }
  }

  Future<void> loadImage({bool restoreSavedState = true}) async {
    final int loadSeq = ++_imageLoadSeq;
    final int imageIndexAtLoad = _currentImageIndex;
    final String assetPathAtLoad = _testImages[imageIndexAtLoad];
    _isImageLoading = true;
    _engineReady = false;
    _showImageTransitionLoader = !_showStartupLoader && _uiImage != null;
    _notify();

    try {
      final ByteData data = await rootBundle.load(assetPathAtLoad);
      if (_disposed || loadSeq != _imageLoadSeq) return;
      final Uint8List bytes = data.buffer.asUint8List();

      final ui.Image preview = await _decodeToUiImage(bytes);
      if (_disposed || loadSeq != _imageLoadSeq) {
        preview.dispose();
        return;
      }

      _replaceUiImage(preview);
      _rawWidth = preview.width;
      _rawHeight = preview.height;
      transformationController.value = Matrix4.identity();
      _showStartupLoader = false;
      _updateFitCache();
      _notify();

      await Future<void>.delayed(Duration.zero);
      if (_disposed || loadSeq != _imageLoadSeq) return;

      final Map<String, Object> prepared =
          await _loadOrPrepareImageData(imageIndexAtLoad, assetPathAtLoad, bytes);
      if (_disposed || loadSeq != _imageLoadSeq) return;

      pixelEngine.applyPreparedImage(prepared);
      if (!pixelEngine.isLoaded) {
        throw StateError('Failed to decode image: $assetPathAtLoad');
      }

      _rawWidth = pixelEngine.imageWidth;
      _rawHeight = pixelEngine.imageHeight;
      _undoStack.clear();

      final ui.Image? loaded =
          restoreSavedState ? await _buildCurrentImageFromSavedState() : null;
      if (_disposed || loadSeq != _imageLoadSeq) {
        loaded?.dispose();
        return;
      }

      if (!restoreSavedState) {
        _rawFillBytes = null;
        _fillCount = 0;
        _undoStack.clear();
      }

      if (loaded != null) {
        _replaceUiImage(loaded);
        transformationController.value = Matrix4.identity();
        _updateFitCache();
      }

      _engineReady = true;
      _showImageTransitionLoader = false;
      _notify();
    } catch (e) {
      _log('LOAD', 'ERROR: $e');
      if (!_disposed && loadSeq == _imageLoadSeq) {
        _engineReady = false;
        _showStartupLoader = false;
        _showImageTransitionLoader = false;
        _notify();
      }
    } finally {
      if (loadSeq == _imageLoadSeq) {
        _isImageLoading = false;
        if (_disposed) {
          _showImageTransitionLoader = false;
        }
      }
      _drainQueuedImageChange();
    }
  }

  int _to8Bit(double channel) {
    final int scaled = (channel * 255.0).round();
    if (scaled < 0) return 0;
    if (scaled > 255) return 255;
    return scaled;
  }

  bool _isSwipeNavigationAllowed() {
    final double currentScale = transformationController.value.getMaxScaleOnAxis();
    return currentScale <= 1.05;
  }

  int _wrapImageIndex(int rawIndex) {
    final int len = _testImages.length;
    return ((rawIndex % len) + len) % len;
  }

  void _drainQueuedImageChange() {
    if (_disposed || _isImageLoading || _queuedImageDelta == 0) return;
    final int queuedDelta = _queuedImageDelta;
    _queuedImageDelta = 0;
    _applyImageChange(queuedDelta);
  }

  void _applyImageChange(int delta) {
    if (delta == 0) return;
    _requestAutosave(immediate: true);
    _currentImageIndex = _wrapImageIndex(_currentImageIndex + delta);
    _notify();
    unawaited(loadImage());
  }

  Future<void> _prepareStorageAndInit() async {
    try {
      final Directory appSupportDir = await getApplicationDocumentsDirectory();
      final Directory sessionDir = Directory(
        '${appSupportDir.path}${Platform.pathSeparator}$_sessionNamespace',
      );
      if (!await sessionDir.exists()) {
        await sessionDir.create(recursive: true);
      }
      _sessionDirectory = sessionDir;

      Hive.init(sessionDir.path);
      _sessionMetaBox =
          await Hive.openBox<dynamic>('$_sessionNamespace$_metaBoxSuffix');
      _storageReady = true;
    } catch (e) {
      _log('STORAGE_INIT', 'ERROR: $e');
      _storageReady = false;
    }

    await _initWithRestore();
  }

  Future<void> _flushStorageOnDispose() async {
    if (!_storageReady) return;
    await _scheduleSessionSave();
  }

  String _imageMetaKey(int imageIndex) => '$_imageMetaKeyPrefix$imageIndex';
  String _preparedMetaKey(int imageIndex) =>
      '$_preparedMetaKeyPrefix$imageIndex';

  File _imageRawFile(int imageIndex) => File(
    '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.image_$imageIndex.raw',
  );

  File _imageUndoRawFile(int imageIndex, int undoIndex) => File(
    '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.image_${imageIndex}_undo_$undoIndex.raw',
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
      if (!_storageReady || _sessionMetaBox == null) return null;
      final dynamic rawMeta = _sessionMetaBox!.get(_preparedMetaKey(imageIndex));
      if (rawMeta is! Map) return null;
      final Map<dynamic, dynamic> meta = rawMeta;
      if (meta['version'] != 1) return null;
      if (meta['assetPath'] != assetPath) return null;
      if (meta['assetByteLength'] != assetByteLength) return null;

      final int width = (meta['width'] is int) ? meta['width'] as int : 0;
      final int height = (meta['height'] is int) ? meta['height'] as int : 0;
      if (width <= 0 || height <= 0) return null;

      final File rawFile = _preparedRawFile(imageIndex);
      final File maskFile = _preparedMaskFile(imageIndex);
      if (!await rawFile.exists() || !await maskFile.exists()) return null;

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
      if (!_storageReady || _sessionMetaBox == null) return;
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
      await _sessionMetaBox!.put(_preparedMetaKey(imageIndex), <String, dynamic>{
        'version': 1,
        'imageId': imageIndex,
        'assetPath': assetPath,
        'assetByteLength': assetByteLength,
        'width': width,
        'height': height,
        'lastModified': DateTime.now().toIso8601String(),
      });
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
    if (cached != null) return cached;

    final Map<String, Object> generated = PixelEngine.decodeAndPrepare(bytes);
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
      if (!_storageReady || _sessionMetaBox == null) return false;
      final dynamic rawMeta = _sessionMetaBox!.get(_sessionMetaKey);
      if (rawMeta is! Map) return false;
      final Map<dynamic, dynamic> meta = rawMeta;

      final int restoredIndex =
          (meta['currentImageIndex'] is int) ? meta['currentImageIndex'] as int : 0;
      if (restoredIndex < 0 || restoredIndex >= _testImages.length) return false;

      _currentImageIndex = restoredIndex;

      if (meta['selectedColor'] is int) {
        _selectedColor = Color(meta['selectedColor'] as int);
      }
      return true;
    } catch (e) {
      _log('RESTORE', 'ERROR: $e');
      return false;
    }
  }

  _SessionSnapshot _captureSessionSnapshot() {
    return _SessionSnapshot(
      imageIndex: _currentImageIndex,
      selectedColorValue: _selectedColor.toARGB32(),
      fillCount: _fillCount,
      rawWidth: _rawWidth,
      rawHeight: _rawHeight,
      rawFillBytes: _rawFillBytes,
      undoStack: List<Uint8List?>.from(_undoStack),
    );
  }

  _SessionMetaSnapshot _captureSessionMetaSnapshot() {
    return _SessionMetaSnapshot(
      currentImageIndex: _currentImageIndex,
      selectedColorValue: _selectedColor.toARGB32(),
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
          final _SessionSnapshot snapshot =
              _pendingImageSnapshots.remove(imageIndex)!;
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
      if (!_storageReady || _sessionMetaBox == null) return;
      if (snapshot.rawWidth <= 0 || snapshot.rawHeight <= 0) return;

      final File imageRawFile = _imageRawFile(snapshot.imageIndex);

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
        await _imageUndoRawFile(snapshot.imageIndex, i)
            .writeAsBytes(entry, flush: true);
      }

      final DateTime now = DateTime.now();
      final Map<String, dynamic> imageMeta = <String, dynamic>{
        'version': 2,
        'imageId': snapshot.imageIndex,
        'fillCount': snapshot.fillCount,
        'hasRawFill': snapshot.rawFillBytes != null,
        'rawWidth': snapshot.rawWidth,
        'rawHeight': snapshot.rawHeight,
        'undoKinds': undoKinds,
        'undoStackPointer': snapshot.undoStack.isEmpty
            ? -1
            : snapshot.undoStack.length - 1,
        'lastModified': now.toIso8601String(),
      };
      await _sessionMetaBox!.put(_imageMetaKey(snapshot.imageIndex), imageMeta);
    } catch (e) {
      _log('AUTOSAVE_IMAGE', 'ERROR: $e');
    }
  }

  Future<void> _persistSessionMetaSnapshot(_SessionMetaSnapshot snapshot) async {
    try {
      if (!_storageReady || _sessionMetaBox == null) return;
      final Map<String, dynamic> sessionMeta = <String, dynamic>{
        'version': 2,
        'currentImageIndex': snapshot.currentImageIndex,
        'selectedColor': snapshot.selectedColorValue,
        'lastModified': DateTime.now().toIso8601String(),
      };
      await _sessionMetaBox!.put(_sessionMetaKey, sessionMeta);
    } catch (e) {
      _log('AUTOSAVE_META', 'ERROR: $e');
    }
  }

  Future<ui.Image?> _buildCurrentImageFromSavedState() async {
    if (!_storageReady || _sessionMetaBox == null) {
      _rawFillBytes = null;
      _fillCount = 0;
      _undoStack.clear();
      return null;
    }

    final dynamic rawMeta = _sessionMetaBox!.get(_imageMetaKey(_currentImageIndex));
    if (rawMeta is Map) {
      try {
        final Map<dynamic, dynamic> meta = rawMeta;

        _fillCount = (meta['fillCount'] is int) ? meta['fillCount'] as int : 0;
        final bool hasRawFill = meta['hasRawFill'] == true;
        final int savedWidth =
            (meta['rawWidth'] is int) ? meta['rawWidth'] as int : _rawWidth;
        final int savedHeight =
            (meta['rawHeight'] is int) ? meta['rawHeight'] as int : _rawHeight;
        final List<int> undoKinds = (meta['undoKinds'] is List)
            ? (meta['undoKinds'] as List)
                .map((dynamic e) => (e is int) ? e : -1)
                .toList()
            : <int>[];
        final int undoStackPointer = (meta['undoStackPointer'] is int)
            ? meta['undoStackPointer'] as int
            : undoKinds.length - 1;

        final List<Uint8List?> restoredUndo = <Uint8List?>[];
        for (int i = 0; i < undoKinds.length; i++) {
          final int kind = undoKinds[i];
          if (kind == 0) {
            restoredUndo.add(null);
            continue;
          }
          if (kind == 1) {
            final File undoFile = _imageUndoRawFile(_currentImageIndex, i);
            if (!await undoFile.exists()) continue;
            final Uint8List rawUndo = await undoFile.readAsBytes();
            if (rawUndo.lengthInBytes == _rawWidth * _rawHeight * 4) {
              restoredUndo.add(rawUndo);
            }
          }
        }
        if (undoStackPointer >= 0 && undoStackPointer < restoredUndo.length) {
          restoredUndo.removeRange(undoStackPointer + 1, restoredUndo.length);
        }
        _undoStack
          ..clear()
          ..addAll(restoredUndo);

        if (hasRawFill && savedWidth == _rawWidth && savedHeight == _rawHeight) {
          final File imageRawFile = _imageRawFile(_currentImageIndex);
          if (await imageRawFile.exists()) {
            final Uint8List raw = await imageRawFile.readAsBytes();
            final int expectedLen = _rawWidth * _rawHeight * 4;
            if (raw.lengthInBytes == expectedLen) {
              _rawFillBytes = raw;
              pixelEngine.updateFromRawBytes(_rawFillBytes!, _rawWidth, _rawHeight);
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
    _undoStack.clear();
    return null;
  }

  Future<ui.Image> _decodeToUiImage(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<ui.Image> _rawRgbaToUiImage(Uint8List rgba, int width, int height) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
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
    _cachedScaleFit = (viewW / imgW < viewH / imgH) ? viewW / imgW : viewH / imgH;
    _cachedFitOffsetX = (viewW - imgW * _cachedScaleFit) / 2.0;
    _cachedFitOffsetY = (viewH - imgH * _cachedScaleFit) / 2.0;
  }

  void _replaceUiImage(ui.Image? nextImage) {
    if (identical(_uiImage, nextImage)) return;
    final ui.Image? old = _uiImage;
    _uiImage = nextImage;
    old?.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _autosaveTimer?.cancel();
    unawaited(_flushStorageOnDispose());
    _replaceUiImage(null);
    transformationController.dispose();
    super.dispose();
  }
}
