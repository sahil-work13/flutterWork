import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'paint_loader.dart';

class PaintCanvasContainer extends StatelessWidget {
  const PaintCanvasContainer({
    super.key,
    required this.image,
    required this.imageWidth,
    required this.imageHeight,
    required this.transformationController,
    required this.showImageTransitionLoader,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.onViewportSizeChanged,
  });

  final ui.Image? image;
  final int imageWidth;
  final int imageHeight;
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
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          double canvasWidth = constraints.maxWidth;
          double canvasHeight = constraints.maxHeight;

          if (imageWidth > 0 && imageHeight > 0) {
            final double imageAspect = imageWidth / imageHeight;
            final double availableAspect =
                constraints.maxWidth / constraints.maxHeight;
            if (availableAspect > imageAspect) {
              canvasHeight = constraints.maxHeight;
              canvasWidth = canvasHeight * imageAspect;
            } else {
              canvasWidth = constraints.maxWidth;
              canvasHeight = canvasWidth / imageAspect;
            }
          }

          onViewportSizeChanged(Size(canvasWidth, canvasHeight));

          return Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: canvasWidth,
              height: canvasHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                      child: _buildCanvasContent(canvasWidth, canvasHeight),
                    ),
                    PaintImageTransitionLoader(
                      visible: showImageTransitionLoader,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCanvasContent(double canvasWidth, double canvasHeight) {
    if (image == null) {
      return const Center(
        key: ValueKey<String>('paint_canvas_loader'),
        child: CircularProgressIndicator(),
      );
    }

    return Listener(
      key: ValueKey<int>(image.hashCode),
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
          width: canvasWidth,
          height: canvasHeight,
          child: Center(
            child: RawImage(image: image, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
