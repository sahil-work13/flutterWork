part of 'basic_screen.dart';

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

extension _BasicScreenStorage on _BasicScreenState {
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

    final dynamic rawMeta = _sessionMetaBox!.get(_imageMetaKey(currentImageIndex));
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
            final File undoFile = _imageUndoRawFile(currentImageIndex, i);
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
          final File imageRawFile = _imageRawFile(currentImageIndex);
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
}
