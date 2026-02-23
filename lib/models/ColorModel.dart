import 'dart:ui';

class ColorModel {
  final int x;
  final int y;
  final Color color;

  ColorModel({required this.x, required this.y, required this.color});

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'color': '#${color.value.toRadixString(16)}',
  };
}