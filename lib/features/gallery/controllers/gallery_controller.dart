import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutterwork/core/storage/coloring_book_session_storage.dart';
import 'package:flutterwork/core/data/canvas_image_assets.dart';
import 'package:hive/hive.dart';
import 'dart:async';
import 'dart:io';

class GalleryController extends ChangeNotifier {
  static const String sessionNamespace =
      ColoringBookSessionStorage.sessionNamespace;
  static const Duration _twoPhaseRefreshDelay = Duration(milliseconds: 650);

  double totalHoursSpent = 0.0;
  int completedCount = 0;

  List<Map<String, dynamic>> galleryItems = [];

  bool loading = true;
  bool _disposed = false;
  int _loadSeq = 0;

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
    final int seq = ++_loadSeq;
    await _loadGalleryInternal(
      seq: seq,
      showLoading: true,
      debugLogs: kDebugMode,
    );

    // Two-phase refresh: the first load can happen before autosave/preview file
    // writes have fully finished. A short, silent retry prevents the gallery
    // from "missing" recently updated images without changing UI/flow.
    unawaited(_twoPhaseRefresh(seq));
  }

  /// Silent refresh used when the Gallery tab becomes visible via the bottom
  /// navigation bar. Keeps the current UI intact (no loading spinner) while
  /// ensuring newly saved items show up quickly.
  Future<void> refreshOnTabVisible() async {
    final int seq = ++_loadSeq;
    await _loadGalleryInternal(seq: seq, showLoading: false, debugLogs: false);
    unawaited(_twoPhaseRefresh(seq));
  }

  Future<void> _twoPhaseRefresh(int seq) async {
    await Future<void>.delayed(_twoPhaseRefreshDelay);
    if (_disposed || seq != _loadSeq) return;
    await _loadGalleryInternal(seq: seq, showLoading: false, debugLogs: false);
  }

  Future<void> _loadGalleryInternal({
    required int seq,
    required bool showLoading,
    required bool debugLogs,
  }) async {
    if (showLoading) {
      loading = true;
      notifyListeners();
    }

    if (debugLogs) {
      debugPrint(
        "[GALLERY_DEBUG] Starting Load. Box: ${sessionNamespace}_metadata_box",
      );
    }

    try {
      final Box<dynamic> metaBox =
          await ColoringBookSessionStorage.ensureMetaBox();

      if (debugLogs) {
        debugPrint("[GALLERY_DEBUG] Box Path: ${metaBox.path}");
        debugPrint("[GALLERY_DEBUG] Total keys found: ${metaBox.length}");
      }

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

        int progressPercent = 0;

        // Supports legacy persisted formats:
        // - 0.95 (0..1 fraction)
        // - 95.0 (double percent)
        // - 95 (int percent)
        if (rawProgress is int) {
          progressPercent = rawProgress;
        } else if (rawProgress is double) {
          progressPercent = rawProgress <= 1.0
              ? (rawProgress * 100).round()
              : rawProgress.round();
        } else {
          progressPercent = int.tryParse(rawProgress.toString()) ?? 0;
        }
        progressPercent = progressPercent.clamp(0, 100);

        if (debugLogs) {
          debugPrint(
            "[GALLERY_DEBUG] Key: $key | RawProgress: $rawProgress | Calculated: $progressPercent%",
          );
        }

        /// Only show completed artworks
        if (progressPercent >= 90) {
          totalSeconds += (meta['totalTimeSeconds'] as int? ?? 0);
          final File previewFile = File(
            '${sessionDir.path}${Platform.pathSeparator}preview_$imageId.png',
          );

          // Flutter caches images by file path. Since our preview file path is
          // stable (`preview_<id>.png`), overwriting the file won't necessarily
          // update what's shown in the Gallery until the app restarts (cache
          // cleared). Evict here so the next build loads the latest bytes.
          try {
            await FileImage(previewFile).evict();
          } catch (_) {
            // Best-effort: if eviction fails for any reason, the preview may
            // remain stale until a later refresh or app restart.
          }

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

      if (!_disposed && seq == _loadSeq) {
        galleryItems = items;
        completedCount = items.length;
        totalHoursSpent = totalSeconds / 3600;
      }
    } catch (e) {
      if (debugLogs) {
        debugPrint("[GALLERY_DEBUG] CRITICAL ERROR: $e");
      }
    } finally {
      if (showLoading) {
        loading = false;
      }
      if (!_disposed && seq == _loadSeq) {
        notifyListeners();
      }
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
