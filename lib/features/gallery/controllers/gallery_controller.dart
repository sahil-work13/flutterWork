import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

class GalleryController extends ChangeNotifier {

  static const String sessionNamespace = 'coloring_book_session_v2';
  static const String metaBoxSuffix = '_metadata_box';

  List<Map<String, dynamic>> galleryItems = [];
  bool loading = true;

  Future<void> loadGallery() async {

    loading = true;
    notifyListeners();

    final Directory dir = await getApplicationDocumentsDirectory();
    final Directory sessionDir =
        Directory('${dir.path}/$sessionNamespace');

    Hive.init(sessionDir.path);
    final box = await Hive.openBox('${sessionNamespace}${metaBoxSuffix}');

    final List<Map<String, dynamic>> items = [];

    for (var key in box.keys) {

      if (!key.toString().startsWith('image_meta_')) continue;

      final meta = box.get(key);

      if (meta == null) continue;
      if (meta['hasRawFill'] != true) continue;

      final int imageIndex = meta['imageId'];

      items.add({
        "emoji": "🎨",
        "title": "Artwork ${imageIndex + 1}",
        "date": DateTime.now().toString().substring(0, 10),
        "imageIndex": imageIndex
      });
    }

    galleryItems = items;
    loading = false;

    notifyListeners();
  }
}