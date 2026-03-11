import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutterwork/core/storage/coloring_book_session_storage.dart';
import 'package:flutterwork/core/data/canvas_image_assets.dart';
import 'package:flutterwork/features/recording/controllers/paint_timelapse_controller.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../../engine/PixelEngine.dart';

void _log(String tag, String msg) {
  if (kDebugMode) {
    debugPrint('[COLOR_APP][$tag] $msg');
  }
}

enum PaintToolMode { fill, brush, eraser }

class _SessionSnapshot {
  final int imageIndex;
  final int selectedColorValue;
  final int fillCount;
  final int totalTimeSeconds;
  final int rawWidth;
  final int rawHeight;
  final Uint8List? rawFillBytes;
  final List<Uint8List?> undoStack;
  final List<Uint8List> timelapseFrames;

  const _SessionSnapshot({
    required this.imageIndex,
    required this.selectedColorValue,
    required this.fillCount,
    required this.totalTimeSeconds,
    required this.rawWidth,
    required this.rawHeight,
    required this.rawFillBytes,
    required this.undoStack,
    required this.timelapseFrames,
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

class _TimelapsePersistResult {
  final int totalFrameCount;
  final int archiveFrameCount;
  final int tailFrameCount;

  const _TimelapsePersistResult({
    required this.totalFrameCount,
    required this.archiveFrameCount,
    required this.tailFrameCount,
  });
}

class _ArchivedUndoEntry {
  final String? filePath;
  final bool isNullSnapshot;

  const _ArchivedUndoEntry._({
    required this.filePath,
    required this.isNullSnapshot,
  });

  const _ArchivedUndoEntry.nullSnapshot()
    : this._(filePath: null, isNullSnapshot: true);

  const _ArchivedUndoEntry.file(String path)
    : this._(filePath: path, isNullSnapshot: false);
}

class _ArchivedUndoReadResult {
  final bool found;
  final Uint8List? snapshot;

  const _ArchivedUndoReadResult({required this.found, required this.snapshot});
}

class BasicScreenController extends ChangeNotifier {
  static const int _maxRemovalSteps = 50;
  static const int _minUndoSteps = _maxRemovalSteps;
  static const int _maxUndoStepsHard = _maxRemovalSteps;
  static const int _undoBudgetBytes = 192 * 1024 * 1024;
  static const int _persistUndoBudgetBytes = 64 * 1024 * 1024;
  static const int _persistUndoHardLimit = _maxRemovalSteps;
  static const int _minTimelapseFrames = 24;
  static const int _maxTimelapseFramesHard = 1800;
  static const int _timelapseBudgetBytes = 256 * 1024 * 1024;
  static const int _sessionRestoreUndoMaxEntries = _maxRemovalSteps;
  static const int _sessionRestoreTimelapseMaxFrames = 24;

  /// Maximum total frames returned to the timelapse player for playback.
  /// Caps the merged archive + tail list so RAM usage is bounded regardless
  /// of how large the on-disk archive has grown.
  static const int _maxPlaybackFrames = 1800;

  /// Maximum frames kept in the archive file per image across all sessions.
  /// When the archive exceeds this, the oldest frames are dropped during the
  /// next autosave so disk usage stays bounded.
  static const int _maxArchiveFrames = 3600;
  static const int _floodFillIsolatePixelThreshold = 160000;
  static const int _progressScanIsolatePixelThreshold = 200000;

  // — Targeted rebuild notifiers —
  // Each notifier fires only when its specific slice of UI state changes.
  // basic_screen.dart listens to these individually instead of the whole controller.
  final ValueNotifier<bool> processingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> progressNotifier = ValueNotifier<int>(0);
  final ValueNotifier<Color> colorNotifier =
      ValueNotifier<Color>(const Color(0xFF000000));
  final ValueNotifier<String?> statusNotifier = ValueNotifier<String?>(null);

  DateTime? _startTime;
  int _accumulatedSeconds = 0;
  final String _sessionNamespace =
      ColoringBookSessionStorage.sessionNamespace;
  final String _sessionMetaKey = 'session_meta';
  final String _imageMetaKeyPrefix = 'image_meta_';
  final String _preparedMetaKeyPrefix = 'prepared_meta_';

  final PixelEngine pixelEngine = PixelEngine();
  final PaintTimelapseController _timelapse = PaintTimelapseController();
  final TransformationController transformationController =
      TransformationController();
  final bool _hasExplicitInitialImage;

  ui.Image? _uiImage;
  Uint8List? _rawFillBytes;

  int _rawWidth = 0;
  int _rawHeight = 0;

  final List<Uint8List?> _undoStack = <Uint8List?>[];
  final List<Uint8List?> _redoStack = <Uint8List?>[];
  int _targetUndoSteps = _minUndoSteps;

  int _fillCount = 0;
  Color _selectedColor = const Color(0xFFFFC107);
  PaintToolMode _activeTool = PaintToolMode.fill;
  bool _isProcessing = false;
  int _progressPercent = 0;
  int _currentImageIndex = 0;
  bool _engineReady = false;
  bool _showStartupLoader = true;
  bool _showImageTransitionLoader = false;
  int _imageLoadSeq = 0;
  bool _isImageLoading = false;
  int _queuedImageDelta = 0;
  bool _isPersisting = false;
  Future<void>? _saveLoopFuture;
  final Map<int, _SessionSnapshot> _pendingImageSnapshots =
      <int, _SessionSnapshot>{};
  _SessionMetaSnapshot? _pendingSessionMeta;
  final Map<int, List<_ArchivedUndoEntry>> _undoArchiveByImage =
      <int, List<_ArchivedUndoEntry>>{};
  int _undoArchiveSeq = 0;
  final Map<int, int> _timelapseArchivedFrameCountByImage = <int, int>{};
  final Map<int, Future<void>> _timelapseArchiveWriteChainByImage =
      <int, Future<void>>{};
  Future<void>? _storageInitFuture;
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
  final List<Color> _recentColors = <Color>[];
  final Map<int, int> _colorUseCount = <int, int>{};

  final List<String> _testImages = List<String>.from(CanvasImageAssets.all);

  BasicScreenController({String? initialImagePath, int? imageIndex})
    : _hasExplicitInitialImage =
          (initialImagePath != null || imageIndex != null) {
    // 1. Prioritize imageIndex from Gallery
    if (imageIndex != null) {
      _currentImageIndex = imageIndex;
    }
    // 2. Fallback to path if index isn't provided (e.g., coming from Explore)
    else if (initialImagePath != null) {
      final int selectedImageIndex = _testImages.indexOf(initialImagePath);
      if (selectedImageIndex >= 0) {
        _currentImageIndex = selectedImageIndex;
      }
    }

    _markColorRecent(_selectedColor);
    colorNotifier.value = _selectedColor;
  }

  ui.Image? get uiImage => _uiImage;
  Color get selectedColor => _selectedColor;
  PaintToolMode get activeTool => _activeTool;
  bool get isProcessing => _isProcessing;
  bool get engineReady => _engineReady;
  bool get showStartupLoader => _showStartupLoader;
  bool get showImageTransitionLoader => _showImageTransitionLoader;
  List<Color> get colorHistory => _colorHistory;
  bool get canUndo =>
      (_undoStack.isNotEmpty || _hasArchivedUndo(_currentImageIndex)) &&
      !_isProcessing &&
      _engineReady;
  bool get canRedo =>
      !_isProcessing && _engineReady && (_undoStack.isNotEmpty || _fillCount > 0);
  bool get canRefresh => !_isProcessing && _engineReady;
  bool get canPickColor => _engineReady;
  bool get hasTimelapseFrames =>
      _timelapse.hasFrames ||
      (_timelapseArchivedFrameCountByImage[_currentImageIndex] ?? 0) > 0;
  List<Uint8List> get timelapseFrames => _timelapse.getFrames();
  int get rawWidth => _rawWidth;
  int get rawHeight => _rawHeight;
  int get fillCount => _fillCount;
  int get progressPercent => _progressPercent;
  int get remainingPercent => 100 - _progressPercent;
  List<Color> get recentOrMostUsedColors => _buildSuggestedColors();
  String? _statusMessage;
  Timer? _messageTimer;

  String? get statusMessage => _statusMessage;

  void init() {
    _startTime = DateTime.now();
    final Future<void> storageInit = _prepareStorageAndInit();
    _storageInitFuture = storageInit;
    unawaited(storageInit);
  }

  Future<void> flushSessionState() async {
    _autosaveTimer?.cancel();
    _stopTrackingTime();
    await _awaitStorageInitialization();
    await _scheduleSessionSave();
  }

  void onAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(flushSessionState());
    }
    if (state == AppLifecycleState.paused) {
      _stopTrackingTime();
    } else if (state == AppLifecycleState.resumed) {
      _startTime = DateTime.now();
    }
  }

  void _stopTrackingTime() {
    if (_startTime != null) {
      _accumulatedSeconds += DateTime.now().difference(_startTime!).inSeconds;
      _startTime = null;
    }
  }

  int _trackedTimeSeconds() {
    if (_startTime == null) {
      return _accumulatedSeconds;
    }
    return _accumulatedSeconds + DateTime.now().difference(_startTime!).inSeconds;
  }

  void onViewportSizeChanged(Size newSize) {
    if (_containerSize != newSize) {
      _containerSize = newSize;
      _updateFitCache();
    }
  }

  void selectColor(Color color) {
    _selectedColor = color;
    _markColorRecent(color);
    colorNotifier.value = _selectedColor;
    _notify();
  }

  void setActiveTool(PaintToolMode tool) {
    if (_activeTool == tool) return;
    _activeTool = tool;
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
              colorNotifier.value = _selectedColor;
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
    await redo();
  }

  Future<void> redo() async {
    if (_isProcessing || !_engineReady) return;
    if (_undoStack.isEmpty) {
      if (_fillCount > 0) {
        _showTemporaryMessage(
          'Use Eraser. You have reached the 50-removal limit.',
        );
      }
      return;
    }

    _isProcessing = true;
    processingNotifier.value = true;
    _notify();
    try {
      final Uint8List? snapshot = _undoStack.removeLast();
      // Branch-aware timelapse: undo moves the timelapse pointer backwards.
      // We do NOT record a new frame for undo itself. If the user undoes all
      // the way back to the original image, we reset the timelapse (and delete
      // any persisted timelapse frames) so new fills start a fresh history.
      _timelapse.stepBackward();
      if (_fillCount > 0) {
        _fillCount--;
      }

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

        // User is back at the original image: drop all previous timelapse
        // history (including on-disk archived/tail frames) so the next fills
        // record a new timelapse from scratch.
        await _clearTimelapseArchiveForImage(_currentImageIndex);
        await _clearTimelapseTailForImage(_currentImageIndex);
        _timelapse.start();
        _timelapse.recordFrame(originalRaw);
      } else {
        _rawFillBytes = snapshot;
        pixelEngine.updateFromRawBytes(snapshot, _rawWidth, _rawHeight);
        restoredImage = await _rawRgbaToUiImage(
          snapshot,
          _rawWidth,
          _rawHeight,
        );
      }
      _recomputeProgressPercent();

      if (_disposed) {
        restoredImage.dispose();
        return;
      }

      _replaceUiImage(restoredImage);
      _isProcessing = false;
      processingNotifier.value = false;
      progressNotifier.value = _progressPercent;
      _notify();
      _requestAutosave(immediate: true);
    } catch (e) {
      _log('REDO', 'ERROR: $e');
      _isProcessing = false;
      processingNotifier.value = false;
      _notify();
    }
  }

  void _showTemporaryMessage(String message) {
    _messageTimer?.cancel();
    _statusMessage = message;
    statusNotifier.value = _statusMessage;
    _notify();

    _messageTimer = Timer(const Duration(seconds: 5), () {
      _statusMessage = null;
      statusNotifier.value = null;
      _notify();
    });
  }

  Future<void> refreshCurrentImage() async {
    if (_isProcessing) return;
    try {
      if (_storageReady) {
        final File rawFile = _imageRawFile(_currentImageIndex);
        int undoEntryCount = 0;
        if (_sessionMetaBox != null) {
          final dynamic rawMeta = _sessionMetaBox!.get(
            _imageMetaKey(_currentImageIndex),
          );
          if (rawMeta is Map && rawMeta['undoKinds'] is List) {
            undoEntryCount = (rawMeta['undoKinds'] as List).length;
          }
          await _sessionMetaBox!.delete(_imageMetaKey(_currentImageIndex));
        }
        if (await rawFile.exists()) await rawFile.delete();
        for (int i = 0; i < undoEntryCount; i++) {
          final File undoFile = _imageUndoRawFile(_currentImageIndex, i);
          if (await undoFile.exists()) {
            await undoFile.delete();
          }
        }
        await _deleteAllUndoFilesForImage(_currentImageIndex);
        await _clearUndoArchiveForImage(_currentImageIndex);
        await _clearTimelapseArchiveForImage(_currentImageIndex);
        final File timelapseFile = _imageTimelapseRawFile(_currentImageIndex);
        if (await timelapseFile.exists()) {
          await timelapseFile.delete();
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

    final int pixelIndex = (pixelY * _rawWidth) + pixelX;
    if (_activeTool == PaintToolMode.fill &&
        pixelEngine.borderMask.lengthInBytes > pixelIndex &&
        pixelEngine.borderMask[pixelIndex] == 1) {
      _showTemporaryMessage('Fill cannot start on the border.');
      return;
    }

    _isProcessing = true;
    processingNotifier.value = true;
    _notify();

      try {
        final Uint8List baseRaw = _rawFillBytes ?? pixelEngine.originalRawRgba;

      final FloodFillRequest request = FloodFillRequest(
          rawRgbaBytes: baseRaw,
          borderMask: pixelEngine.borderMask,
          x: pixelX,
          y: pixelY,
          width: _rawWidth,
          height: _rawHeight,
          fillR: _to8Bit(
            (_activeTool == PaintToolMode.eraser
                    ? Colors.white
                    : _selectedColor)
                .r,
          ),
          fillG: _to8Bit(
            (_activeTool == PaintToolMode.eraser
                    ? Colors.white
                    : _selectedColor)
                .g,
          ),
          fillB: _to8Bit(
            (_activeTool == PaintToolMode.eraser
                    ? Colors.white
                    : _selectedColor)
                .b,
          ),
      );

      final int pixelCount = _rawWidth * _rawHeight;
      final Map<String, Object> floodFillResult = pixelCount >=
              _floodFillIsolatePixelThreshold
          ? await compute<FloodFillRequest, Map<String, Object>>(
              PixelEngine.processFloodFillToMap,
              request,
            )
          : PixelEngine.processFloodFillToMap(request);

      final Uint8List rawResult = floodFillResult['raw'] as Uint8List;
      final bool didChangePixels = floodFillResult['changed'] as bool;
      if (!didChangePixels) {
        _isProcessing = false;
        processingNotifier.value = false;
        _notify();
        return;
      }

      _fillCount++;
      _growUndoTargetForAction();
      _pushUndoSnapshot(_rawFillBytes);
      _redoStack.clear();
      _rawFillBytes = rawResult;
      pixelEngine.updateFromRawBytes(rawResult, _rawWidth, _rawHeight);
      final Uint8List? evictedFrame = _timelapse.recordFrame(_rawFillBytes!);
      if (evictedFrame != null) {
        _enqueueTimelapseArchivedFrame(_currentImageIndex, evictedFrame);
      }
      _recomputeProgressPercent();
      if (didChangePixels && _activeTool != PaintToolMode.eraser) {
        _markColorRecent(_selectedColor, incrementUsage: true);
      }

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
      processingNotifier.value = false;
      progressNotifier.value = _progressPercent;
      colorNotifier.value = _selectedColor;
      _notify();
      _requestAutosave(immediate: true);
    } catch (e) {
      _log('FILL', 'ERROR: $e');
      _isProcessing = false;
      processingNotifier.value = false;
      _notify();
    }
  }

  Future<void> loadImage({bool restoreSavedState = true}) async {
    final Stopwatch loadPerfWatch = Stopwatch()..start();
    final int loadSeq = ++_imageLoadSeq;
    final int imageIndexAtLoad = _currentImageIndex;
    final String assetPathAtLoad = _testImages[imageIndexAtLoad];
    ui.Image? preview;
    _log(
      'LOAD_PERF',
      'START seq=$loadSeq image=$imageIndexAtLoad restore=$restoreSavedState asset=$assetPathAtLoad',
    );
    unawaited(_clearUndoArchiveForImage(imageIndexAtLoad));
    _isImageLoading = true;
    _engineReady = false;
    _showImageTransitionLoader = !_showStartupLoader && _uiImage != null;
    processingNotifier.value = true;
    _notify();

    try {
      final ByteData data = await rootBundle.load(assetPathAtLoad);
      if (_disposed || loadSeq != _imageLoadSeq) return;
      final Uint8List bytes = data.buffer.asUint8List();
      _log(
        'LOAD_PERF',
        'asset_read bytes=${bytes.lengthInBytes} elapsed=${loadPerfWatch.elapsedMilliseconds}ms',
      );

      preview = await _decodeToUiImage(bytes);
      if (_disposed || loadSeq != _imageLoadSeq) {
        preview.dispose();
        preview = null;
        return;
      }
      _log(
        'LOAD_PERF',
        'preview_decoded size=${preview.width}x${preview.height} elapsed=${loadPerfWatch.elapsedMilliseconds}ms',
      );

      _rawWidth = preview.width;
      _rawHeight = preview.height;
      transformationController.value = Matrix4.identity();
      _updateFitCache();

      await Future<void>.delayed(Duration.zero);
      if (_disposed || loadSeq != _imageLoadSeq) return;

      final Map<String, Object> prepared = await _loadOrPrepareImageData(
        imageIndexAtLoad,
        assetPathAtLoad,
        bytes,
      );
      if (_disposed || loadSeq != _imageLoadSeq) return;
      _log(
        'LOAD_PERF',
        'prepared_ready elapsed=${loadPerfWatch.elapsedMilliseconds}ms',
      );

      pixelEngine.applyPreparedImage(prepared);
      if (!pixelEngine.isLoaded) {
        throw StateError('Failed to decode image: $assetPathAtLoad');
      }

      _rawWidth = pixelEngine.imageWidth;
      _rawHeight = pixelEngine.imageHeight;
      _undoStack.clear();
      _redoStack.clear();

      final Stopwatch restorePerfWatch = Stopwatch()..start();
      final ui.Image? loaded = restoreSavedState
          ? await _buildCurrentImageFromSavedState()
          : null;
      if (restoreSavedState) {
        _log(
          'LOAD_PERF',
          'restore_done elapsed=${restorePerfWatch.elapsedMilliseconds}ms',
        );
      }
      if (_disposed || loadSeq != _imageLoadSeq) {
        loaded?.dispose();
        return;
      }

      if (!restoreSavedState) {
        _rawFillBytes = null;
        _fillCount = 0;
        _accumulatedSeconds = 0;
        _targetUndoSteps = _minUndoSteps;
        _undoStack.clear();
        _redoStack.clear();
        _timelapseArchivedFrameCountByImage[_currentImageIndex] = 0;
      }

      final ui.Image nextImage = loaded ?? preview;
      if (loaded == null) {
        preview = null;
      } else {
        preview.dispose();
        preview = null;
      }
      _replaceUiImage(nextImage);
      transformationController.value = Matrix4.identity();
      _updateFitCache();
      if (restoreSavedState && _timelapse.hasFrames) {
        _timelapse.resume();
      } else {
        _timelapse.start();
        final Uint8List? evictedFrame = _timelapse.recordFrame(
          _rawFillBytes ?? pixelEngine.originalRawRgba,
        );
        if (evictedFrame != null) {
          _enqueueTimelapseArchivedFrame(_currentImageIndex, evictedFrame);
        }
      }
      _updateDynamicHistoryCaps();
      _recomputeProgressPercent();

      _engineReady = true;
      _showStartupLoader = false;
      _showImageTransitionLoader = false;
      processingNotifier.value = false;
      progressNotifier.value = _progressPercent;
      colorNotifier.value = _selectedColor;
      statusNotifier.value = null;
      _notify();
      _log(
        'LOAD_PERF',
        'COMPLETE seq=$loadSeq image=$imageIndexAtLoad total=${loadPerfWatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      _log('LOAD', 'ERROR: $e');
      _log(
        'LOAD_PERF',
        'FAIL seq=$loadSeq image=$imageIndexAtLoad elapsed=${loadPerfWatch.elapsedMilliseconds}ms error=$e',
      );
      if (!_disposed && loadSeq == _imageLoadSeq) {
        _engineReady = false;
        _showStartupLoader = false;
        _showImageTransitionLoader = false;
        processingNotifier.value = false;
        _notify();
      }
    } finally {
      preview?.dispose();
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
    final double currentScale = transformationController.value
        .getMaxScaleOnAxis();
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
      _sessionDirectory =
          await ColoringBookSessionStorage.ensureSessionDirectory();
      _sessionMetaBox = await ColoringBookSessionStorage.ensureMetaBox();
      _storageReady = true;
    } catch (e) {
      _log('STORAGE_INIT', 'ERROR: $e');
      _storageReady = false;
    }

    await _initWithRestore();
  }

  Future<void> _awaitStorageInitialization() async {
    final Future<void>? pending = _storageInitFuture;
    if (pending == null) {
      return;
    }
    try {
      await pending;
    } catch (_) {
      // Storage readiness is handled by _storageReady and persist guards.
    }
  }

  Future<void> _flushStorageOnDispose() async {
    if (!_storageReady) return;
    await _flushAllTimelapseArchiveWrites();
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

  File _imageTimelapseRawFile(int imageIndex) => File(
    '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.image_${imageIndex}_timelapse.raw',
  );

  File _imageTimelapseArchiveRawFile(int imageIndex) => File(
    '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.image_${imageIndex}_timelapse_archive.raw',
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
      final dynamic rawMeta = _sessionMetaBox!.get(
        _preparedMetaKey(imageIndex),
      );
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

      final List<Uint8List> preparedBytes = await Future.wait<Uint8List>(
        <Future<Uint8List>>[rawFile.readAsBytes(), maskFile.readAsBytes()],
      );
      final Uint8List raw = preparedBytes[0];
      final Uint8List borderMask = preparedBytes[1];
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
      await _sessionMetaBox!
          .put(_preparedMetaKey(imageIndex), <String, dynamic>{
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

    final Map<String, Object> generated =
        await compute<Uint8List, Map<String, Object>>(
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
      if (!_storageReady || _sessionMetaBox == null) return false;
      final dynamic rawMeta = _sessionMetaBox!.get(_sessionMetaKey);
      if (rawMeta is! Map) return false;
      final Map<dynamic, dynamic> meta = rawMeta;

      final int restoredIndex = (meta['currentImageIndex'] is int)
          ? meta['currentImageIndex'] as int
          : 0;
      if (!_hasExplicitInitialImage) {
        if (restoredIndex < 0 || restoredIndex >= _testImages.length) {
          return false;
        }
        _currentImageIndex = restoredIndex;
      }

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
      totalTimeSeconds: _trackedTimeSeconds(),
      rawWidth: _rawWidth,
      rawHeight: _rawHeight,
      rawFillBytes: _rawFillBytes,
      undoStack: _buildUndoStackForPersistence(),
      timelapseFrames: _timelapse.getFrames(),
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

  Future<void> _requestAutosave({bool immediate = false}) async {
    _stopTrackingTime();
    _startTime = DateTime.now();

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
    await _awaitStorageInitialization();
    while (true) {
      final Future<void>? pending = _saveLoopFuture;
      if (pending != null) {
        await pending;
      } else {
        final Future<void> saveLoop = _drainPendingSessionSaves();
        _saveLoopFuture = saveLoop;
        try {
          await saveLoop;
        } finally {
          if (identical(_saveLoopFuture, saveLoop)) {
            _saveLoopFuture = null;
          }
        }
      }

      if (_pendingImageSnapshots.isEmpty && _pendingSessionMeta == null) {
        return;
      }
    }
  }

  Future<void> _drainPendingSessionSaves() async {
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
      if (!_storageReady || _sessionMetaBox == null) return;
      if (snapshot.rawWidth <= 0 || snapshot.rawHeight <= 0) return;

      final File imageRawFile = _imageRawFile(snapshot.imageIndex);

      if (snapshot.rawFillBytes != null) {
        await imageRawFile.writeAsBytes(snapshot.rawFillBytes!, flush: true);
      } else if (await imageRawFile.exists()) {
        await imageRawFile.delete();
      }

      int previousUndoCount = 0;
      final dynamic previousMeta = _sessionMetaBox!.get(
        _imageMetaKey(snapshot.imageIndex),
      );
      if (previousMeta is Map && previousMeta['undoKinds'] is List) {
        previousUndoCount = (previousMeta['undoKinds'] as List).length;
      }
      if (previousUndoCount > snapshot.undoStack.length) {
        for (int i = snapshot.undoStack.length; i < previousUndoCount; i++) {
          final File undoFile = _imageUndoRawFile(snapshot.imageIndex, i);
          if (await undoFile.exists()) {
            await undoFile.delete();
          }
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
	      final _TimelapsePersistResult timelapsePersistResult =
	          await _persistTimelapseFrames(snapshot);

	      final DateTime now = DateTime.now();
	      int progressPercent = 0;

	      if (snapshot.rawFillBytes != null) {
	        final int pixelCount = snapshot.rawWidth * snapshot.rawHeight;
	        if (pixelCount >= _progressScanIsolatePixelThreshold) {
	          progressPercent = await compute<FillPercentageRequest, int>(
	            PixelEngine.computeProgressPercent,
	            FillPercentageRequest(
	              currentRawRgba: snapshot.rawFillBytes!,
	              originalRawRgba: pixelEngine.originalRawRgba,
	              borderMask: pixelEngine.borderMask,
	            ),
	          );
	        } else {
	          progressPercent = PixelEngine.computeProgressPercent(
	            FillPercentageRequest(
	              currentRawRgba: snapshot.rawFillBytes!,
	              originalRawRgba: pixelEngine.originalRawRgba,
	              borderMask: pixelEngine.borderMask,
	            ),
	          );
	        }
	      }
	      final Map<String, dynamic> imageMeta = <String, dynamic>{
	        'version': 2,
	        'imageId': snapshot.imageIndex,
        'fillCount': snapshot.fillCount,
        'totalTimeSeconds': snapshot.totalTimeSeconds,
	        'hasRawFill': snapshot.rawFillBytes != null,
	        'rawWidth': snapshot.rawWidth,
	        'rawHeight': snapshot.rawHeight,
	        'progressPercent': progressPercent.clamp(0, 100),
	        'undoKinds': undoKinds,
	        'timelapseFrameCount': timelapsePersistResult.totalFrameCount,
	        'timelapseArchiveFrameCount': timelapsePersistResult.archiveFrameCount,
	        'timelapseTailFrameCount': timelapsePersistResult.tailFrameCount,
        'undoStackPointer': snapshot.undoStack.isEmpty
            ? -1
            : snapshot.undoStack.length - 1,
        'lastSaved': now.toIso8601String(),
        'lastModified': now.toIso8601String(),
      };
      if (snapshot.rawFillBytes != null) {
        final Uint8List? png = await pixelEngine.getEncodedPng(
          snapshot.rawFillBytes!,
          snapshot.rawWidth,
          snapshot.rawHeight,
        );

        if (png != null) {
          final File previewFile = File(
            '${_sessionDirectory.path}/preview_${snapshot.imageIndex}.png',
          );

          await previewFile.writeAsBytes(png, flush: true);
        }
      }
      await _sessionMetaBox!.put(_imageMetaKey(snapshot.imageIndex), imageMeta);
    } catch (e) {
      _log('AUTOSAVE_IMAGE', 'ERROR: $e');
    }
  }

  Future<_TimelapsePersistResult> _persistTimelapseFrames(
    _SessionSnapshot snapshot,
  ) async {
    final int frameBytes = snapshot.rawWidth * snapshot.rawHeight * 4;
    if (frameBytes <= 0) {
      return const _TimelapsePersistResult(
        totalFrameCount: 0,
        archiveFrameCount: 0,
        tailFrameCount: 0,
      );
    }

    await _flushTimelapseArchiveWrites(snapshot.imageIndex);

    final List<Uint8List> validFrames = snapshot.timelapseFrames
        .where((Uint8List frame) => frame.lengthInBytes == frameBytes)
        .toList(growable: false);
    final File timelapseFile = _imageTimelapseRawFile(snapshot.imageIndex);
    final File archiveFile = _imageTimelapseArchiveRawFile(snapshot.imageIndex);
    int archiveFrameCount = await _frameCountFromRawFile(
      archiveFile,
      frameBytes,
    );
    final int migratedPrefixFrames = await _archiveExistingTimelapsePrefix(
      imageIndex: snapshot.imageIndex,
      frameBytes: frameBytes,
      keepLastFrames: validFrames.length,
    );
    if (migratedPrefixFrames > 0) {
      archiveFrameCount += migratedPrefixFrames;
      _log(
        'TIMELAPSE_SAVE',
        'archived_tail_prefix image=${snapshot.imageIndex} migrated=$migratedPrefixFrames',
      );
    }
    _timelapseArchivedFrameCountByImage[snapshot.imageIndex] =
        archiveFrameCount;

    // Trim archive if it has grown beyond _maxArchiveFrames.
    // This keeps disk usage bounded across many sessions.
    if (archiveFrameCount > _maxArchiveFrames) {
      final int trimmedCount = await _trimTimelapseArchiveToLastFrames(
        imageIndex: snapshot.imageIndex,
        frameBytes: frameBytes,
        keepLastFrames: _maxArchiveFrames,
      );
      _timelapseArchivedFrameCountByImage[snapshot.imageIndex] = trimmedCount;
      archiveFrameCount = trimmedCount;
      _log(
        'TIMELAPSE_ARCHIVE_TRIM',
        'image=${snapshot.imageIndex} kept=$trimmedCount',
      );
    }

    if (validFrames.isEmpty) {
      if (archiveFrameCount == 0) {
        if (await timelapseFile.exists()) {
          await timelapseFile.delete();
        }
        return const _TimelapsePersistResult(
          totalFrameCount: 0,
          archiveFrameCount: 0,
          tailFrameCount: 0,
        );
      }
      if (await timelapseFile.exists()) {
        await timelapseFile.delete();
      }
      return _TimelapsePersistResult(
        totalFrameCount: archiveFrameCount,
        archiveFrameCount: archiveFrameCount,
        tailFrameCount: 0,
      );
    }

    final IOSink sink = timelapseFile.openWrite();
    for (final Uint8List frame in validFrames) {
      sink.add(frame);
    }
    await sink.flush();
    await sink.close();
    return _TimelapsePersistResult(
      totalFrameCount: archiveFrameCount + validFrames.length,
      archiveFrameCount: archiveFrameCount,
      tailFrameCount: validFrames.length,
    );
  }

  Future<int> _archiveExistingTimelapsePrefix({
    required int imageIndex,
    required int frameBytes,
    required int keepLastFrames,
  }) async {
    if (!_storageReady || frameBytes <= 0 || keepLastFrames <= 0) {
      return 0;
    }

    final File tailFile = _imageTimelapseRawFile(imageIndex);
    if (!await tailFile.exists()) {
      return 0;
    }

    final int existingTailFrames = await _frameCountFromRawFile(
      tailFile,
      frameBytes,
    );
    final int framesToArchive = existingTailFrames - keepLastFrames;
    if (framesToArchive <= 0) {
      return 0;
    }

    final int bytesToArchive = framesToArchive * frameBytes;
    final File archiveFile = _imageTimelapseArchiveRawFile(imageIndex);
    final IOSink archiveSink = archiveFile.openWrite(mode: FileMode.append);
    try {
      await for (final List<int> chunk in tailFile.openRead(
        0,
        bytesToArchive,
      )) {
        archiveSink.add(chunk);
      }
      await archiveSink.flush();
      return framesToArchive;
    } catch (e) {
      _log('TIMELAPSE_ARCHIVE_PREFIX', 'ERROR: $e');
      return 0;
    } finally {
      await archiveSink.close();
    }
  }

  Future<void> _persistSessionMetaSnapshot(
    _SessionMetaSnapshot snapshot,
  ) async {
    try {
      if (!_storageReady || _sessionMetaBox == null) return;
      final Map<String, dynamic> sessionMeta = <String, dynamic>{
        'version': 2,
        'currentImageIndex': snapshot.currentImageIndex,
        'selectedColor': snapshot.selectedColorValue,
        'lastModified': DateTime.now().toIso8601String(),
      };
      await _sessionMetaBox!.put(_sessionMetaKey, sessionMeta);
      await _sessionMetaBox!.flush();
    } catch (e) {
      _log('AUTOSAVE_META', 'ERROR: $e');
    }
  }

  Future<ui.Image?> _buildCurrentImageFromSavedState() async {
    final Stopwatch restorePerfWatch = Stopwatch()..start();
    if (!_storageReady || _sessionMetaBox == null) {
      _rawFillBytes = null;
      _fillCount = 0;
      _accumulatedSeconds = 0;
      _targetUndoSteps = _minUndoSteps;
      _undoStack.clear();
      _redoStack.clear();
      _timelapse.clear();
      _timelapseArchivedFrameCountByImage[_currentImageIndex] = 0;
      _log(
        'RESTORE_PERF',
        'SKIP image=$_currentImageIndex reason=storage_not_ready elapsed=${restorePerfWatch.elapsedMilliseconds}ms',
      );
      return null;
    }

    final dynamic rawMeta = _sessionMetaBox!.get(
      _imageMetaKey(_currentImageIndex),
    );
    if (rawMeta is Map) {
      try {
        final Map<dynamic, dynamic> meta = rawMeta;

        _fillCount = (meta['fillCount'] is int) ? meta['fillCount'] as int : 0;
        _accumulatedSeconds = (meta['totalTimeSeconds'] is int)
            ? meta['totalTimeSeconds'] as int
            : 0;
        final bool hasRawFill = meta['hasRawFill'] == true;
        final int savedWidth = (meta['rawWidth'] is int)
            ? meta['rawWidth'] as int
            : _rawWidth;
        final int savedHeight = (meta['rawHeight'] is int)
            ? meta['rawHeight'] as int
            : _rawHeight;
        final int expectedFrameBytes = _rawWidth * _rawHeight * 4;
        final List<int> undoKinds = (meta['undoKinds'] is List)
            ? (meta['undoKinds'] as List)
                  .map((dynamic e) => (e is int) ? e : -1)
                  .toList()
            : <int>[];
        final int undoStackPointer = (meta['undoStackPointer'] is int)
            ? meta['undoStackPointer'] as int
            : undoKinds.length - 1;
        final int timelapseArchiveFrameCount =
            (meta['timelapseArchiveFrameCount'] is int)
            ? meta['timelapseArchiveFrameCount'] as int
            : 0;
        final int resolvedArchiveFrameCount = timelapseArchiveFrameCount > 0
            ? timelapseArchiveFrameCount
            : await _frameCountFromRawFile(
                _imageTimelapseArchiveRawFile(_currentImageIndex),
                expectedFrameBytes,
              );
        _timelapseArchivedFrameCountByImage[_currentImageIndex] =
            resolvedArchiveFrameCount;
        _log(
          'RESTORE_PERF',
          'meta image=$_currentImageIndex fill=$_fillCount undoKinds=${undoKinds.length} '
              'undoPointer=$undoStackPointer archivedFrames=$resolvedArchiveFrameCount '
              'elapsed=${restorePerfWatch.elapsedMilliseconds}ms',
        );

        final int undoEndExclusive = undoStackPointer >= 0
            ? math.min(undoKinds.length, undoStackPointer + 1)
            : 0;
        final int undoStartIndex = math.max(
          0,
          undoEndExclusive - _sessionRestoreUndoMaxEntries,
        );
        final List<int> undoWindow = undoStartIndex < undoEndExclusive
            ? undoKinds.sublist(undoStartIndex, undoEndExclusive)
            : <int>[];

        final Future<List<Uint8List>?> timelapseFuture =
            _readTimelapseFramesFromImageMeta(
              meta,
              imageIndex: _currentImageIndex,
              width: _rawWidth,
              height: _rawHeight,
              maxFramesToRestore: _sessionRestoreTimelapseMaxFrames,
            );

        final Stopwatch undoPerfWatch = Stopwatch()..start();
        final int expectedUndoBytes = expectedFrameBytes;
        final Map<int, Future<Uint8List?>> undoReadFutures =
            <int, Future<Uint8List?>>{};
        for (int i = 0; i < undoWindow.length; i++) {
          if (undoWindow[i] == 1) {
            final int persistedUndoIndex = undoStartIndex + i;
            undoReadFutures[i] = _readUndoEntry(
              imageIndex: _currentImageIndex,
              undoIndex: persistedUndoIndex,
              expectedBytes: expectedUndoBytes,
            );
          }
        }
        final Map<int, Uint8List?> undoReadResults = <int, Uint8List?>{};
        if (undoReadFutures.isNotEmpty) {
          final List<MapEntry<int, Uint8List?>> resolved =
              await Future.wait<MapEntry<int, Uint8List?>>(
                undoReadFutures.entries.map((
                  MapEntry<int, Future<Uint8List?>> entry,
                ) async {
                  return MapEntry<int, Uint8List?>(
                    entry.key,
                    await entry.value,
                  );
                }),
              );
          for (final MapEntry<int, Uint8List?> entry in resolved) {
            undoReadResults[entry.key] = entry.value;
          }
        }

        final List<Uint8List?> restoredUndo = <Uint8List?>[];
        for (int i = 0; i < undoWindow.length; i++) {
          final int kind = undoWindow[i];
          if (kind == 0) {
            restoredUndo.add(null);
            continue;
          }
          if (kind == 1) {
            final Uint8List? rawUndo = undoReadResults[i];
            if (rawUndo != null) {
              restoredUndo.add(rawUndo);
            }
          }
        }
        _undoStack
          ..clear()
          ..addAll(restoredUndo);
        _targetUndoSteps = math.max(_minUndoSteps, _undoStack.length + 1);
        _updateDynamicHistoryCaps();
        _redoStack.clear();
        _log(
          'RESTORE_PERF',
          'undo_restored count=${restoredUndo.length} window=${undoWindow.length}/$undoEndExclusive '
              'start=$undoStartIndex elapsed=${undoPerfWatch.elapsedMilliseconds}ms',
        );

        final Stopwatch timelapsePerfWatch = Stopwatch()..start();
        final List<Uint8List>? restoredFrames = await timelapseFuture;
        if (restoredFrames != null) {
          _timelapse.replaceFrames(restoredFrames);
        } else {
          _timelapse.clear();
        }
        _log(
          'RESTORE_PERF',
          'timelapse_tail_restored=${restoredFrames?.length ?? 0} '
              'cap=$_sessionRestoreTimelapseMaxFrames elapsed=${timelapsePerfWatch.elapsedMilliseconds}ms',
        );

        if (hasRawFill &&
            savedWidth == _rawWidth &&
            savedHeight == _rawHeight) {
          final Stopwatch rawPerfWatch = Stopwatch()..start();
          final File imageRawFile = _imageRawFile(_currentImageIndex);
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
              _ensureTimelapseEndsWith(_rawFillBytes!);
              final ui.Image restoredImage = await _rawRgbaToUiImage(
                _rawFillBytes!,
                _rawWidth,
                _rawHeight,
              );
              _log(
                'RESTORE_PERF',
                'raw_fill_restored bytes=${raw.lengthInBytes} '
                    'rawElapsed=${rawPerfWatch.elapsedMilliseconds}ms '
                    'total=${restorePerfWatch.elapsedMilliseconds}ms',
              );
              return restoredImage;
            }
          }
          _log(
            'RESTORE_PERF',
            'raw_fill_missing_or_mismatch elapsed=${rawPerfWatch.elapsedMilliseconds}ms',
          );
        }

        _log(
          'RESTORE_PERF',
          'NO_RAW_FILL image=$_currentImageIndex total=${restorePerfWatch.elapsedMilliseconds}ms',
        );
      } catch (e) {
        _log('RESTORE_IMAGE', 'ERROR: $e');
        _log(
          'RESTORE_PERF',
          'FAIL image=$_currentImageIndex elapsed=${restorePerfWatch.elapsedMilliseconds}ms error=$e',
        );
      }
    }

    _rawFillBytes = null;
    _fillCount = 0;
    _accumulatedSeconds = 0;
    _targetUndoSteps = _minUndoSteps;
    _undoStack.clear();
    _redoStack.clear();
    _timelapse.clear();
    _timelapseArchivedFrameCountByImage[_currentImageIndex] = 0;
    _recomputeProgressPercent();
    _log(
      'RESTORE_PERF',
      'EMPTY_STATE image=$_currentImageIndex total=${restorePerfWatch.elapsedMilliseconds}ms',
    );
    return null;
  }

  Future<File?> exportCurrentImagePng() async {
    final ui.Image? image = _uiImage;
    if (image == null) return null;

    final ByteData? pngData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (pngData == null) return null;

    final Directory tempDir = await getTemporaryDirectory();
    final File output = File(
      '${tempDir.path}${Platform.pathSeparator}color_fill_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await output.writeAsBytes(pngData.buffer.asUint8List(), flush: true);
    return output;
  }

  Future<List<Uint8List>> loadTimelapseFramesForPlayback() async {
    final List<Uint8List> liveFrames = _timelapse.getFrames();
    final int frameBytes = _rawWidth * _rawHeight * 4;
    if (!_storageReady || frameBytes <= 0) {
      // No storage — return live frames capped to _maxPlaybackFrames.
      if (liveFrames.length <= _maxPlaybackFrames) return liveFrames;
      return liveFrames.sublist(liveFrames.length - _maxPlaybackFrames);
    }

    await _flushTimelapseArchiveWrites(_currentImageIndex);

    // Resolve the best tail: prefer live frames if they are at least as long
    // as what is persisted (live is always fresher).
    final List<Uint8List> persistedTailFrames = await _readFramesFromRawFile(
      _imageTimelapseRawFile(_currentImageIndex),
      frameBytes,
    );
    final List<Uint8List> tailFrames =
        liveFrames.length >= persistedTailFrames.length
        ? liveFrames
        : persistedTailFrames;

    // How many archive frames can we include without exceeding the playback cap?
    final int archiveSlots =
        (_maxPlaybackFrames - tailFrames.length).clamp(0, _maxPlaybackFrames);

    List<Uint8List> archivedFrames = const <Uint8List>[];
    if (archiveSlots > 0) {
      // Read only the last `archiveSlots` frames from the archive file using
      // openRead(start, end) — avoids reading the whole file into RAM.
      archivedFrames = await _readLastFramesFromRawFile(
        _imageTimelapseArchiveRawFile(_currentImageIndex),
        frameBytes,
        archiveSlots,
      );
    }

    if (archivedFrames.isEmpty) {
      return tailFrames;
    }
    if (tailFrames.isEmpty) {
      return archivedFrames;
    }

    return <Uint8List>[...archivedFrames, ...tailFrames];
  }

  Future<Uint8List?> _readUndoEntry({
    required int imageIndex,
    required int undoIndex,
    required int expectedBytes,
  }) async {
    final File undoFile = _imageUndoRawFile(imageIndex, undoIndex);
    if (!await undoFile.exists()) return null;
    final Uint8List rawUndo = await undoFile.readAsBytes();
    if (rawUndo.lengthInBytes != expectedBytes) return null;
    return rawUndo;
  }

  void _ensureTimelapseEndsWith(Uint8List targetRaw) {
    final List<Uint8List> frames = _timelapse.getFrames();
    if (frames.isEmpty) return;

    final Uint8List last = frames.last;
    if (_rawEquals(last, targetRaw)) return;

    final List<Uint8List> merged = List<Uint8List>.from(frames);
    merged.add(Uint8List.fromList(targetRaw));
    _timelapse.replaceFrames(merged);
  }

  bool _rawEquals(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.lengthInBytes != b.lengthInBytes) return false;
    for (int i = 0; i < a.lengthInBytes; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _growUndoTargetForAction() {
    _targetUndoSteps = math.min(_maxUndoStepsHard, _targetUndoSteps + 1);
  }

  int _runtimeUndoLimit() {
    final int frameBytes = _rawWidth * _rawHeight * 4;
    if (frameBytes <= 0) {
      return _targetUndoSteps.clamp(_minUndoSteps, _maxUndoStepsHard);
    }
    final int memoryCap = (_undoBudgetBytes ~/ frameBytes).clamp(
      _minUndoSteps,
      _maxUndoStepsHard,
    );
    if (_targetUndoSteps > memoryCap) {
      _targetUndoSteps = memoryCap;
    }
    return _targetUndoSteps.clamp(_minUndoSteps, memoryCap);
  }

  int _persistUndoLimit() {
    final int frameBytes = _rawWidth * _rawHeight * 4;
    if (frameBytes <= 0) {
      return _minUndoSteps;
    }
    return (_persistUndoBudgetBytes ~/ frameBytes).clamp(
      _minUndoSteps,
      _persistUndoHardLimit,
    );
  }

  List<Uint8List?> _buildUndoStackForPersistence() {
    if (_undoStack.isEmpty) return <Uint8List?>[];
    final int limit = _persistUndoLimit();
    if (_undoStack.length <= limit) {
      return List<Uint8List?>.from(_undoStack);
    }
    return List<Uint8List?>.from(_undoStack.sublist(_undoStack.length - limit));
  }

  Future<void> _deleteAllUndoFilesForImage(int imageIndex) async {
    final String prefix = '$_sessionNamespace.image_${imageIndex}_undo_';
    await for (final FileSystemEntity entity in _sessionDirectory.list(
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final List<String> parts = entity.uri.pathSegments;
      if (parts.isEmpty) continue;
      final String fileName = parts.last;
      if (fileName.startsWith(prefix) && fileName.endsWith('.raw')) {
        await entity.delete();
      }
    }
  }

  void _updateDynamicHistoryCaps() {
    final int frameBytes = _rawWidth * _rawHeight * 4;
    if (frameBytes <= 0) return;

    final int undoByMemory = (_undoBudgetBytes ~/ frameBytes).clamp(
      _minUndoSteps,
      _maxUndoStepsHard,
    );
    if (_targetUndoSteps > undoByMemory) {
      _targetUndoSteps = undoByMemory;
      if (_undoStack.length > _targetUndoSteps) {
        _undoStack.removeRange(0, _undoStack.length - _targetUndoSteps);
      }
    }

    final int timelapseByMemory = (_timelapseBudgetBytes ~/ frameBytes).clamp(
      _minTimelapseFrames,
      _maxTimelapseFramesHard,
    );
    final List<Uint8List> evictedFrames = _timelapse.setMaxFrames(
      timelapseByMemory,
    );
    for (final Uint8List frame in evictedFrames) {
      _enqueueTimelapseArchivedFrame(_currentImageIndex, frame);
    }
  }

  void _enqueueTimelapseArchivedFrame(int imageIndex, Uint8List frame) {
    if (!_storageReady || frame.isEmpty) return;
    final int frameBytes = _rawWidth * _rawHeight * 4;
    if (frameBytes <= 0 || frame.lengthInBytes != frameBytes) return;

    final Future<void> previous =
        _timelapseArchiveWriteChainByImage[imageIndex] ?? Future<void>.value();
    _timelapseArchiveWriteChainByImage[imageIndex] = previous
        .then((_) async {
          await _imageTimelapseArchiveRawFile(
            imageIndex,
          ).writeAsBytes(frame, mode: FileMode.append, flush: false);
          _timelapseArchivedFrameCountByImage[imageIndex] =
              (_timelapseArchivedFrameCountByImage[imageIndex] ?? 0) + 1;
        })
        .catchError((Object e) {
          _log('TIMELAPSE_ARCHIVE_WRITE', 'ERROR: $e');
        });
  }

  Future<void> _flushTimelapseArchiveWrites(int imageIndex) async {
    final Future<void>? pending =
        _timelapseArchiveWriteChainByImage[imageIndex];
    if (pending == null) return;
    try {
      await pending;
    } catch (e) {
      _log('TIMELAPSE_ARCHIVE_FLUSH', 'ERROR: $e');
    }
    if (identical(_timelapseArchiveWriteChainByImage[imageIndex], pending)) {
      _timelapseArchiveWriteChainByImage.remove(imageIndex);
    }
  }

  Future<void> _flushAllTimelapseArchiveWrites() async {
    final List<int> imageIndexes = _timelapseArchiveWriteChainByImage.keys
        .toList(growable: false);
    for (final int imageIndex in imageIndexes) {
      await _flushTimelapseArchiveWrites(imageIndex);
    }
  }

  Future<void> _clearTimelapseArchiveForImage(int imageIndex) async {
    await _flushTimelapseArchiveWrites(imageIndex);
    final File archiveFile = _imageTimelapseArchiveRawFile(imageIndex);
    if (await archiveFile.exists()) {
      await archiveFile.delete();
    }
    _timelapseArchivedFrameCountByImage[imageIndex] = 0;
  }

  Future<void> _clearTimelapseTailForImage(int imageIndex) async {
    final File tailFile = _imageTimelapseRawFile(imageIndex);
    if (await tailFile.exists()) {
      await tailFile.delete();
    }
  }

  /// Trims the archive file so it contains only the last [keepLastFrames] frames.
  /// Streams the tail portion to a temp file, then atomically renames it over
  /// the original. Returns the actual number of frames kept after trimming.
  /// Returns the existing frame count unchanged if trimming fails.
  Future<int> _trimTimelapseArchiveToLastFrames({
    required int imageIndex,
    required int frameBytes,
    required int keepLastFrames,
  }) async {
    if (!_storageReady || frameBytes <= 0 || keepLastFrames <= 0) return 0;

    final File archiveFile = _imageTimelapseArchiveRawFile(imageIndex);
    if (!await archiveFile.exists()) return 0;

    final int fileBytes = await archiveFile.length();
    final int totalFrames = fileBytes ~/ frameBytes;

    // Nothing to trim.
    if (totalFrames <= keepLastFrames) return totalFrames;

    final int framesToKeep = keepLastFrames;
    final int startOffset = (totalFrames - framesToKeep) * frameBytes;
    final int endOffset = totalFrames * frameBytes;

    // Write tail to a temp file in the same directory so rename is atomic.
    final String tempPath =
        '${archiveFile.parent.path}${Platform.pathSeparator}'
        '${archiveFile.uri.pathSegments.last}.tmp';
    final File tempFile = File(tempPath);

    final IOSink tempSink = tempFile.openWrite();
    try {
      await for (final List<int> chunk in archiveFile.openRead(
        startOffset,
        endOffset,
      )) {
        tempSink.add(chunk);
      }
      await tempSink.flush();
    } catch (e) {
      _log('TIMELAPSE_ARCHIVE_TRIM', 'ERROR writing temp: $e');
      await tempSink.close();
      if (await tempFile.exists()) await tempFile.delete();
      return totalFrames; // Leave archive unchanged on error.
    } finally {
      await tempSink.close();
    }

    // Atomically replace original archive with trimmed version.
    try {
      await tempFile.rename(archiveFile.path);
    } catch (e) {
      _log('TIMELAPSE_ARCHIVE_TRIM', 'ERROR rename: $e');
      if (await tempFile.exists()) await tempFile.delete();
      return totalFrames; // Leave archive unchanged on error.
    }

    return framesToKeep;
  }

  Future<int> _frameCountFromRawFile(File file, int frameBytes) async {
    if (!await file.exists() || frameBytes <= 0) return 0;
    final int bytes = await file.length();
    return bytes ~/ frameBytes;
  }

  Future<List<Uint8List>> _readFramesFromRawFile(
    File file,
    int frameBytes,
  ) async {
    if (!await file.exists() || frameBytes <= 0) {
      return <Uint8List>[];
    }
    final Uint8List raw = await file.readAsBytes();
    final int frameCount = raw.lengthInBytes ~/ frameBytes;
    if (frameCount <= 0) {
      return <Uint8List>[];
    }

    final List<Uint8List> frames = <Uint8List>[];
    for (int i = 0; i < frameCount; i++) {
      final int start = i * frameBytes;
      final int end = start + frameBytes;
      frames.add(Uint8List.sublistView(raw, start, end));
    }
    return frames;
  }

  /// Reads only the last [maxFrames] frames from [file] using a ranged stream.
  /// Does NOT read the whole file into memory — safe for large archive files.
  Future<List<Uint8List>> _readLastFramesFromRawFile(
    File file,
    int frameBytes,
    int maxFrames,
  ) async {
    if (!await file.exists() || frameBytes <= 0 || maxFrames <= 0) {
      return <Uint8List>[];
    }
    final int fileBytes = await file.length();
    final int totalFrames = fileBytes ~/ frameBytes;
    if (totalFrames <= 0) return <Uint8List>[];

    final int framesToRead = math.min(totalFrames, maxFrames);
    final int startOffset = (totalFrames - framesToRead) * frameBytes;
    final int endOffset = totalFrames * frameBytes;

    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in file.openRead(startOffset, endOffset)) {
      builder.add(chunk);
    }
    final Uint8List raw = builder.toBytes();
    final int decoded = raw.lengthInBytes ~/ frameBytes;
    if (decoded <= 0) return <Uint8List>[];

    final List<Uint8List> frames = <Uint8List>[];
    for (int i = 0; i < decoded; i++) {
      frames.add(
        Uint8List.sublistView(raw, i * frameBytes, (i + 1) * frameBytes),
      );
    }
    return frames;
  }

  bool _hasArchivedUndo(int imageIndex) {
    final List<_ArchivedUndoEntry>? archive = _undoArchiveByImage[imageIndex];
    return archive != null && archive.isNotEmpty;
  }

  Future<void> _archiveUndoSnapshot(int imageIndex, Uint8List? snapshot) async {
    final List<_ArchivedUndoEntry> archive = _undoArchiveByImage.putIfAbsent(
      imageIndex,
      () => <_ArchivedUndoEntry>[],
    );
    if (snapshot == null) {
      archive.add(const _ArchivedUndoEntry.nullSnapshot());
      return;
    }
    if (!_storageReady) {
      // If storage is not ready, keep the chain coherent with a null marker.
      archive.add(const _ArchivedUndoEntry.nullSnapshot());
      return;
    }

    final String filePath =
        '${_sessionDirectory.path}${Platform.pathSeparator}$_sessionNamespace.image_${imageIndex}_undo_archive_${_undoArchiveSeq++}.raw';
    final File archiveFile = File(filePath);
    try {
      await archiveFile.writeAsBytes(snapshot, flush: false);
      archive.add(_ArchivedUndoEntry.file(filePath));
    } catch (e) {
      _log('UNDO_ARCHIVE_WRITE', 'ERROR: $e');
      archive.add(const _ArchivedUndoEntry.nullSnapshot());
    }
  }

  Future<_ArchivedUndoReadResult> _popArchivedUndoSnapshot(
    int imageIndex, {
    required int expectedBytes,
  }) async {
    final List<_ArchivedUndoEntry>? archive = _undoArchiveByImage[imageIndex];
    if (archive == null || archive.isEmpty) {
      return const _ArchivedUndoReadResult(found: false, snapshot: null);
    }

    while (archive.isNotEmpty) {
      final _ArchivedUndoEntry entry = archive.removeLast();
      if (entry.isNullSnapshot) {
        return const _ArchivedUndoReadResult(found: true, snapshot: null);
      }

      final String? filePath = entry.filePath;
      if (filePath == null) {
        continue;
      }
      final File file = File(filePath);
      try {
        if (!await file.exists()) {
          continue;
        }
        final Uint8List raw = await file.readAsBytes();
        await file.delete();
        if (raw.lengthInBytes == expectedBytes) {
          return _ArchivedUndoReadResult(found: true, snapshot: raw);
        }
      } catch (e) {
        _log('UNDO_ARCHIVE_READ', 'ERROR: $e');
      }
    }

    _undoArchiveByImage.remove(imageIndex);
    return const _ArchivedUndoReadResult(found: false, snapshot: null);
  }

  Future<void> _clearUndoArchiveForImage(int imageIndex) async {
    final List<_ArchivedUndoEntry>? archive = _undoArchiveByImage.remove(
      imageIndex,
    );
    if (archive == null || archive.isEmpty) return;

    for (final _ArchivedUndoEntry entry in archive) {
      final String? filePath = entry.filePath;
      if (filePath == null) continue;
      try {
        final File file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        _log('UNDO_ARCHIVE_CLEAR', 'ERROR: $e');
      }
    }
  }

  Future<void> _clearAllUndoArchives() async {
    final List<int> imageKeys = _undoArchiveByImage.keys.toList(
      growable: false,
    );
    for (final int imageIndex in imageKeys) {
      await _clearUndoArchiveForImage(imageIndex);
    }
  }

  void _pushUndoSnapshot(Uint8List? snapshot) {
    final int undoLimit = _runtimeUndoLimit();
    if (_undoStack.length >= undoLimit) {
      final int removeCount = _undoStack.length - undoLimit + 1;
      _undoStack.removeRange(0, removeCount);
    }
    _undoStack.add(snapshot);
  }

  void _recomputeProgressPercent() {
    final int pixelCount = _rawWidth * _rawHeight;
    if (pixelCount <= 0) {
      _progressPercent = 0;
      return;
    }

    final Uint8List originalRaw = pixelEngine.originalRawRgba;
    final Uint8List currentRaw = _rawFillBytes ?? originalRaw;
    final Uint8List borderMask = pixelEngine.borderMask;

    if (originalRaw.lengthInBytes != pixelCount * 4 ||
        currentRaw.lengthInBytes != pixelCount * 4 ||
        borderMask.lengthInBytes != pixelCount) {
      _progressPercent = 0;
      return;
    }

    _progressPercent = PixelEngine.computeProgressPercent(
      FillPercentageRequest(
        currentRawRgba: currentRaw,
        originalRawRgba: originalRaw,
        borderMask: borderMask,
      ),
    );
  }

  void _markColorRecent(Color color, {bool incrementUsage = false}) {
    _recentColors.remove(color);
    _recentColors.insert(0, color);
    if (_recentColors.length > 10) {
      _recentColors.removeRange(10, _recentColors.length);
    }
    if (incrementUsage) {
      final int colorKey = color.toARGB32();
      _colorUseCount[colorKey] = (_colorUseCount[colorKey] ?? 0) + 1;
    }
  }

  List<Color> _buildSuggestedColors() {
    final List<Color> out = <Color>[];
    final Set<int> seen = <int>{};
    void addColor(Color color) {
      final int key = color.toARGB32();
      if (seen.add(key)) {
        out.add(color);
      }
    }

    for (final Color color in _recentColors) {
      addColor(color);
    }

    final List<MapEntry<int, int>> mostUsed = _colorUseCount.entries.toList()
      ..sort((MapEntry<int, int> a, MapEntry<int, int> b) => b.value - a.value);
    for (final MapEntry<int, int> entry in mostUsed) {
      addColor(Color(entry.key));
    }

    for (final Color color in _colorHistory) {
      addColor(color);
    }

    return out.take(10).toList(growable: false);
  }

  Future<List<Uint8List>?> _readTimelapseFramesFromImageMeta(
    Map<dynamic, dynamic> meta, {
    required int imageIndex,
    required int width,
    required int height,
    required int maxFramesToRestore,
  }) async {
    final int frameCountFromMeta = (meta['timelapseFrameCount'] is int)
        ? meta['timelapseFrameCount'] as int
        : 0;

    final File timelapseFile = _imageTimelapseRawFile(imageIndex);
    if (!await timelapseFile.exists()) {
      return <Uint8List>[];
    }

    final int frameBytes = width * height * 4;
    if (frameBytes <= 0) {
      return <Uint8List>[];
    }

    final int actualFileBytes = await timelapseFile.length();
    final int completeFramesInFile = actualFileBytes ~/ frameBytes;
    if (completeFramesInFile <= 0) {
      return <Uint8List>[];
    }

    // If metadata lags behind disk writes, trust complete frames available on disk.
    final int availableFrames = frameCountFromMeta > 0
        ? math.max(frameCountFromMeta, completeFramesInFile)
        : completeFramesInFile;
    final int safeFrames = math.min(availableFrames, completeFramesInFile);
    if (safeFrames <= 0) {
      return <Uint8List>[];
    }

    // Only hydrate the tail that can actually be used by the timelapse controller.
    final int capFrames = maxFramesToRestore < 1
        ? _timelapse.maxFrames
        : maxFramesToRestore;
    final int framesToLoad = math.min(
      math.min(safeFrames, _timelapse.maxFrames),
      capFrames,
    );
    final int bytesToLoad = framesToLoad * frameBytes;
    final int endOffset = safeFrames * frameBytes;
    final int startOffset = endOffset - bytesToLoad;

    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in timelapseFile.openRead(
      startOffset,
      endOffset,
    )) {
      builder.add(chunk);
    }
    final Uint8List raw = builder.toBytes();
    final int decodedFrames = raw.lengthInBytes ~/ frameBytes;
    if (decodedFrames <= 0) {
      return <Uint8List>[];
    }

    final List<Uint8List> frames = <Uint8List>[];
    for (int i = 0; i < decodedFrames; i++) {
      final int start = i * frameBytes;
      final int end = start + frameBytes;
      frames.add(Uint8List.sublistView(raw, start, end));
    }
    return frames;
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
    _timelapse.stop();
    _autosaveTimer?.cancel();
    _messageTimer?.cancel();
    _stopTrackingTime();
    unawaited(_flushStorageOnDispose());
    unawaited(_clearAllUndoArchives());
    _replaceUiImage(null);
    processingNotifier.dispose();
    progressNotifier.dispose();
    colorNotifier.dispose();
    statusNotifier.dispose();
    transformationController.dispose();
    super.dispose();
  }
}
