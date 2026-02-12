import 'dart:ui';
import 'dart:math';
import 'package:desktop_encryption_client/pages/subpages/encrypt_page.dart';
import 'package:desktop_encryption_client/utils/app_styles.dart';
import 'package:flutter/material.dart';
import 'package:animations/animations.dart';
import 'package:desktop_encryption_client/pages/subpages/about_page.dart';
import 'package:desktop_encryption_client/pages/splash/splash_screen.dart';

// ============================================================
// BRAND FOOTER SIGNAL EFFECT
// ============================================================
class SignalGlitchText extends StatefulWidget {
  final String text;

  const SignalGlitchText(this.text, {super.key});

  @override
  State<SignalGlitchText> createState() => _SignalGlitchTextState();
}

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
// HOME PAGE ENTRY
// ============================================================
class HomePage extends StatefulWidget {
  final String username;
  final String password;
  final String email;
  final String lastLogin;
  final List<String> keyType;
  final Map<String, dynamic> keyMap;

  const HomePage({
    super.key,
    required this.username,
    required this.password,
    required this.email,
    required this.lastLogin,
    required this.keyType,
    required this.keyMap,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

// ============================================================
// HOME STATE
// ============================================================
class _HomePageState extends State<HomePage> {
  var selectedIndex = 0;

  final ValueNotifier<int> encryptSubTab = ValueNotifier<int>(0);

  String? userName;
  String? userEmail;
  String? lastLoginStr;
  List<String> userKeyType = [];
  Map<String, dynamic> userKeyMap = {};

  // ============================================================
  // INIT SESSION SERVICES
  // ============================================================

  @override
  void initState() {
    super.initState();
    lastLoginStr = widget.lastLogin;
  }

  // ============================================================
  // CLEANUP SESSION SERVICES
  // ============================================================

  @override
  void dispose() {
    encryptSubTab.dispose();
    super.dispose();
  }

  // ============================================================
  // LOGOUT FLOW
  //
  // API logout → clear storage → log activity →
  // return to splash
  // ============================================================

  Future<void> logout(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text(
          "Logout",
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          "Are you sure you want to logout?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => SplashScreen()),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color.fromARGB(255, 255, 82, 82),
            ),
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NAVIGATION HANDLER
  // ============================================================

  void _onDestinationSelected(int index) {
    if (index == 2) {
      logout(context);
    } else {
      setState(() {
        selectedIndex = index;
      });
    }
  }

  // ============================================================
  // SHARED GLASS CONTAINER STYLE
  // ============================================================

  Widget _glassCard({
    required Widget child,
    double radius = 14,
    EdgeInsetsGeometry? padding,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  // ============================================================
  // MAIN LAYOUT
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      EncryptPage(
        username: widget.username,
        email: widget.email,
        lastLogin: widget.lastLogin,
        keyType: widget.keyType,
        keyMap: widget.keyMap,
        subTabListenable: encryptSubTab,
      ),
      AboutPage(),
    ];

    return Scaffold(
      backgroundColor: AppTheme.mainColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color.fromARGB(255, 20, 20, 20).withOpacity(0.55),
                    const Color.fromARGB(255, 20, 20, 20).withOpacity(0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;

              final header = Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ValueListenableBuilder<int>(
                      valueListenable: encryptSubTab,
                      builder: (context, subTab, _) {
                        String title;

                        if (selectedIndex == 0) {
                          title = subTab == 0 ? 'WORKSPACE TAB' : 'UTILITY TAB';
                        } else if (selectedIndex == 1) {
                          title = 'ABOUT US';
                        } else {
                          title = 'DEMO APP';
                        }

                        return Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),

                    const Spacer(),
                    _glassCard(
                      radius: 12,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.username,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.email,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              if (lastLoginStr != null &&
                                  lastLoginStr!.isNotEmpty)
                                Text(
                                  "Last login at ${lastLoginStr}",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          const CircleAvatar(
                            backgroundColor: Colors.purple,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );

              if (isMobile) {
                return Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Column(
                    children: [
                      header,
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: _glassCard(
                            radius: 14,
                            padding: const EdgeInsets.all(12),
                            child: PageTransitionSwitcher(
                              duration: const Duration(milliseconds: 360),
                              transitionBuilder:
                                  (child, animation, secondaryAnimation) {
                                    return FadeThroughTransition(
                                      animation: animation,
                                      secondaryAnimation: secondaryAnimation,
                                      fillColor: Colors.transparent,
                                      child: child,
                                    );
                                  },

                              child: KeyedSubtree(
                                key: ValueKey(selectedIndex),
                                child: pages[selectedIndex],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                return Row(
                  children: [
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _glassCard(
                          radius: 18,
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 14,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 220,
                              maxWidth: 260,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(8),
                                      child: Image.asset(
                                        'assets/images/crypto_logo.png',
                                        width: 22,
                                        height: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'DEMO APP',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                _railItem(
                                  icon: Icons.folder,
                                  label: 'Workspace',
                                  selected:
                                      selectedIndex == 0 &&
                                      encryptSubTab.value == 0,
                                  onTap: () {
                                    encryptSubTab.value = 0;
                                    _onDestinationSelected(0);
                                  },
                                ),
                                const SizedBox(height: 8),
                                _railItem(
                                  icon: Icons.key,
                                  label: 'Utility',
                                  selected:
                                      selectedIndex == 0 &&
                                      encryptSubTab.value == 1,
                                  onTap: () {
                                    encryptSubTab.value = 1;
                                    _onDestinationSelected(0);
                                  },
                                ),
                                const SizedBox(height: 8),
                                _railItem(
                                  icon: Icons.info,
                                  label: 'About',
                                  selected: selectedIndex == 1,
                                  onTap: () => _onDestinationSelected(1),
                                ),
                                const Spacer(),
                                const Divider(color: Colors.white12),
                                const SizedBox(height: 12),
                                _railItem(
                                  icon: Icons.logout_outlined,
                                  label: 'Logout',
                                  selected: false,
                                  onTap: () => _onDestinationSelected(2),
                                  accent: Colors.redAccent,
                                ),
                                const SizedBox(height: 20),
                                const Center(
                                  child: SignalGlitchText(
                                    'ENCRYPTION CLIENT V1.2',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 20,
                        ),
                        child: Column(
                          children: [
                            header,
                            const SizedBox(height: 12),
                            Expanded(
                              child: _glassCard(
                                radius: 18,
                                padding: const EdgeInsets.all(18),
                                child: PageTransitionSwitcher(
                                  duration: const Duration(milliseconds: 360),
                                  transitionBuilder:
                                      (child, animation, secondaryAnimation) {
                                        return FadeThroughTransition(
                                          animation: animation,
                                          secondaryAnimation:
                                              secondaryAnimation,
                                          fillColor: Colors.transparent,
                                          child: child,
                                        );
                                      },

                                  child: KeyedSubtree(
                                    key: ValueKey(selectedIndex),
                                    child: pages[selectedIndex],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NAVIGATION RAIL ITEM
  // ============================================================

  Widget _railItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? accent,
  }) {
    final color = accent ?? Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected
                    ? color.withOpacity(0.14)
                    : Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: selected ? color : Colors.white70),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.white70,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
