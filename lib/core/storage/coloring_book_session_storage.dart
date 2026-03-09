import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

class ColoringBookSessionStorage {
  static const String sessionNamespace = 'coloring_book_session_v2';
  static const String metaBoxName = '${sessionNamespace}_metadata_box';

  static Directory? _sessionDirectory;
  static Box<dynamic>? _metaBox;
  static Future<Box<dynamic>>? _openBoxFuture;

  static Future<Directory> ensureSessionDirectory() async {
    final Directory? cached = _sessionDirectory;
    if (cached != null) {
      return cached;
    }

    final Directory appSupportDir = await getApplicationDocumentsDirectory();
    final Directory sessionDir = Directory(
      '${appSupportDir.path}${Platform.pathSeparator}$sessionNamespace',
    );
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }
    _sessionDirectory = sessionDir;
    return sessionDir;
  }

  static Future<Box<dynamic>> ensureMetaBox() async {
    final Box<dynamic>? cached = _metaBox;
    if (cached != null && cached.isOpen) {
      return cached;
    }

    final Future<Box<dynamic>>? pending = _openBoxFuture;
    if (pending != null) {
      return pending;
    }

    final Future<Box<dynamic>> openFuture = _openMetaBox();
    _openBoxFuture = openFuture;
    try {
      final Box<dynamic> box = await openFuture;
      _metaBox = box;
      return box;
    } finally {
      if (identical(_openBoxFuture, openFuture)) {
        _openBoxFuture = null;
      }
    }
  }

  static Future<Box<dynamic>> _openMetaBox() async {
    final Directory sessionDir = await ensureSessionDirectory();
    Hive.init(sessionDir.path);
    if (Hive.isBoxOpen(metaBoxName)) {
      return Hive.box<dynamic>(metaBoxName);
    }
    return Hive.openBox<dynamic>(metaBoxName);
  }

  static String imageMetaKey(int imageIndex) => 'image_meta_$imageIndex';

  static Future<File> previewFileForImage(int imageIndex) async {
    final Directory sessionDir = await ensureSessionDirectory();
    return File(
      '${sessionDir.path}${Platform.pathSeparator}preview_$imageIndex.png',
    );
  }
}
