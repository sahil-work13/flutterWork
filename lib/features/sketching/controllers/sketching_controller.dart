import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutterwork/core/storage/coloring_book_session_storage.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

enum SketchTool { pencil, eraser, line, circle, rect }

class SketchPoint {
  const SketchPoint({
    required this.dx,
    required this.dy,
  });

  final double dx;
  final double dy;

  SketchPoint copy() => SketchPoint(dx: dx, dy: dy);

  Offset resolve(Size size) => Offset(dx * size.width, dy * size.height);
}

class SketchStroke {
  const SketchStroke({
    required this.tool,
    required this.color,
    required this.opacity,
    required this.size,
    required this.symmetry,
    required this.points,
  });

  final SketchTool tool;
  final Color color;
  final double opacity;
  final double size;
  final int symmetry;
  final List<SketchPoint> points;

  SketchStroke copyWith({
    SketchTool? tool,
    Color? color,
    double? opacity,
    double? size,
    int? symmetry,
    List<SketchPoint>? points,
  }) {
    return SketchStroke(
      tool: tool ?? this.tool,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      size: size ?? this.size,
      symmetry: symmetry ?? this.symmetry,
      points: points ?? this.points,
    );
  }

  SketchStroke deepCopy() {
    return SketchStroke(
      tool: tool,
      color: color,
      opacity: opacity,
      size: size,
      symmetry: symmetry,
      points: points.map((SketchPoint point) => point.copy()).toList(),
    );
  }
}

class SketchToolOption {
  const SketchToolOption({
    required this.tool,
    required this.icon,
    required this.label,
  });

  final SketchTool tool;
  final IconData icon;
  final String label;
}

class SymmetryOption {
  const SymmetryOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final int value;
  final String label;
  final IconData icon;
}

class CuratedSketchPalette {
  const CuratedSketchPalette({
    required this.name,
    required this.colors,
  });

  final String name;
  final List<Color> colors;
}

class SketchingController extends GetxController {
  SketchingController();

  static const List<double> brushSizes = <double>[2, 4, 8, 14, 22];
  static const List<SymmetryOption> symmetryOptions = <SymmetryOption>[
    SymmetryOption(value: 0, label: 'Off', icon: Icons.close_rounded),
    SymmetryOption(
      value: 2,
      label: '2x Mirror',
      icon: Icons.flip_rounded,
    ),
    SymmetryOption(
      value: 4,
      label: '4x Quad',
      icon: Icons.grid_4x4_rounded,
    ),
    SymmetryOption(
      value: 6,
      label: '6x Hex',
      icon: Icons.hexagon_outlined,
    ),
    SymmetryOption(
      value: 8,
      label: '8x Mandala',
      icon: Icons.auto_awesome_rounded,
    ),
  ];
  static const List<SketchToolOption> toolOptions = <SketchToolOption>[
    SketchToolOption(
      tool: SketchTool.pencil,
      icon: Icons.edit_rounded,
      label: 'Pencil',
    ),
    SketchToolOption(
      tool: SketchTool.eraser,
      icon: Icons.cleaning_services_rounded,
      label: 'Eraser',
    ),
    SketchToolOption(
      tool: SketchTool.line,
      icon: Icons.show_chart_rounded,
      label: 'Line',
    ),
    SketchToolOption(
      tool: SketchTool.circle,
      icon: Icons.circle_outlined,
      label: 'Circle',
    ),
    SketchToolOption(
      tool: SketchTool.rect,
      icon: Icons.crop_square_rounded,
      label: 'Rect',
    ),
  ];
  static const List<Color> palette = <Color>[
    Color(0xFFFF6B9D),
    Color(0xFF6C63FF),
    Color(0xFFFFB830),
    Color(0xFF22C55E),
    Color(0xFFFF8C42),
    Color(0xFF4ECDC4),
    Color(0xFFE91E63),
    Color(0xFF2196F3),
    Color(0xFF9C27B0),
    Color(0xFFF44336),
    Color(0xFFFFFFFF),
    Color(0xFF000000),
  ];
  static const List<CuratedSketchPalette> curatedPalettes =
      <CuratedSketchPalette>[
        CuratedSketchPalette(
          name: 'Candy Pop',
          colors: <Color>[
            Color(0xFFFF6B9D),
            Color(0xFFFF8C42),
            Color(0xFFFFB830),
            Color(0xFF4ECDC4),
          ],
        ),
        CuratedSketchPalette(
          name: 'Night Studio',
          colors: <Color>[
            Color(0xFF6C63FF),
            Color(0xFF2196F3),
            Color(0xFF1C1C2E),
            Color(0xFFFFFFFF),
          ],
        ),
      ];
  static const int _historyLimit = 40;
  static const int _maxTimelapseFrames = 180;
  static const double _referenceCanvasSize = 340.0;
  static const Color _canvasBackground = Color(0xFF1C1C2E);
  static const int timelapseWidth = 340;
  static const int timelapseHeight = 340;
  static const String _sessionKey = 'sketching_session_v1';
  static const String _sessionJsonFile = 'sketching_session_v1.json';
  static const String _timelapseRawFile = 'sketching_session_v1_timelapse.raw';

  final GlobalKey repaintBoundaryKey = GlobalKey();

  final List<List<SketchStroke>> _undoStack = <List<SketchStroke>>[];
  final List<List<SketchStroke>> _redoStack = <List<SketchStroke>>[];
  final List<SketchStroke> _strokes = <SketchStroke>[];
  final List<Uint8List> _timelapseFrames = <Uint8List>[];

  SketchStroke? _draftStroke;
  SketchTool _selectedTool = SketchTool.pencil;
  Color _selectedColor = palette.first;
  double _selectedBrushSize = brushSizes[2];
  double _opacity = 1.0;
  int _symmetry = 0;
  bool _showGrid = false;
  bool _isSaving = false;
  bool _isSharing = false;
  bool _isDrawing = false;
  bool _isCapturingTimelapseFrame = false;
  bool _timelapseCaptureQueued = false;
  bool _queuedTimelapseMutationDestructive = false;
  bool _storageReady = false;
  Directory? _sessionDirectory;
  Box<dynamic>? _sessionMetaBox;
  Future<void>? _storageInitFuture;
  Timer? _autosaveTimer;

  List<SketchStroke> get strokes =>
      _strokes.map((SketchStroke stroke) => stroke.deepCopy()).toList();
  SketchStroke? get draftStroke => _draftStroke?.deepCopy();
  SketchTool get selectedTool => _selectedTool;
  Color get selectedColor => _selectedColor;
  double get selectedBrushSize => _selectedBrushSize;
  double get opacity => _opacity;
  int get symmetry => _symmetry;
  bool get showGrid => _showGrid;
  bool get isSaving => _isSaving;
  bool get isSharing => _isSharing;
  bool get canUndo => _undoStack.isNotEmpty && !_isBusy;
  bool get canRedo => _redoStack.isNotEmpty && !_isBusy;
  bool get hasSketchContent => _strokes.isNotEmpty || _draftStroke != null;
  bool get hasTimelapseFrames => _timelapseFrames.length > 1;
  List<Uint8List> get timelapseFrames =>
      List<Uint8List>.unmodifiable(_timelapseFrames);
  bool get _isBusy => _isSaving || _isSharing;

  @override
  void onInit() {
    super.onInit();
    _storageInitFuture = _prepareStorageAndRestore();
    unawaited(_storageInitFuture!);
  }

  @override
  void onClose() {
    _autosaveTimer?.cancel();
    unawaited(flushSessionState());
    super.onClose();
  }

  Future<void> initSession() async {
    final Future<void> initFuture =
        _storageInitFuture ??= _prepareStorageAndRestore();
    await initFuture;
  }

  Future<void> flushSessionState() async {
    _autosaveTimer?.cancel();
    await initSession();
    await _persistSessionState();
  }

  String get symmetryLabel {
    for (final SymmetryOption option in symmetryOptions) {
      if (option.value == _symmetry) {
        return option.label;
      }
    }
    return 'Off';
  }

  void setTool(SketchTool tool) {
    if (_selectedTool == tool) return;
    _selectedTool = tool;
    _scheduleSessionSave();
    update(<Object>['controls']);
  }

  void setBrushSize(double size) {
    if (_selectedBrushSize == size) return;
    _selectedBrushSize = size;
    _scheduleSessionSave();
    update(<Object>['controls']);
  }

  void setOpacity(double value) {
    final double clamped = value.clamp(0.10, 1.0).toDouble();
    if ((_opacity - clamped).abs() < 0.001) return;
    _opacity = clamped;
    _scheduleSessionSave();
    update(<Object>['controls']);
  }

  void setColor(Color color) {
    if (_selectedColor.toARGB32() == color.toARGB32()) return;
    _selectedColor = color;
    _scheduleSessionSave();
    update(<Object>['controls']);
  }

  Future<void> showPicker(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Pick a Custom Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _selectedColor,
            onColorChanged: (Color color) {
              _selectedColor = color;
              _scheduleSessionSave();
              update(<Object>['controls']);
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void cycleSymmetry() {
    final int currentIndex = symmetryOptions.indexWhere(
      (SymmetryOption option) => option.value == _symmetry,
    );
    final int nextIndex =
        currentIndex < 0 ? 0 : (currentIndex + 1) % symmetryOptions.length;
    _symmetry = symmetryOptions[nextIndex].value;
    _scheduleSessionSave();
    update(<Object>['controls', 'canvas', 'chrome']);
  }

  void toggleGrid() {
    _showGrid = !_showGrid;
    _scheduleSessionSave();
    update(<Object>['controls', 'canvas']);
  }

  void clearCanvas() {
    if (_strokes.isEmpty && _draftStroke == null) return;
    _pushUndoSnapshot();
    _strokes.clear();
    _draftStroke = null;
    _redoStack.clear();
    unawaited(_refreshTimelapseAfterMutation(destructive: true));
    _scheduleSessionSave();
    update(<Object>['canvas', 'controls', 'chrome']);
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(_cloneStrokeList(_strokes));
    final List<SketchStroke> snapshot = _undoStack.removeLast();
    _restoreSnapshot(snapshot);
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(_cloneStrokeList(_strokes));
    final List<SketchStroke> snapshot = _redoStack.removeLast();
    _restoreSnapshot(snapshot);
  }

  void beginStroke(Offset localPosition, Size size) {
    if (_isBusy || size.width <= 0 || size.height <= 0) return;
    _pushUndoSnapshot();
    _redoStack.clear();
    _isDrawing = true;
    final SketchPoint start = _normalize(localPosition, size);
    _draftStroke = SketchStroke(
      tool: _selectedTool,
      color: _selectedColor,
      opacity: _opacity,
      size: _selectedBrushSize,
      symmetry: _symmetry,
      points: <SketchPoint>[start],
    );
    update(<Object>['canvas', 'chrome']);
  }

  void updateStroke(Offset localPosition, Size size) {
    if (!_isDrawing || _draftStroke == null) return;

    final SketchPoint point = _normalize(localPosition, size);
    if (_draftStroke!.tool == SketchTool.pencil ||
        _draftStroke!.tool == SketchTool.eraser) {
      final List<SketchPoint> nextPoints = List<SketchPoint>.from(
        _draftStroke!.points,
      );
      if (nextPoints.isEmpty ||
          _distanceSquared(nextPoints.last, point) > 0.0000025) {
        nextPoints.add(point);
        _draftStroke = _draftStroke!.copyWith(points: nextPoints);
        update(<Object>['canvas']);
      }
      return;
    }

    if (_draftStroke!.points.length == 1) {
      _draftStroke = _draftStroke!.copyWith(
        points: <SketchPoint>[_draftStroke!.points.first, point],
      );
    } else {
      final List<SketchPoint> nextPoints = List<SketchPoint>.from(
        _draftStroke!.points,
      );
      nextPoints[nextPoints.length - 1] = point;
      _draftStroke = _draftStroke!.copyWith(points: nextPoints);
    }
    update(<Object>['canvas']);
  }

  void endStroke(Offset? localPosition, Size size) {
    if (localPosition != null) {
      updateStroke(localPosition, size);
    }
    _isDrawing = false;
    final SketchStroke? draft = _draftStroke;
    if (draft == null) {
      update(<Object>['chrome']);
      return;
    }
    if (_isMeaningfulStroke(draft)) {
      _strokes.add(draft.deepCopy());
      unawaited(
        _refreshTimelapseAfterMutation(
          destructive: draft.tool == SketchTool.eraser,
        ),
      );
      _scheduleSessionSave();
    } else if (_undoStack.isNotEmpty) {
      _undoStack.removeLast();
    }
    _draftStroke = null;
    update(<Object>['canvas', 'controls', 'chrome']);
  }

  Future<bool> saveSketchToGallery() async {
    if (_isSaving) return false;
    _isSaving = true;
    update(<Object>['chrome']);
    try {
      final Uint8List? bytes = await exportCanvasBytes();
      if (bytes == null) return false;
      final bool granted = await _ensureGalleryPermission();
      if (!granted) return false;
      final SaveResult result = await SaverGallery.saveImage(
        bytes,
        quality: 100,
        fileName: 'sketch_${DateTime.now().millisecondsSinceEpoch}.png',
        extension: 'png',
        androidRelativePath: 'Pictures/Flutterwork/Sketches',
        skipIfExists: false,
      );
      return result.isSuccess;
    } finally {
      _isSaving = false;
      update(<Object>['chrome']);
    }
  }

  Future<bool> shareSketch() async {
    if (_isSharing) return false;
    _isSharing = true;
    update(<Object>['chrome']);
    try {
      final Uint8List? bytes = await exportCanvasBytes();
      if (bytes == null) return false;
      final Directory directory = await getTemporaryDirectory();
      final File file = File(
        '${directory.path}${Platform.pathSeparator}sketch_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        text: 'Check out my sketch from Flutterwork.',
      );
      return true;
    } finally {
      _isSharing = false;
      update(<Object>['chrome']);
    }
  }

  Future<Uint8List?> exportCanvasBytes() async {
    final RenderObject? renderObject =
        repaintBoundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      return null;
    }
    final double devicePixelRatio = ui.PlatformDispatcher
        .instance
        .views
        .first
        .devicePixelRatio;
    final double pixelRatio =
        (devicePixelRatio * 2.0).clamp(2.0, 4.0).toDouble();
    final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void _restoreSnapshot(List<SketchStroke> snapshot) {
    _strokes
      ..clear()
      ..addAll(_cloneStrokeList(snapshot));
    _draftStroke = null;
    unawaited(_refreshTimelapseAfterMutation(destructive: true));
    _scheduleSessionSave();
    update(<Object>['canvas', 'controls', 'chrome']);
  }

  void _pushUndoSnapshot() {
    _undoStack.add(_cloneStrokeList(_strokes));
    if (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
  }

  List<SketchStroke> _cloneStrokeList(List<SketchStroke> source) {
    return source.map((SketchStroke stroke) => stroke.deepCopy()).toList();
  }

  SketchPoint _normalize(Offset localPosition, Size size) {
    final double dx = (localPosition.dx / size.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final double dy = (localPosition.dy / size.height)
        .clamp(0.0, 1.0)
        .toDouble();
    return SketchPoint(dx: dx, dy: dy);
  }

  double _distanceSquared(SketchPoint a, SketchPoint b) {
    final double dx = a.dx - b.dx;
    final double dy = a.dy - b.dy;
    return dx * dx + dy * dy;
  }

  bool _isMeaningfulStroke(SketchStroke stroke) {
    if (stroke.points.isEmpty) return false;
    if (stroke.tool == SketchTool.pencil || stroke.tool == SketchTool.eraser) {
      return true;
    }
    return stroke.points.length >= 2;
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

  void _scheduleSessionSave() {
    if (!_storageReady) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(flushSessionState()),
    );
  }

  Future<void> _prepareStorageAndRestore() async {
    try {
      _sessionDirectory =
          await ColoringBookSessionStorage.ensureSessionDirectory();
      _sessionMetaBox = await ColoringBookSessionStorage.ensureMetaBox();
      _storageReady = true;
      await _restoreSessionState();
    } catch (_) {
      _storageReady = false;
    }
  }

  Future<void> _restoreSessionState() async {
    if (!_storageReady || _sessionDirectory == null) return;
    final File sessionFile = File(_sessionJsonPath);
    if (!await sessionFile.exists()) {
      return;
    }

    try {
      final String raw = await sessionFile.readAsString();
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _selectedTool = SketchTool.values[_readBoundedInt(
        data['tool'],
        min: 0,
        max: SketchTool.values.length - 1,
      )];
      _selectedColor = Color(
        (data['selectedColor'] as num?)?.toInt() ?? palette.first.toARGB32(),
      );
      _selectedBrushSize = _readBoundedDouble(
        data['selectedBrushSize'],
        min: brushSizes.first,
        max: brushSizes.last,
        fallback: brushSizes[2],
      );
      _opacity = _readBoundedDouble(
        data['opacity'],
        min: 0.10,
        max: 1.0,
        fallback: 1.0,
      );
      final int restoredSymmetry = _readBoundedInt(
        data['symmetry'],
        min: 0,
        max: symmetryOptions.last.value,
      );
      _symmetry = symmetryOptions.any(
            (SymmetryOption option) => option.value == restoredSymmetry,
          )
          ? restoredSymmetry
          : 0;
      _showGrid = data['showGrid'] as bool? ?? false;

      _strokes
        ..clear()
        ..addAll(
          (data['strokes'] as List<dynamic>? ?? <dynamic>[])
              .whereType<Map<dynamic, dynamic>>()
              .map(_strokeFromJson),
        );

      await _restoreTimelapseFrames();
      update(<Object>['canvas', 'controls', 'chrome']);
    } catch (_) {
      _strokes.clear();
      _timelapseFrames.clear();
    }
  }

  Future<void> _restoreTimelapseFrames() async {
    _timelapseFrames.clear();
    if (_sessionDirectory == null) return;
    final File rawFile = File(_timelapseRawPath);
    if (!await rawFile.exists()) return;
    final Uint8List bytes = await rawFile.readAsBytes();
    final int frameBytes = timelapseWidth * timelapseHeight * 4;
    final int frameCount = bytes.lengthInBytes ~/ frameBytes;
    for (int index = 0; index < frameCount; index++) {
      final int start = index * frameBytes;
      final int end = start + frameBytes;
      _timelapseFrames.add(Uint8List.sublistView(bytes, start, end));
    }
  }

  Future<void> _persistSessionState() async {
    if (!_storageReady || _sessionDirectory == null) return;
    if (_strokes.isEmpty && _timelapseFrames.isEmpty) {
      await _clearPersistedSessionState();
      return;
    }

    final File sessionFile = File(_sessionJsonPath);
    final Map<String, dynamic> data = <String, dynamic>{
      'tool': _selectedTool.index,
      'selectedColor': _selectedColor.toARGB32(),
      'selectedBrushSize': _selectedBrushSize,
      'opacity': _opacity,
      'symmetry': _symmetry,
      'showGrid': _showGrid,
      'strokes': _strokes.map(_strokeToJson).toList(growable: false),
    };
    await sessionFile.writeAsString(jsonEncode(data), flush: true);
    await _persistTimelapseFrames();
    await _sessionMetaBox?.put(
      _sessionKey,
      <String, dynamic>{'lastSaved': DateTime.now().toIso8601String()},
    );
    await _sessionMetaBox?.flush();
  }

  Future<void> _persistTimelapseFrames() async {
    if (_sessionDirectory == null) return;
    final File rawFile = File(_timelapseRawPath);
    if (_timelapseFrames.isEmpty) {
      if (await rawFile.exists()) {
        await rawFile.delete();
      }
      return;
    }
    final IOSink sink = rawFile.openWrite();
    try {
      for (final Uint8List frame in _timelapseFrames) {
        sink.add(frame);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<void> _clearPersistedSessionState() async {
    final File sessionFile = File(_sessionJsonPath);
    if (await sessionFile.exists()) {
      await sessionFile.delete();
    }
    final File rawFile = File(_timelapseRawPath);
    if (await rawFile.exists()) {
      await rawFile.delete();
    }
    await _sessionMetaBox?.delete(_sessionKey);
    await _sessionMetaBox?.flush();
  }

  Map<String, dynamic> _strokeToJson(SketchStroke stroke) {
    return <String, dynamic>{
      'tool': stroke.tool.index,
      'color': stroke.color.toARGB32(),
      'opacity': stroke.opacity,
      'size': stroke.size,
      'symmetry': stroke.symmetry,
      'points': stroke.points
          .map((SketchPoint point) => <double>[point.dx, point.dy])
          .toList(growable: false),
    };
  }

  SketchStroke _strokeFromJson(Map<dynamic, dynamic> json) {
    final List<dynamic> rawPoints = json['points'] as List<dynamic>? ?? <dynamic>[];
    return SketchStroke(
      tool: SketchTool.values[_readBoundedInt(
        json['tool'],
        min: 0,
        max: SketchTool.values.length - 1,
      )],
      color: Color((json['color'] as num?)?.toInt() ?? palette.first.toARGB32()),
      opacity: (json['opacity'] as num? ?? 1.0).toDouble(),
      size: (json['size'] as num? ?? brushSizes[2]).toDouble(),
      symmetry: _readBoundedInt(
        json['symmetry'],
        min: 0,
        max: symmetryOptions.last.value,
      ),
      points: rawPoints.map((dynamic point) {
        final List<dynamic> pair = point as List<dynamic>;
        return SketchPoint(
          dx: (pair[0] as num).toDouble(),
          dy: (pair[1] as num).toDouble(),
        );
      }).toList(growable: false),
    );
  }

  String get _sessionJsonPath =>
      '${_sessionDirectory!.path}${Platform.pathSeparator}$_sessionJsonFile';

  String get _timelapseRawPath =>
      '${_sessionDirectory!.path}${Platform.pathSeparator}$_timelapseRawFile';

  Future<void> _refreshTimelapseAfterMutation({
    required bool destructive,
  }) async {
    if (_isCapturingTimelapseFrame) {
      _timelapseCaptureQueued = true;
      _queuedTimelapseMutationDestructive =
          _queuedTimelapseMutationDestructive || destructive;
      return;
    }
    _isCapturingTimelapseFrame = true;
    try {
      bool pendingDestructive = destructive;
      do {
        final bool applyDestructive = pendingDestructive;
        pendingDestructive = false;
        _timelapseCaptureQueued = false;
        _queuedTimelapseMutationDestructive = false;
        final Uint8List? frame = await _renderTimelapseFrame();
        if (frame == null) continue;
        if (_isBlankFrame(frame)) {
          _timelapseFrames.clear();
        } else if (!applyDestructive) {
          if (_timelapseFrames.isEmpty ||
              !_frameBytesEqual(_timelapseFrames.last, frame)) {
            _timelapseFrames.add(frame);
          }
        } else {
          final int matchIndex = _findMatchingTimelapseFrameIndex(frame);
          if (matchIndex >= 0) {
            _timelapseFrames.removeRange(
              matchIndex + 1,
              _timelapseFrames.length,
            );
          } else if (_timelapseFrames.isEmpty) {
            _timelapseFrames.add(frame);
          } else {
            _timelapseFrames[_timelapseFrames.length - 1] = frame;
          }
        }
        if (_timelapseFrames.length > _maxTimelapseFrames) {
          _timelapseFrames.removeRange(
            0,
            _timelapseFrames.length - _maxTimelapseFrames,
          );
        }
        update(<Object>['chrome']);
        _scheduleSessionSave();
        pendingDestructive =
            pendingDestructive || _queuedTimelapseMutationDestructive;
      } while (_timelapseCaptureQueued);
    } finally {
      _isCapturingTimelapseFrame = false;
      _queuedTimelapseMutationDestructive = false;
    }
  }

  Future<Uint8List?> _renderTimelapseFrame() async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Size size = Size(
      timelapseWidth.toDouble(),
      timelapseHeight.toDouble(),
    );
    SketchCanvasPainter(
      strokes: _cloneStrokeList(_strokes),
      draftStroke: null,
    ).paint(canvas, size);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(timelapseWidth, timelapseHeight);
    try {
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  int _findMatchingTimelapseFrameIndex(Uint8List frame) {
    for (int index = _timelapseFrames.length - 1; index >= 0; index--) {
      if (_frameBytesEqual(_timelapseFrames[index], frame)) {
        return index;
      }
    }
    return -1;
  }

  bool _isBlankFrame(Uint8List frame) {
    if (frame.lengthInBytes != timelapseWidth * timelapseHeight * 4) {
      return false;
    }
    final int colorValue = _canvasBackground.toARGB32();
    final int alpha = (colorValue >> 24) & 0xFF;
    final int red = (colorValue >> 16) & 0xFF;
    final int green = (colorValue >> 8) & 0xFF;
    final int blue = colorValue & 0xFF;
    for (int index = 0; index < frame.lengthInBytes; index += 4) {
      if (frame[index] != red ||
          frame[index + 1] != green ||
          frame[index + 2] != blue ||
          frame[index + 3] != alpha) {
        return false;
      }
    }
    return true;
  }

  bool _frameBytesEqual(Uint8List a, Uint8List b) {
    if (a.lengthInBytes != b.lengthInBytes) return false;
    for (int index = 0; index < a.lengthInBytes; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  int _readBoundedInt(
    Object? raw, {
    required int min,
    required int max,
    int? fallback,
  }) {
    final int value = (raw as num?)?.toInt() ?? fallback ?? min;
    return value.clamp(min, max).toInt();
  }

  double _readBoundedDouble(
    Object? raw, {
    required double min,
    required double max,
    required double fallback,
  }) {
    final double value = (raw as num?)?.toDouble() ?? fallback;
    return value.clamp(min, max).toDouble();
  }
}

class SketchCanvasPainter extends CustomPainter {
  const SketchCanvasPainter({
    required this.strokes,
    required this.draftStroke,
  });

  final List<SketchStroke> strokes;
  final SketchStroke? draftStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint background = Paint()..color = SketchingController._canvasBackground;
    canvas.drawRect(Offset.zero & size, background);
    for (final SketchStroke stroke in strokes) {
      _paintStroke(canvas, size, stroke);
    }
    if (draftStroke != null) {
      _paintStroke(canvas, size, draftStroke!);
    }
  }

  void _paintStroke(Canvas canvas, Size size, SketchStroke stroke) {
    final List<_SymmetryTransform> transforms = _symmetryTransforms(
      stroke.symmetry,
    );
    final Paint paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke.size * (size.shortestSide / SketchingController._referenceCanvasSize)
      ..color = (stroke.tool == SketchTool.eraser
              ? SketchingController._canvasBackground
              : stroke.color)
          .withValues(alpha: stroke.opacity);

    final Offset center = size.center(Offset.zero);
    for (final _SymmetryTransform transform in transforms) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(transform.angle);
      if (transform.flipX) {
        canvas.scale(-1, 1);
      }
      canvas.translate(-center.dx, -center.dy);
      switch (stroke.tool) {
        case SketchTool.pencil:
        case SketchTool.eraser:
          _paintFreehand(canvas, size, stroke, paint);
          break;
        case SketchTool.line:
          _paintLine(canvas, size, stroke, paint);
          break;
        case SketchTool.circle:
          _paintCircle(canvas, size, stroke, paint);
          break;
        case SketchTool.rect:
          _paintRect(canvas, size, stroke, paint);
          break;
      }
      canvas.restore();
    }
  }

  void _paintFreehand(
    Canvas canvas,
    Size size,
    SketchStroke stroke,
    Paint paint,
  ) {
    if (stroke.points.isEmpty) return;
    if (stroke.points.length == 1) {
      final Offset point = stroke.points.first.resolve(size);
      canvas.drawCircle(point, paint.strokeWidth / 2, Paint()..color = paint.color);
      return;
    }

    final Path path = Path();
    final List<Offset> points = stroke.points
        .map((SketchPoint point) => point.resolve(size))
        .toList(growable: false);
    path.moveTo(points.first.dx, points.first.dy);
    for (int index = 1; index < points.length - 1; index++) {
      final Offset current = points[index];
      final Offset next = points[index + 1];
      final Offset mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    final Offset last = points.last;
    path.lineTo(last.dx, last.dy);
    canvas.drawPath(path, paint);
  }

  void _paintLine(Canvas canvas, Size size, SketchStroke stroke, Paint paint) {
    if (stroke.points.length < 2) return;
    canvas.drawLine(
      stroke.points.first.resolve(size),
      stroke.points.last.resolve(size),
      paint,
    );
  }

  void _paintCircle(Canvas canvas, Size size, SketchStroke stroke, Paint paint) {
    if (stroke.points.length < 2) return;
    final Offset center = stroke.points.first.resolve(size);
    final Offset edge = stroke.points.last.resolve(size);
    final double radius = (edge - center).distance;
    canvas.drawCircle(center, radius, paint);
  }

  void _paintRect(Canvas canvas, Size size, SketchStroke stroke, Paint paint) {
    if (stroke.points.length < 2) return;
    final Rect rect = Rect.fromPoints(
      stroke.points.first.resolve(size),
      stroke.points.last.resolve(size),
    );
    canvas.drawRect(rect, paint);
  }

  List<_SymmetryTransform> _symmetryTransforms(int symmetry) {
    if (symmetry == 0) {
      return const <_SymmetryTransform>[_SymmetryTransform(angle: 0, flipX: false)];
    }
    if (symmetry == 2) {
      return const <_SymmetryTransform>[
        _SymmetryTransform(angle: 0, flipX: false),
        _SymmetryTransform(angle: 0, flipX: true),
      ];
    }
    final List<_SymmetryTransform> transforms = <_SymmetryTransform>[];
    for (int index = 0; index < symmetry; index++) {
      final double angle = (index / symmetry) * (2 * math.pi);
      transforms.add(_SymmetryTransform(angle: angle, flipX: false));
      transforms.add(_SymmetryTransform(angle: angle, flipX: true));
    }
    return transforms;
  }

  @override
  bool shouldRepaint(covariant SketchCanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.draftStroke != draftStroke;
  }
}

class SketchOverlayPainter extends CustomPainter {
  const SketchOverlayPainter({
    required this.showGrid,
    required this.symmetry,
  });

  final bool showGrid;
  final int symmetry;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      _paintGrid(canvas, size);
    }
  }

  Offset _rayToRectEdge({
    required Size size,
    required Offset center,
    required double angle,
  }) {
    final double dirX = math.cos(angle);
    final double dirY = math.sin(angle);

    final double halfWidth = size.width / 2;
    final double halfHeight = size.height / 2;

    final double tX =
        dirX == 0 ? double.infinity : halfWidth / dirX.abs();
    final double tY =
        dirY == 0 ? double.infinity : halfHeight / dirY.abs();
    final double t = math.min(tX, tY);

    return center + Offset(dirX * t, dirY * t);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final Paint fineLine = Paint()
      ..color = const Color(0x1F6C63FF)
      ..strokeWidth = 0.7;
    final Paint axisLine = Paint()
      ..color = const Color(0x4D6C63FF)
      ..strokeWidth = 1.0;
    final Offset center = size.center(Offset.zero);

    if (symmetry == 2) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        axisLine,
      );
      return;
    }

    if (symmetry == 4) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        axisLine,
      );
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        axisLine,
      );
      return;
    }

    if (symmetry == 6 || symmetry == 8) {
      for (int index = 0; index < symmetry; index++) {
        final double angle = (-math.pi / 2) + ((2 * math.pi * index) / symmetry);
        final Offset edge = _rayToRectEdge(
          size: size,
          center: center,
          angle: angle,
        );
        canvas.drawLine(center, edge, axisLine);
      }
      return;
    }

    const int divisions = 17;
    for (int index = 0; index < divisions; index++) {
      final double dx = (size.width / (divisions - 1)) * index;
      final double dy = (size.height / (divisions - 1)) * index;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), fineLine);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), fineLine);
    }
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      axisLine,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      axisLine,
    );
  }

  @override
  bool shouldRepaint(covariant SketchOverlayPainter oldDelegate) {
    return oldDelegate.showGrid != showGrid || oldDelegate.symmetry != symmetry;
  }
}

class _SymmetryTransform {
  const _SymmetryTransform({
    required this.angle,
    required this.flipX,
  });

  final double angle;
  final bool flipX;
}
