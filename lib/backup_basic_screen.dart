import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
  Color selectedColor = Colors.amber;

  final TransformationController _transformationController = TransformationController();
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  List<Color> colorHistory = [Colors.red, Colors.blue, Colors.green, Colors.black];
  final List<String> testImages = [
    'assets/images/doremon.png',
    'assets/images/shinchan.png',
    'assets/images/mandala.png',
    'assets/images/mandala-thick.png',
    'assets/images/smilie.png',
  ];
  int currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    loadImage();
    // Logic to prevent sub-pixel drift when returning to normal zoom
    _transformationController.addListener(() {
      double scale = _transformationController.value.getMaxScaleOnAxis();
      if (scale > 0.99 && scale < 1.01) {
        // Snap to perfect identity if very close to 1.0
        // This prevents the "neighbor pixel" error
      }
    });
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
      debugPrint('Error: $e');
    }
  }

  void handleTap(TapDownDetails details, Size containerSize) {
    if (!pixelEngine.isLoaded || imageBytes == null) return;

    // 1. Get exact Matrix and its Inverse
    final Matrix4 transform = _transformationController.value;
    final Matrix4 inverse = Matrix4.inverted(transform);

    // 2. Map Screen touch to Scene coordinate
    final Offset localOffset = details.localPosition;
    final Vector3 untransformed = inverse.transform3(Vector3(localOffset.dx, localOffset.dy, 0));
    final Offset sceneOffset = Offset(untransformed.x, untransformed.y);

    double imgW = pixelEngine.imageWidth.toDouble();
    double imgH = pixelEngine.imageHeight.toDouble();
    double viewW = containerSize.width;
    double viewH = containerSize.height;

    // 3. Robust BoxFit.contain Logic
    double scaleFit = (viewW / imgW < viewH / imgH) ? (viewW / imgW) : (viewH / imgH);

    // Explicitly define offsets to ensure 1.0 zoom maps perfectly
    double actualW = imgW * scaleFit;
    double actualH = imgH * scaleFit;
    double offsetX = (viewW - actualW) / 2.0;
    double offsetY = (viewH - actualH) / 2.0;

    // 4. Pixel Mapping with high-precision floor
    // Adding a tiny epsilon (0.0001) helps avoid floating point "boundary" errors
    int pixelX = ((sceneOffset.dx - offsetX) / scaleFit + 0.0001).floor();
    int pixelY = ((sceneOffset.dy - offsetY) / scaleFit + 0.0001).floor();

    print('--- STABILITY DEBUG ---');
    print('Scale: ${transform.getMaxScaleOnAxis().toStringAsFixed(4)}');
    print('Scene Offset: $sceneOffset');
    print('Target Pixel: ($pixelX, $pixelY)');

    if (pixelX >= 0 && pixelX < imgW && pixelY >= 0 && pixelY < imgH) {
      pixelEngine.floodFill(pixelX, pixelY, selectedColor);
      setState(() {
        imageBytes = pixelEngine.exportImage();
      });
    }
  }

  // Rest of your UI (build, showPicker, nextImage, etc.) remains identical...
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Image ${currentImageIndex + 1}'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: () {
          setState(() => currentImageIndex = (currentImageIndex - 1 + testImages.length) % testImages.length);
          loadImage();
        }),
        actions: [
          IconButton(icon: const Icon(Icons.arrow_forward_ios), onPressed: () {
            setState(() => currentImageIndex = (currentImageIndex + 1) % testImages.length);
            loadImage();
          }),
          IconButton(icon: Icon(Icons.palette, color: selectedColor), onPressed: showPicker),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: imageBytes == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return RawScrollbar(
                  controller: _hScroll,
                  child: RawScrollbar(
                    controller: _vScroll,
                    notificationPredicate: (n) => n.depth == 1,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 1.0,
                      maxScale: 20.0,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      child: GestureDetector(
                        onTapDown: (details) => handleTap(details, size),
                        behavior: HitTestBehavior.opaque,
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
                  ),
                );
              },
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  void showPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: selectedColor,
            onColorChanged: (c) => setState(() => selectedColor = c),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.colorize, size: 30), onPressed: showPicker),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: colorHistory.length,
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => setState(() => selectedColor = colorHistory[i]),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 45,
                  decoration: BoxDecoration(
                    color: colorHistory[i],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selectedColor == colorHistory[i] ? Colors.black : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}