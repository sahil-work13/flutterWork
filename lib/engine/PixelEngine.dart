import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:collection';
import 'dart:math';
import 'package:flutter/material.dart' as material;

class PixelEngine {
  img.Image? _image;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  int get imageWidth => _image?.width ?? 0;
  int get imageHeight => _image?.height ?? 0;

  static const int _tolerance = 15;

  void loadImage(Uint8List bytes) {
    _image = img.decodeImage(bytes);
    _isLoaded = _image != null;
  }

  bool _isSimilar(int a, int b) => (a - b).abs() <= _tolerance;

  void floodFill(int x, int y, material.Color fillColor) {
    if (!_isLoaded || _image == null) return;

    final int startPixel = _image!.getPixel(x, y);
    final int sR = img.getRed(startPixel);
    final int sG = img.getGreen(startPixel);
    final int sB = img.getBlue(startPixel);

    // Border protection: Stop if clicking near-black lines
    if (sR < 60 && sG < 60 && sB < 60) return;

    final Queue<Point<int>> queue = Queue()..add(Point(x, y));

    while (queue.isNotEmpty) {
      final p = queue.removeFirst();
      if (p.x < 0 || p.y < 0 || p.x >= _image!.width || p.y >= _image!.height) continue;

      final int current = _image!.getPixel(p.x, p.y);
      if (_isSimilar(img.getRed(current), sR) &&
          _isSimilar(img.getGreen(current), sG) &&
          _isSimilar(img.getBlue(current), sB)) {

        if (!(img.getRed(current) < 60 && img.getGreen(current) < 60 && img.getBlue(current) < 60)) {
          _image!.setPixelRgba(p.x, p.y, fillColor.red, fillColor.green, fillColor.blue, 255);
          queue.add(Point(p.x + 1, p.y));
          queue.add(Point(p.x - 1, p.y));
          queue.add(Point(p.x, p.y + 1));
          queue.add(Point(p.x, p.y - 1));
        }
      }
    }
  }

  Uint8List exportImage() => Uint8List.fromList(img.encodePng(_image!));
}