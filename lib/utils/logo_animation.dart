import 'package:flutter/material.dart';

class LogoAnimation extends StatelessWidget {
  const LogoAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    return Logo1();
  }
}

class Logo1 extends StatefulWidget {
  const Logo1({super.key});

  @override
  State<Logo1> createState() => _Logo1State();
}

class _Logo1State extends State<Logo1> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);
  late final Animation<Offset> _animation = Tween(
    begin: Offset.zero,
    end: Offset(0, 0.08),
  ).animate(_controller);

  // @override
  // void initState() {
  //   super.initState();
  //   _controller = AnimationController(vsync: this);
  // }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _animation,
      child: Image.asset(
        'assets/images/crypto_logo.png',
        width: 300,
        height: 200,
        fit: BoxFit.contain,
      ),
    );
  }
}
