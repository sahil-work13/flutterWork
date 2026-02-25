import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../engine/PixelEngine.dart';

class BasicScreen extends StatefulWidget {
  const BasicScreen({super.key});

  @override
  State<BasicScreen> createState() => _BasicScreenState();
}

class _BasicScreenState extends State<BasicScreen> {
  final PixelEngine pixelEngine = PixelEngine();
  Uint8List? imageBytes;
  Color selectedColor = const Color(0xFFFFC107);
  bool isProcessing = false;
  int currentImageIndex = 0;
  final TransformationController _transformationController = TransformationController();

  // Container size stored for tap coordinate math
  Size _containerSize = Size.zero;

  // Tap detection — tracks pointer events to distinguish tap vs pan/pinch
  int _activePointers = 0;
  Offset? _pointerDownPosition;
  int _pointerDownTimeMs = 0;
  bool _pointerDragged = false;
  static const double _tapMoveThreshold = 10.0; // px — beyond this = drag, not tap
  static const int _tapMaxDurationMs = 250;      // ms — beyond this = long-press, not tap

  final List<Color> colorHistory = [
    const Color(0xFFF44336), const Color(0xFFE91E63), const Color(0xFF9C27B0),
    const Color(0xFF2196F3), const Color(0xFF00BCD4), const Color(0xFF4CAF50),
    const Color(0xFFFFEB3B), const Color(0xFFFF9800), const Color(0xFF795548),
    const Color(0xFF000000), const Color(0xFF9E9E9E), const Color(0xFFFFFFFF),
  ];

  final List<String> testImages = [
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

  Future<void> loadImage() async {
    try {
      final data = await rootBundle.load(testImages[currentImageIndex]);
      final bytes = data.buffer.asUint8List();
      pixelEngine.loadImage(bytes);
      setState(() {
        imageBytes = bytes;
        _transformationController.value = Matrix4.identity();
      });
    } catch (e) {
      debugPrint('UI: Load Error: $e');
    }
  }

  void showPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Pick a Custom Color"),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: selectedColor,
            onColorChanged: (c) => setState(() => selectedColor = c),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers == 1) {
      // First finger down — record for tap detection
      _pointerDownPosition = event.localPosition;
      _pointerDownTimeMs = DateTime.now().millisecondsSinceEpoch;
      _pointerDragged = false;
    } else {
      // Second finger (pinch-to-zoom) — cancel any pending tap
      _pointerDownPosition = null;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerDownPosition != null && !_pointerDragged) {
      final double dist = (event.localPosition - _pointerDownPosition!).distance;
      if (dist > _tapMoveThreshold) {
        _pointerDragged = true; // Finger moved too far — this is a pan, not a tap
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);

    // Only fire fill if: single finger, didn't drag, released quickly
    if (_pointerDownPosition != null &&
        !_pointerDragged &&
        _activePointers == 0) {
      final int elapsed = DateTime.now().millisecondsSinceEpoch - _pointerDownTimeMs;
      if (elapsed <= _tapMaxDurationMs) {
        // Genuine tap — use the DOWN position for accuracy (not up, which may drift)
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
    if (!pixelEngine.isLoaded || imageBytes == null || isProcessing) return;

    final double imgW = pixelEngine.imageWidth.toDouble();
    final double imgH = pixelEngine.imageHeight.toDouble();
    final double viewW = _containerSize.width;
    final double viewH = _containerSize.height;

    if (viewW == 0 || viewH == 0) return;

    // BoxFit.contain scale and centering offsets
    final double scaleFit = (viewW / imgW < viewH / imgH) ? (viewW / imgW) : (viewH / imgH);
    final double fitOffsetX = (viewW - imgW * scaleFit) / 2.0;
    final double fitOffsetY = (viewH - imgH * scaleFit) / 2.0;

    // Invert the InteractiveViewer transform: screen coords -> scene coords
    final Matrix4 transform = _transformationController.value;
    final Matrix4 inverse = Matrix4.inverted(transform);
    final Vector3 scenePoint = inverse.transform3(
      Vector3(localOffset.dx, localOffset.dy, 0),
    );

    // Scene coords -> image pixel coords
    final int pixelX = ((scenePoint.x - fitOffsetX) / scaleFit).floor();
    final int pixelY = ((scenePoint.y - fitOffsetY) / scaleFit).floor();

    // --- DEBUG (remove once confirmed working) ---
    final double zoomScale = transform.getMaxScaleOnAxis();
    final double panX = transform.getTranslation().x;
    final double panY = transform.getTranslation().y;
    debugPrint('');
    debugPrint('========== TAP DEBUG ==========');
    debugPrint('[1]  RAW TAP        : (${localOffset.dx.toStringAsFixed(2)}, ${localOffset.dy.toStringAsFixed(2)})');
    debugPrint('[2]  CONTAINER SIZE : ${viewW.toStringAsFixed(1)} x ${viewH.toStringAsFixed(1)}');
    debugPrint('[3]  IMAGE SIZE     : ${imgW.toInt()} x ${imgH.toInt()} px');
    debugPrint('[4]  FIT SCALE      : ${scaleFit.toStringAsFixed(5)}');
    debugPrint('[5]  FIT OFFSET     : dx=${fitOffsetX.toStringAsFixed(2)}, dy=${fitOffsetY.toStringAsFixed(2)}');
    debugPrint('[6]  ZOOM / PAN     : zoom=${zoomScale.toStringAsFixed(4)}, panX=${panX.toStringAsFixed(2)}, panY=${panY.toStringAsFixed(2)}');
    debugPrint('[7]  SCENE POINT    : (${scenePoint.x.toStringAsFixed(3)}, ${scenePoint.y.toStringAsFixed(3)})');
    debugPrint('[8]  PIXEL TARGET   : ($pixelX, $pixelY)');
    final Vector3 cs = inverse.transform3(Vector3(viewW / 2, viewH / 2, 0));
    final int cPxX = ((cs.x - fitOffsetX) / scaleFit).floor();
    final int cPxY = ((cs.y - fitOffsetY) / scaleFit).floor();
    debugPrint('[9]  SCREEN CENTER  : maps to pixel ($cPxX, $cPxY)  [expected near (${(imgW / 2).toInt()}, ${(imgH / 2).toInt()})]');
    // --- END DEBUG ---

    if (pixelX >= 0 && pixelX < imgW && pixelY >= 0 && pixelY < imgH) {
      final img.Image? previewImg = img.decodeImage(imageBytes!);
      if (previewImg != null) {
        final int prePixel = previewImg.getPixel(pixelX, pixelY);
        final int preR = img.getRed(prePixel);
        final int preG = img.getGreen(prePixel);
        final int preB = img.getBlue(prePixel);
        debugPrint('[10] PRE-FILL COLOR : R=$preR G=$preG B=$preB   (border? ${preR < 60 && preG < 60 && preB < 60})');
      }
      debugPrint('================================');

      setState(() => isProcessing = true);

      final request = FloodFillRequest(
        imageBytes: imageBytes!,
        x: pixelX,
        y: pixelY,
        fillColorRgba: img.getColor(selectedColor.red, selectedColor.green, selectedColor.blue, 255),
      );

      final Uint8List updatedBytes = await compute(PixelEngine.processFloodFill, request);

      debugPrint('[11] FILL APPLIED at ($pixelX, $pixelY)');

      pixelEngine.loadImage(updatedBytes);
      setState(() {
        imageBytes = updatedBytes;
        isProcessing = false;
      });
    } else {
      debugPrint('[10] !! OUT OF BOUNDS — ($pixelX, $pixelY) outside ${imgW.toInt()}x${imgH.toInt()}');
      debugPrint('================================');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text('Coloring Book',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: isProcessing
            ? const Padding(padding: EdgeInsets.all(15), child: CircularProgressIndicator(strokeWidth: 2))
            : null,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.black), onPressed: loadImage),
          IconButton(icon: Icon(Icons.colorize, color: selectedColor), onPressed: showPicker),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: imageBytes == null
                        ? const Center(child: CircularProgressIndicator())
                        : LayoutBuilder(
                      builder: (context, constraints) {
                        _containerSize = Size(constraints.maxWidth, constraints.maxHeight);
                        return Listener(
                          // Listener sits OUTSIDE InteractiveViewer so localPosition
                          // is always relative to the true container top-left.
                          // We manually distinguish tap vs pan/pinch using pointer tracking.
                          onPointerDown: _onPointerDown,
                          onPointerMove: _onPointerMove,
                          onPointerUp: _onPointerUp,
                          onPointerCancel: _onPointerCancel,
                          child: InteractiveViewer(
                            transformationController: _transformationController,
                            panEnabled: true,
                            minScale: 1.0,
                            maxScale: 10.0,
                            constrained: true,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: Center(
                                child: Image.memory(
                                  imageBytes!,
                                  key: ValueKey('img_${currentImageIndex}_${imageBytes!.length}'),
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
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
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _navBtn(Icons.arrow_back_ios, () => _changeImage(-1)),
                const Text("PALETTE",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.grey)),
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
              itemBuilder: (context, i) => _buildColorCircle(colorHistory[i]),
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
          border: Border.all(color: isSelected ? Colors.blueAccent : Colors.white, width: 3),
          boxShadow: [if (isSelected) BoxShadow(color: color.withOpacity(0.5), blurRadius: 10)],
        ),
        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
      ),
    );
  }

  void _changeImage(int delta) {
    setState(() => currentImageIndex = (currentImageIndex + delta) % testImages.length);
    loadImage();
  }

  Widget _navBtn(IconData icon, VoidCallback tap) =>
      IconButton(icon: Icon(icon, size: 18), onPressed: tap);
}