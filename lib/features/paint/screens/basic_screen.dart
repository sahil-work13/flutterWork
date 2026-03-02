import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../../engine/PixelEngine.dart';
import '../widgets/paint_canvas.dart';
import '../widgets/paint_toolbar.dart';
import '../widgets/startup_loader.dart';

part 'basic_screen_state.dart';
part 'basic_screen_storage.dart';
part 'basic_screen_image.dart';
part 'basic_screen_interaction.dart';

void _log(String tag, String msg) {
  debugPrint('[COLOR_APP][$tag] $msg');
}

class BasicScreen extends StatefulWidget {
  const BasicScreen({super.key});

  @override
  State<BasicScreen> createState() => _BasicScreenState();
}
