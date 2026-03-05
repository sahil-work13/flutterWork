import 'package:flutter/material.dart';
import 'package:flutterwork/core/widgets/image_card.dart';

class TrendingSection extends StatelessWidget {
  const TrendingSection({
    super.key,
    required this.items,
    required this.onTapItem,
  });

  final List<ImageCardItem> items;
  final ValueChanged<ImageCardItem> onTapItem;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '🔥 Trending',
            style: TextStyle(
              color: Color(0xFF1A1A2E),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children: List<Widget>.generate(items.length, (int index) {
              final ImageCardItem item = items[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == items.length - 1 ? 0 : 10,
                ),
                child: ImageCard(
                  item: item,
                  variant: ImageCardVariant.trending,
                  rank: index + 1,
                  onTap: () => onTapItem(item),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
