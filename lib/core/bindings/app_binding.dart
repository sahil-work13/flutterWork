import 'package:get/get.dart';

import '../../features/gallery/controllers/gallery_controller.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    // Global controllers (kept for the lifetime of the app).
    Get.put<GalleryController>(GalleryController(), permanent: true);
  }
}

