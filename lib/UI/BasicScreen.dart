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
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.orange,
    Colors.purple,
    Colors.black,
  ];

  @override
  void initState() {
    super.initState();
    loadImage();
  }

  Future<void> loadImage() async {
    print('🟢 Loading asset image...');
    final data = await rootBundle.load('assets/images/mandala-thick.png');
    final bytes = data.buffer.asUint8List();

    pixelEngine.loadImage(bytes);
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
    final localPos = box.globalToLocal(details.globalPosition);

    final imageWidth = box.size.width;
    final imageHeight = box.size.height;

    final scaleX = pixelEngine.imageWidth / imageWidth;
    final scaleY = pixelEngine.imageHeight / imageHeight;

    final x = (localPos.dx * scaleX).toInt();
    final y = (localPos.dy * scaleY).toInt();

    print('🟡 Tap UI → (${localPos.dx.toInt()}, ${localPos.dy.toInt()})');
    print('🟡 Mapped Pixel → ($x, $y)');
    print('🟡 Selected Color → $selectedColor');

    pixelEngine.floodFill(x, y, selectedColor);

    setState(() {
      imageBytes = pixelEngine.exportImage();
      print('🔄 UI setState called → bytes length: ${imageBytes!.length}');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (imageBytes == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Coloring App'),centerTitle: true,),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: GestureDetector(
                onTapDown: (d) => onTapDown(d, context),
                child: Image.memory(
                  imageBytes!,
                  key: ValueKey(imageBytes!.length), // 🔥 Uses data length as key to force refresh
                  gaplessPlayback: true, // 🔥 Prevents white flash during update
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
                        color: c == selectedColor
                            ? Colors.white
                            : Colors.transparent,
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