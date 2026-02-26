import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart' as material;

/// Passed to the background isolate for each fill operation.
///
/// KEY FIX — [borderMask]:
/// Computed ONCE from the original PNG in [PixelEngine.loadImage] and never
/// changed again. Passing it here means the isolate never re-derives borders
/// from the current (possibly user-filled) pixels, so black-filled regions
/// are never mistaken for outline borders.
class FloodFillRequest {
  final Uint8List imageBytes;
  final int       x;
  final int       y;
  final int       fillColorRgba;
  final bool      isRawRgba;  // true = Image.fromBytes (fast), false = decodeImage (1st fill)
  final int       rawWidth;
  final int       rawHeight;
  final Uint8List borderMask; // frozen from original PNG — never mutated

  const FloodFillRequest({
    required this.imageBytes,
    required this.x,
    required this.y,
    required this.fillColorRgba,
    required this.borderMask,
    this.isRawRgba = false,
    this.rawWidth  = 0,
    this.rawHeight = 0,
  });
}

class PixelEngine {
  img.Image? _image;
  bool       _isLoaded = false;

  // Frozen border mask — computed once from original PNG, never updated on fills.
  // This is the fix that allows black-filled regions to be re-filled.
  Uint8List _borderMask = Uint8List(0);

  static const int _tolerance       = 35;
  static const int _borderThreshold = 60; // unchanged — same rule as before

  bool get isLoaded    => _isLoaded;
  int  get imageWidth  => _image?.width  ?? 0;
  int  get imageHeight => _image?.height ?? 0;

  /// Expose frozen mask so BasicScreen can pass it into every FloodFillRequest.
  Uint8List get borderMask => _borderMask;

  /// Decode original PNG and bake the border mask from it once.
  /// The mask is frozen here — fills never touch it.
  void loadImage(Uint8List bytes) {
    _image = img.decodeImage(bytes);
    if (_image == null) { _isLoaded = false; return; }

    final int w   = _image!.width;
    final int h   = _image!.height;
    final int len = w * h;
    _borderMask   = Uint8List(len);

    for (int i = 0; i < len; i++) {
      final int p = _image!.getPixel(i % w, i ~/ w);
      // Border rule UNCHANGED: dark pixel on all three channels
      if (img.getRed(p)   < _borderThreshold &&
          img.getGreen(p) < _borderThreshold &&
          img.getBlue(p)  < _borderThreshold) {
        _borderMask[i] = 1;
      }
    }
    _isLoaded = true;
  }

  /// Called after each fill — wraps raw RGBA in an img.Image (zero decode).
  /// Does NOT touch _borderMask — it stays frozen from loadImage().
  void updateFromRawBytes(Uint8List rawRgba, int width, int height) {
    _image    = img.Image.fromBytes(width, height, rawRgba);
    _isLoaded = true;
    // _borderMask intentionally NOT updated here
  }

  void floodFill(int x, int y, material.Color fillColor) {
    material.debugPrint('Use compute(PixelEngine.processFloodFill, request)');
  }

  /// BFS flood-fill — runs in a compute() isolate (static = no closure capture).
  ///
  /// Uses request.borderMask (frozen from original PNG) so user-painted
  /// black pixels are never treated as borders.
  /// Returns raw RGBA bytes — no encode step at all.
  static Uint8List processFloodFill(FloodFillRequest request) {
    final img.Image image = request.isRawRgba
        ? img.Image.fromBytes(request.rawWidth, request.rawHeight, request.imageBytes)
        : (img.decodeImage(request.imageBytes) ?? img.Image(0, 0));

    if (image.width == 0) return request.imageBytes;

    final int w = image.width;
    final int h = image.height;
    int startX  = request.x;
    int startY  = request.y;

    // Use the PRE-BAKED frozen border mask — never re-derived from current pixels
    final Uint8List borderMask = request.borderMask;

    bool isBorder(int px, int py) {
      if (px < 0 || px >= w || py < 0 || py >= h) return true;
      return borderMask[py * w + px] == 1;
    }

    // Nudge off border pixel — UNCHANGED logic
    if (isBorder(startX, startY)) {
      bool found = false;
      outer:
      for (int i = -2; i <= 2; i++) {
        for (int j = -2; j <= 2; j++) {
          if (!isBorder(startX + i, startY + j)) {
            startX += i;
            startY += j;
            found   = true;
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

    // Already this colour — nothing to do
    if ((sR - fR).abs() <= _tolerance &&
        (sG - fG).abs() <= _tolerance &&
        (sB - fB).abs() <= _tolerance) {
      return image.getBytes();
    }

    // BFS — int-encoded coords, pre-allocated Int32List ring buffer, zero heap allocs
    final int       len     = w * h;
    final Uint8List visited = Uint8List(len);
    final Int32List queue   = Int32List(len);
    int head = 0, tail = 0;

    final int si  = startY * w + startX;
    queue[tail++] = si;
    visited[si]   = 1;

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

      if (px + 1 < w)  { final int ni = idx + 1; if (visited[ni] == 0) { visited[ni] = 1; queue[tail++] = ni; } }
      if (px - 1 >= 0) { final int ni = idx - 1; if (visited[ni] == 0) { visited[ni] = 1; queue[tail++] = ni; } }
      if (py + 1 < h)  { final int ni = idx + w; if (visited[ni] == 0) { visited[ni] = 1; queue[tail++] = ni; } }
      if (py - 1 >= 0) { final int ni = idx - w; if (visited[ni] == 0) { visited[ni] = 1; queue[tail++] = ni; } }
    }

    return image.getBytes(); // raw RGBA, no encode
  }

  /// Export as lossless PNG — call only on save/share.
  Uint8List exportImage() => Uint8List.fromList(img.encodePng(_image!));
}