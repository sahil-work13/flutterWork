import 'package:flutter/material.dart';

class EmptyGallery extends StatelessWidget {
  const EmptyGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("🎨", style: TextStyle(fontSize: 50)),
          const SizedBox(height: 10),
          const Text(
            "No artworks yet",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 6),
          const Text(
            "Start coloring to build your gallery",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {},
            child: const Text("Explore Illustrations"),
          )
        ],
      ),
    );
  }
}