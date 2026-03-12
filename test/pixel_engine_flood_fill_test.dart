import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterwork/engine/pixelEngine.dart';

void main() {
  group('PixelEngine flood fill', () {
    test('matches the legacy BFS behavior for region-fill and fallback paths', () {
      final Random random = Random(123456);

      for (int caseIndex = 0; caseIndex < 40; caseIndex++) {
        final PixelEngine engine = PixelEngine();
        final int width = 6 + random.nextInt(10);
        final int height = 6 + random.nextInt(10);
        final _RandomImage image = _buildRandomImage(random, width, height);
        final int startX = random.nextInt(width);
        final int startY = random.nextInt(height);
        final FloodFillRequest request = FloodFillRequest(
          rawRgbaBytes: image.raw,
          borderMask: image.borderMask,
          x: startX,
          y: startY,
          width: width,
          height: height,
          fillR: random.nextInt(256),
          fillG: random.nextInt(256),
          fillB: random.nextInt(256),
        );

        engine.applyPreparedImage(<String, Object>{
          'width': width,
          'height': height,
          'raw': image.raw,
          'borderMask': image.borderMask,
        });

        final _ReferenceFillResult expected = _runReferenceFloodFill(request);
        final Map<String, Object> cachedStaticActual =
            PixelEngine.processFloodFillToMap(request);
        final Map<String, Object> fallbackStaticActual =
            PixelEngine.processFloodFillToMap(
              FloodFillRequest(
                rawRgbaBytes: image.raw,
                borderMask: Uint8List.fromList(image.borderMask),
                x: startX,
                y: startY,
                width: width,
                height: height,
                fillR: request.fillR,
                fillG: request.fillG,
                fillB: request.fillB,
              ),
            );
        final Map<String, Object> localActual = engine.processFloodFillToMapLocal(
          request,
        );

        expect(
          cachedStaticActual['changed'],
          expected.changed,
          reason: 'cached static changed mismatch on case $caseIndex',
        );
        expect(
          fallbackStaticActual['changed'],
          expected.changed,
          reason: 'fallback static changed mismatch on case $caseIndex',
        );
        expect(
          localActual['changed'],
          expected.changed,
          reason: 'local changed mismatch on case $caseIndex',
        );
        expect(
          cachedStaticActual['raw'],
          orderedEquals(expected.raw),
          reason: 'cached static raw mismatch on case $caseIndex',
        );
        expect(
          fallbackStaticActual['raw'],
          orderedEquals(expected.raw),
          reason: 'fallback static raw mismatch on case $caseIndex',
        );
        expect(
          localActual['raw'],
          orderedEquals(expected.raw),
          reason: 'local raw mismatch on case $caseIndex',
        );
      }
    });

    test('keeps the original buffer on no-op fills', () {
      final Uint8List raw = Uint8List.fromList(<int>[
        100, 110, 120, 255,
        100, 110, 120, 255,
        100, 110, 120, 255,
        100, 110, 120, 255,
      ]);
      final Uint8List borderMask = Uint8List(4);
      final FloodFillRequest request = FloodFillRequest(
        rawRgbaBytes: raw,
        borderMask: borderMask,
        x: 0,
        y: 0,
        width: 2,
        height: 2,
        fillR: 120,
        fillG: 125,
        fillB: 130,
      );

      final PixelEngine engine = PixelEngine();
      engine.applyPreparedImage(<String, Object>{
        'width': 2,
        'height': 2,
        'raw': raw,
        'borderMask': borderMask,
      });

      final Map<String, Object> staticActual =
          PixelEngine.processFloodFillToMap(request);
      final Map<String, Object> localActual = engine.processFloodFillToMapLocal(
        request,
      );

      expect(staticActual['changed'], isFalse);
      expect(localActual['changed'], isFalse);
      expect(identical(staticActual['raw'], raw), isTrue);
      expect(identical(localActual['raw'], raw), isTrue);
    });
  });
}

class _RandomImage {
  final Uint8List raw;
  final Uint8List borderMask;

  const _RandomImage({required this.raw, required this.borderMask});
}

class _ReferenceFillResult {
  final Uint8List raw;
  final bool changed;

  const _ReferenceFillResult({required this.raw, required this.changed});
}

_RandomImage _buildRandomImage(Random random, int width, int height) {
  final List<int> palette = <int>[0, 24, 48, 64, 96, 128, 160, 192, 224, 255];
  final int len = width * height;
  final Uint8List raw = Uint8List(len * 4);
  final Uint8List borderMask = Uint8List(len);

  for (int i = 0, bi = 0; i < len; i++, bi += 4) {
    final bool isBorder = random.nextInt(100) < 18;
    borderMask[i] = isBorder ? 1 : 0;
    raw[bi] = palette[random.nextInt(palette.length)];
    raw[bi + 1] = palette[random.nextInt(palette.length)];
    raw[bi + 2] = palette[random.nextInt(palette.length)];
    raw[bi + 3] = 255;
  }

  return _RandomImage(raw: raw, borderMask: borderMask);
}

_ReferenceFillResult _runReferenceFloodFill(FloodFillRequest request) {
  const int tolerance = 35;
  final int width = request.width;
  final int height = request.height;
  if (width <= 0 || height <= 0) {
    return _ReferenceFillResult(raw: request.rawRgbaBytes, changed: false);
  }

  final int len = width * height;
  if (request.rawRgbaBytes.lengthInBytes < len * 4 ||
      request.borderMask.lengthInBytes < len) {
    return _ReferenceFillResult(raw: request.rawRgbaBytes, changed: false);
  }

  final Uint8List input = request.rawRgbaBytes;
  final Uint8List borderMask = request.borderMask;
  int startX = request.x;
  int startY = request.y;

  bool isBorder(int px, int py) {
    if (px < 0 || px >= width || py < 0 || py >= height) {
      return true;
    }
    return borderMask[(py * width) + px] == 1;
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
    if (!found) {
      return _ReferenceFillResult(raw: request.rawRgbaBytes, changed: false);
    }
  }

  final int startPixelBase = ((startY * width) + startX) << 2;
  final int sourceR = input[startPixelBase];
  final int sourceG = input[startPixelBase + 1];
  final int sourceB = input[startPixelBase + 2];

  if ((sourceR - request.fillR).abs() <= tolerance &&
      (sourceG - request.fillG).abs() <= tolerance &&
      (sourceB - request.fillB).abs() <= tolerance) {
    return _ReferenceFillResult(raw: request.rawRgbaBytes, changed: false);
  }

  final Uint8List output = Uint8List.fromList(input);
  final Uint8List visited = Uint8List(len);
  final Int32List queue = Int32List(len);
  int head = 0;
  int tail = 0;

  final int startIndex = (startY * width) + startX;
  queue[tail++] = startIndex;
  visited[startIndex] = 1;

  while (head < tail) {
    final int index = queue[head++];
    if (borderMask[index] == 1) {
      continue;
    }

    final int byteBase = index << 2;
    if ((output[byteBase] - sourceR).abs() > tolerance ||
        (output[byteBase + 1] - sourceG).abs() > tolerance ||
        (output[byteBase + 2] - sourceB).abs() > tolerance) {
      continue;
    }

    output[byteBase] = request.fillR;
    output[byteBase + 1] = request.fillG;
    output[byteBase + 2] = request.fillB;
    output[byteBase + 3] = 255;

    final int px = index % width;
    final int py = index ~/ width;

    if (px + 1 < width) {
      final int nextIndex = index + 1;
      if (visited[nextIndex] == 0) {
        visited[nextIndex] = 1;
        queue[tail++] = nextIndex;
      }
    }
    if (px - 1 >= 0) {
      final int nextIndex = index - 1;
      if (visited[nextIndex] == 0) {
        visited[nextIndex] = 1;
        queue[tail++] = nextIndex;
      }
    }
    if (py + 1 < height) {
      final int nextIndex = index + width;
      if (visited[nextIndex] == 0) {
        visited[nextIndex] = 1;
        queue[tail++] = nextIndex;
      }
    }
    if (py - 1 >= 0) {
      final int nextIndex = index - width;
      if (visited[nextIndex] == 0) {
        visited[nextIndex] = 1;
        queue[tail++] = nextIndex;
      }
    }
  }

  return _ReferenceFillResult(raw: output, changed: true);
}
