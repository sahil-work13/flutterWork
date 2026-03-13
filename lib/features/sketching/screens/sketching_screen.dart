import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutterwork/features/recording/screens/paint_timelapse_player.dart';

import '../controllers/sketching_controller.dart';
import '../widgets/sketching_canvas_stage.dart';
import '../widgets/sketching_controls_panel.dart';
import '../widgets/sketching_top_bar.dart';

class SketchingScreen extends StatefulWidget {
  const SketchingScreen({super.key});

  @override
  State<SketchingScreen> createState() => _SketchingScreenState();
}

class _SketchingScreenState extends State<SketchingScreen>
    with WidgetsBindingObserver {
  late final String _controllerTag;
  late final SketchingController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controllerTag = 'sketching_${DateTime.now().microsecondsSinceEpoch}';
    _controller = Get.put<SketchingController>(
      SketchingController(),
      tag: _controllerTag,
    );
    unawaited(_controller.initSession());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.flushSessionState());
    if (Get.isRegistered<SketchingController>(tag: _controllerTag)) {
      Get.delete<SketchingController>(tag: _controllerTag);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_controller.flushSessionState());
    }
  }

  Future<bool> _confirmExit() async {
    if (!_controller.hasSketchContent) return true;
    final bool? shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Discard Sketch?'),
          content: const Text('Your sketch will be lost if you go back now.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep Drawing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
              ),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );
    return shouldDiscard ?? false;
  }

  Future<void> _handleBackPressed() async {
    final bool shouldPop = await _confirmExit();
    if (!mounted || !shouldPop) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _openColorPicker() async {
    await _controller.showPicker(context);
  }

  Future<void> _shareSketch() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool shared = await _controller.shareSketch();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          shared
              ? 'Sketch shared successfully.'
              : 'Unable to share the sketch right now.',
        ),
      ),
    );
  }

  Future<void> _openTimelapse() async {
    if (!_controller.hasTimelapseFrames) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No timelapse frames available.')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PaintTimelapsePlayer(
          frames: _controller.timelapseFrames,
          width: SketchingController.timelapseWidth,
          height: SketchingController.timelapseHeight,
        ),
      ),
    );
  }

  Future<void> _saveSketch() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool saved = await _controller.saveSketchToGallery();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Sketch saved to gallery.'
              : 'Unable to save the sketch right now.',
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final bool? shouldClear = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Clear Canvas?'),
          content: const Text('This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD14A4A),
              ),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
    if (shouldClear == true) {
      _controller.clearCanvas();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _confirmExit,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0E1C),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              SketchingTopBar(
                controllerTag: _controllerTag,
                onBackPressed: _handleBackPressed,
                onUndoPressed: _controller.undo,
                onTimelapsePressed: _openTimelapse,
                onSharePressed: _shareSketch,
                onSavePressed: _saveSketch,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SketchingCanvasStage(controllerTag: _controllerTag),
                ),
              ),
              SketchingControlsPanel(
                controllerTag: _controllerTag,
                onPickColor: _openColorPicker,
                onClearPressed: _confirmClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
