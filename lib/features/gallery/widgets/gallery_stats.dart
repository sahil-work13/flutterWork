import 'package:flutter/material.dart';

class GalleryStats extends StatelessWidget {
  final int count;
  final double hours;

  const GalleryStats({
    super.key, 
    required this.count, 
    required this.hours,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3, // Fixed: Added required argument
      shrinkWrap: true,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _statCard("🎨", "$count", "Completed"),
        _statCard("⏱️", "${hours.toStringAsFixed(1)}h", "Time spent"),
        _statCard("🔥", "7", "Day streak"),
      ],
    );
  }

  // Fixed: Added the missing statCard method
  Widget _statCard(String icon, String value, String label) {
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
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A1A2E),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}