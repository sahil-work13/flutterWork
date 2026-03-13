import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/sketching_controller.dart';

class SketchingTopBar extends StatelessWidget {
  const SketchingTopBar({
    super.key,
    required this.controllerTag,
    required this.onBackPressed,
    required this.onUndoPressed,
    required this.onTimelapsePressed,
    required this.onSharePressed,
    required this.onSavePressed,
  });

  final String controllerTag;
  final VoidCallback onBackPressed;
  final VoidCallback onUndoPressed;
  final VoidCallback onTimelapsePressed;
  final VoidCallback onSharePressed;
  final VoidCallback onSavePressed;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SketchingController>(
      tag: controllerTag,
      id: 'chrome',
      builder: (SketchingController controller) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: <Widget>[
              _circleButton(
                icon: Icons.arrow_back_rounded,
                onPressed: onBackPressed,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: <Widget>[
                    const Text(
                      'Sketching',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Symmetry: ${controller.symmetryLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color.fromRGBO(255, 255, 255, 0.40),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (controller.isSharing || controller.isSaving)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  _circleButton(
                    icon: Icons.undo_rounded,
                    onPressed: controller.canUndo &&
                            !controller.isSharing &&
                            !controller.isSaving
                        ? onUndoPressed
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _circleButton(
                    icon: Icons.play_circle_fill_rounded,
                    onPressed: controller.hasTimelapseFrames &&
                            !controller.isSharing &&
                            !controller.isSaving
                        ? onTimelapsePressed
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _circleButton(
                    icon: Icons.share_rounded,
                    onPressed: controller.isSharing || controller.isSaving
                        ? null
                        : onSharePressed,
                  ),
                  const SizedBox(width: 8),
                  _circleButton(
                    icon: Icons.camera_alt_rounded,
                    onPressed: controller.isSharing || controller.isSaving
                        ? null
                        : onSavePressed,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final bool enabled = onPressed != null;
    return IconButton(
      onPressed: onPressed,
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll<Size>(Size(38, 38)),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.white.withValues(alpha: 0.05);
            }
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.18);
            }
            return Colors.white.withValues(alpha: 0.08);
          },
        ),
        overlayColor: WidgetStatePropertyAll<Color?>(
          Colors.white.withValues(alpha: 0.08),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
      ),
      icon: Icon(
        icon,
        size: 18,
        color: enabled
            ? Colors.white
            : const Color.fromRGBO(255, 255, 255, 0.35),
      ),
    );
  }
}
