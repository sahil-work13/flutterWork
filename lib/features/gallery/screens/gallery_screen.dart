import 'package:flutter/material.dart';
import 'package:flutterwork/core/widgets/app_bottom_nav_bar.dart';
import 'package:flutterwork/features/explore/screens/explore_screen.dart';
import 'package:flutterwork/features/home/screens/home_screen.dart';

import '../controllers/gallery_controller.dart';
import '../widgets/gallery_header.dart';
import '../widgets/gallery_stats.dart';
import '../widgets/gallery_grid.dart';
import '../widgets/empty_gallery.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {

  final GalleryController controller = GalleryController();

  @override
  void initState() {
    super.initState();
    controller.loadGallery();
  }

  void _onBottomNavTap(int index) {

    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }

    if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ExploreScreen()),
      );
    }

    if (index == 2) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {

        final galleryItems = controller.galleryItems;

        return Scaffold(
          backgroundColor: const Color(0xffF5F5F7),

          body: SafeArea(
            child: Column(
              children: [

                GalleryHeader(count: galleryItems.length),

                Expanded(
                  child: controller.loading
                      ? const Center(child: CircularProgressIndicator())
                      : galleryItems.isEmpty
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
                  child: AppBottomNavBar(
                    activeIndex: 2,
                    onTap: _onBottomNavTap,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
} 