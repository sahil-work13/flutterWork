import 'package:flutter/material.dart';

class ProBanner extends StatelessWidget {
  const ProBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFFA78BFA)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              blurRadius: 30,
              color: const Color(0xFF6C63FF).withOpacity(.3),
              offset: const Offset(0, 10))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Upgrade to Pro 👑",
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16),
              ),
              SizedBox(height: 4),
              Text(
                "Unlock all illustrations",
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              "\$24.99/yr",
              style: TextStyle(
                  color: Color(0xFF6C63FF), fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
    );
  }
}