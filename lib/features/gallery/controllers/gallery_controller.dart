import 'package:flutter/material.dart';
import 'package:flutterwork/core/data/canvas_image_assets.dart';
import 'package:hive/hive.dart';

class GalleryController extends ChangeNotifier {
  static const String sessionNamespace = 'coloring_book_session_v2';

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
      final metaBox = await Hive.openBox('${sessionNamespace}_metadata_box');

      debugPrint("[GALLERY_DEBUG] Box Path: ${metaBox.path}");
      debugPrint("[GALLERY_DEBUG] Total keys found: ${metaBox.length}");

      final List<Map<String, dynamic>> items = [];
      int totalSeconds = 0;

      for (var key in metaBox.keys) {
        final rawData = metaBox.get(key);
        if (rawData == null) continue;

        final meta = Map<String, dynamic>.from(rawData);

        dynamic rawProgress = meta['progressPercent'] ?? 0;

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

          final int imageId = meta['imageId'] ?? 0;

          items.add({
            "id": imageId,
            "title": _getImageName(imageId),
            "date": _formatDate(meta['lastSaved']),
            "progress": progressPercent,
          });
        }
      }

      /// Latest artwork first
      items.sort((a, b) => b['id'].compareTo(a['id']));

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
}