import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'paint_loader.dart';

class PaintCanvasContainer extends StatefulWidget {
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
  State<PaintCanvasContainer> createState() => _PaintCanvasContainerState();
}

class _PaintCanvasContainerState extends State<PaintCanvasContainer> {
  Size? _lastViewportSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          double canvasWidth = constraints.maxWidth;
          double canvasHeight = constraints.maxHeight;

          if (widget.imageWidth > 0 && widget.imageHeight > 0) {
            final double imageAspect = widget.imageWidth / widget.imageHeight;
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

          final Size viewportSize = Size(canvasWidth, canvasHeight);
          if (_lastViewportSize != viewportSize) {
            _lastViewportSize = viewportSize;
            widget.onViewportSizeChanged(viewportSize);
          }

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
                    _buildCanvasContent(canvasWidth, canvasHeight),
                    PaintImageTransitionLoader(
                      visible: widget.showImageTransitionLoader,
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
    if (widget.image == null) {
      return const Center(
        key: ValueKey<String>('paint_canvas_loader'),
        child: CircularProgressIndicator(),
      );
    }

    return Listener(
      key: ValueKey<int>(widget.image.hashCode),
      onPointerDown: widget.onPointerDown,
      onPointerMove: widget.onPointerMove,
      onPointerUp: widget.onPointerUp,
      onPointerCancel: widget.onPointerCancel,
      child: InteractiveViewer(
        transformationController: widget.transformationController,
        panEnabled: true,
        minScale: 1.0,
        maxScale: 10.0,
        child: SizedBox(
          width: canvasWidth,
          height: canvasHeight,
          child: Center(
            child: RawImage(image: widget.image, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
