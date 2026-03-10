import 'dart:typed_data';

class PaintTimelapseController {
  PaintTimelapseController({int maxFrames = 300}) : _maxFrames = maxFrames;

  /// Memory per frame in bytes: `width * height * 4` (RGBA8888).
  /// Total memory upper bound: `maxFrames * width * height * 4`.
  int _maxFrames;

  int get maxFrames => _maxFrames;

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

  List<Uint8List> setMaxFrames(int maxFrames) {
    final List<Uint8List> evicted = <Uint8List>[];
    final int next = maxFrames < 1 ? 1 : maxFrames;
    if (next == _maxFrames) return evicted;
    _maxFrames = next;
    if (_frames.length > _maxFrames) {
      final int removeCount = _frames.length - _maxFrames;
      evicted.addAll(_frames.take(removeCount));
      _frames.removeRange(0, removeCount);
    }
    return evicted;
  }

  Uint8List? recordFrame(Uint8List raw) {
    if (!isRecording || raw.isEmpty) return null;
    _frames.add(Uint8List.fromList(raw));
    if (_frames.length > maxFrames) {
      return _frames.removeAt(0);
    }
    return null;
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