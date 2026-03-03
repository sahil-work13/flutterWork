import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const MethodChannel _galleryChannel = MethodChannel('paint_timelapse/gallery');

Future<String?> saveTimelapseBytes(Uint8List bytes, String fileName) async {
  if (bytes.isEmpty) return null;

  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final String? savedPath = await _galleryChannel.invokeMethod<String>(
        'saveGifToGallery',
        <String, dynamic>{
          'bytes': bytes,
          'fileName': fileName,
        },
      );
      if (savedPath != null && savedPath.isNotEmpty) {
        return savedPath;
      }
    } catch (_) {}
  }

  Directory? targetDirectory;
  try {
    targetDirectory = await getDownloadsDirectory();
  } catch (_) {}
  targetDirectory ??= await getApplicationDocumentsDirectory();

  if (!await targetDirectory.exists()) {
    await targetDirectory.create(recursive: true);
  }

  final File file = File(
    '${targetDirectory.path}${Platform.pathSeparator}$fileName',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
