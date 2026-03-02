part of 'basic_screen.dart';

class _BasicScreenState extends State<BasicScreen> with WidgetsBindingObserver {
  final String _sessionNamespace = 'coloring_book_session_v1';
  final String _sessionMetaKey = 'session_meta';
  final String _imageMetaKeyPrefix = 'image_meta_';
  final String _preparedMetaKeyPrefix = 'prepared_meta_';
  final String _metaBoxSuffix = '_metadata_box';
  final PixelEngine pixelEngine = PixelEngine();
  final TransformationController _transformationController =
      TransformationController();

  ui.Image? _uiImage;
  Uint8List? _rawFillBytes;

  int _rawWidth = 0;
  int _rawHeight = 0;

  final List<Uint8List?> _undoStack = <Uint8List?>[];
  final int _maxUndoSteps = 20;

  int _fillCount = 0;
  Color selectedColor = const Color(0xFFFFC107);
  bool isProcessing = false;
  int currentImageIndex = 0;
  bool _engineReady = false;
  bool _showStartupLoader = true;
  bool _showImageTransitionLoader = false;
  int _imageLoadSeq = 0;
  bool _isImageLoading = false;
  int _queuedImageDelta = 0;
  bool _isPersisting = false;
  final Map<int, _SessionSnapshot> _pendingImageSnapshots =
      <int, _SessionSnapshot>{};
  _SessionMetaSnapshot? _pendingSessionMeta;
  Directory _sessionDirectory = Directory.current;
  Box<dynamic>? _sessionMetaBox;
  bool _storageReady = false;
  Timer? _autosaveTimer;
  final Duration _autosaveDebounce = const Duration(milliseconds: 350);

  Size _containerSize = Size.zero;
  double _cachedScaleFit = 1.0;
  double _cachedFitOffsetX = 0.0;
  double _cachedFitOffsetY = 0.0;

  int _activePointers = 0;
  Offset? _pointerDownPosition;
  int _pointerDownTimeMs = 0;
  bool _pointerDragged = false;
  final double _tapMoveThreshold = 10.0;
  final int _tapMaxDurationMs = 250;
  final double _swipeMinDistance = 64.0;
  final double _swipeMaxCrossAxis = 42.0;
  final int _swipeMaxDurationMs = 450;

  final List<Color> colorHistory = <Color>[
    const Color(0xFFF44336),
    const Color(0xFFE91E63),
    const Color(0xFF9C27B0),
    const Color(0xFF2196F3),
    const Color(0xFF00BCD4),
    const Color(0xFF4CAF50),
    const Color(0xFFFFEB3B),
    const Color(0xFFFF9800),
    const Color(0xFF795548),
    const Color(0xFF000000),
    const Color(0xFF9E9E9E),
    const Color(0xFFFFFFFF),
  ];

  final List<String> testImages = <String>[
    'assets/images/doremon.png',
    'assets/images/shinchan.png',
    'assets/images/mandala.png',
    'assets/images/smilie.png',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_prepareStorageAndInit());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    unawaited(_flushStorageOnDispose());
    _uiImage?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _requestAutosave(immediate: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uiImage == null && _showStartupLoader) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F7),
        body: SafeArea(child: Center(child: PaintStartupLoader())),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Coloring Book',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: isProcessing
            ? const Padding(
                padding: EdgeInsets.all(15),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        actions: <Widget>[
          IconButton(
            icon: Icon(
              Icons.undo,
              color: (_undoStack.isNotEmpty && !isProcessing && _engineReady)
                  ? Colors.black
                  : Colors.grey.shade300,
            ),
            onPressed: (_undoStack.isNotEmpty && !isProcessing && _engineReady)
                ? _undo
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: (isProcessing || !_engineReady)
                ? null
                : _refreshCurrentImage,
          ),
          IconButton(
            icon: Icon(Icons.colorize, color: selectedColor),
            onPressed: _engineReady ? showPicker : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: PaintCanvas(
                image: _uiImage,
                showImageTransitionLoader: _showImageTransitionLoader,
                transformationController: _transformationController,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                onViewportSizeChanged: (Size newSize) {
                  if (_containerSize != newSize) {
                    _containerSize = newSize;
                    _updateFitCache();
                  }
                },
              ),
            ),
            PaintToolbar(
              colorHistory: colorHistory,
              selectedColor: selectedColor,
              onColorSelected: (Color color) {
                setState(() => selectedColor = color);
              },
              onPreviousImage: () => _changeImage(-1),
              onNextImage: () => _changeImage(1),
            ),
          ],
        ),
      ),
    );
  }
}
