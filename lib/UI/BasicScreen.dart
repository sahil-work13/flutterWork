import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;
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

  // ui.Image rendered directly by RawImage — no encode/decode for display
  ui.Image? _uiImage;

  // Raw RGBA bytes cached between fills — isolate skips decodeImage on 2nd+ fills
  Uint8List? _rawFillBytes;
  // Original PNG bytes — used only for the very first fill
  Uint8List? _originalBytes;
  int _rawWidth  = 0;
  int _rawHeight = 0;

  // ── Undo stack ─────────────────────────────────────────────────────────────
  // Each entry is the raw RGBA snapshot BEFORE that fill was applied.
  // Pop to restore the previous state. Capped at 20 to limit memory.
  final Queue<Uint8List> _undoStack = Queue<Uint8List>();
  static const int _maxUndoSteps   = 20;

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

  // ── Image loading ──────────────────────────────────────────────────────────

  Future<void> loadImage() async {
    try {
      final ByteData data   = await rootBundle.load(testImages[currentImageIndex]);
      final Uint8List bytes = data.buffer.asUint8List();

      // loadImage now also bakes the frozen border mask from the original PNG
      pixelEngine.loadImage(bytes);
      _originalBytes = bytes;
      _rawFillBytes  = null;
      _rawWidth      = pixelEngine.imageWidth;
      _rawHeight     = pixelEngine.imageHeight;

      // Clear undo history when a new image is loaded
      _undoStack.clear();

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

  Future<ui.Image> _decodeToUiImage(Uint8List bytes) async {
    final ui.Codec     codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<ui.Image> _rawRgbaToUiImage(Uint8List rgba, int width, int height) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width:       width,
      height:      height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final ui.Codec     codec = await descriptor.instantiateCodec();
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

  // ── Pointer handlers — UNCHANGED ───────────────────────────────────────────

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

    // Lock without setState — no UI flicker
    isProcessing = true;

    // ── Push undo snapshot BEFORE the fill ─────────────────────────────────
    // Store whatever the current raw bytes are so we can restore them on undo.
    // _rawFillBytes is null before the first fill, so we snapshot _originalBytes.
    final Uint8List snapshot = _rawFillBytes ?? _originalBytes!;
    if (_undoStack.length >= _maxUndoSteps) _undoStack.removeFirst();
    _undoStack.addLast(snapshot);

    final bool hasRaw = _rawFillBytes != null;

    // BFS fill in background isolate — returns raw RGBA, no encode.
    // Now passes the frozen borderMask so user-filled black pixels
    // are never treated as borders.
    final Uint8List rawResult = await compute(
      PixelEngine.processFloodFill,
      FloodFillRequest(
        imageBytes:    hasRaw ? _rawFillBytes! : _originalBytes!,
        x:             pixelX,
        y:             pixelY,
        fillColorRgba: img.getColor(
          selectedColor.red, selectedColor.green, selectedColor.blue, 255,
        ),
        borderMask: pixelEngine.borderMask, // frozen from original PNG
        isRawRgba:  hasRaw,
        rawWidth:   _rawWidth,
        rawHeight:  _rawHeight,
      ),
    );

    _rawFillBytes = rawResult;
    pixelEngine.updateFromRawBytes(rawResult, _rawWidth, _rawHeight);

    final ui.Image newUiImage =
    await _rawRgbaToUiImage(rawResult, _rawWidth, _rawHeight);

    final ui.Image? oldImage = _uiImage;
    setState(() {
      _uiImage     = newUiImage;
      isProcessing = false;
    });
    oldImage?.dispose();
  }

  // ── Undo ───────────────────────────────────────────────────────────────────

  Future<void> _undo() async {
    if (_undoStack.isEmpty || isProcessing) return;

    isProcessing = true;

    // Pop the most recent snapshot
    final Uint8List previous = _undoStack.removeLast();

    // Determine if the snapshot is raw RGBA or original encoded PNG.
    // The very first snapshot pushed is _originalBytes (encoded PNG).
    // Every subsequent snapshot is raw RGBA from a fill.
    // We distinguish them by checking if this snapshot IS _originalBytes.
    final bool isOriginalPng = identical(previous, _originalBytes);

    ui.Image restoredImage;

    if (isOriginalPng) {
      // Restoring to clean slate — decode the original PNG
      restoredImage  = await _decodeToUiImage(previous);
      _rawFillBytes  = null; // back to clean state, next fill will decode PNG
    } else {
      // Restoring to a previous raw RGBA fill state
      restoredImage = await _rawRgbaToUiImage(previous, _rawWidth, _rawHeight);
      _rawFillBytes = previous;
    }

    pixelEngine.updateFromRawBytes(
      isOriginalPng
          ? (img.decodeImage(previous)?.getBytes() ?? previous)
          : previous,
      _rawWidth,
      _rawHeight,
    );

    final ui.Image? oldImage = _uiImage;
    setState(() {
      _uiImage     = restoredImage;
      isProcessing = false;
    });
    oldImage?.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        elevation:       0,
        backgroundColor: Colors.white,
        title: const Text(
          'Coloring Book',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: isProcessing
            ? const Padding(
          padding: EdgeInsets.all(15),
          child:   CircularProgressIndicator(strokeWidth: 2),
        )
            : null,
        actions: [
          // Undo button — greyed out when stack is empty
          IconButton(
            icon: Icon(
              Icons.undo,
              color: _undoStack.isNotEmpty ? Colors.black : Colors.grey.shade300,
            ),
            onPressed: _undoStack.isNotEmpty ? _undo : null,
            tooltip: 'Undo',
          ),
          IconButton(
            icon:      const Icon(Icons.refresh, color: Colors.black),
            onPressed: loadImage,
            tooltip:   'Reset image',
          ),
          IconButton(
            icon:      Icon(Icons.colorize, color: selectedColor),
            onPressed: showPicker,
            tooltip:   'Pick colour',
          ),
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
                    color:        Colors.white,
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
                                child: RawImage(
                                  image:         _uiImage,
                                  fit:           BoxFit.contain,
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
                const Text(
                  'PALETTE',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 12, color: Colors.grey),
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
              padding:         const EdgeInsets.symmetric(horizontal: 15),
              itemCount:       colorHistory.length,
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
        margin:   const EdgeInsets.symmetric(horizontal: 8),
        width:    isSelected ? 52 : 44,
        decoration: BoxDecoration(
          color:  color,
          shape:  BoxShape.circle,
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
    setState(
            () => currentImageIndex = (currentImageIndex + delta) % testImages.length);
    loadImage();
  }

  Widget _navBtn(IconData icon, VoidCallback tap) =>
      IconButton(icon: Icon(icon, size: 18), onPressed: tap);
}