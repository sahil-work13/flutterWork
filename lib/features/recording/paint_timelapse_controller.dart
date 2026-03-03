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

  void resume() {
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

  void replaceFrames(List<Uint8List> frames) {
    _frames.clear();
    if (frames.isEmpty) return;

    final int start = frames.length > maxFrames ? frames.length - maxFrames : 0;
    for (int i = start; i < frames.length; i++) {
      final Uint8List raw = frames[i];
      if (raw.isEmpty) continue;
      _frames.add(Uint8List.fromList(raw));
    }
  }

  List<Uint8List> getFrames() => List<Uint8List>.unmodifiable(_frames);
}
