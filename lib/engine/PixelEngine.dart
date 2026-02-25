import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:collection';
import 'dart:math';
import 'package:flutter/material.dart' as material;

/// Data class to pass data to the background Isolate
class FloodFillRequest {
  final Uint8List imageBytes;
  final int x;
  final int y;
  final int fillColorRgba;

  FloodFillRequest({
    required this.imageBytes,
    required this.x,
    required this.y,
    required this.fillColorRgba,
  });
}

class PixelEngine {
  img.Image? _image;
  img.Image? _originalImage;
  bool _isLoaded = false;

  static const int _tolerance = 35;
  static const int _borderThreshold = 60;

  bool get isLoaded => _isLoaded;
  int get imageWidth => _image?.width ?? 0;
  int get imageHeight => _image?.height ?? 0;

  void loadImage(Uint8List bytes) {
    _image = img.decodeImage(bytes);
    _originalImage = img.decodeImage(bytes);
    _isLoaded = _image != null;
  }

  // Added back to prevent 'undefined_method' errors in backup files
  void floodFill(int x, int y, material.Color fillColor) {
    // This is now a placeholder or can be used for non-async fills
    material.debugPrint("Use compute(PixelEngine.processFloodFill, request) for better performance");
  }

  static Uint8List processFloodFill(FloodFillRequest request) {
    final img.Image? currentImage = img.decodeImage(request.imageBytes);
    final img.Image? maskImage = img.decodeImage(request.imageBytes);

    if (currentImage == null || maskImage == null) return request.imageBytes;

    int x = request.x;
    int y = request.y;

    bool isBorder(int px, int py) {
      if (px < 0 || px >= currentImage.width || py < 0 || py >= currentImage.height) return true;
      final int p = maskImage.getPixel(px, py);
      return img.getRed(p) < _borderThreshold &&
          img.getGreen(p) < _borderThreshold &&
          img.getBlue(p) < _borderThreshold;
    }

    if (isBorder(x, y)) {
      bool found = false;
      for (int i = -2; i <= 2 && !found; i++) {
        for (int j = -2; j <= 2 && !found; j++) {
          if (!isBorder(x + i, y + j)) {
            x += i; y += j;
            found = true;
          }
        }
      }
      if (!found) return request.imageBytes;
    }

    final int startPixel = currentImage.getPixel(x, y);
    final int sR = img.getRed(startPixel), sG = img.getGreen(startPixel), sB = img.getBlue(startPixel);

    if (startPixel == request.fillColorRgba) return request.imageBytes;

    final int w = currentImage.width, h = currentImage.height;
    final Uint8List visited = Uint8List(w * h);
    final Queue<Point<int>> queue = Queue()..add(Point(x, y));

    while (queue.isNotEmpty) {
      final p = queue.removeFirst();
      if (p.x < 0 || p.y < 0 || p.x >= w || p.y >= h) continue;

      final int idx = p.y * w + p.x;
      if (visited[idx] == 1) continue;
      visited[idx] = 1;

      if (isBorder(p.x, p.y)) continue;

      final int current = currentImage.getPixel(p.x, p.y);
      if ((img.getRed(current) - sR).abs() <= _tolerance &&
          (img.getGreen(current) - sG).abs() <= _tolerance &&
          (img.getBlue(current) - sB).abs() <= _tolerance) {

        currentImage.setPixel(p.x, p.y, request.fillColorRgba);

        queue.add(Point(p.x + 1, p.y));
        queue.add(Point(p.x - 1, p.y));
        queue.add(Point(p.x, p.y + 1));
        queue.add(Point(p.x, p.y - 1));
      }
    }
    return Uint8List.fromList(img.encodePng(currentImage));
  }

  Uint8List exportImage() => Uint8List.fromList(img.encodePng(_image!));
}