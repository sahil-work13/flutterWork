import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart' as material;

/// Passed to the background isolate for each fill operation.
/// [isRawRgba] tells the isolate whether [imageBytes] is raw RGBA
/// (from a previous fill) or an encoded image (PNG/JPEG on first fill).
class FloodFillRequest {
  final Uint8List imageBytes;
  final int x;
  final int y;
  final int fillColorRgba;
  final bool isRawRgba; // true = skip decodeImage, reconstruct directly
  final int rawWidth;   // only used when isRawRgba == true
  final int rawHeight;  // only used when isRawRgba == true

  FloodFillRequest({
    required this.imageBytes,
    required this.x,
    required this.y,
    required this.fillColorRgba,
    this.isRawRgba = false,
    this.rawWidth  = 0,
    this.rawHeight = 0,
  });
}

class PixelEngine {
  img.Image? _image;
  bool _isLoaded = false;

  static const int _tolerance       = 35;
  static const int _borderThreshold = 60;

  bool get isLoaded    => _isLoaded;
  int  get imageWidth  => _image?.width  ?? 0;
  int  get imageHeight => _image?.height ?? 0;

  /// Initial load from asset — decodes PNG once.
  void loadImage(Uint8List bytes) {
    _image    = img.decodeImage(bytes);
    _isLoaded = _image != null;
  }

  /// After each fill the isolate returns raw RGBA bytes.
  /// Reconstruct the image directly — zero decode cost.
  void updateFromRawBytes(Uint8List rawRgba, int width, int height) {
    _image    = img.Image.fromBytes(width, height, rawRgba);
    _isLoaded = true;
  }

  void floodFill(int x, int y, material.Color fillColor) {
    material.debugPrint('Use compute(PixelEngine.processFloodFill, request)');
  }

  /// Runs in a background isolate.
  ///
  /// First fill : imageBytes = PNG, isRawRgba = false → decodeImage (once ever)
  /// Later fills: imageBytes = raw RGBA, isRawRgba = true → Image.fromBytes (fast)
  ///
  /// Always returns raw RGBA bytes — no encode step.
  static Uint8List processFloodFill(FloodFillRequest request) {
    // Reconstruct image — either from encoded bytes or raw RGBA
    final img.Image image = request.isRawRgba
        ? img.Image.fromBytes(request.rawWidth, request.rawHeight, request.imageBytes)
        : (img.decodeImage(request.imageBytes) ?? img.Image(0, 0));

    if (image.width == 0) return request.imageBytes;

    final int w = image.width;
    final int h = image.height;
    int startX  = request.x;
    int startY  = request.y;

    // Pre-bake border mask — single pass, O(w*h)
    final int       len        = w * h;
    final Uint8List borderMask = Uint8List(len);
    for (int i = 0; i < len; i++) {
      final int p = image.getPixel(i % w, i ~/ w);
      if (img.getRed(p)   < _borderThreshold &&
          img.getGreen(p) < _borderThreshold &&
          img.getBlue(p)  < _borderThreshold) {
        borderMask[i] = 1;
      }
    }

    bool isBorder(int px, int py) {
      if (px < 0 || px >= w || py < 0 || py >= h) return true;
      return borderMask[py * w + px] == 1;
    }

    // Nudge off border pixel
    if (isBorder(startX, startY)) {
      bool found = false;
      outer:
      for (int i = -2; i <= 2; i++) {
        for (int j = -2; j <= 2; j++) {
          if (!isBorder(startX + i, startY + j)) {
            startX += i; startY += j;
            found = true;
            break outer;
          }
        }
      }
      if (!found) return image.getBytes();
    }

    final int startPixel = image.getPixel(startX, startY);
    final int sR = img.getRed(startPixel);
    final int sG = img.getGreen(startPixel);
    final int sB = img.getBlue(startPixel);

    final int fR = img.getRed(request.fillColorRgba);
    final int fG = img.getGreen(request.fillColorRgba);
    final int fB = img.getBlue(request.fillColorRgba);

    if ((sR - fR).abs() <= _tolerance &&
        (sG - fG).abs() <= _tolerance &&
        (sB - fB).abs() <= _tolerance) {
      return image.getBytes();
    }

    // BFS — int-encoded coords, pre-allocated ring buffer, zero allocations
    final Uint8List visited = Uint8List(len);
    final Int32List queue   = Int32List(len);
    int head = 0, tail = 0;

    final int si      = startY * w + startX;
    queue[tail++]     = si;
    visited[si]       = 1;

    while (head < tail) {
      final int idx = queue[head++];
      final int px  = idx % w;
      final int py  = idx ~/ w;

      if (borderMask[idx] == 1) continue;

      final int cur = image.getPixel(px, py);
      if ((img.getRed(cur)   - sR).abs() > _tolerance ||
          (img.getGreen(cur) - sG).abs() > _tolerance ||
          (img.getBlue(cur)  - sB).abs() > _tolerance) continue;

      image.setPixel(px, py, request.fillColorRgba);

      if (px + 1 < w) { final int ni = idx + 1; if (visited[ni] == 0) { visited[ni] = 1; queue[tail++] = ni; } }
      if (px - 1 >= 0) { final int ni = idx - 1; if (visited[ni] == 0) { visited[ni] = 1; queue[tail++] = ni; } }
      if (py + 1 < h)  { final int ni = idx + w; if (visited[ni] == 0) { visited[ni] = 1; queue[tail++] = ni; } }
      if (py - 1 >= 0) { final int ni = idx - w; if (visited[ni] == 0) { visited[ni] = 1; queue[tail++] = ni; } }
    }

    // Return raw RGBA — caller does the encode separately (or not at all)
    return image.getBytes();
  }

  Uint8List exportImage() => Uint8List.fromList(img.encodePng(_image!));
}