import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterwork/core/utils/greeting_utils.dart';
import 'package:flutterwork/core/widgets/app_bottom_nav_bar.dart';
import 'package:flutterwork/core/widgets/image_card.dart';
import 'package:flutterwork/features/home/widgets/categories_section.dart';
import 'package:flutterwork/features/home/widgets/daily_challenge_card.dart';
import 'package:flutterwork/features/home/widgets/featured_section.dart';
import 'package:flutterwork/features/home/widgets/greeting_header.dart';
import 'package:flutterwork/features/home/widgets/trending_section.dart';
import 'package:flutterwork/features/paint/basic_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<String> _assetImages = <String>[
    'assets/images/doremon.png',
    'assets/images/shinchan.png',
    'assets/images/mandala.png',
    'assets/images/smilie.png',
  ];

  static const List<String> _difficulties = <String>[
    'Easy',
    'Medium',
    'Hard',
    'Easy',
  ];

  static const List<int> _zones = <int>[84, 126, 240, 62];
  static const List<double> _ratings = <double>[4.8, 4.7, 4.9, 4.6];
  static const List<List<Color>> _gradients = <List<Color>>[
    <Color>[Color(0xFFDCE7FF), Color(0xFFEEF3FF)],
    <Color>[Color(0xFFFFE4EE), Color(0xFFFFF1F6)],
    <Color>[Color(0xFFEAFDEB), Color(0xFFF4FFF4)],
    <Color>[Color(0xFFFFF3E1), Color(0xFFFFFAF1)],
  ];
  static const List<String> _categories = <String>[
    'Mandalas 🌸',
    'Animals 🦊',
    'Nature 🌿',
    'Fantasy 🏰',
    'Abstract ⬡',
    'Cities 🌆',
    'Food 🍜',
  ];

  final int _streakDays = 7;
  final int _notifications = 2;
  final int _level = 5;
  final int _xp = 980;

  late final List<ImageCardItem> _items;
  Timer? _greetingTicker;

  @override
  void initState() {
    super.initState();
    _items = List<ImageCardItem>.generate(_assetImages.length, (int index) {
      return ImageCardItem(
        imagePath: _assetImages[index],
        title: _titleFromAsset(_assetImages[index]),
        difficulty: _difficulties[index],
        zones: _zones[index],
        rating: _ratings[index],
        previewGradient: _gradients[index],
      );
    });
    _greetingTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _greetingTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      body: Stack(
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 108),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  GreetingHeader(
                    greetingText: GreetingUtils.greetingForIndiaTime(),
                    streakDays: _streakDays,
                    notifications: _notifications,
                    onStreakTap: _onStreakTap,
                    onNotificationTap: _onNotificationTap,
                  ),
                  const SizedBox(height: 12),
                  DailyChallengeCard(
                    title: _items.first.title,
                    imagePath: _items.first.imagePath,
                    onStartTap: () => _openPainter(_items.first.imagePath),
                  ),
                  const SizedBox(height: 16),
                  _buildLevelCard(),
                  const SizedBox(height: 18),
                  FeaturedSection(
                    items: _items,
                    onTapItem: (ImageCardItem item) =>
                        _openPainter(item.imagePath),
                  ),
                  const SizedBox(height: 20),
                  CategoriesSection(categories: _categories),
                  const SizedBox(height: 20),
                  TrendingSection(
                    items: _items,
                    onTapItem: (ImageCardItem item) =>
                        _openPainter(item.imagePath),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: AppBottomNavBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelCard() {
    final double progress = (_xp / 1500).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.06),
              blurRadius: 16,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Level $_level Artist',
                        style: const TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_xp / 1500 XP',
                        style: const TextStyle(
                          color: Color(0xFF7C7C9A),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[Color(0xFFFFB830), Color(0xFFFF8C42)],
                    ),
                  ),
                  child: Text(
                    '$_level',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: progress,
                backgroundColor: const Color(0xFFEAEAF3),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF6C63FF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPainter(String selectedImage) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BasicScreen(imagePath: selectedImage),
      ),
    );
  }

  void _onStreakTap() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🔥 7-day streak! Keep it up!')),
    );
  }

  void _onNotificationTap() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notifications are coming soon.')),
    );
  }

  String _titleFromAsset(String assetPath) {
    final String fileName = assetPath.split('/').last.split('.').first;
    return fileName
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .where((String s) => s.isNotEmpty)
        .map((String s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
  }
}
