import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterwork/core/widgets/app_bottom_nav_bar.dart';
import 'package:flutterwork/features/explore/screens/explore_screen.dart';
import 'package:flutterwork/features/gallery/screens/gallery_screen.dart';
import 'package:flutterwork/features/gallery/controllers/gallery_controller.dart';
import 'package:flutterwork/features/home/screens/home_screen.dart';
import 'package:flutterwork/features/profile/screens/profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  static MainNavigationScreenState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<MainNavigationScreenState>();
  }

  @override
  State<MainNavigationScreen> createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;
  late final List<Widget> _pages;
  late final GalleryController _galleryController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
    _galleryController = GalleryController();
    _pages = <Widget>[
      const HomeScreen(),
      const ExploreScreen(),
      GalleryScreen(controller: _galleryController),
      const ProfileScreen(),
    ];
  }

  void setTab(int index) {
    if (index < 0 || index >= _pages.length) return;
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });

    // Auto-refresh Gallery when the user navigates to the Gallery tab via the
    // bottom navigation bar. This keeps the existing UI/flow while ensuring
    // recently autosaved artwork appears reliably.
    if (index == 2) {
      unawaited(_galleryController.refreshOnTabVisible());
    }
  }

  void _onNavTap(int index) => setTab(index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: AppBottomNavBar(
        activeIndex: _currentIndex,
        onTap: _onNavTap,
      ),
    );
  }

  @override
  void dispose() {
    _galleryController.dispose();
    super.dispose();
  }
}
