import 'package:flutter/material.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFFA78BFA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text("🎨", style: TextStyle(fontSize: 32)),
            ),
          ),

          const SizedBox(width: 16),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                "Creative Artist",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 4),
              Text(
                "Joined March 2025",
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),

          const Spacer(),

          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.settings, color: Colors.white),
          )
        ],
      ),
    );
  }
}