import 'package:flutter/material.dart';

class ProfileMenu extends StatelessWidget {
  const ProfileMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      {"icon": "🎨", "label": "My Palettes"},
      {"icon": "❤️", "label": "Favorites"},
      {"icon": "📊", "label": "Statistics"},
      {"icon": "🔔", "label": "Notifications"},
      {"icon": "ℹ️", "label": "About"},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: items.map((item) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      blurRadius: 10,
                      color: Colors.black.withOpacity(.05))
                ]),
            child: Row(
              children: [
                Text(item["icon"]!, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(item["label"]!,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const Icon(Icons.chevron_right)
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}