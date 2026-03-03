import 'dart:typed_data';

class PaintTimelapseController {
  PaintTimelapseController({this.maxFrames = 300});

  /// Memory per frame in bytes: `width * height * 4` (RGBA8888).
  /// Total memory upper bound: `maxFrames * width * height * 4`.
  final int maxFrames;

  final List<Uint8List> _frames = <Uint8List>[];
  bool isRecording = false;

  bool get hasFrames => _frames.isNotEmpty;

  void start() {
    clear();
    isRecording = true;
  }

  void stop() {
    isRecording = false;
  }

  void recordFrame(Uint8List raw) {
    if (!isRecording || raw.isEmpty) return;
    _frames.add(Uint8List.fromList(raw));
    if (_frames.length > maxFrames) {
      _frames.removeAt(0);
    }
  }

  void clear() {
    _frames.clear();
  }

  List<Uint8List> getFrames() => List<Uint8List>.unmodifiable(_frames);
}
