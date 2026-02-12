import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:animations/animations.dart';
import 'package:desktop_encryption_client/pages/subpages/tabpages/file_tab.dart';
import 'package:desktop_encryption_client/pages/subpages/tabpages/utility_tab.dart';

// ============================================================
// PAGE WRAPPER
// Forwards data into main stateful controller
// ============================================================
class EncryptPage extends StatelessWidget {
  final String username;
  final String email;
  final String lastLogin;
  final List<String> keyType;
  final Map<String, dynamic> keyMap;
  final ValueListenable<int> subTabListenable;

  const EncryptPage({
    super.key,
    required this.username,
    required this.email,
    required this.lastLogin,
    required this.keyType,
    required this.keyMap,
    required this.subTabListenable,
  });

  @override
  Widget build(BuildContext context) {
    return Test1(
      username: username,
      email: email,
      lastLogin: lastLogin,
      keyType: keyType,
      keyMap: keyMap,
      subTabListenable: subTabListenable,
    );
  }
}

// ============================================================
// MAIN ENCRYPT CONTROLLER
// ============================================================
class Test1 extends StatefulWidget {
  final String username;
  final String email;
  final String lastLogin;
  final List<String> keyType;
  final Map<String, dynamic> keyMap;
  final ValueListenable<int> subTabListenable;

  const Test1({
    super.key,
    required this.username,
    required this.email,
    required this.lastLogin,
    required this.keyType,
    required this.keyMap,
    required this.subTabListenable,
  });

  @override
  State<Test1> createState() => _Test1State();
}

// ============================================================
// CONTROLLER STATE
// ============================================================
class _Test1State extends State<Test1> {
  String encryptionType = "AES256";
  String keyTypeName = "PERSONAL";

  final GlobalKey<FileTabState> _fileTabKey = GlobalKey<FileTabState>();

  // ============================================================
  // MODE RESOLUTION
  // Workspace vs Utility
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final int subTab = widget.subTabListenable.value;
    final bool isWorkspace = subTab == 0;

    final String title = isWorkspace
        ? "Work In Your Workspace"
        : "Encrypt & Decrypt with Crypto";

    final String subtitle = isWorkspace
        ? "All your encrypted files are stored here"
        : "Choose encryption type and preferred key";

    final String displayAlgo = isWorkspace ? "AES256" : encryptionType;
    final String displayKeyName = isWorkspace ? "PERSONAL" : keyTypeName;

    final String mappedKeyType =
        (widget.keyMap[displayKeyName] ?? displayKeyName).toString();

    // ============================================================
    // HEADER / TITLE / REFRESH
    // ============================================================

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),

                IconButton(
                  tooltip: "Refresh",
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: () {
                    if (widget.subTabListenable.value == 0) {
                      _fileTabKey.currentState?.refreshExplorer();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: Colors.white70)),

            const SizedBox(height: 10),

            // ============================================================
            // ALGORITHM & KEY SELECTION
            // ============================================================
            Stack(
              children: [
                Dropdowns(
                  disablePickers: isWorkspace,
                  algoValue: displayAlgo,
                  keyValue: displayKeyName,
                  onChanged: (algo, key) {
                    if (isWorkspace) return;
                    setState(() {
                      encryptionType = algo;
                      keyTypeName = key;
                    });
                  },
                ),

                if (isWorkspace)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 420,
                    child: AbsorbPointer(
                      absorbing: true,
                      child: Opacity(
                        opacity: 0.65,
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
              ],
            ),

            //const SizedBox(height: 16),

            /*Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white30),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "🔒 $encryptionType",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    "🗝 $keyTypeName",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),*/
            const SizedBox(height: 20),

            // ============================================================
            // TAB SWITCHING
            // Workspace -> FileTab
            // Utility   -> UtilityTab
            // ============================================================
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: widget.subTabListenable,
                builder: (context, subTab, _) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: PageTransitionSwitcher(
                      duration: const Duration(milliseconds: 320),
                      transitionBuilder:
                          (child, animation, secondaryAnimation) {
                            return SharedAxisTransition(
                              animation: animation,
                              secondaryAnimation: secondaryAnimation,
                              transitionType:
                                  SharedAxisTransitionType.horizontal,
                              fillColor: Colors.transparent,
                              child: child,
                            );
                          },
                      child: KeyedSubtree(
                        key: ValueKey(subTab),
                        child: subTab == 0
                            ? FileTab(
                                key: _fileTabKey,
                                encryptionType: displayAlgo,
                                keyType: mappedKeyType,
                              )
                            : UtilityTab(
                                encryptionType: displayAlgo,
                                keyType: mappedKeyType,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DROPDOWN CONTROLLER
// ============================================================
class Dropdowns extends StatefulWidget {
  final Function(String, String) onChanged;
  final bool disablePickers;

  final String algoValue;
  final String keyValue;

  const Dropdowns({
    super.key,
    required this.onChanged,
    this.disablePickers = false,
    required this.algoValue,
    required this.keyValue,
  });

  @override
  State<Dropdowns> createState() => _DropdownsState();
}

// ============================================================
// DROPDOWN STATE & DATA LOADING
// ============================================================
class _DropdownsState extends State<Dropdowns> {
  bool _loading = false;

  List<String> algorithms = ['AES256', 'Threefish', 'Chacha20'];
  Map<String, String> keyMap = {};
  List<String> keyType = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // ============================================================
  // LOAD AVAILABLE KEYS
  // ============================================================

  Future<void> _initData() async {
    await Future.delayed(const Duration(milliseconds: 300));

    keyMap = {
      "PERSONAL": "demo_personal_key",
      "TEAM A": "demo_team_a_key",
      "TEAM B": "demo_team_b_key",
    };

    keyType = keyMap.keys.toList();

    if (!mounted) return;

    setState(() {});
  }

  // ============================================================
  // KEY GENERATION FLOW
  // Dongle + API logging
  // ============================================================

  Future<void> generateKey() async {
    setState(() => _loading = true);

    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Key generated successfully (demo)."),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ============================================================
  // DROPDOWN UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Opacity(
              opacity: widget.disablePickers ? 0.65 : 1.0,
              child: AbsorbPointer(
                absorbing: widget.disablePickers,
                child: CustomDropdown<String>(
                  icon: Icons.key,
                  color: Colors.amber,
                  value: widget.algoValue,
                  items: algorithms
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) {
                    widget.onChanged(v!, widget.keyValue);
                  },
                ),
              ),
            ),

            const SizedBox(width: 16),

            Opacity(
              opacity: widget.disablePickers ? 0.65 : 1.0,
              child: AbsorbPointer(
                absorbing: widget.disablePickers,
                child: CustomDropdown<String>(
                  icon: Icons.people,
                  color: Colors.pinkAccent,
                  value: widget.keyValue,
                  items: keyMap.keys
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: keyMap.isEmpty
                      ? (_) {}
                      : (v) {
                          widget.onChanged(widget.algoValue, v!);
                        },
                ),
              ),
            ),

            const Spacer(),
            ElevatedButton.icon(
              onPressed: _loading ? null : generateKey,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent.withOpacity(0.2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.vpn_key),
              label: Text(
                _loading ? "Generating..." : "Generate Key",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),
      ],
    );
  }
}

// ============================================================
// REUSABLE DROPDOWN WIDGET
// ============================================================
class CustomDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final Color? color;
  final IconData icon;

  const CustomDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 5,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            icon: Icon(icon, color: Colors.black),
            value: value,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
