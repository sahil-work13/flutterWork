import 'package:flutter/material.dart';
import 'package:flutterwork/features/home/screens/home_screen.dart';
import 'package:flutterwork/features/splash_and_onboarding/widgets/onboarding_progress_dots.dart';
import 'package:flutterwork/features/splash_and_onboarding/widgets/onboarding_slide_content.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.imagePath,
    required this.title,
    required this.description,
    required this.colors,
  });

  final String imagePath;
  final String title;
  final String description;
  final List<Color> colors;
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const List<_OnboardingSlide> _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      imagePath: 'assets/images/brush-onboarding.png',
      title: 'Paint with Freedom',
      description:
          'Fill colors your way. Thousands of illustrations await your creative touch.',
      colors: <Color>[Color(0xFF6C63FF), Color(0xFFA78BFA)],
    ),
    _OnboardingSlide(
      imagePath: 'assets/images/splash_screen_artist_palet.png',
      title: 'Your Perfect Palette',
      description:
          'Pick from infinite colors, create custom palettes, and save your favorites.',
      colors: <Color>[Color(0xFFFF6B9D), Color(0xFFFF8C42)],
    ),
    _OnboardingSlide(
      imagePath: 'assets/images/starts-onboarding.png',
      title: 'Share Your Art',
      description:
          'Export in 4K, create speed-replay videos, and dazzle your social feed.',
      colors: <Color>[Color(0xFF22C55E), Color(0xFF16A34A)],
    ),
  ];

  int _onboardingSlide = 0;

  void _goToBasicScreen() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 260),
      ),
    );
  }

  void _onContinuePressed() {
    if (_onboardingSlide < _slides.length - 1) {
      setState(() {
        _onboardingSlide++;
      });
      return;
    }
    _goToBasicScreen();
  }

  @override
  Widget build(BuildContext context) {
    final _OnboardingSlide slide = _slides[_onboardingSlide];
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: slide.colors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextButton(
                    onPressed: _goToBasicScreen,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: Color.fromRGBO(255, 255, 255, 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: OnboardingSlideContent(
                  imagePath: slide.imagePath,
                  title: slide.title,
                  description: slide.description,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 44),
                child: Column(
                  children: <Widget>[
                    OnboardingProgressDots(
                      count: _slides.length,
                      activeIndex: _onboardingSlide,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _onContinuePressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF6C63FF),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(
                          _onboardingSlide < _slides.length - 1
                              ? 'Continue'
                              : 'Get Started ðŸŽ¨',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
