import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../engine/PixelEngine.dart';

void _log(String tag, String msg) {
  debugPrint('[COLOR_APP][$tag] $msg');
}

class BasicScreen extends StatefulWidget {
  const BasicScreen({super.key});

  @override
  State<BasicScreen> createState() => _BasicScreenState();
}

class _BasicScreenState extends State<BasicScreen> {
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
    const ui.Color.fromARGB(255, 255, 255, 255),
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
    loadImage();
  }

  @override
  void dispose() {
    _uiImage?.dispose();
    super.dispose();
  }

  Future<void> loadImage() async {
    try {
      final ByteData data = await rootBundle.load(
        testImages[currentImageIndex],
      );
      final Uint8List bytes = data.buffer.asUint8List();

      pixelEngine.loadImage(bytes);
      _rawFillBytes = null;
      _rawWidth = pixelEngine.imageWidth;
      _rawHeight = pixelEngine.imageHeight;
      _fillCount = 0;
      _undoStack.clear();

      final ui.Image loaded = await _decodeToUiImage(bytes);
      if (!mounted) {
        loaded.dispose();
        return;
      }

      final ui.Image? oldImage = _uiImage;
      setState(() {
        _uiImage = loaded;
        _transformationController.value = Matrix4.identity();
      });
      oldImage?.dispose();
      _updateFitCache();
    } catch (e) {
      _log('LOAD', 'ERROR: $e');
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
    if (_uiImage == null || isProcessing) return;

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

    isProcessing = true;
    _fillCount++;
    final int thisFill = _fillCount;

    final Uint8List? snapshot = _rawFillBytes == null
        ? null
        : Uint8List.fromList(_rawFillBytes!);

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
  }

  Future<void> _undo() async {
    if (_undoStack.isEmpty || isProcessing) return;

    setState(() => isProcessing = true);
    final Uint8List? snapshot = _undoStack.removeLast();

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
  }

  @override
  Widget build(BuildContext context) {
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
              color: (_undoStack.isNotEmpty && !isProcessing)
                  ? Colors.black
                  : Colors.grey.shade300,
            ),
            onPressed: (_undoStack.isNotEmpty && !isProcessing) ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: loadImage,
          ),
          IconButton(
            icon: Icon(Icons.colorize, color: selectedColor),
            onPressed: showPicker,
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
                    color: ui.Color.fromARGB(255, 0, 0, 0),
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

  Widget _buildColorCircle(Color color) {
    final bool isSelected = selectedColor == color;
    return GestureDetector(
      onTap: () => setState(() => selectedColor = color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: isSelected ? 52 : 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Colors.blueAccent
                : const ui.Color.fromARGB(255, 0, 0, 0),
            width: 3,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }

  void _changeImage(int delta) {
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
