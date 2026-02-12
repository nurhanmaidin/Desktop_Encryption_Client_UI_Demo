import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

class UtilityTab extends StatefulWidget {
  final String encryptionType;
  final String keyType;

  const UtilityTab({
    super.key,
    required this.encryptionType,
    required this.keyType,
  });

  @override
  State<UtilityTab> createState() => _UtilityTabState();
}

// ============================================================
// Utility Tab State
// Handles standalone encryption/decryption operations
// outside workspace.
// ============================================================
class _UtilityTabState extends State<UtilityTab> {
  bool _fileLoading = false;
  bool _dirLoading = false;

  // ============================================================
  // ENGINE CONFIGURATION
  // Build executable name & path
  // ============================================================

  String _downloadsDir() {
    if (Platform.isWindows) {
      return p.join(Platform.environment['USERPROFILE'] ?? 'C:\\', 'Downloads');
    }
    if (Platform.isMacOS) {
      return p.join(Platform.environment['HOME'] ?? '/', 'Downloads');
    }
    return Directory.current.path;
  }

  // ============================================================
  // MESSAGE / TOAST OVERLAYS
  // ============================================================

  OverlayEntry? _messageOverlay;
  String text = "";

  String? _lastMessage;
  DateTime? _lastMessageTime;

  final ScrollController _consoleScroll = ScrollController();

  @override
  void dispose() {
    _messageOverlay?.remove();
    _messageOverlay = null;
    _consoleScroll.dispose();
    super.dispose();
  }

  // ============================================================
  // CONSOLE HELPERS
  // ============================================================

  final List<String> _consoleLines = [];

  void _consoleWrite(String line) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    if (!mounted) return;

    setState(() {
      _consoleLines.add("[$ts] $line");
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_consoleScroll.hasClients) return;
      _consoleScroll.animateTo(
        _consoleScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _consoleClear() {
    setState(() => _consoleLines.clear());
  }

  Future<String> _fakeOperation(String action) async {
    _consoleWrite("$action started");
    await Future.delayed(const Duration(seconds: 1));
    _consoleWrite("Processing...");
    await Future.delayed(const Duration(seconds: 1));
    _consoleWrite("$action completed successfully (demo)");
    return "$action completed successfully (demo)";
  }

  void showMessage(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 5),
  }) {
    if (!mounted) return;

    final now = DateTime.now();
    if (_lastMessage == message &&
        _lastMessageTime != null &&
        now.difference(_lastMessageTime!) < const Duration(seconds: 4)) {
      return;
    }

    _lastMessage = message;
    _lastMessageTime = now;

    _messageOverlay?.remove();
    _messageOverlay = null;

    final overlay = Overlay.of(context);
    final shortened = _shortenMessage(message);

    _messageOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _messageOverlay?.remove();
                _messageOverlay = null;
              },
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.38,
            left: MediaQuery.of(context).size.width * 0.28,
            width: MediaQuery.of(context).size.width * 0.44,
            child: Material(
              color: Colors.transparent,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black.withOpacity(0.55),
                    border: Border.all(
                      color: isError
                          ? Colors.redAccent.withOpacity(0.65)
                          : Colors.white.withOpacity(0.18),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isError
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            color: isError
                                ? Colors.redAccent
                                : Colors.greenAccent,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isError ? 'Failed' : 'Success',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        shortened,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_messageOverlay!);

    Future.delayed(duration, () {
      _messageOverlay?.remove();
      _messageOverlay = null;
    });
  }

  String _shortenMessage(String text, {int maxLength = 140}) {
    if (text.length <= maxLength) return text;
    return "${text.substring(0, maxLength)}...";
  }

  // ============================================================
  // FILE OPERATIONS
  // ============================================================

  Future<void> encryptFile() async {
    setState(() => _fileLoading = true);

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (result == null) {
      showMessage("ERROR: No file selected.", isError: true);
      setState(() => _fileLoading = false);
      return;
    }

    final msg = await _fakeOperation("File encryption");
    showMessage(msg);

    setState(() => _fileLoading = false);
  }

  Future<void> decryptFile() async {
    setState(() => _fileLoading = true);

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (result == null) {
      showMessage("ERROR: No file selected.", isError: true);
      setState(() => _fileLoading = false);
      return;
    }

    final msg = await _fakeOperation("File decryption");
    showMessage(msg);

    setState(() => _fileLoading = false);
  }

  // ============================================================
  // FOLDER OPERATIONS
  // ============================================================

  Future<void> encryptDirectory() async {
    setState(() => _dirLoading = true);

    final dir = await FilePicker.platform.getDirectoryPath();

    if (dir == null) {
      showMessage("ERROR: No folder selected.", isError: true);
      setState(() => _dirLoading = false);
      return;
    }

    final msg = await _fakeOperation("Folder encryption");
    showMessage(msg);

    setState(() => _dirLoading = false);
  }

  Future<void> decryptDirectory() async {
    setState(() => _dirLoading = true);

    final dir = await FilePicker.platform.getDirectoryPath();

    if (dir == null) {
      showMessage("ERROR: No folder selected.", isError: true);
      setState(() => _dirLoading = false);
      return;
    }

    final msg = await _fakeOperation("Folder decryption");
    showMessage(msg);

    setState(() => _dirLoading = false);
  }

  // ============================================================
  // UI COMPONENTS
  // Reusable surfaces & buttons
  // ============================================================

  Widget glassSurface({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    double opacity = 0.08,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color.fromARGB(195, 255, 255, 255).withOpacity(0.12),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget actionSection({
    required IconData icon,
    required String title,
    required Widget subtitle,
    required List<Widget> actions,
  }) {
    return glassSurface(
      opacity: 0.10,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          subtitle,
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 12, children: actions),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = true,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: primary
            ? const Color.fromARGB(221, 255, 255, 255)
            : const Color.fromARGB(221, 255, 255, 255).withOpacity(0.12),
        foregroundColor: primary ? Colors.black : Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  // ============================================================
  // CONSOLE VIEW ( TERMINAL )
  // ============================================================

  Widget _terminal() {
    return glassSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              const Text(
                "Console",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _consoleLines.isEmpty ? null : _consoleClear,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text("Clear"),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Scrollbar(
                controller: _consoleScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _consoleScroll,
                  child: SelectableText(
                    _consoleLines.isEmpty
                        ? "No activity yet.\nRun Encrypt / Decrypt to see logs here."
                        : _consoleLines.join("\n"),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontFamily: "monospace",
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WIDGET BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final busy = _fileLoading || _dirLoading;

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (busy)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: glassSurface(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'Processing...',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 8),
                              LinearProgressIndicator(
                                minHeight: 5,
                                backgroundColor: Color.fromARGB(
                                  31,
                                  255,
                                  255,
                                  255,
                                ),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    glassSurface(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Utility",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Quickly Encrypt and Decrypt files or folders from any location with ease.",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.70),
                            ),
                          ),
                          const SizedBox(height: 16),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: actionSection(
                                  icon: Icons.insert_drive_file,
                                  title: "Files",
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      /*RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.55,
                                            ),
                                            fontSize: 12.5,
                                          ),
                                          children: [
                                            const TextSpan(
                                              text: "Group Key : ",
                                            ),
                                            TextSpan(
                                              text: widget.keyType,
                                              style: const TextStyle(
                                                color: Color.fromARGB(
                                                  255,
                                                  229,
                                                  13,
                                                  107,
                                                ),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),*/
                                      const SizedBox(height: 4),

                                      RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.55,
                                            ),
                                            fontSize: 12.5,
                                          ),
                                          children: [
                                            const TextSpan(
                                              text: "Encryption Type : ",
                                            ),
                                            TextSpan(
                                              text: widget.encryptionType,
                                              style: const TextStyle(
                                                color: Colors.amberAccent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  actions: [
                                    _actionButton(
                                      label: "Encrypt Files",
                                      icon: Icons.lock,
                                      onPressed: busy ? null : encryptFile,
                                    ),
                                    _actionButton(
                                      label: "Decrypt Files",
                                      icon: Icons.lock_open,
                                      onPressed: busy ? null : decryptFile,
                                      primary: false,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: actionSection(
                                  icon: Icons.folder,
                                  title: "Folders",
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      /*RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.55,
                                            ),
                                            fontSize: 12.5,
                                          ),
                                          children: [
                                            const TextSpan(
                                              text: "Group Key : ",
                                            ),
                                            TextSpan(
                                              text: widget.keyType,
                                              style: const TextStyle(
                                                color: Color.fromARGB(
                                                  255,
                                                  229,
                                                  13,
                                                  107,
                                                ),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),*/
                                      const SizedBox(height: 4),

                                      RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.55,
                                            ),
                                            fontSize: 12.5,
                                          ),
                                          children: [
                                            const TextSpan(
                                              text: "Encryption Type : ",
                                            ),
                                            TextSpan(
                                              text: widget.encryptionType,
                                              style: const TextStyle(
                                                color: Colors.amberAccent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    _actionButton(
                                      label: "Encrypt Folder",
                                      icon: Icons.folder_off_outlined,
                                      onPressed: busy ? null : encryptDirectory,
                                    ),
                                    _actionButton(
                                      label: "Decrypt Folder",
                                      icon: Icons.folder_open,
                                      onPressed: busy ? null : decryptDirectory,
                                      primary: false,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverFillRemaining(
              hasScrollBody: false,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 170),
                child: _terminal(),
              ),
            ),
          ],
        );
      },
    );
  }
}
