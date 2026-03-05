import 'package:flutter/material.dart';

class PaintStartupLoader extends StatelessWidget {
  const PaintStartupLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.palette_outlined, size: 36),
        ),
        const SizedBox(height: 18),
        const Text(
          'Loading Coloring Book...',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 14),
        const SizedBox(
          width: 170,
          child: LinearProgressIndicator(
            minHeight: 5,
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
        ),
      ],
    );
  }
}

class PaintImageTransitionLoader extends StatelessWidget {
  const PaintImageTransitionLoader({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Container(
          color: Colors.white.withValues(alpha: 0.28),
          child: Center(
            child: Container(
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ),
      ),
    );
  }
}
