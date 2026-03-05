import 'package:flutter/material.dart';
import 'package:flutterwork/core/widgets/image_card.dart';

class FeaturedSection extends StatelessWidget {
  const FeaturedSection({
    super.key,
    required this.items,
    required this.onTapItem,
  });

  final List<ImageCardItem> items;
  final ValueChanged<ImageCardItem> onTapItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: <Widget>[
              const Text(
                'Featured',
                style: TextStyle(
                  color: Color(0xFF1A1A2E),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6C63FF),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('See all →'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 246,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemBuilder: (BuildContext context, int index) {
              final ImageCardItem item = items[index];
              return ImageCard(
                item: item,
                variant: ImageCardVariant.featured,
                onTap: () => onTapItem(item),
              );
            },
            separatorBuilder: (_, int index) => const SizedBox(width: 14),
            itemCount: items.length,
          ),
        ),
      ],
    );
  }
}
