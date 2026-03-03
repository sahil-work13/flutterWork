import 'dart:typed_data';

typedef TimelapseExportProgress = void Function(double progress);

Future<String?> exportTimelapseVideo({
  required List<Uint8List> frames,
  required int width,
  required int height,
  required Duration frameInterval,
  TimelapseExportProgress? onProgress,
}) async {
  return null;
}
