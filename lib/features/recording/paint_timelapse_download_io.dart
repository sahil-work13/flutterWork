import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

typedef TimelapseExportProgress = void Function(double progress);

const MethodChannel _videoExportChannel =
    MethodChannel('paint_timelapse/video_export');
const EventChannel _videoExportProgressChannel =
    EventChannel('paint_timelapse/video_export_progress');

Future<String?> exportTimelapseVideo({
  required List<Uint8List> frames,
  required int width,
  required int height,
  required Duration frameInterval,
  TimelapseExportProgress? onProgress,
}) async {
  if (frames.isEmpty || width <= 0 || height <= 0) return null;

  final int expectedFrameBytes = width * height * 4;
  final int frameDurationMs = frameInterval.inMilliseconds < 1
      ? 1
      : frameInterval.inMilliseconds;
  final String exportId =
      'export_${DateTime.now().microsecondsSinceEpoch.toString()}';
  final String fileName =
      'coloring_timelapse_${DateTime.now().millisecondsSinceEpoch}.mp4';

  final Directory tempDir = await getTemporaryDirectory();
  final File rawFile = File('${tempDir.path}${Platform.pathSeparator}$exportId.raw');
  final IOSink sink = rawFile.openWrite();

  StreamSubscription<dynamic>? progressSubscription;
  try {
    int validFrames = 0;
    for (int i = 0; i < frames.length; i++) {
      final Uint8List frame = frames[i];
      if (frame.lengthInBytes != expectedFrameBytes) continue;
      sink.add(frame);
      validFrames++;
      final double prepProgress = ((i + 1) / frames.length) * 0.2;
      onProgress?.call(prepProgress);
    }
    await sink.flush();
    await sink.close();

    if (validFrames == 0) return null;
    onProgress?.call(0.2);

    progressSubscription = _videoExportProgressChannel
        .receiveBroadcastStream()
        .listen((dynamic event) {
      if (event is! Map<dynamic, dynamic>) return;
      if (event['exportId'] != exportId) return;

      final dynamic rawProgress = event['progress'];
      if (rawProgress is num) {
        final double clamped = rawProgress.toDouble().clamp(0.0, 1.0);
        onProgress?.call(0.2 + (clamped * 0.8));
      }
    });

    final String? savedPath = await _videoExportChannel.invokeMethod<String>(
      'exportMp4ToGallery',
      <String, dynamic>{
        'exportId': exportId,
        'fileName': fileName,
        'rawPath': rawFile.path,
        'frameCount': validFrames,
        'width': width,
        'height': height,
        'frameDurationMs': frameDurationMs,
      },
    );
    onProgress?.call(1.0);
    return savedPath;
  } finally {
    await progressSubscription?.cancel();
    if (await rawFile.exists()) {
      await rawFile.delete();
    }
  }
}
