import 'dart:ui';

class ColorModel {
  final int x;
  final int y;
  final Color color;

  const ColorModel({required this.x, required this.y, required this.color});

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'color': '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
  };
}
