import 'package:flutter/material.dart';

class CuratedPalette {
  const CuratedPalette({
    required this.name,
    required this.colors,
  });

  final String name;
  final List<Color> colors;
}

Future<Color?> showPaintColorPickerSheet({
  required BuildContext context,
  required Color initialColor,
  required List<Color> quickColors,
  required List<Color> suggestedColors,
  required List<CuratedPalette> curatedPalettes,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) {
      return FractionallySizedBox(
        heightFactor: 0.92,
        child: _PaintColorPickerSheet(
          initialColor: initialColor,
          quickColors: quickColors,
          suggestedColors: suggestedColors,
          curatedPalettes: curatedPalettes,
        ),
      );
    },
  );
}

class _PaintColorPickerSheet extends StatefulWidget {
  const _PaintColorPickerSheet({
    required this.initialColor,
    required this.quickColors,
    required this.suggestedColors,
    required this.curatedPalettes,
  });

  final Color initialColor;
  final List<Color> quickColors;
  final List<Color> suggestedColors;
  final List<CuratedPalette> curatedPalettes;

  @override
  State<_PaintColorPickerSheet> createState() => _PaintColorPickerSheetState();
}

class _PaintColorPickerSheetState extends State<_PaintColorPickerSheet> {
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF0EFF8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  _circleIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Color Picker',
                    style: TextStyle(
                      color: Color(0xFF1A1A2E),
                      fontSize: 36 / 2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSelectedColorCard(),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  children: <Widget>[
                    const Text(
                      'Quick Colors',
                      style: TextStyle(
                        color: Color(0xFF1A1A2E),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildSwatchGrid(widget.quickColors),
                    if (widget.suggestedColors.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 14),
                      const Text(
                        'Recent & Most Used',
                        style: TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildHorizontalSwatches(widget.suggestedColors),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'Curated Palettes',
                      style: TextStyle(
                        color: Color(0xFF1A1A2E),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...widget.curatedPalettes.map(
                      (CuratedPalette palette) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildCuratedPaletteCard(palette),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_selectedColor),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Apply Color ✓',
                    style: TextStyle(fontSize: 18 / 2, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedColorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _selectedColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Selected Color',
                  style: TextStyle(
                    color: Color(0xFF1A1A2E),
                    fontSize: 14 / 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '#${_selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                  style: const TextStyle(
                    color: Color(0xFF4C5CFF),
                    fontSize: 16 / 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    _miniChip('HEX', active: true),
                    const SizedBox(width: 6),
                    _miniChip('RGB'),
                    const SizedBox(width: 6),
                    _miniChip('HSL'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwatchGrid(List<Color> colors) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: colors.map(_buildSwatch).toList(growable: false),
    );
  }

  Widget _buildHorizontalSwatches(List<Color> colors) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: colors.length,
        itemBuilder: (BuildContext context, int index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildSwatch(colors[index]),
          );
        },
      ),
    );
  }

  Widget _buildCuratedPaletteCard(CuratedPalette palette) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                palette.name,
                style: const TextStyle(
                  color: Color(0xFF1A1A2E),
                  fontSize: 14 / 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedColor = palette.colors.first;
                  });
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Use',
                  style: TextStyle(
                    color: Color(0xFF6C63FF),
                    fontSize: 14 / 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: palette.colors.map(_buildSwatch).toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildSwatch(Color color) {
    final bool selected = color.toARGB32() == _selectedColor.toARGB32();
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedColor = color;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF6C63FF) : Colors.white,
            width: selected ? 3 : 2,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String label, {bool active = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE5E8FF) : const Color(0xFFE7E7EE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? const Color(0xFF6C63FF) : const Color(0xFF8E91A8),
          fontSize: 12 / 2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: const Color(0xFF1A1A2E), size: 18),
        ),
      ),
    );
  }
}
