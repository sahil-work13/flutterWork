import 'package:flutter/material.dart';

class PaintStartupLoader extends StatelessWidget {
  const PaintStartupLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Icon(Icons.palette_outlined, size: 34),
        ),
        const SizedBox(height: 18),
        const Text(
          'Loading Coloring Book...',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 14),
        const SizedBox(
          width: 150,
          child: LinearProgressIndicator(
            minHeight: 4,
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
        ),
      ],
    );
  }
}
