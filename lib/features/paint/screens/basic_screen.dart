import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controllers/basic_screen_controller.dart';

class BasicScreen extends StatefulWidget {
  const BasicScreen({super.key});

  @override
  State<BasicScreen> createState() => _BasicScreenState();
}

class _BasicScreenState extends State<BasicScreen> with WidgetsBindingObserver {
  late final BasicScreenController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BasicScreenController();
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        if (_controller.uiImage == null && _controller.showStartupLoader) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F5F7),
            body: SafeArea(child: Center(child: _buildStartupLoader())),
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
            leading: _controller.isProcessing
                ? const Padding(
                    padding: EdgeInsets.all(15),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            actions: <Widget>[
              IconButton(
                icon: Icon(
                  Icons.undo,
                  color: _controller.canUndo ? Colors.black : Colors.grey.shade300,
                ),
                onPressed: _controller.canUndo ? _controller.undo : null,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.black),
                onPressed:
                    _controller.canRefresh ? _controller.refreshCurrentImage : null,
              ),
              IconButton(
                icon: Icon(Icons.colorize, color: _controller.selectedColor),
                onPressed: _controller.canPickColor
                    ? () => _controller.showPicker(context)
                    : null,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(flex: 3, child: _buildCanvas()),
                _buildBottomControls(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCanvas() {
    final ui.Image? image = _controller.uiImage;
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              image == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        _controller.onViewportSizeChanged(
                          Size(constraints.maxWidth, constraints.maxHeight),
                        );
                        return Listener(
                          onPointerDown: _controller.onPointerDown,
                          onPointerMove: _controller.onPointerMove,
                          onPointerUp: _controller.onPointerUp,
                          onPointerCancel: _controller.onPointerCancel,
                          child: InteractiveViewer(
                            transformationController:
                                _controller.transformationController,
                            panEnabled: true,
                            minScale: 1.0,
                            maxScale: 10.0,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: Center(
                                child: RawImage(image: image, fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _controller.showImageTransitionLoader ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.28),
                    child: Center(
                      child: Container(
                        width: 38,
                        height: 38,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _navBtn(Icons.arrow_back_ios, () => _controller.changeImage(-1)),
                const Text(
                  'PALETTE',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                _navBtn(Icons.arrow_forward_ios, () => _controller.changeImage(1)),
              ],
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 55,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemCount: _controller.colorHistory.length,
              itemBuilder: (BuildContext context, int i) {
                return _buildColorCircle(_controller.colorHistory[i]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartupLoader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Icon(Icons.palette_outlined, size: 34),
        ),
        const SizedBox(height: 18),
        const Text(
          'Loading Coloring Book...',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 14),
        const SizedBox(
          width: 150,
          child: LinearProgressIndicator(
            minHeight: 4,
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
        ),
      ],
    );
  }

  Widget _buildColorCircle(Color color) {
    final bool isSelected = _controller.selectedColor == color;
    final double luminance = color.computeLuminance();
    final Color selectedBorderColor = luminance < 0.5 ? Colors.white : Colors.black;
    final Color checkColor = selectedBorderColor;

    return GestureDetector(
      onTap: () => _controller.selectColor(color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: isSelected ? 52 : 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: null,
          border: Border.all(
            color: isSelected ? selectedBorderColor : Colors.black,
            width: isSelected ? 2.0 : 2.5,
          ),
        ),
        child: isSelected ? Icon(Icons.check, color: checkColor, size: 20) : null,
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback tap) {
    return IconButton(icon: Icon(icon, size: 18), onPressed: tap);
  }
}
