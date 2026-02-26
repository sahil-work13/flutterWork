import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart' as material;

/// Passed to the background isolate for each fill operation.
///
/// [isRawRgba] tells the isolate whether [imageBytes] is raw RGBA
/// (from a previous fill) or an encoded image (PNG/JPEG on first fill).
///
/// [borderMask] is a pre-baked flat Uint8List computed ONCE from the
/// original PNG on load. It is passed on every fill so the isolate never
/// re-derives borders from the current (possibly user-filled) pixels.
/// This is what allows black fills to be re-filled — the mask never
/// changes after load, so user-painted black pixels are NOT treated as borders.
class FloodFillRequest {
  final Uint8List imageBytes;
  final int       x;
  final int       y;
  final int       fillColorRgba;
  final bool      isRawRgba;   // true = skip decodeImage, use Image.fromBytes
  final int       rawWidth;    // required when isRawRgba == true
  final int       rawHeight;   // required when isRawRgba == true
  final Uint8List borderMask;  // computed once from original PNG, never mutated

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

  // Border mask computed once from original PNG and never changed.
  // Passed to every FloodFillRequest so user-filled dark pixels
  // are never mistaken for outline borders.
  Uint8List _borderMask = Uint8List(0);

  static const int _tolerance       = 35;
  static const int _borderThreshold = 60;  // ← UNTOUCHED — same as before

  bool get isLoaded    => _isLoaded;
  int  get imageWidth  => _image?.width  ?? 0;
  int  get imageHeight => _image?.height ?? 0;

  /// Border mask getter — passed into every FloodFillRequest.
  Uint8List get borderMask => _borderMask;

  /// Decode original PNG once and bake the border mask from it.
  /// Called only on image load — never on fills.
  void loadImage(Uint8List bytes) {
    _image = img.decodeImage(bytes);
    if (_image == null) { _isLoaded = false; return; }

    // Bake border mask from the ORIGINAL image pixels.
    // This mask is frozen here and never updated, so user-filled black pixels
    // will never be classified as borders on future fills.
    final int w   = _image!.width;
    final int h   = _image!.height;
    final int len = w * h;
    _borderMask   = Uint8List(len);
    for (int i = 0; i < len; i++) {
      final int p = _image!.getPixel(i % w, i ~/ w);
      if (img.getRed(p)   < _borderThreshold &&
          img.getGreen(p) < _borderThreshold &&
          img.getBlue(p)  < _borderThreshold) {
        _borderMask[i] = 1;
      }
    }

    _isLoaded = true;
  }

  /// After each fill the isolate returns raw RGBA bytes.
  /// Reconstruct working image directly — zero decode cost.
  /// The border mask is NOT recomputed here — it stays frozen from loadImage().
  void updateFromRawBytes(Uint8List rawRgba, int width, int height) {
    _image    = img.Image.fromBytes(width, height, rawRgba);
    _isLoaded = true;
    // _borderMask intentionally NOT touched — stays as original
  }

  void floodFill(int x, int y, material.Color fillColor) {
    material.debugPrint('Use compute(PixelEngine.processFloodFill, request)');
  }

  /// BFS flood-fill — runs inside a compute() isolate (must be static).
  ///
  /// Border detection uses [request.borderMask] which was baked from the
  /// original PNG. This means user-filled dark/black pixels are NEVER treated
  /// as borders — they remain re-fillable with any colour.
  ///
  /// The border outline logic itself is completely unchanged:
  ///   pixels where R < 60 && G < 60 && B < 60  →  border (in original image)
  ///
  /// Returns raw RGBA bytes — no encode step.
  static Uint8List processFloodFill(FloodFillRequest request) {
    // Reconstruct working image
    final img.Image image = request.isRawRgba
        ? img.Image.fromBytes(request.rawWidth, request.rawHeight, request.imageBytes)
        : (img.decodeImage(request.imageBytes) ?? img.Image(0, 0));

    if (image.width == 0) return request.imageBytes;

    final int w = image.width;
    final int h = image.height;
    int startX  = request.x;
    int startY  = request.y;

    // Use the PRE-BAKED border mask from the original PNG.
    // ── BORDER LOGIC UNCHANGED ──────────────────────────────────────────────
    // The mask was built with: R < 60 && G < 60 && B < 60 → border
    // Exactly the same rule as before — but computed from the original image,
    // so user-filled black pixels are invisible to this mask.
    final Uint8List borderMask = request.borderMask;

    bool isBorder(int px, int py) {
      if (px < 0 || px >= w || py < 0 || py >= h) return true;
      return borderMask[py * w + px] == 1;
    }
    // ── END BORDER LOGIC ────────────────────────────────────────────────────

    // Nudge off border pixel — UNTOUCHED
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