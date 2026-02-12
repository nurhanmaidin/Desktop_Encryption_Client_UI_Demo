import 'package:desktop_encryption_client/pages/initial/home_page.dart';
import 'package:desktop_encryption_client/utils/logo_animation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:ui';

// ============================================================
// LOADING PAGE WRAPPER
// ============================================================
class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LoadingWidget1();
  }
}

// ============================================================
// MAIN LOADING CONTROLLER
// ============================================================
class LoadingWidget1 extends StatefulWidget {
  const LoadingWidget1({super.key});

  @override
  State<LoadingWidget1> createState() => _LoadingWidget1State();
}

// ============================================================
// LOADING STATE
// ============================================================
class _LoadingWidget1State extends State<LoadingWidget1> {
  double progress = 0.0;
  String loadingMessage = "Loading Data...";

  // ============================================================
  // INIT PIPELINE
  // ============================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  // ============================================================
  // DATA RETRIEVAL PIPELINE
  //
  // restore token → fetch user info →
  // load keys → navigate to home
  // ============================================================

  Future<void> _loadData() async {
    await _animateProgressTo(0.2);
    setState(() => loadingMessage = "Preparing demo session...");

    await _animateProgressTo(0.4);
    setState(() => loadingMessage = "Loading user profile...");

    await _animateProgressTo(0.6);
    setState(() => loadingMessage = "Loading encryption keys...");

    await _animateProgressTo(0.8);
    setState(() => loadingMessage = "Finalizing workspace...");

    await _animateProgressTo(1.0);
    setState(() => loadingMessage = "Ready");

    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    // ===== DEMO DATA =====
    Get.to(
      () => HomePage(
        username: "Demo User",
        password: "demo",
        email: "demo@crypto.local",
        lastLogin: "12 Feb 2026, 10:00 AM",
        keyType: ["PERSONAL", "SHARED"],
        keyMap: {
          "PERSONAL": {"id": 1},
          "SHARED": {"id": 2},
        },
      ),
      transition: Transition.rightToLeft,
      duration: const Duration(milliseconds: 700),
    );
  }

  // ============================================================
  // PROGRESS ANIMATION
  // ============================================================

  Future<void> _animateProgressTo(double target) async {
    while (progress < target) {
      await Future.delayed(const Duration(milliseconds: 80));
      setState(() {
        progress = (progress + 0.02).clamp(0.0, target);
      });
    }
  }

  // ============================================================
  // LOADING UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LogoAnimation(),
                  const SizedBox(height: 25),
                  Text(
                    loadingMessage,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          height: 18,
                          width: double.infinity,
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: progress),
                          duration: const Duration(milliseconds: 500),
                          builder: (context, value, _) {
                            return Container(
                              height: 18,
                              width: MediaQuery.of(context).size.width * value,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color.fromARGB(255, 174, 26, 66),
                                    Color.fromARGB(255, 13, 89, 139),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Text(
                        "${(progress * 100).toInt()}%",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
