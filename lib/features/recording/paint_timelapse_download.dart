import 'dart:typed_data';

import 'paint_timelapse_download_stub.dart'
    if (dart.library.html) 'paint_timelapse_download_web.dart'
    if (dart.library.io) 'paint_timelapse_download_io.dart' as impl;

Future<String?> saveTimelapseBytes(Uint8List bytes, String fileName) {
  return impl.saveTimelapseBytes(bytes, fileName);
}
