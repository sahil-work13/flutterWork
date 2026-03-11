import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutterwork/core/widgets/app_bottom_nav_bar.dart';

import 'main_navigation_controller.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late final MainNavigationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.isRegistered<MainNavigationController>()
        ? Get.find<MainNavigationController>()
        : Get.put<MainNavigationController>(
            MainNavigationController(initialIndex: widget.initialIndex),
            permanent: true,
          );
    _controller.setTab(widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(
        () => IndexedStack(
          index: _controller.currentIndex.value,
          children: _controller.pages,
        ),
      ),
      bottomNavigationBar: Obx(
        () => AppBottomNavBar(
          activeIndex: _controller.currentIndex.value,
          onTap: _controller.setTab,
        ),
      ),
    );
  }
}
