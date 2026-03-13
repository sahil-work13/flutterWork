import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/sketching_controller.dart';

class SketchingControlsPanel extends StatelessWidget {
  const SketchingControlsPanel({
    super.key,
    required this.controllerTag,
    required this.onPickColor,
    required this.onClearPressed,
  });

  final String controllerTag;
  final VoidCallback onPickColor;
  final VoidCallback onClearPressed;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SketchingController>(
      tag: controllerTag,
      id: 'controls',
      builder: (SketchingController controller) {
        final double brushSizeValue = controller.selectedBrushSize;
        final double brushSizeMin = SketchingController.brushSizes.first;
        final double brushSizeMax = SketchingController.brushSizes.last;
        final double brushSizeT = brushSizeMax == brushSizeMin
            ? 0
            : ((brushSizeValue - brushSizeMin) / (brushSizeMax - brushSizeMin))
                .clamp(0.0, 1.0);
        final double brushDotDiameter = 10 + (brushSizeT * 18);
        final double opacityValue = controller.opacity.clamp(0.0, 1.0);
        final double opacityDotDiameter = 10 + (opacityValue * 14);

        final SliderThemeData mediumSliderTheme = SliderTheme.of(context).copyWith(
          activeTrackColor: const Color(0xFF6C63FF),
          inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
          thumbColor: Colors.white,
          overlayColor: const Color(0x336C63FF),
          trackHeight: 5,
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 8,
          ),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        );

        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: <Widget>[
                    for (final SketchToolOption option
                        in SketchingController.toolOptions) ...<Widget>[
                      _toolButton(
                        icon: option.icon,
                        label: option.label,
                        active: controller.selectedTool == option.tool,
                        onTap: () => controller.setTool(option.tool),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      width: 1,
                      height: 40,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                    const SizedBox(width: 8),
                    _toolButton(
                      icon: controller.symmetry == 0
                          ? Icons.rotate_90_degrees_ccw_rounded
                          : SketchingController.symmetryOptions
                                  .firstWhere(
                                    (SymmetryOption option) =>
                                        option.value == controller.symmetry,
                                  )
                                  .icon,
                      label:
                          controller.symmetry == 0 ? 'No Sym' : 'Symmetry',
                      active: controller.symmetry > 0,
                      compactValue:
                          controller.symmetry == 0 ? 'SYM' : '${controller.symmetry}x',
                      onTap: controller.cycleSymmetry,
                    ),
                    const SizedBox(width: 8),
                    _toolButton(
                      icon: Icons.grid_view_rounded,
                      label: 'Grid',
                      active: controller.showGrid,
                      onTap: controller.toggleGrid,
                    ),
                    const SizedBox(width: 8),
                    _toolButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Clear',
                      active: false,
                      accentColor: const Color(0xFFFF6B6B),
                      onTap: onClearPressed,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  const Text(
                    'SIZE',
                    style: TextStyle(
                      color: Color.fromRGBO(255, 255, 255, 0.30),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: 'Brush size ${brushSizeValue.round()}',
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          width: brushDotDiameter,
                          height: brushDotDiameter,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: controller.selectedColor,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.70),
                              width: 1.2,
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: controller.selectedColor.withValues(
                                  alpha: 0.25,
                                ),
                                blurRadius: 10,
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SliderTheme(
                      data: mediumSliderTheme,
                      child: Slider(
                        min: SketchingController.brushSizes.first,
                        max: SketchingController.brushSizes.last,
                        value: controller.selectedBrushSize,
                        onChanged: controller.setBrushSize,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  const Text(
                    'OPACITY',
                    style: TextStyle(
                      color: Color.fromRGBO(255, 255, 255, 0.30),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: 'Opacity ${(opacityValue * 100).round()} percent',
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 1.0,
                                ),
                              ),
                              child: ClipOval(
                                child: CustomPaint(
                                  painter: _OpacityCheckerPainter(
                                    light: Colors.white.withValues(alpha: 0.10),
                                    dark: Colors.black.withValues(alpha: 0.10),
                                    squareSize: 4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOut,
                            width: opacityDotDiameter,
                            height: opacityDotDiameter,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: controller.selectedColor.withValues(
                                alpha: opacityValue,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.70),
                                width: 1.2,
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: controller.selectedColor.withValues(
                                    alpha:
                                        (0.20 * opacityValue).clamp(0.0, 0.20),
                                  ),
                                  blurRadius: 10,
                                  spreadRadius: 0.5,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SliderTheme(
                      data: mediumSliderTheme,
                      child: Slider(
                        min: 0.10,
                        max: 1.0,
                        value: controller.opacity,
                        onChanged: controller.setOpacity,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    GestureDetector(
                      onTap: onPickColor,
                      child: Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: controller.selectedColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 1.6),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0xFF6C63FF),
                              blurRadius: 0,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    ...SketchingController.palette.map(
                      (Color color) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => controller.setColor(color),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: color == const Color(0xFFFFFFFF)
                                    ? Colors.white.withValues(alpha: 0.30)
                                    : Colors.transparent,
                              ),
                              boxShadow: <BoxShadow>[
                                if (controller.selectedColor.toARGB32() ==
                                    color.toARGB32())
                                  const BoxShadow(
                                    color: Color(0xFF6C63FF),
                                    blurRadius: 0,
                                    spreadRadius: 2,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback? onTap,
    String? compactValue,
    Color? accentColor,
  }) {
    final bool enabled = onTap != null;
    final Color foreground = accentColor ??
        (active
            ? const Color(0xFFA78BFA)
            : const Color.fromRGBO(255, 255, 255, 0.55));
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Material(
        color: active
          ? const Color(0xFF6C63FF).withValues(alpha: 0.20)
          : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minWidth: 58),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active
                    ? const Color(0xFF6C63FF)
                    : Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (compactValue != null)
                  Text(
                    compactValue,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                else
                  Icon(icon, color: foreground, size: 18),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: accentColor != null
                        ? accentColor.withValues(alpha: 0.80)
                        : const Color.fromRGBO(255, 255, 255, 0.70),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _OpacityCheckerPainter extends CustomPainter {
  const _OpacityCheckerPainter({
    required this.light,
    required this.dark,
    required this.squareSize,
  });

  final Color light;
  final Color dark;
  final double squareSize;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    for (double y = 0; y < size.height; y += squareSize) {
      for (double x = 0; x < size.width; x += squareSize) {
        final bool isLight =
            (((x / squareSize).floor() + (y / squareSize).floor()) % 2) == 0;
        paint.color = isLight ? light : dark;
        canvas.drawRect(
          Rect.fromLTWH(x, y, squareSize, squareSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OpacityCheckerPainter oldDelegate) {
    return oldDelegate.light != light ||
        oldDelegate.dark != dark ||
        oldDelegate.squareSize != squareSize;
  }
}
