import 'package:flutter/material.dart';

class SplashLogoCard extends StatelessWidget {
  const SplashLogoCard({
    super.key,
    required this.pulseAnimation,
    required this.imagePath,
  });

  final Animation<double> pulseAnimation;
  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF6C63FF), Color(0xFFFF6B9D)],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.50),
                blurRadius: 60,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Image.asset(imagePath, fit: BoxFit.contain),
            ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: AnimatedBuilder(
            animation: pulseAnimation,
            builder: (BuildContext context, Widget? child) {
              final double t = pulseAnimation.value;
              return Opacity(
                opacity: (0.5 * (1.0 - t)).clamp(0.0, 0.5),
                child: Transform.scale(scale: 1.0 + (t * 0.5), child: child),
              );
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFFFFB830),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
