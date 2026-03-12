import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutterwork/features/recording/paint_timelapse_download.dart';

class PaintTimelapsePlayer extends StatefulWidget {
  const PaintTimelapsePlayer({
    super.key,
    required this.frames,
    required this.width,
    required this.height,
    this.frameInterval = const Duration(milliseconds: 120),
  });

  final List<Uint8List> frames;
  final int width;
  final int height;
  final Duration frameInterval;

  @override
  State<PaintTimelapsePlayer> createState() => _PaintTimelapsePlayerState();
}

class _PaintTimelapsePlayerState extends State<PaintTimelapsePlayer> {
  static const int _maxRenderedFrameDimension = 1280;
  static const List<double> _speedOptions = <double>[
    0.25,
    0.5,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  late final List<Uint8List> _frames;

  ui.Image? _currentImage;
  Timer? _timer;
  int _frameIndex = 0;
  bool _isPlaying = false;
  bool _isDecoding = false;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  double _playbackSpeed = 2.0;

  @override
  void initState() {
    super.initState();
    _frames = List<Uint8List>.unmodifiable(widget.frames);
    if (_hasValidInput()) {
      unawaited(_showFrame(0));
      if (_frames.length > 1) {
        _startPlayback();
      }
    }
  }

  bool _hasValidInput() {
    return _frames.isNotEmpty && widget.width > 0 && widget.height > 0;
  }

  void _startPlayback() {
    if (_frames.length <= 1) return;
    _timer?.cancel();
    _isPlaying = true;
    _timer = Timer.periodic(_effectiveFrameInterval, (_) {
      if (_isDecoding || !_hasValidInput()) return;
      final int next = (_frameIndex + 1) % _frames.length;
      unawaited(_showFrame(next));
    });
    if (mounted) setState(() {});
  }

  void _stopPlayback({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    if (_isPlaying) {
      _isPlaying = false;
      if (notify && mounted) setState(() {});
    }
  }

  void _togglePlayback() {
    if (_frames.length <= 1) return;
    if (_isPlaying) {
      _stopPlayback();
      return;
    }
    _startPlayback();
  }

  void _stepFrame(int delta) {
    if (!_hasValidInput()) return;
    _stopPlayback();
    final int target = (_frameIndex + delta).clamp(0, _frames.length - 1);
    unawaited(_showFrame(target));
  }

  void _onScrubTo(double value) {
    if (!_hasValidInput()) return;
    final int target = value.round().clamp(0, _frames.length - 1);
    if (target == _frameIndex) return;
    _stopPlayback();
    unawaited(_showFrame(target));
  }

  Future<void> _openSpeedSheet() async {
    if (!_hasValidInput()) return;
    final double? selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (BuildContext context) {
        return _SpeedBottomSheet(
          options: _speedOptions,
          currentSpeed: _playbackSpeed,
          formatSpeed: _formatSpeed,
        );
      },
    );
    if (selected != null) {
      _setPlaybackSpeed(selected);
    }
  }

  Duration get _effectiveFrameInterval {
    final int baseMs = widget.frameInterval.inMilliseconds;
    final int effectiveMs = (baseMs * (2.0 / _playbackSpeed)).round();
    return Duration(milliseconds: effectiveMs < 1 ? 1 : effectiveMs);
  }

  void _setPlaybackSpeed(double speed) {
    if (_playbackSpeed == speed) return;
    setState(() {
      _playbackSpeed = speed;
    });
    if (_isPlaying) {
      _startPlayback();
    }
  }

  Future<void> _downloadTimelapse() async {
    if (_isExporting || !_hasValidInput()) return;

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    try {
      final String? savedPath = await exportTimelapseVideo(
        frames: _frames,
        width: widget.width,
        height: widget.height,
        frameInterval: _effectiveFrameInterval,
        onProgress: (double progress) {
          if (!mounted) return;
          setState(() {
            _exportProgress = progress.clamp(0.0, 1.0);
          });
        },
      );
      if (!mounted) return;

      if (savedPath == null) {
        _showSnackBar('MP4 export is not available on this device');
      } else {
        _showSnackBar('Saved video: $savedPath');
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Failed to export timelapse video');
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportProgress = 0.0;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A2A44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 90),
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        duration: const Duration(milliseconds: 2500),
      ),
    );
  }

  String _formatSpeed(double speed) {
    if (speed == speed.roundToDouble()) {
      return speed.toStringAsFixed(0);
    }
    final String twoDecimals = speed.toStringAsFixed(2);
    if (twoDecimals.endsWith('0')) {
      return speed.toStringAsFixed(1);
    }
    return twoDecimals;
  }

  String _formatPercent(double value) {
    return '${(value * 100).clamp(0, 100).toStringAsFixed(0)}%';
  }

  Future<void> _showFrame(int index) async {
    if (index < 0 || index >= _frames.length) return;

    final int expectedLength = widget.width * widget.height * 4;
    final Uint8List raw = _frames[index];
    if (raw.lengthInBytes != expectedLength) return;

    _isDecoding = true;
    try {
      final ui.Image image = await _rawRgbaToUiImage(
        raw,
        widget.width,
        widget.height,
      );
      if (!mounted) {
        image.dispose();
        return;
      }
      _replaceCurrentImage(image);
      setState(() {
        _frameIndex = index;
      });
    } finally {
      _isDecoding = false;
    }
  }

  Future<ui.Image> _rawRgbaToUiImage(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      rgba,
    );
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final ({int width, int height}) scaled = _scaledFrameDimensions(
      width: width,
      height: height,
    );
    final ui.Codec codec = await descriptor.instantiateCodec(
      targetWidth: scaled.width,
      targetHeight: scaled.height,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }

  static ({int width, int height}) _scaledFrameDimensions({
    required int width,
    required int height,
  }) {
    final int longestSide = width > height ? width : height;
    if (width <= 0 ||
        height <= 0 ||
        longestSide <= _maxRenderedFrameDimension) {
      return (width: width, height: height);
    }
    final double scale = _maxRenderedFrameDimension / longestSide;
    final int scaledWidth = (width * scale).round();
    final int scaledHeight = (height * scale).round();
    return (
      width: scaledWidth < 1 ? 1 : scaledWidth,
      height: scaledHeight < 1 ? 1 : scaledHeight,
    );
  }

  void _replaceCurrentImage(ui.Image? nextImage) {
    if (identical(_currentImage, nextImage)) return;
    final ui.Image? old = _currentImage;
    _currentImage = nextImage;
    old?.dispose();
  }

  @override
  void dispose() {
    _stopPlayback(notify: false);
    _replaceCurrentImage(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasValidInput = _hasValidInput();
    final int totalFrames = _frames.length;
    final double scrubMax = totalFrames > 1 ? (totalFrames - 1).toDouble() : 1.0;
    final double scrubValue = totalFrames > 1 ? _frameIndex.toDouble() : 0.0;
    final String framePillText = totalFrames > 0
        ? '${_frameIndex + 1} / $totalFrames'
        : '0 / 0';
    final String scrubLeft = totalFrames > 0 ? 'Frame ${_frameIndex + 1}' : 'Frame 0';
    final String scrubRight = '$totalFrames frames';

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: <Widget>[
                  _RoundIconButton(
                    icon: Icons.arrow_back,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Timelapse Replay',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _FramePill(text: framePillText),
                  const SizedBox(width: 10),
                  _RoundIconButton(
                    icon: Icons.download_rounded,
                    onPressed: hasValidInput && !_isExporting
                        ? _downloadTimelapse
                        : null,
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _isExporting
                  ? Padding(
                      key: const ValueKey<String>('export_banner'),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: _ExportBanner(
                        progress: _exportProgress,
                        percentText: _formatPercent(_exportProgress),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey<String>('export_banner_hidden'),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: AspectRatio(
                      aspectRatio: hasValidInput
                          ? (widget.width / widget.height)
                          : 1.0,
                      child: _CanvasFrame(
                        image: _currentImage,
                        showLoading: _isDecoding,
                        hasValidInput: hasValidInput,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: const Color(0xFF6C63FF),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                  thumbColor: const Color(0xFF6C63FF),
                  overlayColor: const Color(0xFF6C63FF).withValues(alpha: 0.12),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: IgnorePointer(
                  ignoring: !hasValidInput || totalFrames <= 1,
                  child: Slider(
                    value: scrubValue.clamp(0.0, scrubMax),
                    min: 0.0,
                    max: scrubMax,
                    onChanged: _onScrubTo,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: <Widget>[
                  Text(
                    scrubLeft,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    scrubRight,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                    width: 1.2,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _ControlButton(
                      icon: Icons.skip_previous_rounded,
                      onPressed: hasValidInput && totalFrames > 1
                          ? () => _stepFrame(-1)
                          : null,
                    ),
                    _PlayButton(
                      isPlaying: _isPlaying,
                      enabled: hasValidInput && totalFrames > 1 && !_isExporting,
                      onPressed: _togglePlayback,
                    ),
                    _ControlButton(
                      icon: Icons.skip_next_rounded,
                      onPressed: hasValidInput && totalFrames > 1
                          ? () => _stepFrame(1)
                          : null,
                    ),
                    _SpeedPill(
                      label: '${_formatSpeed(_playbackSpeed)}x',
                      onPressed: hasValidInput ? _openSpeedSheet : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll<Size>(Size(38, 38)),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.white.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.24);
            }
            return Colors.white.withValues(alpha: 0.12);
          },
        ),
        overlayColor: WidgetStatePropertyAll<Color?>(
          Colors.white.withValues(alpha: 0.10),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
      ),
      icon: Icon(
        icon,
        size: 18,
        color: onPressed == null
            ? Colors.white.withValues(alpha: 0.35)
            : Colors.white,
      ),
    );
  }
}

class _FramePill extends StatelessWidget {
  const _FramePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.70),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ExportBanner extends StatelessWidget {
  const _ExportBanner({required this.progress, required this.percentText});

  final double progress;
  final String percentText;

  @override
  Widget build(BuildContext context) {
    final double clamped = progress.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1.2,
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const _PulseDot(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Exporting video...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  percentText,
                  style: const TextStyle(
                    color: Color(0xFF6C63FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Container(color: Colors.white.withValues(alpha: 0.12)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: clamped,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Color(0xFF6C63FF),
                            Color(0xFFFF6B9D),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      lowerBound: 0.7,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFFF6B9D),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _CanvasFrame extends StatelessWidget {
  const _CanvasFrame({
    required this.image,
    required this.showLoading,
    required this.hasValidInput,
  });

  final ui.Image? image;
  final bool showLoading;
  final bool hasValidInput;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 60,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (hasValidInput)
              RawImage(image: image, fit: BoxFit.contain)
            else
              const Center(
                child: Text(
                  'No timelapse frames available',
                  textAlign: TextAlign.center,
                ),
              ),
            if (showLoading)
              Container(
                color: Colors.white.withValues(alpha: 0.55),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1.0,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withValues(alpha: 0.14),
          highlightColor: Colors.white.withValues(alpha: 0.10),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.enabled,
    required this.onPressed,
  });

  final bool isPlaying;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final List<BoxShadow> shadows = isPlaying
        ? <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.65),
              blurRadius: 36,
              spreadRadius: 0,
            ),
            BoxShadow(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.20),
              blurRadius: 60,
              spreadRadius: 0,
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.30),
              blurRadius: 24,
              spreadRadius: 0,
            ),
          ];

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          customBorder: const CircleBorder(),
          splashColor: Colors.white.withValues(alpha: 0.18),
          highlightColor: Colors.white.withValues(alpha: 0.12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF6C63FF),
                  Color(0xFFA78BFA),
                ],
              ),
              boxShadow: shadows,
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedPill extends StatelessWidget {
  const _SpeedPill({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1.0,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          splashColor: Colors.white.withValues(alpha: 0.14),
          highlightColor: Colors.white.withValues(alpha: 0.10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.5),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.speed_rounded,
                  size: 16,
                  color: const Color(0xFF6C63FF),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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

class _SpeedBottomSheet extends StatelessWidget {
  const _SpeedBottomSheet({
    required this.options,
    required this.currentSpeed,
    required this.formatSpeed,
  });

  final List<double> options;
  final double currentSpeed;
  final String Function(double speed) formatSpeed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Playback Speed',
            style: TextStyle(
              color: Color(0xFF1A1A2E),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: options.map((double speed) {
              final bool isActive = speed == currentSpeed;
              return Material(
                color: isActive
                    ? const Color(0xFF6C63FF)
                    : const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: () => Navigator.pop<double>(context, speed),
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 11,
                    ),
                    child: Text(
                      '${formatSpeed(speed)}x',
                      style: TextStyle(
                        color: isActive ? Colors.white : const Color(0xFF6C63FF),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }
}
