import 'package:flutter/material.dart';

enum ImageCardVariant { featured, trending }

class ImageCardItem {
  const ImageCardItem({
    required this.imagePath,
    required this.title,
    required this.difficulty,
    required this.zones,
    required this.rating,
    required this.previewGradient,
  });

  final String imagePath;
  final String title;
  final String difficulty;
  final int zones;
  final double rating;
  final List<Color> previewGradient;
}

class ImageCard extends StatelessWidget {
  const ImageCard({
    super.key,
    required this.item,
    required this.variant,
    required this.onTap,
    this.rank,
  });

  final ImageCardItem item;
  final ImageCardVariant variant;
  final VoidCallback onTap;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    if (variant == ImageCardVariant.trending) {
      return _TrendingCard(item: item, onTap: onTap, rank: rank);
    }
    return _FeaturedCard(item: item, onTap: onTap);
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.item, required this.onTap});

  final ImageCardItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          width: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.08),
                blurRadius: 20,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                height: 160,
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: item.previewGradient,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(item.imagePath, fit: BoxFit.cover),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        _DifficultyBadge(label: item.difficulty),
                        const Spacer(),
                        Text(
                          '${item.zones} zones',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7C7C9A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  const _TrendingCard({
    required this.item,
    required this.onTap,
    required this.rank,
  });

  final ImageCardItem item;
  final VoidCallback onTap;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.05),
                blurRadius: 12,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: item.previewGradient,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(item.imagePath, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        _DifficultyBadge(label: item.difficulty),
                        const SizedBox(width: 8),
                        Text(
                          '⭐ ${item.rating.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF7C7C9A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (rank != null)
                Text(
                  '#$rank',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF6C63FF),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DifficultyBadge extends StatelessWidget {
  const _DifficultyBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final String normalized = label.toLowerCase();
    Color background = const Color(0xFFE8ECFF);
    Color text = const Color(0xFF3A47B5);
    if (normalized == 'easy') {
      background = const Color(0xFFE7F7EE);
      text = const Color(0xFF207F4C);
    } else if (normalized == 'medium') {
      background = const Color(0xFFFFF4D9);
      text = const Color(0xFF986100);
    } else if (normalized == 'hard') {
      background = const Color(0xFFFFE3E3);
      text = const Color(0xFFAF2E2E);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }
}
