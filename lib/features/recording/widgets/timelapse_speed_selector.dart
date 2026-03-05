import 'package:flutter/material.dart';

class TimelapseSpeedSelector extends StatelessWidget {
  const TimelapseSpeedSelector({
    super.key,
    required this.currentSpeed,
    required this.options,
    required this.onSelected,
    required this.formatSpeed,
  });

  final double currentSpeed;
  final List<double> options;
  final ValueChanged<double> onSelected;
  final String Function(double speed) formatSpeed;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: currentSpeed,
      onSelected: onSelected,
      itemBuilder: (BuildContext context) {
        return options.map((double speed) {
          return PopupMenuItem<double>(
            value: speed,
            child: Text('${formatSpeed(speed)}x'),
          );
        }).toList();
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '${formatSpeed(currentSpeed)}x',
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
