import 'package:flutter/material.dart';
import 'gallery_item.dart';

class GalleryGrid extends StatelessWidget {
  final List items;

  const GalleryGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      itemCount: items.length + 1,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: .8,
      ),
      itemBuilder: (context, index) {
        if (index == items.length) {
          return addNewCard();
        }

        return GalleryItem(data: items[index]);
      },
    );
  }

  Widget addNewCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xff6C63FF), width: 2),
        color: const Color(0xffEEEFFF),
      ),
      child: const Center(
        child: Text(
          "New Artwork",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xff6C63FF),
          ),
        ),
      ),
    );
  }
}