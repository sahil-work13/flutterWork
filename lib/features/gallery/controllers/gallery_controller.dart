import 'package:flutter/material.dart';
import 'package:flutterwork/core/storage/coloring_book_session_storage.dart';
import 'package:flutterwork/core/data/canvas_image_assets.dart';
import 'package:hive/hive.dart';
import 'dart:io';

class GalleryController extends ChangeNotifier {
  static const String sessionNamespace =
      ColoringBookSessionStorage.sessionNamespace;

  double totalHoursSpent = 0.0;
  int completedCount = 0;

  List<Map<String, dynamic>> galleryItems = [];

  bool loading = true;

  String _getImageName(int imageId) {
  try {
    final String path = CanvasImageAssets.all[imageId];

    // assets/images/doremon.png → doremon
    final String fileName = path.split('/').last.split('.').first;

    // Capitalize first letter
    return fileName[0].toUpperCase() + fileName.substring(1);
  } catch (_) {
    return "Artwork ${imageId + 1}";
  }
}

  Future<void> loadGallery() async {
    loading = true;
    notifyListeners();

    debugPrint(
        "[GALLERY_DEBUG] Starting Load. Box: ${sessionNamespace}_metadata_box");

    try {
      final Box<dynamic> metaBox =
          await ColoringBookSessionStorage.ensureMetaBox();
      await metaBox.flush();

      debugPrint("[GALLERY_DEBUG] Box Path: ${metaBox.path}");
      debugPrint("[GALLERY_DEBUG] Total keys found: ${metaBox.length}");

      final Directory sessionDir =
          await ColoringBookSessionStorage.ensureSessionDirectory();
      final List<Map<String, dynamic>> items = [];
      int totalSeconds = 0;

      for (final dynamic key in metaBox.keys) {
        if (key is! String || !key.startsWith('image_meta_')) {
          continue;
        }

        final dynamic rawData = metaBox.get(key);
        if (rawData == null) continue;
        if (rawData is! Map) continue;

        final Map<String, dynamic> meta = Map<String, dynamic>.from(rawData);

        final int imageId = meta['imageId'] as int? ?? -1;
        if (imageId < 0 || imageId >= CanvasImageAssets.all.length) {
          continue;
        }

        final dynamic rawProgress = meta['progressPercent'] ?? 0;

        int progressPercent;

        /// Handle both 0.95 and 95 formats
        if (rawProgress is double && rawProgress <= 1.0) {
          progressPercent = (rawProgress * 100).toInt();
        } else {
          progressPercent = rawProgress.toInt();
        }

        debugPrint(
            "[GALLERY_DEBUG] Key: $key | RawProgress: $rawProgress | Calculated: $progressPercent%");

        /// Only show completed artworks
        if (progressPercent >= 90) {
          totalSeconds += (meta['totalTimeSeconds'] as int? ?? 0);
          final File previewFile = File(
            '${sessionDir.path}${Platform.pathSeparator}preview_$imageId.png',
          );

          items.add({
            "id": imageId,
            "title": _getImageName(imageId),
            "date": _formatDate(meta['lastSaved']),
            "progress": progressPercent,
            "previewPath": previewFile.path,
            "lastSaved": meta['lastSaved'],
          });
        }
      }

      items.sort((a, b) {
        final DateTime aDate = _parseSortDate(a["lastSaved"]);
        final DateTime bDate = _parseSortDate(b["lastSaved"]);
        return bDate.compareTo(aDate);
      });

      galleryItems = items;
      completedCount = items.length;
      totalHoursSpent = totalSeconds / 3600;
    } catch (e) {
      debugPrint("[GALLERY_DEBUG] CRITICAL ERROR: $e");
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return "Unknown";

    try {
      final DateTime dt = DateTime.parse(dateStr.toString());
      return "${dt.day}/${dt.month}/${dt.year}";
    } catch (_) {
      return "Recent";
    }
  }

  DateTime _parseSortDate(dynamic dateStr) {
    if (dateStr == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    try {
      return DateTime.parse(dateStr.toString());
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String getFormattedTime() {
  final int totalSeconds = (totalHoursSpent * 3600).round();

  if (totalSeconds < 60) {
    return "${totalSeconds}s";
  }

  if (totalSeconds < 3600) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;

    return seconds == 0 ? "${minutes}m" : "${minutes}m ${seconds}s";
  }

  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;

  return "${hours}h ${minutes}m";
}
}
