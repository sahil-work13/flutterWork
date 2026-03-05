import 'package:flutter/material.dart';

class TimelapseExportProgressBar extends StatelessWidget {
  const TimelapseExportProgressBar({
    super.key,
    required this.progress,
    required this.label,
    required this.percentText,
  });

  final double progress;
  final String label;
  final String percentText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                percentText,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }
}
