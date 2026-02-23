import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'dart:collection';
import 'dart:math';

class PixelEngine {
  late img.Image _image;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  int get imageWidth => _image.width;
  int get imageHeight => _image.height;

  static const int _tolerance = 10;

  void loadImage(Uint8List bytes) {
    print('🟢 PixelEngine: Loading image...');
    _image = img.decodeImage(bytes)!;

    // 🔍 Detect if image has large black filled areas
    bool hasFilledRegions = false;

    for (int y = 0; y < _image.height; y += 20) {
      for (int x = 0; x < _image.width; x += 20) {
        final p = _image.getPixel(x, y);
        if (p.r < 10 && p.g < 10 && p.b < 10) {
          hasFilledRegions = true;
          break;
        }
      }
      if (hasFilledRegions) break;
    }

    if (hasFilledRegions) {
      print('🟢 Filled-shape image detected → skipping preprocessing');
    } else {
      print('🟡 Line-art image detected → preprocessing');

      // --- BINARIZE ---
      for (int y = 0; y < _image.height; y++) {
        for (int x = 0; x < _image.width; x++) {
          final p = _image.getPixel(x, y);
          final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
          if (lum > 210) {
            _image.setPixelRgba(x, y, 255, 255, 255, 255);
          } else {
            _image.setPixelRgba(x, y, 0, 0, 0, 255);
          }
        }
      }

      // --- THICKEN BORDERS ---
      final copy = img.Image.from(_image);
      for (int y = 1; y < _image.height - 1; y++) {
        for (int x = 1; x < _image.width - 1; x++) {
          final p = copy.getPixel(x, y);
          if (p.r == 0 && p.g == 0 && p.b == 0) {
            for (int dy = -1; dy <= 1; dy++) {
              for (int dx = -1; dx <= 1; dx++) {
                _image.setPixelRgba(x + dx, y + dy, 0, 0, 0, 255);
              }
            }
          }
        }
      }
    }

    _isLoaded = true;
    print('🟢 Image ready → ${_image.width} x ${_image.height}');
  }

  /// 🔍 FIXED: supports int + num (alpha channel)
  bool _isSimilar(num a, num b) {
    return (a - b).abs() <= _tolerance;
  }

  // ... inside floodFill method in PixelEngine.dart

  void floodFill(int x, int y, ui.Color fillColor) {
    if (!_isLoaded) return;

    if (x < 0 || y < 0 || x >= _image.width || y >= _image.height) return;

    final startPixel = _image.getPixel(x, y);

    // 🔥 NEW: Protection logic
    // If the user taps something very dark (the lines), don't fill anything.
    if (startPixel.r < 50 && startPixel.g < 50 && startPixel.b < 50) {
      print('🟠 Tap ignored: You hit a black line/border.');
      return;
    }

    if (_isSimilar(startPixel.r, fillColor.red) &&
        _isSimilar(startPixel.g, fillColor.green) &&
        _isSimilar(startPixel.b, fillColor.blue)) {
      return;
    }

    final Queue<Point<int>> queue = Queue();
    queue.add(Point(x, y));

    // Create a 'target' to match against so we don't bleed into the black lines
    final int targetR = startPixel.r.toInt();
    final int targetG = startPixel.g.toInt();
    final int targetB = startPixel.b.toInt();

    while (queue.isNotEmpty) {
      final p = queue.removeFirst();

      if (p.x < 0 || p.y < 0 || p.x >= _image.width || p.y >= _image.height) continue;

      final current = _image.getPixel(p.x, p.y);

      // 🔥 IMPROVED: Strict boundary check
      // We only fill if the pixel is 'similar' to the white/light area we started in
      if (_isSimilar(current.r, targetR) &&
          _isSimilar(current.g, targetG) &&
          _isSimilar(current.b, targetB)) {

        _image.setPixelRgba(p.x, p.y, fillColor.red, fillColor.green, fillColor.blue, 255);

        queue.add(Point(p.x + 1, p.y));
        queue.add(Point(p.x - 1, p.y));
        queue.add(Point(p.x, p.y + 1));
        queue.add(Point(p.x, p.y - 1));
      }
    }
    print('🟢 Fill Finished');
  }

  Uint8List exportImage() {
    print('🟢 Exporting image bytes...');
    return Uint8List.fromList(img.encodePng(_image));
  }
}