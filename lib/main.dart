import 'dart:io';
import 'package:desktop_encryption_client/pages/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
import 'package:url_launcher_windows/url_launcher_windows.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

// ============================================================
// MAIN
// ============================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  UrlLauncherWindows.registerWith();

  const windowOptions = WindowOptions(
    minimumSize: Size(400, 750),
    size: Size(1300, 800),
    center: true,
    title: 'Desktop Encryption Client',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  HttpOverrides.global = MyHttpOverrides();

  runApp(const MyApp());
}

// ============================================================
// APP ROOT
// ============================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: Colors.black),
      home: SplashScreen(),
    );
  }
}
