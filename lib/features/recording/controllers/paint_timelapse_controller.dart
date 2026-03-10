import 'dart:typed_data';

class PaintTimelapseController {
  PaintTimelapseController({int maxFrames = 300}) : _maxFrames = maxFrames;

  /// Memory per frame in bytes: `width * height * 4` (RGBA8888).
  /// Total memory upper bound: `maxFrames * width * height * 4`.
  int _maxFrames;

  int get maxFrames => _maxFrames;

  final List<Uint8List> _frames = <Uint8List>[];
  bool isRecording = false;

  /// Index of the "current" frame in [_frames].
  ///
  /// This enables branch-aware recording: if the user undoes back to an earlier
  /// frame and then records a new frame, all frames after this pointer are
  /// discarded and the new frame is appended (creating a new branch).
  int _timelinePointer = -1;

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
      if (_frames.isEmpty) {
        _timelinePointer = -1;
      } else {
        _timelinePointer -= removeCount;
        if (_timelinePointer < 0) _timelinePointer = 0;
        if (_timelinePointer > _frames.length - 1) {
          _timelinePointer = _frames.length - 1;
        }
      }
    }
    return evicted;
  }

  Uint8List? recordFrame(Uint8List raw) {
    if (!isRecording || raw.isEmpty) return null;

    // If the user has undone steps, the pointer will be behind the end of the
    // list. Recording from that point creates a new branch, so we discard the
    // "future" frames first.
    if (_timelinePointer >= 0 && _timelinePointer < _frames.length - 1) {
      _frames.removeRange(_timelinePointer + 1, _frames.length);
    }

    _frames.add(Uint8List.fromList(raw));
    _timelinePointer = _frames.length - 1;
    if (_frames.length > maxFrames) {
      final Uint8List evicted = _frames.removeAt(0);
      _timelinePointer = _frames.isEmpty ? -1 : _frames.length - 1;
      return evicted;
    }
    return null;
  }

  /// Moves the timeline pointer backward by one frame.
  ///
  /// Used by undo to move "back in time" without recording new frames. We keep
  /// the pointer clamped at 0 when frames exist so the initial frame is never
  /// treated as "undone".
  void stepBackward() {
    if (_timelinePointer > 0) {
      _timelinePointer--;
    } else if (_frames.isNotEmpty) {
      _timelinePointer = 0;
    } else {
      _timelinePointer = -1;
    }
  }

  void clear() {
    _frames.clear();
    _timelinePointer = -1;
  }

  void replaceFrames(List<Uint8List> frames) {
    _frames.clear();
    _timelinePointer = -1;
    if (frames.isEmpty) return;

    final int start = frames.length > maxFrames ? frames.length - maxFrames : 0;
    for (int i = start; i < frames.length; i++) {
      final Uint8List raw = frames[i];
      if (raw.isEmpty) continue;
      _frames.add(Uint8List.fromList(raw));
    }
    _timelinePointer = _frames.isEmpty ? -1 : _frames.length - 1;
  }

  List<Uint8List> getFrames() => List<Uint8List>.unmodifiable(_frames);
}
