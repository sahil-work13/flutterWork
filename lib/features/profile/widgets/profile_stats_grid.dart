import 'package:flutter/material.dart';

class ProfileStatsGrid extends StatelessWidget {
  const ProfileStatsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final stats = [
      {"icon": "🖼️", "label": "Artworks", "value": "12"},
      {"icon": "🔥", "label": "Streak", "value": "7 days"},
      {"icon": "⭐", "label": "XP", "value": "1450"},
      {"icon": "🎨", "label": "Colors", "value": "24"},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        itemCount: stats.length,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemBuilder: (_, i) {
          final item = stats[i];

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      blurRadius: 12,
                      color: Colors.black.withOpacity(.05))
                ]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item["icon"]!, style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 8),
                Text(
                  item["value"]!,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: Color(0xFF6C63FF)),
                ),
                Text(item["label"]!, style: const TextStyle(fontSize: 12))
              ],
            ),
          );
        },
      ),
    );
  }
}