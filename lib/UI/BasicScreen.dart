import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../engine/PixelEngine.dart';

class BasicScreen extends StatefulWidget {
  const BasicScreen({super.key});

  @override
  State<BasicScreen> createState() => _BasicScreenState();
}

class _BasicScreenState extends State<BasicScreen> {
  final PixelEngine pixelEngine = PixelEngine();
  Uint8List? imageBytes;
  Color selectedColor = Colors.red;

  final List<Color> paletteColors = [
    Colors.red, Colors.green, Colors.blue, Colors.yellow,
    Colors.orange, Colors.purple, Colors.black,
  ];

  @override
  void initState() {
    super.initState();
    loadImage();
  }

  Future<void> loadImage() async {
    print('🟢 Loading asset image...');
    final data = await rootBundle.load('assets/images/doremon.png');
    final bytes = data.buffer.asUint8List();

    pixelEngine.loadImage(bytes);

    setState(() {
      imageBytes = bytes;
    });

    print('🟢 Image ready for UI');
  }

  void onTapDown(TapDownDetails details, BuildContext context) {
    if (!pixelEngine.isLoaded) {
      print('🔴 Tap ignored: image not loaded yet');
      return;
    }

    final RenderBox box = context.findRenderObject() as RenderBox;
    final Size size = box.size;

    // --- NEW: LOGIC TO REMOVE EMPTY SPACE (LETTERBOXING) ---
    double imageAspectRatio = pixelEngine.imageWidth / pixelEngine.imageHeight;
    double screenAspectRatio = size.width / size.height;

    double actualDisplayedWidth, actualDisplayedHeight;
    double offsetX = 0, offsetY = 0;

    if (screenAspectRatio > imageAspectRatio) {
      // Screen is wider than image (bars on left/right)
      actualDisplayedHeight = size.height;
      actualDisplayedWidth = size.height * imageAspectRatio;
      offsetX = (size.width - actualDisplayedWidth) / 2;
    } else {
      // Screen is taller than image (bars on top/bottom)
      actualDisplayedWidth = size.width;
      actualDisplayedHeight = size.width / imageAspectRatio;
      offsetY = (size.height - actualDisplayedHeight) / 2;
    }

    // Adjust tap position based on the offset
    final double relativeX = details.localPosition.dx - offsetX;
    final double relativeY = details.localPosition.dy - offsetY;

    // Scale to pixel coordinates
    final int x = (relativeX * (pixelEngine.imageWidth / actualDisplayedWidth)).toInt();
    final int y = (relativeY * (pixelEngine.imageHeight / actualDisplayedHeight)).toInt();

    print('🟡 Tap UI → (${details.localPosition.dx.toInt()}, ${details.localPosition.dy.toInt()})');
    print('🟡 Offset → (X: ${offsetX.toInt()}, Y: ${offsetY.toInt()})');
    print('🟡 Mapped Pixel → ($x, $y)');
    print('🟡 Selected Color → $selectedColor');

    // Only process if the tap is inside the image bounds
    if (x >= 0 && x < pixelEngine.imageWidth && y >= 0 && y < pixelEngine.imageHeight) {
      pixelEngine.floodFill(x, y, selectedColor);

      setState(() {
        imageBytes = pixelEngine.exportImage();
        print('🔄 UI setState called → bytes length: ${imageBytes!.length}');
      });
    } else {
      print('🟠 Tap outside image boundaries');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (imageBytes == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Coloring App'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: GestureDetector(
                  onTapDown: (d) => onTapDown(d, context),
                  child: Image.memory(
                    imageBytes!,
                    key: ValueKey(imageBytes!.length),
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                  )
              ),
            ),
          ),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: paletteColors.length,
              itemBuilder: (_, i) {
                final c = paletteColors[i];
                return GestureDetector(
                  onTap: () {
                    print('🎨 Color selected → $c');
                    setState(() => selectedColor = c);
                  },
                  child: Container(
                    margin: const EdgeInsets.all(10),
                    width: 50,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == selectedColor ? Colors.white : Colors.transparent,
                        width: 4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}