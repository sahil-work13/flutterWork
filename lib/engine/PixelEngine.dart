import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:collection';
import 'dart:math';
import 'package:flutter/material.dart' as material;

class PixelEngine {
  img.Image? _image;
  bool _isLoaded = false;

  static const int _tolerance = 30;

  bool get isLoaded => _isLoaded;
  int get imageWidth => _image?.width ?? 0;
  int get imageHeight => _image?.height ?? 0;

  void loadImage(Uint8List bytes) {
    _image = img.decodeImage(bytes);
    _isLoaded = _image != null;
    if (_isLoaded) {
      print('ENGINE: Image loaded successfully. Size: ${imageWidth}x${imageHeight}');
    }
  }

  void floodFill(int x, int y, material.Color fillColor) {
    if (!_isLoaded || _image == null) return;

    final int startPixel = _image!.getPixel(x, y);
    final int sR = img.getRed(startPixel);
    final int sG = img.getGreen(startPixel);
    final int sB = img.getBlue(startPixel);

    print('ENGINE: Start Fill at ($x, $y) | Target RGB: ($sR, $sG, $sB)');

    // Block if clicking on a black border (RGB < 60)
    if (sR < 60 && sG < 60 && sB < 60) {
      print('ENGINE: Canceled - Touched a black border.');
      return;
    }

    // Prevent re-filling same color
    if (sR == fillColor.red && sG == fillColor.green && sB == fillColor.blue) {
      print('ENGINE: Canceled - Area already matches selected color.');
      return;
    }

    final int w = _image!.width;
    final int h = _image!.height;
    final Uint8List visited = Uint8List(w * h);
    final Queue<Point<int>> queue = Queue()..add(Point(x, y));
    int filledCount = 0;

    while (queue.isNotEmpty) {
      final p = queue.removeFirst();
      if (p.x < 0 || p.y < 0 || p.x >= w || p.y >= h) continue;

      final int index = p.y * w + p.x;
      if (visited[index] == 1) continue;
      visited[index] = 1;

      final int current = _image!.getPixel(p.x, p.y);
      if (_isSimilar(current, sR, sG, sB)) {
        _image!.setPixelRgba(p.x, p.y, fillColor.red, fillColor.green, fillColor.blue, 255);
        filledCount++;

        queue.add(Point(p.x + 1, p.y));
        queue.add(Point(p.x - 1, p.y));
        queue.add(Point(p.x, p.y + 1));
        queue.add(Point(p.x, p.y - 1));
      }
    }
    print('ENGINE: Fill completed. Total pixels updated: $filledCount');
  }

  bool _isSimilar(int pixel, int sR, int sG, int sB) {
    return (img.getRed(pixel) - sR).abs() <= _tolerance &&
        (img.getGreen(pixel) - sG).abs() <= _tolerance &&
        (img.getBlue(pixel) - sB).abs() <= _tolerance;
  }

  Uint8List exportImage() => Uint8List.fromList(img.encodePng(_image!));
}