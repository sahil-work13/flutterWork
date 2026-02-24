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

  final List<Color> colorHistory = [
    Colors.red, Colors.blue, Colors.green, Colors.black,
    Colors.yellow, Colors.orange, Colors.purple, Colors.pink
  ];

  final List<String> testImages = [
    'assets/images/doremon.png',
    'assets/images/shinchan.png',
    'assets/images/mandala.png',
    'assets/images/smilie.png',
    'assets/images/mandala-thick.png',
  ];
  int currentImageIndex = 0;

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
      debugPrint('UI: Loaded image ${testImages[currentImageIndex]}');
    } catch (e) {
      debugPrint('UI: Load Error: $e');
    }
  }

  void handleTap(TapDownDetails details, Size containerSize) {
    if (!pixelEngine.isLoaded || imageBytes == null) return;

    debugPrint('--- TAP DEBUG START ---');
    debugPrint('Screen Touch: ${details.localPosition}');

    // 1. Convert Screen Touch to Zoomed Coordinate
    final Matrix4 transform = _transformationController.value;
    final Matrix4 inverse = Matrix4.inverted(transform);
    final Vector3 untransformed = inverse.transform3(Vector3(details.localPosition.dx, details.localPosition.dy, 0));

    debugPrint('Zoom Level: ${transform.getMaxScaleOnAxis()}');
    debugPrint('Coordinate after Zoom-Correction: (${untransformed.x}, ${untransformed.y})');

    // 2. Map Coordinate to Image Pixels
    double imgW = pixelEngine.imageWidth.toDouble();
    double imgH = pixelEngine.imageHeight.toDouble();
    double viewW = containerSize.width;
    double viewH = containerSize.height;

    double scaleFit = (viewW / imgW < viewH / imgH) ? (viewW / imgW) : (viewH / imgH);
    double offsetX = (viewW - (imgW * scaleFit)) / 2.0;
    double offsetY = (viewH - (imgH * scaleFit)) / 2.0;

    int pixelX = ((untransformed.x - offsetX) / scaleFit).round();
    int pixelY = ((untransformed.y - offsetY) / scaleFit).round();

    debugPrint('Scaling Math: FitScale=$scaleFit, OffsetX=$offsetX, OffsetY=$offsetY');
    debugPrint('TARGET PIXEL: ($pixelX, $pixelY) on ${imgW.toInt()}x${imgH.toInt()} image');

    if (pixelX >= 0 && pixelX < imgW && pixelY >= 0 && pixelY < imgH) {
      pixelEngine.floodFill(pixelX, pixelY, selectedColor);
      setState(() {
        imageBytes = pixelEngine.exportImage();
      });
    } else {
      debugPrint('TAP OUTSIDE IMAGE BOUNDS');
    }
    debugPrint('--- TAP DEBUG END ---');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Art ${currentImageIndex + 1}'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: loadImage),
          IconButton(icon: Icon(Icons.palette, color: selectedColor), onPressed: showPicker),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: imageBytes == null
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                    builder: (context, constraints) {
                      return InteractiveViewer(
                        transformationController: _transformationController,
                        panEnabled: true,
                        minScale: 1.0,
                        maxScale: 8.0,
                        child: GestureDetector(
                          onTapDown: (details) => handleTap(details, Size(constraints.maxWidth, constraints.maxHeight)),
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
                      );
                    },
                  ),
                ),
              ),
            ),

            Container(
              height: 140,
              padding: const EdgeInsets.only(top: 15, bottom: 25),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          setState(() => currentImageIndex = (currentImageIndex - 1 + testImages.length) % testImages.length);
                          loadImage();
                        },
                        child: const Icon(Icons.chevron_left),
                      ),
                      const Text("PICK A COLOR", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      ElevatedButton(
                        onPressed: () {
                          setState(() => currentImageIndex = (currentImageIndex + 1) % testImages.length);
                          loadImage();
                        },
                        child: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
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
                              color: selectedColor == colorHistory[i] ? Colors.blue : Colors.grey.shade300,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void showPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
}