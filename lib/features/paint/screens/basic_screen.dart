import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutterwork/features/paint/controllers/basic_screen_controller.dart';
import 'package:flutterwork/features/paint/widgets/paint_canvas_container.dart';
import 'package:flutterwork/features/paint/widgets/paint_loader.dart';
import 'package:flutterwork/features/paint/widgets/paint_palette_bar.dart';
import 'package:flutterwork/features/recording/paint_timelapse_player.dart';
import 'package:share_plus/share_plus.dart';

class BasicScreen extends StatefulWidget {
  const BasicScreen({super.key, this.imagePath});

  final String? imagePath;

  @override
  State<BasicScreen> createState() => _BasicScreenState();
}

class _BasicScreenState extends State<BasicScreen> with WidgetsBindingObserver {
  late final BasicScreenController _controller;
  bool _isOpeningTimelapse = false;

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

  Future<void> _shareCurrentImage() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final file = await _controller.exportCurrentImagePng();
      if (!mounted) return;
      if (file == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Unable to share image right now.')),
        );
        return;
      }
      await Share.shareXFiles(<XFile>[
        XFile(file.path),
      ], text: 'Check out my coloring progress!');
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Sharing failed. Please try again.')),
      );
    }
  }

  Future<void> _openTimelapsePlayer() async {
    if (_isOpeningTimelapse) return;
    setState(() {
      _isOpeningTimelapse = true;
    });

    try {
      final List<Uint8List> frames = await _controller
          .loadTimelapseFramesForPlayback();
      if (!mounted) return;
      if (frames.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No timelapse frames available')),
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PaintTimelapsePlayer(
            frames: frames,
            width: _controller.rawWidth,
            height: _controller.rawHeight,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open timelapse right now')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningTimelapse = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        if (_controller.showStartupLoader) {
          return Scaffold(
            backgroundColor: const Color(0xFF1A1A2E),
            body: const SafeArea(child: Center(child: PaintStartupLoader())),
          );
        }

        final int progressPercent = _controller.progressPercent;
        final int remainingPercent = _controller.remainingPercent;
        final double progressValue = progressPercent / 100.0;

        return Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                _buildTopBar(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Text(
                            'Progress',
                            style: TextStyle(
                              color: Color.fromRGBO(255, 255, 255, 0.55),
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$progressPercent% filled',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '$remainingPercent% remaining',
                          style: const TextStyle(
                            color: Color.fromRGBO(255, 255, 255, 0.55),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: progressValue,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF6C63FF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: PaintCanvasContainer(
                    image: _controller.uiImage,
                    imageWidth: _controller.rawWidth,
                    imageHeight: _controller.rawHeight,
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
                _buildToolBar(),
                PaintPaletteBar(
                  colorHistory: _controller.colorHistory,
                  recentColors: _controller.recentOrMostUsedColors,
                  selectedColor: _controller.selectedColor,
                  onSelectColor: _controller.selectColor,
                  onOpenColorPicker: () => _controller.showPicker(context),
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

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Row(
        children: <Widget>[
          _buildActionIconButton(
            icon: Icons.arrow_back,
            enabled: true,
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: <Widget>[
                const Text(
                  'Coloring Book',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_controller.rawWidth} x ${_controller.rawHeight} px',
                  style: const TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_controller.isProcessing) ...<Widget>[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (_isOpeningTimelapse) ...<Widget>[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              _buildActionIconButton(
                icon: Icons.undo,
                enabled: _controller.canUndo,
                onPressed: _controller.undo,
              ),
              const SizedBox(width: 6),
              // _buildActionIconButton(
              //   icon: Icons.redo,
              //   enabled: _controller.canRedo,
              //   onPressed: _controller.redo,
              // ),
              const SizedBox(width: 6),
              _buildActionIconButton(
                icon: Icons.share,
                enabled: _controller.engineReady && !_controller.isProcessing,
                onPressed: _shareCurrentImage,
              ),
              const SizedBox(width: 6),
              _buildActionIconButton(
                icon: Icons.play_circle_fill,
                enabled: _controller.hasTimelapseFrames && !_isOpeningTimelapse,
                onPressed: _openTimelapsePlayer,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _buildToolButton(
            icon: Icons.format_color_fill_rounded,
            label: 'Fill',
            active: _controller.activeTool == PaintToolMode.fill,
            onTap: () => _controller.setActiveTool(PaintToolMode.fill),
          ),
          const SizedBox(width: 8),
          _buildToolButton(
            icon: Icons.cleaning_services_rounded,
            label: 'Eraser',
            active: _controller.activeTool == PaintToolMode.eraser,
            onTap: () => _controller.setActiveTool(PaintToolMode.eraser),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback? onTap,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.78 : 1.0,
      child: Material(
        color: active
            ? const Color(0xFF6C63FF).withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active
                    ? const Color(0xFF6C63FF)
                    : Colors.white.withValues(alpha: 0.05),
                width: 1.2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, color: const Color(0xFFFFC856), size: 18),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.72),
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

  Widget _buildActionIconButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
    Color? iconColor,
  }) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(
        fixedSize: const Size(36, 36),
        backgroundColor: enabled
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      icon: Icon(
        icon,
        size: 17,
        color: enabled
            ? (iconColor ?? Colors.white)
            : const Color.fromRGBO(255, 255, 255, 0.35),
      ),
    );
  }
}