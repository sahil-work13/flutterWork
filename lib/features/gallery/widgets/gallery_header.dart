import 'package:flutter/material.dart';

class GalleryHeader extends StatelessWidget {
  final int count;

  const GalleryHeader({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "My Gallery 🖼️",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            "$count artworks",
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}