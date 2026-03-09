import 'package:flutter/material.dart';
import 'package:flutterwork/core/widgets/app_bottom_nav_bar.dart';
import 'package:flutterwork/features/explore/screens/explore_screen.dart';
import 'package:flutterwork/features/home/screens/home_screen.dart';
import 'package:flutterwork/features/paint/screens/basic_screen.dart';
import 'package:flutterwork/features/profile/screens/profile_screen.dart';

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
    // REFRESH LOGIC: If already on gallery, reload data
    controller.loadGallery();
    return;
  }
  if (index == 3) {
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
  }
  }

  void _startPainting(String path) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => BasicScreen(imagePath: path)),
  ).then((_) {
    // This executes when the user returns to this screen from the painter
    controller.loadGallery();
  });
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
                GalleryHeader(count: controller.completedCount),
                Expanded(
                  child: controller.loading
                      ? const Center(child: CircularProgressIndicator())
                      : galleryItems.isEmpty
                          ? const EmptyGallery()
                          : SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                children: [
                                  // FIXED LINE BELOW:
                                  GalleryStats(
                                    count: controller.completedCount,
                                    hours: controller.totalHoursSpent,
                                  ),
                                  const SizedBox(height: 20),
                                  GalleryGrid(
                                    items: galleryItems,
                                    onItemClosed: controller.loadGallery,
                                  ),
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
