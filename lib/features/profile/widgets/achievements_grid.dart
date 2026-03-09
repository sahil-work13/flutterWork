import 'package:flutter/material.dart';

class AchievementsGrid extends StatelessWidget {
  const AchievementsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final achievements = [
      {"icon": "🏆", "name": "Starter"},
      {"icon": "🎨", "name": "Painter"},
      {"icon": "🔥", "name": "Streak"},
      {"icon": "⭐", "name": "XP"},
      {"icon": "👑", "name": "Pro"},
      {"icon": "💎", "name": "Master"},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        itemCount: achievements.length,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemBuilder: (_, i) {
          final a = achievements[i];

          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      blurRadius: 10,
                      color: Colors.black.withOpacity(.05))
                ]),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(a["icon"]!, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 6),
                Text(a["name"]!,
                    style: const TextStyle(fontSize: 11),
                    textAlign: TextAlign.center),
              ],
            ),
          );
        },
      ),
    );
  }
}