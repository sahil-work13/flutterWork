import 'package:flutter/material.dart';

class GalleryItem extends StatelessWidget {
  final Map data;

  const GalleryItem({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            blurRadius: 8,
            color: Colors.black.withOpacity(.05),
          )
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Text(
                data["emoji"] ?? "🎨",
                style: const TextStyle(fontSize: 50),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Text(
                  data["title"] ?? "",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  data["date"] ?? "",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}