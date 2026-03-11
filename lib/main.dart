import 'package:flutter/material.dart';
import 'package:flutterwork/core/bindings/app_binding.dart';
import 'package:flutterwork/features/splash_and_onboarding/screens/splash_screen.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  
  // Use hive_flutter for automatic path handling
  await Hive.initFlutter();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'ColorFill',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
        useMaterial3: true,
      ),
      initialBinding: AppBinding(),
      home: const SplashScreen(),
    );
  }
}
