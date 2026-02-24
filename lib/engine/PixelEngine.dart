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

  static const int _tolerance = 20;

  void loadImage(Uint8List bytes) {
    _image = img.decodeImage(bytes);
    _isLoaded = _image != null;
  }

  bool _isSimilar(int pixel, int sR, int sG, int sB) {
    final pr = img.getRed(pixel);
    final pg = img.getGreen(pixel);
    final pb = img.getBlue(pixel);
    return (pr - sR).abs() <= _tolerance &&
        (pg - sG).abs() <= _tolerance &&
        (pb - sB).abs() <= _tolerance;
  }

  void floodFill(int x, int y, material.Color fillColor) {
    if (!_isLoaded || _image == null) return;

    final int startPixel = _image!.getPixel(x, y);
    final int sR = img.getRed(startPixel);
    final int sG = img.getGreen(startPixel);
    final int sB = img.getBlue(startPixel);

    // Stop if hitting dark lines/borders
    if (sR < 65 && sG < 65 && sB < 65) return;
    if (sR == fillColor.red && sG == fillColor.green && sB == fillColor.blue) return;

    final Queue<Point<int>> queue = Queue()..add(Point(x, y));
    final int w = _image!.width;
    final int h = _image!.height;

    while (queue.isNotEmpty) {
      final p = queue.removeFirst();
      if (p.x < 0 || p.y < 0 || p.x >= w || p.y >= h) continue;

      final int current = _image!.getPixel(p.x, p.y);
      if (_isSimilar(current, sR, sG, sB)) {
        // Prevent color "leaking" through thin lines
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