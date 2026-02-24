import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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

  // History of colors used
  List<Color> colorHistory = [Colors.red, Colors.blue, Colors.green, Colors.black];

  // List of images for testing
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
    loadImage(); // Initial load
  }

  // Optimized single loadImage function
  Future<void> loadImage() async {
    try {
      print('🟢 Loading: ${testImages[currentImageIndex]}');
      final data = await rootBundle.load(testImages[currentImageIndex]);
      final bytes = data.buffer.asUint8List();

      pixelEngine.loadImage(bytes);

      setState(() {
        imageBytes = bytes;
      });
    } catch (e) {
      print('🔴 Error loading image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load ${testImages[currentImageIndex]}')),
      );
    }
  }

  void nextImage() {
    setState(() {
      currentImageIndex = (currentImageIndex + 1) % testImages.length;
      imageBytes = null; // Show loading spinner
    });
    loadImage();
  }

  void previousImage() {
    setState(() {
      currentImageIndex = (currentImageIndex - 1 + testImages.length) % testImages.length;
      imageBytes = null; // Show loading spinner
    });
    loadImage();
  }

  void showPicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pick a color!'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: selectedColor,
              onColorChanged: (Color color) {
                setState(() => selectedColor = color);
              },
            ),
          ),
          actions: <Widget>[
            ElevatedButton(
              child: const Text('Got it'),
              onPressed: () {
                if (!colorHistory.contains(selectedColor)) {
                  setState(() => colorHistory.insert(0, selectedColor));
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void handleTap(TapDownDetails details, Size containerSize) {
    if (!pixelEngine.isLoaded) return;

    double imageWidth = pixelEngine.imageWidth.toDouble();
    double imageHeight = pixelEngine.imageHeight.toDouble();
    double containerWidth = containerSize.width;
    double containerHeight = containerSize.height;

    double scale = (containerWidth / imageWidth < containerHeight / imageHeight)
        ? containerWidth / imageWidth
        : containerHeight / imageHeight;

    double actualVisibleWidth = imageWidth * scale;
    double actualVisibleHeight = imageHeight * scale;

    double offsetX = (containerWidth - actualVisibleWidth) / 2;
    double offsetY = (containerHeight - actualVisibleHeight) / 2;

    double relativeX = details.localPosition.dx - offsetX;
    double relativeY = details.localPosition.dy - offsetY;

    int pixelX = (relativeX / scale).toInt();
    int pixelY = (relativeY / scale).toInt();

    if (pixelX >= 0 && pixelX < imageWidth && pixelY >= 0 && pixelY < imageHeight) {
      pixelEngine.floodFill(pixelX, pixelY, selectedColor);
      setState(() {
        imageBytes = pixelEngine.exportImage();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Test Image ${currentImageIndex + 1}/${testImages.length}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: previousImage,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: nextImage,
          ),
          IconButton(
            icon: Icon(Icons.palette, color: selectedColor),
            onPressed: showPicker,
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: imageBytes == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) => handleTap(details, Size(constraints.maxWidth, constraints.maxHeight)),
                  child: Center(
                    child: Image.memory(
                      imageBytes!,
                      // Using both length and index as key to ensure refresh on image swap
                      key: ValueKey('${imageBytes!.length}_$currentImageIndex'),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
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

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: showPicker,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 15),
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selectedColor,
                border: Border.all(color: Colors.grey, width: 2),
              ),
              child: const Icon(Icons.colorize, color: Colors.white),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: colorHistory.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => setState(() => selectedColor = colorHistory[index]),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      width: 40,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorHistory[index],
                          border: Border.all(
                              color: selectedColor == colorHistory[index] ? Colors.black : Colors.transparent,
                              width: 2
                          )
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}