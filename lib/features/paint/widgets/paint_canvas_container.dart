import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'paint_loader.dart';

class PaintCanvasContainer extends StatelessWidget {
  const PaintCanvasContainer({
    super.key,
    required this.image,
    required this.transformationController,
    required this.showImageTransitionLoader,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.onViewportSizeChanged,
  });

  final ui.Image? image;
  final TransformationController transformationController;
  final bool showImageTransitionLoader;
  final void Function(PointerDownEvent event) onPointerDown;
  final void Function(PointerMoveEvent event) onPointerMove;
  final void Function(PointerUpEvent event) onPointerUp;
  final void Function(PointerCancelEvent event) onPointerCancel;
  final void Function(Size size) onViewportSizeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF1A1A2E).withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 10),
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
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            onViewportSizeChanged(
                              Size(constraints.maxWidth, constraints.maxHeight),
                            );
                            return Listener(
                              onPointerDown: onPointerDown,
                              onPointerMove: onPointerMove,
                              onPointerUp: onPointerUp,
                              onPointerCancel: onPointerCancel,
                              child: InteractiveViewer(
                                transformationController:
                                    transformationController,
                                panEnabled: true,
                                minScale: 1.0,
                                maxScale: 10.0,
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                  child: Center(
                                    child: RawImage(
                                      image: image,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                    ),
              PaintImageTransitionLoader(visible: showImageTransitionLoader),
            ],
          ),
        ),
      ),
    );
  }
}
