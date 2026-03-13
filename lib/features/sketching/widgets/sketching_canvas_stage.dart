import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';

import '../controllers/sketching_controller.dart';

class SketchingCanvasStage extends StatelessWidget {
  const SketchingCanvasStage({
    super.key,
    required this.controllerTag,
  });

  final String controllerTag;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SketchingController>(
      tag: controllerTag,
      id: 'canvas',
      builder: (SketchingController controller) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double availableWidth = constraints.maxWidth;
            final double availableHeight = constraints.maxHeight;
            final double boardSize = <double>[
              availableWidth - 24,
              availableHeight,
              344,
            ]
                .reduce((double a, double b) => a < b ? a : b)
                .clamp(160.0, 344.0)
                .toDouble();

            return Center(
              child: SizedBox(
                width: boardSize,
                height: boardSize,
                child: _InteractiveCanvasBoard(
                  controller: controller,
                  size: Size.square(boardSize),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _InteractiveCanvasBoard extends StatelessWidget {
  const _InteractiveCanvasBoard({
    required this.controller,
    required this.size,
  });

  final SketchingController controller;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent event) =>
          controller.beginStroke(event.localPosition, size),
      onPointerMove: (PointerMoveEvent event) =>
          controller.updateStroke(event.localPosition, size),
      onPointerUp: (PointerUpEvent event) =>
          controller.endStroke(event.localPosition, size),
      onPointerCancel: (_) => controller.endStroke(null, size),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.60),
                  blurRadius: 60,
                  offset: Offset(0, 20),
                ),
              ],
            ),
            child: RepaintBoundary(
              key: controller.repaintBoundaryKey,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: CustomPaint(
                  size: size,
                  painter: SketchCanvasPainter(
                    strokes: controller.strokes,
                    draftStroke: controller.draftStroke,
                  ),
                  foregroundPainter: SketchOverlayPainter(
                    showGrid: controller.showGrid,
                    symmetry: controller.symmetry,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
