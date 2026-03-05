import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutterwork/features/recording/paint_timelapse_download.dart';
import 'package:flutterwork/features/recording/widgets/timelapse_export_progress.dart';
import 'package:flutterwork/features/recording/widgets/timelapse_speed_selector.dart';

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

  void _stopPlayback() {
    _timer?.cancel();
    _timer = null;
    if (_isPlaying) {
      _isPlaying = false;
      if (mounted) setState(() {});
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
    ).showSnackBar(SnackBar(content: Text(message)));
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
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }

  void _replaceCurrentImage(ui.Image? nextImage) {
    if (identical(_currentImage, nextImage)) return;
    final ui.Image? old = _currentImage;
    _currentImage = nextImage;
    old?.dispose();
  }

  @override
  void dispose() {
    _stopPlayback();
    _replaceCurrentImage(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasValidInput = _hasValidInput();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timelapse Replay'),
        actions: <Widget>[
          TimelapseSpeedSelector(
            currentSpeed: _playbackSpeed,
            options: _speedOptions,
            onSelected: _setPlaybackSpeed,
            formatSpeed: _formatSpeed,
          ),
          IconButton(
            onPressed: _hasValidInput() && !_isExporting
                ? _downloadTimelapse
                : null,
            icon: const Icon(Icons.download),
          ),
          IconButton(
            onPressed: _frames.length > 1 ? _togglePlayback : null,
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_isExporting)
            TimelapseExportProgressBar(
              progress: _exportProgress,
              label: 'Downloading video...',
              percentText: _formatPercent(_exportProgress),
            ),
          Expanded(
            child: hasValidInput
                ? Center(
                    child: AspectRatio(
                      aspectRatio: widget.width / widget.height,
                      child: Container(
                        color: Colors.white,
                        child: RawImage(
                          image: _currentImage,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  )
                : const Center(child: Text('No timelapse frames available')),
          ),
        ],
      ),
    );
  }
}
