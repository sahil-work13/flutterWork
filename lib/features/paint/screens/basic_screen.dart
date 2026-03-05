import 'package:flutter/material.dart';
import 'package:flutterwork/features/paint/basic_screen_controller.dart';
import 'package:flutterwork/features/paint/widgets/paint_canvas_container.dart';
import 'package:flutterwork/features/paint/widgets/paint_loader.dart';
import 'package:flutterwork/features/paint/widgets/paint_palette_bar.dart';
import 'package:flutterwork/features/recording/paint_timelapse_player.dart';

class BasicScreen extends StatefulWidget {
  const BasicScreen({super.key, this.imagePath});

  final String? imagePath;

  @override
  State<BasicScreen> createState() => _BasicScreenState();
}

class _BasicScreenState extends State<BasicScreen> with WidgetsBindingObserver {
  late final BasicScreenController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BasicScreenController(initialImagePath: widget.imagePath);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.onAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        if (_controller.uiImage == null && _controller.showStartupLoader) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F5F7),
            body: const SafeArea(child: Center(child: PaintStartupLoader())),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8F7FF),
          appBar: AppBar(
            scrolledUnderElevation: 0,
            elevation: 0,
            backgroundColor: const Color(0xFFF8F7FF),
            title: const Text(
              'Coloring Book',
              style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontWeight: FontWeight.w900,
              ),
            ),
            centerTitle: true,
            leading: _controller.isProcessing
                ? const Padding(
                    padding: EdgeInsets.all(15),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            actions: <Widget>[
              _buildActionIconButton(
                icon: Icons.play_circle_fill,
                enabled: _controller.hasTimelapseFrames,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PaintTimelapsePlayer(
                        frames: _controller.timelapseFrames,
                        width: _controller.rawWidth,
                        height: _controller.rawHeight,
                      ),
                    ),
                  );
                },
              ),
              _buildActionIconButton(
                icon: Icons.undo,
                enabled: _controller.canUndo,
                onPressed: _controller.undo,
              ),
              _buildActionIconButton(
                icon: Icons.refresh,
                enabled: _controller.canRefresh,
                onPressed: _controller.refreshCurrentImage,
              ),
              _buildActionIconButton(
                icon: Icons.colorize,
                enabled: _controller.canPickColor,
                iconColor: _controller.selectedColor,
                onPressed: () => _controller.showPicker(context),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: PaintCanvasContainer(
                    image: _controller.uiImage,
                    transformationController:
                        _controller.transformationController,
                    showImageTransitionLoader:
                        _controller.showImageTransitionLoader,
                    onPointerDown: _controller.onPointerDown,
                    onPointerMove: _controller.onPointerMove,
                    onPointerUp: _controller.onPointerUp,
                    onPointerCancel: _controller.onPointerCancel,
                    onViewportSizeChanged: _controller.onViewportSizeChanged,
                  ),
                ),
                PaintPaletteBar(
                  colorHistory: _controller.colorHistory,
                  selectedColor: _controller.selectedColor,
                  onSelectColor: _controller.selectColor,
                  onPreviousImage: () => _controller.changeImage(-1),
                  onNextImage: () => _controller.changeImage(1),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionIconButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
    Color? iconColor,
  }) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(
        backgroundColor: enabled ? Colors.white : const Color(0xFFF1F1F8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(
        icon,
        size: 20,
        color: enabled
            ? (iconColor ?? const Color(0xFF1A1A2E))
            : const Color(0xFFBFC1D4),
      ),
    );
  }
}
