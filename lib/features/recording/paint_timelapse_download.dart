import 'dart:typed_data';

import 'paint_timelapse_download_fallback.dart'
    if (dart.library.html) 'paint_timelapse_download_web.dart'
    if (dart.library.io) 'paint_timelapse_download_io.dart' as impl;

typedef TimelapseExportProgress = void Function(double progress);

Future<String?> exportTimelapseVideo({
  required List<Uint8List> frames,
  required int width,
  required int height,
  required Duration frameInterval,
  TimelapseExportProgress? onProgress,
}) {
  return impl.exportTimelapseVideo(
    frames: frames,
    width: width,
    height: height,
    frameInterval: frameInterval,
    onProgress: onProgress,
  );
}
