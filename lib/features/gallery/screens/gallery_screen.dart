import 'package:flutter/material.dart';
import 'package:flutterwork/core/widgets/app_bottom_nav_bar.dart';
import 'package:flutterwork/features/explore/screens/explore_screen.dart';
import 'package:flutterwork/features/home/screens/home_screen.dart';
import '../widgets/gallery_header.dart';
import '../widgets/gallery_stats.dart';
import '../widgets/gallery_grid.dart';
import '../widgets/empty_gallery.dart';

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List galleryItems = []; // replace with your saved artworks
    void _onBottomNavTap(int index) {
    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
    }
    if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const ExploreScreen()),
      );
    }
    if (index == 2) {
      return;
    }
    // ScaffoldMessenger.of(context).showSnackBar(
    //   const SnackBar(content: Text('This tab will be available soon.')),
    // );
  }
    return Scaffold(
      backgroundColor: const Color(0xffF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            GalleryHeader(count: galleryItems.length),

            Expanded(
              child: galleryItems.isEmpty
                  ? const EmptyGallery()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          GalleryStats(count: galleryItems.length),
                          const SizedBox(height: 20),
                          GalleryGrid(items: galleryItems),
                        ],
                      ),
                    ),
            ),

            Align(
            alignment: Alignment.bottomCenter,
            child: AppBottomNavBar(activeIndex: 2, onTap: _onBottomNavTap),
          ),
          ],
        ),
      ),
    );
  }
}