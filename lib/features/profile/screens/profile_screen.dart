import 'package:flutter/material.dart';
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
          ],
        ),
      ),
    );
  }
}
