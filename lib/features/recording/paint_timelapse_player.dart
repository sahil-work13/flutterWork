import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'paint_timelapse_download.dart';

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
    });

    try {
      final Uint8List gifBytes = _encodeGifBytes();
      if (gifBytes.isEmpty) {
        _showSnackBar('Could not export timelapse');
        return;
      }

      final String fileName =
          'coloring_timelapse_${DateTime.now().millisecondsSinceEpoch}.gif';
      final String? savedPath = await saveTimelapseBytes(gifBytes, fileName);
      if (!mounted) return;

      if (savedPath == null) {
        _showSnackBar('Download is not available on this platform');
      } else {
        _showSnackBar('Saved: $savedPath');
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Failed to download timelapse');
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Uint8List _encodeGifBytes() {
    final int expectedLength = widget.width * widget.height * 4;
    final int frameDurationCs = (_effectiveFrameInterval.inMilliseconds / 10).round();
    final img.GifEncoder encoder = img.GifEncoder(repeat: 0);

    for (final Uint8List raw in _frames) {
      if (raw.lengthInBytes != expectedLength) continue;
      final img.Image frame = img.Image.fromBytes(
        widget.width,
        widget.height,
        Uint8List.fromList(raw),
      );
      encoder.addFrame(frame, duration: frameDurationCs < 1 ? 1 : frameDurationCs);
    }

    final List<int>? bytes = encoder.finish();
    if (bytes == null || bytes.isEmpty) return Uint8List(0);
    return Uint8List.fromList(bytes);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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

  Future<void> _showFrame(int index) async {
    if (index < 0 || index >= _frames.length) return;

    final int expectedLength = widget.width * widget.height * 4;
    final Uint8List raw = _frames[index];
    if (raw.lengthInBytes != expectedLength) return;

    _isDecoding = true;
    try {
      final ui.Image image =
          await _rawRgbaToUiImage(raw, widget.width, widget.height);
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

  Future<ui.Image> _rawRgbaToUiImage(Uint8List rgba, int width, int height) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
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
          PopupMenuButton<double>(
            tooltip: 'Playback speed',
            initialValue: _playbackSpeed,
            onSelected: _setPlaybackSpeed,
            itemBuilder: (BuildContext context) {
              return _speedOptions.map((double speed) {
                return PopupMenuItem<double>(
                  value: speed,
                  child: Text(
                    '${_formatSpeed(speed)}x',
                  ),
                );
              }).toList();
            },
            icon: const Icon(Icons.speed),
          ),
          _isExporting
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton(
                  onPressed: _hasValidInput() ? _downloadTimelapse : null,
                  icon: const Icon(Icons.download),
                ),
          IconButton(
            onPressed: _frames.length > 1 ? _togglePlayback : null,
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
          ),
        ],
      ),
      body: hasValidInput
          ? Center(
              child: AspectRatio(
                aspectRatio: widget.width / widget.height,
                child: Container(
                  color: Colors.white,
                  child: RawImage(image: _currentImage, fit: BoxFit.contain),
                ),
              ),
            )
          : const Center(child: Text('No timelapse frames available')),
    );
  }
}
