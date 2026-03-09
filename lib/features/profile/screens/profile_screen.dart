import 'package:flutter/material.dart';
import 'package:flutterwork/core/widgets/app_bottom_nav_bar.dart';
import 'package:flutterwork/features/explore/screens/explore_screen.dart';
import 'package:flutterwork/features/gallery/screens/gallery_screen.dart';
import 'package:flutterwork/features/home/screens/home_screen.dart';
import '../widgets/profile_header.dart';
import '../widgets/pro_banner.dart';
import '../widgets/profile_stats_grid.dart';
import '../widgets/achievements_grid.dart';
import '../widgets/profile_menu.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const GalleryScreen()),
      );
    }
    if(index == 3){
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: const [
                  ProfileHeader(),
                  ProBanner(),
                  SizedBox(height: 10),
                  ProfileStatsGrid(),
                  SizedBox(height: 10),
                  AchievementsGrid(),
                  SizedBox(height: 10),
                  ProfileMenu(),
                ],
              ),
            ),

            Align(
                  alignment: Alignment.bottomCenter,
                  child: AppBottomNavBar(
                    activeIndex: 3,
                    onTap: _onBottomNavTap,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}