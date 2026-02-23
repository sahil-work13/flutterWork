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

  static const int _tolerance = 15; // Adjusted for better detail catching

  void loadImage(Uint8List bytes) {
    print('🟢 PixelEngine: Loading image...');
    _image = img.decodeImage(bytes)!;

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
    }

    _isLoaded = true;
    print('🟢 Image ready → ${_image.width} x ${_image.height}');
  }

  bool _isSimilar(num a, num b) {
    return (a - b).abs() <= _tolerance;
  }

  void floodFill(int x, int y, ui.Color fillColor) {
    if (!_isLoaded) return;
    if (x < 0 || y < 0 || x >= _image.width || y >= _image.height) return;

    final startPixel = _image.getPixel(x, y);

    // 🛑 NEW: Protection logic - Don't fill if user hits a black border
    if (startPixel.r < 50 && startPixel.g < 50 && startPixel.b < 50) {
      print('🟠 Tap ignored: You hit a black line/border.');
      return;
    }

    // LOGS PRESERVED
    print('🟡 FloodFill requested at ($x, $y)');
    print('🟡 Start Pixel RGBA → ${startPixel.r}, ${startPixel.g}, ${startPixel.b}, ${startPixel.a}');

    final int targetR = startPixel.r.toInt();
    final int targetG = startPixel.g.toInt();
    final int targetB = startPixel.b.toInt();

    if (targetR == fillColor.red && targetG == fillColor.green && targetB == fillColor.blue) return;

    final Queue<Point<int>> queue = Queue();
    queue.add(Point(x, y));

    int pixelsFilled = 0;

    while (queue.isNotEmpty) {
      final p = queue.removeFirst();

      if (p.x < 0 || p.y < 0 || p.x >= _image.width || p.y >= _image.height) continue;

      final current = _image.getPixel(p.x, p.y);

      // We fill if pixel is similar to what we tapped AND isn't a black line
      if (_isSimilar(current.r, targetR) &&
          _isSimilar(current.g, targetG) &&
          _isSimilar(current.b, targetB)) {

        // Final check to make sure we aren't bleeding into black lines
        if (!(current.r < 50 && current.g < 50 && current.b < 50)) {
          _image.setPixelRgba(p.x, p.y, fillColor.red, fillColor.green, fillColor.blue, 255);
          pixelsFilled++;

          queue.add(Point(p.x + 1, p.y));
          queue.add(Point(p.x - 1, p.y));
          queue.add(Point(p.x, p.y + 1));
          queue.add(Point(p.x, p.y - 1));
        }
      }
    }
    print('🟢 FloodFill complete → $pixelsFilled pixels filled');
  }

  Uint8List exportImage() {
    print('🟢 Exporting image bytes...');
    return Uint8List.fromList(img.encodePng(_image));
  }
}