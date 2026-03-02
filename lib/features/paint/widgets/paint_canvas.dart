import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class PaintCanvas extends StatelessWidget {
  const PaintCanvas({
    super.key,
    required this.image,
    required this.showImageTransitionLoader,
    required this.transformationController,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.onViewportSizeChanged,
  });

  final ui.Image? image;
  final bool showImageTransitionLoader;
  final TransformationController transformationController;
  final void Function(PointerDownEvent event) onPointerDown;
  final void Function(PointerMoveEvent event) onPointerMove;
  final void Function(PointerUpEvent event) onPointerUp;
  final void Function(PointerCancelEvent event) onPointerCancel;
  final ValueChanged<Size> onViewportSizeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              image == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        onViewportSizeChanged(
                          Size(constraints.maxWidth, constraints.maxHeight),
                        );
                        return Listener(
                          onPointerDown: onPointerDown,
                          onPointerMove: onPointerMove,
                          onPointerUp: onPointerUp,
                          onPointerCancel: onPointerCancel,
                          child: InteractiveViewer(
                            transformationController: transformationController,
                            panEnabled: true,
                            minScale: 1.0,
                            maxScale: 10.0,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: Center(
                                child: RawImage(image: image, fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: showImageTransitionLoader ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.28),
                    child: Center(
                      child: Container(
                        width: 38,
                        height: 38,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
