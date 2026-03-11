import 'package:flutter/material.dart';
import 'package:flutterwork/features/paint/screens/basic_screen.dart';
import 'package:get/get.dart';

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
  final GalleryController controller = Get.find<GalleryController>();

  @override
  void initState() {
    super.initState();
    controller.loadGallery();
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
    return Scaffold(
      backgroundColor: const Color(0xffF5F5F7),
      body: Obx(() {
        final List<Map<String, dynamic>> galleryItems =
            controller.galleryItems.toList(growable: false);
        final bool isLoading = controller.loading.value;
        final int completedCount = controller.completedCount.value;

        return SafeArea(
          child: Column(
            children: [
              GalleryHeader(count: completedCount),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : galleryItems.isEmpty
                        ? const EmptyGallery()
                        : SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                GalleryStats(
                                  count: completedCount,
                                  formattedTime: controller.getFormattedTime(),
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
            ],
          ),
        );
      }),
    );
  }
}
