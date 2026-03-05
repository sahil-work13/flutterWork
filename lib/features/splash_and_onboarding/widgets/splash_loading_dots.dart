import 'package:flutter/material.dart';

class SplashLoadingDots extends StatelessWidget {
  const SplashLoadingDots({super.key, required this.pulseAnimation});

  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (BuildContext context, Widget? child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (int i) {
            final double v = (pulseAnimation.value - (i * 0.2)) % 1.0;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(
                  0xFF6C63FF,
                ).withValues(alpha: (0.35 + ((1 - v) * 0.65)).clamp(0.35, 1.0)),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
