import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'bindings/coloring_binding.dart';
import 'routes/app_pages.dart';
import 'routes/app_routes.dart';

void main() {
  runApp(const ColoringApp());
}

class ColoringApp extends StatelessWidget {
  const ColoringApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title:                      'Coloring Book',
      debugShowCheckedModeBanner: false,
      initialRoute:               AppRoutes.coloring,
      initialBinding:             ColoringBinding(),
      getPages:                   AppPages.pages,
    );
  }
}
