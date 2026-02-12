import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:desktop_encryption_client/pages/initial/login_page.dart';

// ============================================================
// SPLASH ENTRY
// ============================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

// ============================================================
// SPLASH STATE
// ============================================================
class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _controller;
  File? _tempVideoFile;
  bool _isVideoReady = false;
  bool _showLogin = false;

  // ============================================================
  // VIDEO INITIALIZATION
  // Load asset -> copy to temp -> play -> schedule transition
  // ============================================================

  Future<void> _initVideo() async {
    final byteData = await rootBundle.load('assets/videos/background.mp4');
    final tempDir = await getTemporaryDirectory();
    final tempVideo = File('${tempDir.path}/background.mp4');

    if (await tempVideo.exists()) {
      try {
        await tempVideo.delete();
      } catch (_) {}
    }

    await tempVideo.writeAsBytes(byteData.buffer.asUint8List());
    _tempVideoFile = tempVideo;

    _controller = VideoPlayerController.file(tempVideo);
    await _controller.initialize();
    _controller.setLooping(true);
    _controller.play();

    setState(() {
      _isVideoReady = true;
    });

    Timer(const Duration(milliseconds: 800), () {
      setState(() {
        _showLogin = true;
      });
    });
  }

  // ============================================================
  // INIT LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  // ============================================================
  // CLEANUP
  // Dispose controller & delete temp files
  // ============================================================

  @override
  void dispose() {
    _controller.dispose();
    if (_tempVideoFile != null && _tempVideoFile!.existsSync()) {
      try {
        _tempVideoFile!.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  // ============================================================
  // UI RENDER
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _isVideoReady
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                )
              : Container(color: Colors.black),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: _showLogin
                ? const LoginPage()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        "Loading...",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
