import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutterwork/features/paint/controllers/basic_screen_controller.dart';
import 'package:flutterwork/features/paint/widgets/paint_canvas_container.dart';
import 'package:flutterwork/features/paint/widgets/paint_loader.dart';
import 'package:flutterwork/features/paint/widgets/paint_palette_bar.dart';
import 'package:flutterwork/features/recording/screens/paint_timelapse_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

class BasicScreen extends StatefulWidget {
  
  final String imagePath;
  final int? imageIndex; 
  const BasicScreen({
    super.key, 
    required this.imagePath, 
    this.imageIndex, 
  });
  @override
  State<BasicScreen> createState() => _BasicScreenState();
}

class _BasicScreenState extends State<BasicScreen> with WidgetsBindingObserver {
  late final BasicScreenController _controller;
  final GlobalKey _canvasCaptureKey = GlobalKey();
  bool _isOpeningTimelapse = false;
  bool _isSharingImage = false;
  bool _isCapturingCanvas = false;
  bool _isLeavingCanvas = false;
  bool _allowImmediatePop = false;
  bool _showCaptureFlash = false;

  Future<void> _handleBackNavigation() async {
    if (_isLeavingCanvas) return;
    setState(() {
      _isLeavingCanvas = true;
      _allowImmediatePop = true;
    });
    unawaited(_controller.flushSessionState());
    if (!mounted) return;
    final bool popped = await Navigator.maybePop(context);
    if (mounted && !popped) {
      setState(() {
        _isLeavingCanvas = false;
        _allowImmediatePop = false;
      });
    }
  }

  Future<bool> _handleWillPop() async {
    if (_allowImmediatePop) {
      _allowImmediatePop = false;
      return true;
    }
    if (_isLeavingCanvas) return false;
    setState(() {
      _isLeavingCanvas = true;
    });
    unawaited(_controller.flushSessionState());
    return true;
  }

  @override
  void initState() {
    super.initState();
    // Pass both values to the controller
    _controller = BasicScreenController(
      initialImagePath: widget.imagePath,
      imageIndex: widget.imageIndex, 
    );
    
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
    if (_isSharingImage) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isSharingImage = true;
    });
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
    } finally {
      if (mounted) {
        setState(() {
          _isSharingImage = false;
        });
      }
    }
  }

  Future<void> _captureCanvasScreenshot() async {
    if (_isCapturingCanvas) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isCapturingCanvas = true;
    });

    try {
      final bool granted = await _ensureGalleryPermission();
      if (!mounted) return;
      if (!granted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Allow gallery access to save the canvas screenshot.'),
          ),
        );
        return;
      }

      final RenderObject? renderObject =
          _canvasCaptureKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Canvas screenshot is not ready yet.')),
        );
        return;
      }

      _triggerCaptureFlash();
      await WidgetsBinding.instance.endOfFrame;

      final double pixelRatio = _resolveCanvasCapturePixelRatio(renderObject);
      final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();
      if (!mounted) return;
      if (byteData == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Unable to capture the canvas.')),
        );
        return;
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final SaveResult result = await SaverGallery.saveImage(
        pngBytes,
        quality: 100,
        fileName: 'canvas_${DateTime.now().millisecondsSinceEpoch}.png',
        extension: 'png',
        androidRelativePath: 'Pictures/Flutterwork/Canvas',
        skipIfExists: false,
      );
      if (!mounted) return;

      if (result.isSuccess) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Canvas screenshot saved to gallery.')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ?? 'Unable to save screenshot right now.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Canvas screenshot failed. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingCanvas = false;
        });
      }
    }
  }

  Future<bool> _ensureGalleryPermission() async {
    if (Platform.isIOS) {
      PermissionStatus status = await Permission.photosAddOnly.status;
      if (!status.isGranted && !status.isLimited) {
        status = await Permission.photosAddOnly.request();
      }
      return status.isGranted || status.isLimited;
    }

    if (Platform.isAndroid) {
      PermissionStatus status = await Permission.photos.status;
      if (!status.isGranted && !status.isLimited) {
        status = await Permission.photos.request();
      }
      if (status.isGranted || status.isLimited) {
        return true;
      }

      status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      return status.isGranted;
    }

    return true;
  }

  double _resolveCanvasCapturePixelRatio(RenderRepaintBoundary boundary) {
    final double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final Size boundarySize = boundary.size;
    if (boundarySize.width <= 0 ||
        boundarySize.height <= 0 ||
        _controller.rawWidth <= 0 ||
        _controller.rawHeight <= 0) {
      return (devicePixelRatio * 2.0).clamp(2.0, 4.0).toDouble();
    }

    final double sourceScale = math.min(
      _controller.rawWidth / boundarySize.width,
      _controller.rawHeight / boundarySize.height,
    );
    final double targetRatio = math.min(devicePixelRatio * 2.0, sourceScale);
    return targetRatio.clamp(devicePixelRatio, 4.0).toDouble();
  }

  void _triggerCaptureFlash() {
    if (!mounted) return;
    setState(() {
      _showCaptureFlash = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _showCaptureFlash = false;
      });
    });
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
            resizeToAvoidBottomInset: false, 
            body: const SafeArea(child: Center(child: PaintStartupLoader())),
          );
        }

        final int progressPercent = _controller.progressPercent;
        final int remainingPercent = _controller.remainingPercent;
        final double progressValue = progressPercent / 100.0;

        return WillPopScope(
          onWillPop: _handleWillPop,
          child: Scaffold(
            backgroundColor: const Color(0xFF1A1A2E),
            body: SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Column(
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
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.12,
                                ),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF6C63FF),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildStatusBanner(),
                      Expanded(
                        flex: 3,
                        child: PaintCanvasContainer(
                          repaintBoundaryKey: _canvasCaptureKey,
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
                          onViewportSizeChanged:
                              _controller.onViewportSizeChanged,
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
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        opacity: _showCaptureFlash ? 0.92 : 0.0,
                        child: Container(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
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
            enabled: !_isLeavingCanvas,
            onPressed: _handleBackNavigation,
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
              if (_isSharingImage) ...<Widget>[
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
              if (_isCapturingCanvas) ...<Widget>[
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
                icon: Icons.share,
                enabled: _controller.engineReady &&
                    !_controller.isProcessing &&
                    !_isSharingImage &&
                    !_isLeavingCanvas,
                onPressed: _shareCurrentImage,
              ),
              const SizedBox(width: 6),
              _buildActionIconButton(
                icon: Icons.camera_alt_rounded,
                enabled: _controller.engineReady &&
                    !_controller.isProcessing &&
                    !_isCapturingCanvas &&
                    !_isLeavingCanvas,
                onPressed: _captureCanvasScreenshot,
              ),
              const SizedBox(width: 6),
              _buildActionIconButton(
                icon: Icons.play_circle_fill,
                enabled: _controller.hasTimelapseFrames &&
                    !_isOpeningTimelapse &&
                    !_isLeavingCanvas,
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
            icon: Icons.edit_rounded,
            label: 'Pencil',
            active: _controller.activeTool == PaintToolMode.brush,
            onTap: () => _controller.setActiveTool(PaintToolMode.brush),
          ),
          const SizedBox(width: 8),
          _buildToolButton(
            icon: Icons.cleaning_services_rounded,
            label: 'Eraser',
            active: _controller.activeTool == PaintToolMode.eraser,
            onTap: () => _controller.setActiveTool(PaintToolMode.eraser),
          ),
          const SizedBox(width: 8),
          _buildToolButton(
            icon: Icons.redo_rounded,
            label: 'Undo',
            active: false,
            onTap: _controller.canRedo ? _controller.redo : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final String? message = _controller.statusMessage;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: message == null
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey<String>(message),
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC856).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFFC856).withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll<Size>(Size(36, 36)),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.white.withValues(alpha: 0.05);
            }
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.24);
            }
            return Colors.white.withValues(alpha: 0.12);
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
        size: 17,
        color: enabled
            ? (iconColor ?? Colors.white)
            : const Color.fromRGBO(255, 255, 255, 0.35),
      ),
    );
  }
}
