import 'package:flutter/material.dart';
import 'package:flutterwork/core/navigation/main_navigation_screen.dart';
import 'package:flutterwork/features/explore/screens/explore_screen.dart';

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
            onPressed: () {
              final MainNavigationScreenState? shell =
                  MainNavigationScreen.maybeOf(context);
              if (shell != null) {
                shell.setTab(1);
                return;
              }
              Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(builder: (_) => const ExploreScreen()),
              );
            },
            child: const Text("Explore Illustrations"),
          )
        ],
      ),
    );
  }
}
