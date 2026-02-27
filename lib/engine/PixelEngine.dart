import 'dart:typed_data';
import 'package:image/image.dart' as img;

class FloodFillRequest {
  final Uint8List rawRgbaBytes;
  final Uint8List borderMask;
  final int x;
  final int y;
  final int width;
  final int height;
  final int fillR;
  final int fillG;
  final int fillB;

  const FloodFillRequest({
    required this.rawRgbaBytes,
    required this.borderMask,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.fillR,
    required this.fillG,
    required this.fillB,
  });
}

class PixelEngine {
  static const int _tolerance = 35;
  static const int _borderThreshold = 60;

  bool _isLoaded = false;
  int _width = 0;
  int _height = 0;
  Uint8List _originalRawRgba = Uint8List(0);
  Uint8List _currentRawRgba = Uint8List(0);
  Uint8List _borderMask = Uint8List(0);

  bool get isLoaded => _isLoaded;
  int get imageWidth => _width;
  int get imageHeight => _height;
  Uint8List get borderMask => _borderMask;
  Uint8List get originalRawRgba => _originalRawRgba;

  static Map<String, Object> decodeAndPrepare(Uint8List bytes) {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return <String, Object>{
        'width': 0,
        'height': 0,
        'raw': Uint8List(0),
        'borderMask': Uint8List(0),
      };
    }

    final int width = decoded.width;
    final int height = decoded.height;
    final Uint8List raw = Uint8List.fromList(decoded.getBytes());
    final int len = width * height;
    final Uint8List borderMask = Uint8List(len);

    for (int i = 0, bi = 0; i < len; i++, bi += 4) {
      if (raw[bi] < _borderThreshold &&
          raw[bi + 1] < _borderThreshold &&
          raw[bi + 2] < _borderThreshold) {
        borderMask[i] = 1;
      }
    }

    return <String, Object>{
      'width': width,
      'height': height,
      'raw': raw,
      'borderMask': borderMask,
    };
  }

  void applyPreparedImage(Map<String, Object> prepared) {
    final int width = prepared['width'] as int;
    final int height = prepared['height'] as int;
    final Uint8List raw = prepared['raw'] as Uint8List;
    final Uint8List borderMask = prepared['borderMask'] as Uint8List;

    if (width <= 0 || height <= 0 || raw.isEmpty || borderMask.isEmpty) {
      _isLoaded = false;
      _width = 0;
      _height = 0;
      _originalRawRgba = Uint8List(0);
      _currentRawRgba = Uint8List(0);
      _borderMask = Uint8List(0);
      return;
    }

    _width = width;
    _height = height;
    _originalRawRgba = raw;
    _currentRawRgba = _originalRawRgba;
    _borderMask = borderMask;
    _isLoaded = true;
  }

  void loadImage(Uint8List bytes) {
    applyPreparedImage(decodeAndPrepare(bytes));
  }

  void updateFromRawBytes(Uint8List rawRgba, int width, int height) {
    _width = width;
    _height = height;
    _currentRawRgba = rawRgba;
    _isLoaded = true;
  }

  static Uint8List processFloodFill(FloodFillRequest request) {
    final int w = request.width;
    final int h = request.height;
    if (w <= 0 || h <= 0) return request.rawRgbaBytes;

    final int len = w * h;
    if (request.rawRgbaBytes.lengthInBytes < len * 4 ||
        request.borderMask.lengthInBytes < len) {
      return request.rawRgbaBytes;
    }

    final Uint8List input = request.rawRgbaBytes;
    final Uint8List borderMask = request.borderMask;

    int startX = request.x;
    int startY = request.y;

    bool isBorder(int px, int py) {
      if (px < 0 || px >= w || py < 0 || py >= h) return true;
      return borderMask[(py * w) + px] == 1;
    }

    if (isBorder(startX, startY)) {
      bool found = false;
      outer:
      for (int i = -2; i <= 2; i++) {
        for (int j = -2; j <= 2; j++) {
          if (!isBorder(startX + i, startY + j)) {
            startX += i;
            startY += j;
            found = true;
            break outer;
          }
        }
      }
      if (!found) return request.rawRgbaBytes;
    }

    final int startPixelBase = ((startY * w) + startX) << 2;
    final int sR = input[startPixelBase];
    final int sG = input[startPixelBase + 1];
    final int sB = input[startPixelBase + 2];

    final int fR = request.fillR;
    final int fG = request.fillG;
    final int fB = request.fillB;

    if ((sR - fR).abs() <= _tolerance &&
        (sG - fG).abs() <= _tolerance &&
        (sB - fB).abs() <= _tolerance) {
      return request.rawRgbaBytes;
    }

    final Uint8List output = Uint8List.fromList(input);
    final Uint8List visited = Uint8List(len);
    final Int32List queue = Int32List(len);
    int head = 0;
    int tail = 0;

    final int startIndex = (startY * w) + startX;
    queue[tail++] = startIndex;
    visited[startIndex] = 1;

    while (head < tail) {
      final int idx = queue[head++];
      if (borderMask[idx] == 1) continue;

      final int byteBase = idx << 2;
      if ((output[byteBase] - sR).abs() > _tolerance ||
          (output[byteBase + 1] - sG).abs() > _tolerance ||
          (output[byteBase + 2] - sB).abs() > _tolerance) {
        continue;
      }

      output[byteBase] = fR;
      output[byteBase + 1] = fG;
      output[byteBase + 2] = fB;
      output[byteBase + 3] = 255;

      final int px = idx % w;
      final int py = idx ~/ w;

      if (px + 1 < w) {
        final int ni = idx + 1;
        if (visited[ni] == 0) {
          visited[ni] = 1;
          queue[tail++] = ni;
        }
      }
      if (px - 1 >= 0) {
        final int ni = idx - 1;
        if (visited[ni] == 0) {
          visited[ni] = 1;
          queue[tail++] = ni;
        }
      }
      if (py + 1 < h) {
        final int ni = idx + w;
        if (visited[ni] == 0) {
          visited[ni] = 1;
          queue[tail++] = ni;
        }
      }
      if (py - 1 >= 0) {
        final int ni = idx - w;
        if (visited[ni] == 0) {
          visited[ni] = 1;
          queue[tail++] = ni;
        }
      }
    }

    return output;
  }

  Uint8List exportImage() {
    if (!_isLoaded || _width == 0 || _height == 0 || _currentRawRgba.isEmpty) {
      return Uint8List(0);
    }
    final img.Image image = img.Image.fromBytes(
      _width,
      _height,
      _currentRawRgba,
    );
    return Uint8List.fromList(img.encodePng(image));
  }
}
