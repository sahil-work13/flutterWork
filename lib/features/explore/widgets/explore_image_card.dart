import 'package:flutter/material.dart';
import 'package:flutterwork/features/explore/models/explore_item.dart';

class ExploreImageCard extends StatelessWidget {
  const ExploreImageCard({
    super.key,
    required this.item,
    required this.isLiked,
    required this.onTap,
    required this.onToggleLike,
  });

  final ExploreItem item;
  final bool isLiked;
  final VoidCallback onTap;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.08),
                blurRadius: 18,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                height: 130,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFFE5F0FF), Color(0xFFF8FBFF)],
                  ),
                ),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(item.assetPath, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: onToggleLike,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 16,
                            color: isLiked
                                ? const Color(0xFFFF5B8C)
                                : const Color(0xFF8A8AA6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1A1A2E),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        _DifficultyBadge(label: item.difficulty),
                        const Spacer(),
                        Text(
                          '⭐ ${item.rating.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: Color(0xFF7C7C9A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
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

class _DifficultyBadge extends StatelessWidget {
  const _DifficultyBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final String normalized = label.toLowerCase();
    Color background = const Color(0xFFEAFDEB);
    Color text = const Color(0xFF207F4C);
    if (normalized == 'intermediate') {
      background = const Color(0xFFFFF4D9);
      text = const Color(0xFF986100);
    } else if (normalized == 'advanced') {
      background = const Color(0xFFFFE3E3);
      text = const Color(0xFFAF2E2E);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
