import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../engine/PixelEngine.dart';

// Passed to the encode isolate
class _EncodeRequest {
  final Uint8List bytes;
  final int width;
  final int height;
  _EncodeRequest(this.bytes, this.width, this.height);
}

class BasicScreen extends StatefulWidget {
  const BasicScreen({super.key});

  @override
  State<BasicScreen> createState() => _BasicScreenState();
}

class _BasicScreenState extends State<BasicScreen> {
  final PixelEngine pixelEngine = PixelEngine();

  // What Image.memory() renders — JPEG encoded
  Uint8List? imageBytes;

  // Raw RGBA pixels from the last fill — passed back to isolate on next fill
  // so it can skip decodeImage entirely
  Uint8List? _rawFillBytes;
  int _rawWidth  = 0;
  int _rawHeight = 0;

  Color selectedColor     = const Color(0xFFFFC107);
  bool  isProcessing      = false;
  int   currentImageIndex = 0;
  final TransformationController _transformationController = TransformationController();

  Size   _containerSize    = Size.zero;
  double _cachedScaleFit   = 1.0;
  double _cachedFitOffsetX = 0.0;
  double _cachedFitOffsetY = 0.0;

  int     _activePointers    = 0;
  Offset? _pointerDownPosition;
  int     _pointerDownTimeMs = 0;
  bool    _pointerDragged    = false;
  static const double _tapMoveThreshold = 10.0;
  static const int    _tapMaxDurationMs = 250;

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
      final ByteData data   = await rootBundle.load(testImages[currentImageIndex]);
      final Uint8List bytes = data.buffer.asUint8List();
      pixelEngine.loadImage(bytes);

      // Reset raw cache — new image, start fresh
      _rawFillBytes = null;
      _rawWidth     = pixelEngine.imageWidth;
      _rawHeight    = pixelEngine.imageHeight;

      setState(() {
        imageBytes = bytes; // display original PNG directly — no re-encode needed
        _transformationController.value = Matrix4.identity();
      });
      _updateFitCache();
    } catch (e) {
      debugPrint('Load error: $e');
    }
  }

  void _updateFitCache() {
    if (_containerSize == Size.zero || !pixelEngine.isLoaded) return;
    final double imgW  = pixelEngine.imageWidth.toDouble();
    final double imgH  = pixelEngine.imageHeight.toDouble();
    final double viewW = _containerSize.width;
    final double viewH = _containerSize.height;
    _cachedScaleFit   = (viewW / imgW < viewH / imgH) ? viewW / imgW : viewH / imgH;
    _cachedFitOffsetX = (viewW - imgW * _cachedScaleFit) / 2.0;
    _cachedFitOffsetY = (viewH - imgH * _cachedScaleFit) / 2.0;
  }

  void showPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a Custom Color'),
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

  // ── Pointer handlers ───────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers == 1) {
      _pointerDownPosition = event.localPosition;
      _pointerDownTimeMs   = DateTime.now().millisecondsSinceEpoch;
      _pointerDragged      = false;
    } else {
      _pointerDownPosition = null;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointerDownPosition != null && !_pointerDragged) {
      if ((event.localPosition - _pointerDownPosition!).distance > _tapMoveThreshold) {
        _pointerDragged = true;
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    if (_pointerDownPosition != null && !_pointerDragged && _activePointers == 0) {
      final int elapsed = DateTime.now().millisecondsSinceEpoch - _pointerDownTimeMs;
      if (elapsed <= _tapMaxDurationMs) handleTap(_pointerDownPosition!);
    }
    if (_activePointers == 0) {
      _pointerDownPosition = null;
      _pointerDragged      = false;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    if (_activePointers == 0) {
      _pointerDownPosition = null;
      _pointerDragged      = false;
    }
  }

  // ── Fill pipeline ──────────────────────────────────────────────────────────

  Future<void> handleTap(Offset localOffset) async {
    if (!pixelEngine.isLoaded || imageBytes == null || isProcessing) return;

    final Matrix4 inverse = Matrix4.inverted(_transformationController.value);
    final Vector3 scene   = inverse.transform3(
      Vector3(localOffset.dx, localOffset.dy, 0),
    );

    final int pixelX = ((scene.x - _cachedFitOffsetX) / _cachedScaleFit).floor();
    final int pixelY = ((scene.y - _cachedFitOffsetY) / _cachedScaleFit).floor();

    if (pixelX < 0 || pixelX >= _rawWidth || pixelY < 0 || pixelY >= _rawHeight) return;

    setState(() => isProcessing = true);

    final bool hasRaw = _rawFillBytes != null;

    // ┌─────────────────────────────────────────────────────────────┐
    // │  FILL ISOLATE                                               │
    // │  First fill: decodes PNG once                               │
    // │  Every fill after: Image.fromBytes (raw RGBA) — near-zero  │
    // └─────────────────────────────────────────────────────────────┘
    final Uint8List rawResult = await compute(
      PixelEngine.processFloodFill,
      FloodFillRequest(
        imageBytes:    hasRaw ? _rawFillBytes! : imageBytes!,
        x:             pixelX,
        y:             pixelY,
        fillColorRgba: img.getColor(
          selectedColor.red, selectedColor.green, selectedColor.blue, 255,
        ),
        isRawRgba: hasRaw,
        rawWidth:  _rawWidth,
        rawHeight: _rawHeight,
      ),
    );

    // Cache raw result — passed straight back on next tap
    _rawFillBytes = rawResult;

    // Update engine in-memory image from raw bytes (no decode)
    pixelEngine.updateFromRawBytes(rawResult, _rawWidth, _rawHeight);

    // ┌─────────────────────────────────────────────────────────────┐
    // │  ENCODE ISOLATE                                             │
    // │  Convert raw RGBA → JPEG for display, off the UI thread     │
    // └─────────────────────────────────────────────────────────────┘
    final Uint8List displayBytes = await compute(
      _encodeToJpeg,
      _EncodeRequest(rawResult, _rawWidth, _rawHeight),
    );

    setState(() {
      imageBytes   = displayBytes;
      isProcessing = false;
    });
  }

  static Uint8List _encodeToJpeg(_EncodeRequest req) {
    final img.Image image = img.Image.fromBytes(req.width, req.height, req.bytes);
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.black), onPressed: loadImage),
          IconButton(icon: Icon(Icons.colorize, color: selectedColor),      onPressed: showPicker),
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
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: imageBytes == null
                        ? const Center(child: CircularProgressIndicator())
                        : LayoutBuilder(
                      builder: (context, constraints) {
                        final Size newSize =
                        Size(constraints.maxWidth, constraints.maxHeight);
                        if (_containerSize != newSize) {
                          _containerSize = newSize;
                          _updateFitCache();
                        }
                        return Listener(
                          onPointerDown:   _onPointerDown,
                          onPointerMove:   _onPointerMove,
                          onPointerUp:     _onPointerUp,
                          onPointerCancel: _onPointerCancel,
                          child: InteractiveViewer(
                            transformationController: _transformationController,
                            panEnabled:  true,
                            minScale:    1.0,
                            maxScale:    10.0,
                            constrained: true,
                            child: SizedBox(
                              width:  constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: Center(
                                child: Image.memory(
                                  imageBytes!,
                                  key:             ValueKey(imageBytes.hashCode),
                                  fit:             BoxFit.contain,
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
          topLeft:  Radius.circular(30),
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
                _navBtn(Icons.arrow_back_ios,    () => _changeImage(-1)),
                const Text('PALETTE',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 12, color: Colors.grey)),
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
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white,
            width: 3,
          ),
          boxShadow: [
            if (isSelected) BoxShadow(color: color.withOpacity(0.5), blurRadius: 10),
          ],
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
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