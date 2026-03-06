import 'package:flutter/material.dart';

class GalleryStats extends StatelessWidget {
  final int count;

  const GalleryStats({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        statCard("🎨", "$count", "Completed"),
        statCard("⏱️", "2.4h", "Time spent"),
        statCard("🔥", "7", "Day streak"),
      ],
    );
  }

  Widget statCard(String icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black.withOpacity(.05),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xff6C63FF),
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}