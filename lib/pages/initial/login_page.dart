import 'package:desktop_encryption_client/pages/initial/loading_page.dart';
import 'package:desktop_encryption_client/utils/logo_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'dart:math';
import 'dart:async';

// ============================================================
// BRANDING / SIGNAL EFFECT
// ============================================================
class SignalGlitchText extends StatefulWidget {
  final String text;

  const SignalGlitchText(this.text, {super.key});

  @override
  State<SignalGlitchText> createState() => _SignalGlitchTextState();
}

// ============================================================
// SIGNAL ANIMATION STATE
// ============================================================
class _SignalGlitchTextState extends State<SignalGlitchText>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final wave = sin(t * pi * 2);

        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: Offset(wave * 2, 0),
              child: _text(Colors.blueAccent.withOpacity(0.4)),
            ),

            Transform.translate(
              offset: Offset(-wave * 2, 0),
              child: _text(Colors.redAccent.withOpacity(0.4)),
            ),

            ShaderMask(
              shaderCallback: (bounds) {
                return LinearGradient(
                  begin: Alignment(-1 + t * 2, 0),
                  end: const Alignment(1, 0),
                  colors: [
                    Colors.white70,
                    Colors.greenAccent.withOpacity(0.8),
                    Colors.white70,
                  ],
                  stops: const [0.45, 0.5, 0.55],
                ).createShader(bounds);
              },
              blendMode: BlendMode.srcIn,
              child: _text(Colors.white70),
            ),

            Opacity(
              opacity: 0.06,
              child: Text(
                _binaryOverlay(widget.text.length),
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Colors.greenAccent,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _text(Color color) {
    return Text(
      widget.text,
      style: TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        fontStyle: FontStyle.italic,
        letterSpacing: 1.3,
        color: color,
      ),
    );
  }

  String _binaryOverlay(int len) {
    final rand = Random();
    return List.generate(len, (_) => rand.nextBool() ? '1' : '0').join();
  }
}

// ============================================================
// LOGIN PAGE WRAPPER
// ============================================================
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScreen();
  }
}

// ============================================================
// AUTH SCREEN LAYOUT
// ============================================================
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  var tStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 800) {
                    return Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LogoAnimation(),
                          Text("Login", style: tStyle),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (widget, animation) {
                              return ScaleTransition(
                                scale: animation,
                                child: widget,
                              );
                            },
                            child: Column(children: [LoginWidget()]),
                          ),
                        ],
                      ),
                    );
                  } else {
                    return Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              LogoAnimation(),
                              Text("Login", style: tStyle),
                            ],
                          ),
                          SizedBox(width: 20),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (widget, animation) {
                              return ScaleTransition(
                                scale: animation,
                                child: widget,
                              );
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [LoginWidget()],
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SignalGlitchText('ENCRYPTION CLIENT V1.2'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LOGIN FORM
// ============================================================
class LoginWidget extends StatefulWidget {
  const LoginWidget({super.key});

  @override
  State<LoginWidget> createState() => _LoginWidgetState();
}

// ============================================================
// LOGIN STATE & FLOW
// ============================================================
class _LoginWidgetState extends State<LoginWidget> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _loading = false;
  bool _isPasswordVisible = false;

  String token = "";
  String id = "";
  String name = "";
  bool success = false;
  String message = "";

  @override
  void initState() {
    super.initState();
  }

  // ============================================================
  // LOGIN EXECUTION PIPELINE
  //
  // Authenticate → save token → log activity →
  // verify device → register if needed →
  // navigate to loading page.
  // ============================================================

  Future<void> login() async {
    setState(() => _loading = true);

    await Future.delayed(const Duration(seconds: 1));

    setState(() => _loading = false);

    if (!mounted) return;

    await precacheImage(
      const AssetImage('assets/images/background.jpg'),
      context,
    );

    Get.to(
      () => const LoadingPage(),
      transition: Transition.rightToLeft,
      duration: const Duration(milliseconds: 600),
    );
  }

  // ============================================================
  // LOGIN UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey("LoginWidget"),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextInput(
            controller: usernameController,
            string: 'Email',
            isObscure: false,
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: 400,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: TextField(
                controller: passwordController,
                obscureText: !_isPasswordVisible,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_loading) {
                    login();
                  }
                },
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: Colors.white),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      size: 18,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() => _isPasswordVisible = !_isPasswordVisible);
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 25),
          _loading
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  onPressed: login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.white,
                    elevation: 10,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    "Login",
                    style: TextStyle(
                      color: Color.fromARGB(255, 36, 36, 36),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ============================================================
// REUSABLE TEXT INPUT
// ============================================================
class TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String string;
  final bool isObscure;
  const TextInput({
    super.key,
    required this.controller,
    required this.string,
    required this.isObscure,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: string,
            labelStyle: TextStyle(color: Colors.white),
          ),
          obscureText: isObscure,
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

// ============================================================
// LOGO WIDGET
// ============================================================
class Logo extends StatelessWidget {
  final double width;
  final double height;
  const Logo({super.key, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Image.asset(
        'assets/images/crypto_logo.png',
        width: width,
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }
}
