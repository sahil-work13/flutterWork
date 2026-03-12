import 'package:flutterwork/core/data/canvas_image_assets.dart';
import 'package:flutterwork/features/explore/models/explore_item.dart';

class ExploreCatalogService {
  const ExploreCatalogService._();

  static Future<List<ExploreItem>> loadItems() {
    final List<String> assetPaths = List<String>.from(CanvasImageAssets.all);

    final List<ExploreItem> items = List<ExploreItem>.generate(
      assetPaths.length,
      (int index) {
        final String path = assetPaths[index];
        final String fileName = path.split('/').last.split('.').first;
        final String category = _categoryFromFileName(fileName);
        final String difficulty = _difficultyFor(category, fileName);
        final double rating = _ratingFor(fileName);

        return ExploreItem(
          assetPath: path,
          title: _titleFromFileName(fileName),
          category: category,
          difficulty: difficulty,
          rating: rating,
        );
      },
    );
    return Future<List<ExploreItem>>.value(items);
  }

  static Future<List<String>> loadCategories() async {
    final List<ExploreItem> items = await loadItems();
    final List<String> categories =
        items.map((ExploreItem item) => item.category).toSet().toList()..sort();
    return categories;
  }

  static String _titleFromFileName(String fileName) {
    final List<String> words = fileName
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .where((String part) => part.trim().isNotEmpty)
        .toList();
    return words
        .map((String word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  static String _categoryFromFileName(String fileName) {
    final String lower = fileName.toLowerCase();
    if (lower == 'test1') return 'Characters';
    if (lower.contains('mandala')) return 'Mandalas';
    if (lower.contains('onboarding') || lower.contains('splash')) {
      return 'Onboarding';
    }
    if (lower.contains('doremon') ||
        lower.contains('shinchan') ||
        lower.contains('smilie')) {
      return 'Characters';
    }
    if (lower.contains('test')) return 'Practice';
    return 'Others';
  }

  static String _difficultyFor(String category, String fileName) {
    final String lower = fileName.toLowerCase();
    if (category == 'Mandalas') return 'Advanced';
    if (lower == 'test1') return 'Intermediate';
    if (lower.contains('test')) return 'Beginner';
    if (lower.contains('smilie')) return 'Beginner';
    if (lower.contains('doremon') || lower.contains('shinchan')) {
      return 'Intermediate';
    }
    return 'Intermediate';
  }

  static double _ratingFor(String fileName) {
    final int sum = fileName.runes.fold<int>(0, (int a, int b) => a + b);
    final double value = 4.4 + ((sum % 6) * 0.1);
    return double.parse(value.toStringAsFixed(1));
  }
}
