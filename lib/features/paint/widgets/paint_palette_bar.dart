import 'package:flutter/material.dart';

class PaintPaletteBar extends StatelessWidget {
  const PaintPaletteBar({
    super.key,
    required this.colorHistory,
    required this.selectedColor,
    required this.onSelectColor,
    required this.onPreviousImage,
    required this.onNextImage,
  });

  final List<Color> colorHistory;
  final Color selectedColor;
  final ValueChanged<Color> onSelectColor;
  final VoidCallback onPreviousImage;
  final VoidCallback onNextImage;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _navBtn(Icons.arrow_back_ios, onPreviousImage),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text(
                    'PALETTE',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: Color(0xFF6C63FF),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                _navBtn(Icons.arrow_forward_ios, onNextImage),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 58,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: colorHistory.length,
              itemBuilder: (BuildContext context, int i) {
                return _buildColorCircle(colorHistory[i]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorCircle(Color color) {
    final bool isSelected = selectedColor == color;
    final double luminance = color.computeLuminance();
    final Color selectedBorderColor = luminance < 0.5
        ? Colors.white
        : Colors.black;

    return GestureDetector(
      onTap: () => onSelectColor(color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: isSelected ? 52 : 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? selectedBorderColor : Colors.black,
            width: isSelected ? 2.0 : 2.5,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.18 : 0.1),
              blurRadius: isSelected ? 10 : 6,
            ),
          ],
        ),
        child: isSelected
            ? Icon(Icons.check, color: selectedBorderColor, size: 20)
            : null,
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback tap) {
    return Material(
      color: const Color(0xFFEEF0FF),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: tap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 16, color: const Color(0xFF1A1A2E)),
        ),
      ),
    );
  }
}
