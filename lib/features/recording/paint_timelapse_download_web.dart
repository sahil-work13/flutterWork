// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:typed_data';

typedef TimelapseExportProgress = void Function(double progress);

Future<String?> exportTimelapseVideo({
  required List<Uint8List> frames,
  required int width,
  required int height,
  required Duration frameInterval,
  TimelapseExportProgress? onProgress,
}) async {
  onProgress?.call(0.0);
  html.window.alert('MP4 export is supported on Android and iOS in this app.');
  return null;
}
