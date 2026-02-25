import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../engine/PixelEngine.dart';

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

  // ui.Image is rendered directly by RawImage — no encode/decode for display
  ui.Image? _uiImage;

  // Raw RGBA bytes cached between fills — isolate skips decodeImage on 2nd+ fills
  Uint8List? _rawFillBytes;
  // Original PNG bytes — used only for the very first fill
  Uint8List? _originalBytes;
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

  @override
  void dispose() {
    _uiImage?.dispose();
    super.dispose();
  }

  Future<void> loadImage() async {
    try {
      final ByteData data   = await rootBundle.load(testImages[currentImageIndex]);
      final Uint8List bytes = data.buffer.asUint8List();

      pixelEngine.loadImage(bytes);
      _originalBytes = bytes;
      _rawFillBytes  = null;
      _rawWidth      = pixelEngine.imageWidth;
      _rawHeight     = pixelEngine.imageHeight;

      // Decode to ui.Image for flicker-free display
      final ui.Image loaded = await _decodeToUiImage(bytes);

      _uiImage?.dispose();
      setState(() {
        _uiImage = loaded;
        _transformationController.value = Matrix4.identity();
      });
      _updateFitCache();
    } catch (e) {
      debugPrint('Load error: $e');
    }
  }

  /// Decodes any encoded image bytes (PNG/JPEG) to a ui.Image
  Future<ui.Image> _decodeToUiImage(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// Converts raw RGBA bytes directly to ui.Image — no codec, instant
  Future<ui.Image> _rawRgbaToUiImage(Uint8List rgba, int width, int height) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width:           width,
      height:          height,
      pixelFormat:     ui.PixelFormat.rgba8888,
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
    final double imgW  = _rawWidth.toDouble();
    final double imgH  = _rawHeight.toDouble();
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
    if (_uiImage == null || isProcessing) return;

    final Matrix4 inverse = Matrix4.inverted(_transformationController.value);
    final Vector3 scene   = inverse.transform3(
      Vector3(localOffset.dx, localOffset.dy, 0),
    );

    final int pixelX = ((scene.x - _cachedFitOffsetX) / _cachedScaleFit).floor();
    final int pixelY = ((scene.y - _cachedFitOffsetY) / _cachedScaleFit).floor();

    if (pixelX < 0 || pixelX >= _rawWidth || pixelY < 0 || pixelY >= _rawHeight) return;

    // Lock — no setState here, no UI flicker
    isProcessing = true;

    final bool hasRaw = _rawFillBytes != null;

    // BFS fill in background isolate — returns raw RGBA, no encode
    final Uint8List rawResult = await compute(
      PixelEngine.processFloodFill,
      FloodFillRequest(
        imageBytes:    hasRaw ? _rawFillBytes! : _originalBytes!,
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

    // Cache raw bytes for next fill
    _rawFillBytes = rawResult;
    pixelEngine.updateFromRawBytes(rawResult, _rawWidth, _rawHeight);

    // Convert raw RGBA → ui.Image directly — no PNG/JPEG encode at all
    final ui.Image newUiImage = await _rawRgbaToUiImage(rawResult, _rawWidth, _rawHeight);

    // Swap old image for new — single setState, no intermediate blank frame
    final ui.Image? oldImage = _uiImage;
    setState(() {
      _uiImage     = newUiImage;
      isProcessing = false;
    });
    // Dispose old image AFTER setState so it's never disposed while being rendered
    oldImage?.dispose();
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
        // Subtle indicator — no full-screen loader
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
                    child: _uiImage == null
                        ? const Center(child: CircularProgressIndicator())
                        : LayoutBuilder(
                      builder: (context, constraints) {
                        final Size newSize = Size(constraints.maxWidth, constraints.maxHeight);
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
                                // RawImage renders ui.Image directly on the GPU
                                // No encode → decode cycle, no widget rebuild flicker
                                child: RawImage(
                                  image:    _uiImage,
                                  fit:      BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
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