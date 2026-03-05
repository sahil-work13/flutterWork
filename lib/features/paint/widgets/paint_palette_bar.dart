import 'package:flutter/material.dart';

class PaintPaletteBar extends StatelessWidget {
  const PaintPaletteBar({
    super.key,
    required this.colorHistory,
    required this.recentColors,
    required this.selectedColor,
    required this.onSelectColor,
    required this.onOpenColorPicker,
    required this.onPreviousImage,
    required this.onNextImage,
  });

  final List<Color> colorHistory;
  final List<Color> recentColors;
  final Color selectedColor;
  final ValueChanged<Color> onSelectColor;
  final VoidCallback onOpenColorPicker;
  final VoidCallback onPreviousImage;
  final VoidCallback onNextImage;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A44).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              _navBtn(Icons.arrow_back_ios, onPreviousImage),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onOpenColorPicker,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selectedColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6C63FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: recentColors.length,
                    itemBuilder: (BuildContext context, int index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _buildColorCircle(recentColors[index]),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _navBtn(Icons.arrow_forward_ios, onNextImage),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: colorHistory
                .map((Color color) {
                  return _buildColorCircle(color);
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 2),
          const Text(
            'Palette',
            style: TextStyle(
              color: Color.fromRGBO(255, 255, 255, 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? selectedBorderColor : Colors.white,
            width: isSelected ? 2.0 : 2.2,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.24 : 0.12),
              blurRadius: isSelected ? 8 : 5,
            ),
          ],
        ),
        child: isSelected
            ? Icon(Icons.check, color: selectedBorderColor, size: 14)
            : null,
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback tap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}
