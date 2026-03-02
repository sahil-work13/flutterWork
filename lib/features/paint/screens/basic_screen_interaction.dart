// ignore_for_file: invalid_use_of_protected_member

part of 'basic_screen.dart';

extension _BasicScreenInteraction on _BasicScreenState {
  int _to8Bit(double channel) {
    final int scaled = (channel * 255.0).round();
    if (scaled < 0) return 0;
    if (scaled > 255) return 255;
    return scaled;
  }

  bool _isSwipeNavigationAllowed() {
    final double currentScale = _transformationController.value.getMaxScaleOnAxis();
    return currentScale <= 1.05;
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
        _changeImage(delta.dx < 0 ? 1 : -1);
      } else if (!_pointerDragged && elapsed <= _tapMaxDurationMs) {
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
    final int pixelX = ((scene.dx - _cachedFitOffsetX) / _cachedScaleFit).floor();
    final int pixelY = ((scene.dy - _cachedFitOffsetY) / _cachedScaleFit).floor();

    if (pixelX < 0 || pixelX >= _rawWidth || pixelY < 0 || pixelY >= _rawHeight) {
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
          fillR: _to8Bit(selectedColor.r),
          fillG: _to8Bit(selectedColor.g),
          fillB: _to8Bit(selectedColor.b),
        ),
      );

      _rawFillBytes = rawResult;
      pixelEngine.updateFromRawBytes(rawResult, _rawWidth, _rawHeight);

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
        restoredImage = await _rawRgbaToUiImage(originalRaw, _rawWidth, _rawHeight);
      } else {
        _rawFillBytes = snapshot;
        pixelEngine.updateFromRawBytes(snapshot, _rawWidth, _rawHeight);
        restoredImage = await _rawRgbaToUiImage(snapshot, _rawWidth, _rawHeight);
      }

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
      if (_storageReady) {
        final File rawFile = _imageRawFile(currentImageIndex);
        if (_sessionMetaBox != null) {
          await _sessionMetaBox!.delete(_imageMetaKey(currentImageIndex));
        }
        if (await rawFile.exists()) await rawFile.delete();
        for (int i = 0; i < _maxUndoSteps; i++) {
          final File undoFile = _imageUndoRawFile(currentImageIndex, i);
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

  void _changeImage(int delta) {
    if (delta == 0) return;
    if (_isImageLoading) {
      _queuedImageDelta += delta;
      return;
    }
    _applyImageChange(delta);
  }
}
