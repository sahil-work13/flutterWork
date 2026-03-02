import 'package:flutter/material.dart';

class PaintToolbar extends StatelessWidget {
  const PaintToolbar({
    super.key,
    required this.colorHistory,
    required this.selectedColor,
    required this.onColorSelected,
    required this.onPreviousImage,
    required this.onNextImage,
  });

  final List<Color> colorHistory;
  final Color selectedColor;
  final ValueChanged<Color> onColorSelected;
  final VoidCallback onPreviousImage;
  final VoidCallback onNextImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _navBtn(Icons.arrow_back_ios, onPreviousImage),
                const Text(
                  'PALETTE',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                _navBtn(Icons.arrow_forward_ios, onNextImage),
              ],
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 55,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
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
    final Color selectedBorderColor = luminance < 0.5 ? Colors.white : Colors.black;
    final Color checkColor = selectedBorderColor;

    return GestureDetector(
      onTap: () => onColorSelected(color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: isSelected ? 52 : 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: null,
          border: Border.all(
            color: isSelected ? selectedBorderColor : Colors.black,
            width: isSelected ? 2.0 : 2.5,
          ),
        ),
        child: isSelected ? Icon(Icons.check, color: checkColor, size: 20) : null,
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback tap) {
    return IconButton(icon: Icon(icon, size: 18), onPressed: tap);
  }
}
