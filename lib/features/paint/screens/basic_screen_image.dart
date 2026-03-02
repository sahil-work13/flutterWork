// ignore_for_file: invalid_use_of_protected_member

part of 'basic_screen.dart';

extension _BasicScreenImage on _BasicScreenState {
  int _wrapImageIndex(int rawIndex) {
    final int len = testImages.length;
    return ((rawIndex % len) + len) % len;
  }

  void _drainQueuedImageChange() {
    if (!mounted || _isImageLoading || _queuedImageDelta == 0) return;
    final int queuedDelta = _queuedImageDelta;
    _queuedImageDelta = 0;
    _applyImageChange(queuedDelta);
  }

  void _applyImageChange(int delta) {
    if (delta == 0) return;
    _requestAutosave(immediate: true);
    setState(() {
      currentImageIndex = _wrapImageIndex(currentImageIndex + delta);
    });
    unawaited(loadImage());
  }

  Future<void> loadImage({bool restoreSavedState = true}) async {
    final int loadSeq = ++_imageLoadSeq;
    final int imageIndexAtLoad = currentImageIndex;
    final String assetPathAtLoad = testImages[imageIndexAtLoad];
    _isImageLoading = true;
    if (mounted) {
      setState(() {
        _engineReady = false;
        _showImageTransitionLoader = !_showStartupLoader && _uiImage != null;
      });
    } else {
      _showImageTransitionLoader = !_showStartupLoader && _uiImage != null;
    }

    try {
      final ByteData data = await rootBundle.load(assetPathAtLoad);
      if (!mounted || loadSeq != _imageLoadSeq) return;
      final Uint8List bytes = data.buffer.asUint8List();

      final ui.Image preview = await _decodeToUiImage(bytes);
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

      await Future<void>.delayed(Duration.zero);
      if (!mounted || loadSeq != _imageLoadSeq) return;

      final Map<String, Object> prepared =
          await _loadOrPrepareImageData(imageIndexAtLoad, assetPathAtLoad, bytes);
      if (!mounted || loadSeq != _imageLoadSeq) return;

      pixelEngine.applyPreparedImage(prepared);
      if (!pixelEngine.isLoaded) {
        throw StateError('Failed to decode image: $assetPathAtLoad');
      }

      _rawWidth = pixelEngine.imageWidth;
      _rawHeight = pixelEngine.imageHeight;
      _undoStack.clear();

      final ui.Image? loaded =
          restoreSavedState ? await _buildCurrentImageFromSavedState() : null;
      if (!mounted || loadSeq != _imageLoadSeq) {
        loaded?.dispose();
        return;
      }

      if (!restoreSavedState) {
        _rawFillBytes = null;
        _fillCount = 0;
        _undoStack.clear();
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
          _showImageTransitionLoader = false;
        });
      }
    } catch (e) {
      _log('LOAD', 'ERROR: $e');
      if (mounted && loadSeq == _imageLoadSeq) {
        setState(() {
          _engineReady = false;
          _showStartupLoader = false;
          _showImageTransitionLoader = false;
        });
      }
    } finally {
      if (loadSeq == _imageLoadSeq) {
        _isImageLoading = false;
        if (!mounted) {
          _showImageTransitionLoader = false;
        }
      }
      _drainQueuedImageChange();
    }
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
}
