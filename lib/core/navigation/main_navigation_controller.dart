import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutterwork/features/explore/screens/explore_screen.dart';
import 'package:flutterwork/features/gallery/controllers/gallery_controller.dart';
import 'package:flutterwork/features/gallery/screens/gallery_screen.dart';
import 'package:flutterwork/features/home/screens/home_screen.dart';
import 'package:flutterwork/features/profile/screens/profile_screen.dart';

class MainNavigationController extends GetxController {
  MainNavigationController({int initialIndex = 0}) {
    currentIndex.value = initialIndex.clamp(0, 3);
    pages = const <Widget>[
      HomeScreen(),
      ExploreScreen(),
      GalleryScreen(),
      ProfileScreen(),
    ];
  }

  final RxInt currentIndex = 0.obs;

  late final List<Widget> pages;

  void setTab(int index) {
    if (index < 0 || index >= pages.length) return;
    if (index == currentIndex.value) return;
    currentIndex.value = index;

    // Keep Gallery fresh when switching via bottom tabs.
    if (index == 2) {
      try {
        unawaited(Get.find<GalleryController>().refreshOnTabVisible());
      } catch (_) {
        // If the controller is not registered yet, ignore.
      }
    }
  }
}
