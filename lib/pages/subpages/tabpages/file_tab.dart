import 'dart:io';
import 'dart:ui';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:desktop_encryption_client/pages/subpages/tabpages/workspace_tab.dart';

enum CryptoResultStatus { success, dongleMissing, failed }

class CryptoResult {
  final CryptoResultStatus status;
  final String message;

  CryptoResult(this.status, this.message);
}

class FileTab extends StatefulWidget {
  final String encryptionType;
  final String keyType;
  const FileTab({
    super.key,
    required this.encryptionType,
    required this.keyType,
  });

  @override
  FileTabState createState() => FileTabState();
}

// ============================================================
// File Tab State
// ============================================================
class FileTabState extends State<FileTab> {
  final GlobalKey _explorerKey = GlobalKey();
  String? _currentDirectory;

  // ============================================================
  // INIT & PATH PREPARATION
  // ============================================================

  @override
  void initState() {
    super.initState();
    _initUserPaths();
  }

  // ============================================================
  // MODE / SAFE CONFIGURATION
  // ============================================================

  bool get _isWorkspaceMode {
    return widget.encryptionType == "AES256" &&
        widget.keyType.toUpperCase().contains("PERSONAL");
  }

  String get _safeEncryptionType {
    return _isWorkspaceMode ? "AES256" : widget.encryptionType;
  }

  String get _safeKeyType {
    return _isWorkspaceMode ? widget.keyType : widget.keyType;
  }

  // ============================================================
  // WORKSPACE BOUNDARY ENFORCEMENT
  // ============================================================

  bool _isInsideWorkspace(String path) {
    final abs = FileSystemEntity.isDirectorySync(path)
        ? Directory(path).absolute.path
        : File(path).absolute.path;

    final root = Directory(_workspaceRoot).absolute.path;

    return abs == root || abs.startsWith('$root${p.separator}');
  }

  // ============================================================
  // UI STATE
  // ============================================================

  bool _fileLoading = false;
  bool _dirLoading = false;
  OverlayEntry? _messageOverlay;

  @override
  void dispose() {
    _messageOverlay?.remove();
    _messageOverlay = null;
    super.dispose();
  }

  bool _isErrorMessage(String msg) {
    return msg.startsWith("ERROR:");
  }

  String text = "";

  String? _lastMessage;
  DateTime? _lastMessageTime;

  String get _homeDir {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:\\';
    }
    return Platform.environment['HOME'] ?? '/';
  }

  late String _workspaceRoot;
  late String _tempRoot;
  bool _pathsReady = false;

  // ============================================================
  // USER WORKSPACE PATHS
  // ============================================================

  Future<void> _initUserPaths() async {
    final rawKey = "demo_user";

    final safeKey = rawKey.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

    final base = p.join(_homeDir, 'crypto');

    _workspaceRoot = p.join(base, 'workspace', safeKey);
    _tempRoot = p.join(base, 'temp', safeKey);

    final workspaceDir = Directory(_workspaceRoot);
    if (!workspaceDir.existsSync()) {
      workspaceDir.createSync(recursive: true);
    }

    final tempDir = Directory(_tempRoot);
    if (!tempDir.existsSync()) {
      tempDir.createSync(recursive: true);
    }

    if (!mounted) return;
    setState(() {
      _pathsReady = true;
      _currentDirectory = _workspaceRoot;
    });
  }

  // ============================================================
  // EXPLORER BRIDGE
  // ============================================================

  void refreshExplorer() {
    final state = _explorerKey.currentState;
    if (state != null) {
      (state as dynamic).refresh();
    }
  }

  Future<String> _fakeOperation(String action) async {
    await Future.delayed(const Duration(seconds: 1));
    return "$action completed successfully (demo).";
  }

  // ============================================================
  // USER FEEDBACK / TOAST
  // ============================================================

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
                          ? Colors.redAccent.withOpacity(0.6)
                          : Colors.white.withOpacity(0.2),
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
                            isError ? 'Error' : 'Success',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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

  String _shortenMessage(String text, {int maxLength = 120}) {
    if (text.length <= maxLength) return text;
    return "${text.substring(0, maxLength)}...";
  }

  // ============================================================
  // FILE OPERATIONS
  // ============================================================

  Future<void> encryptFile() async {
    setState(() => _fileLoading = true);

    text = await _fakeOperation("Encryption");

    setState(() => _fileLoading = false);

    showMessage(text, isError: false);
    refreshExplorer();
  }

  Future<void> decryptFile() async {
    setState(() => _fileLoading = true);

    text = await _fakeOperation("Decryption");

    setState(() => _fileLoading = false);

    showMessage(text, isError: false);
    refreshExplorer();
  }

  // ============================================================
  // DIRECTORY OPERATIONS
  // ============================================================

  Future<void> encryptDirectory() async {
    setState(() => _dirLoading = true);

    text = await _fakeOperation("Directory encryption");

    setState(() => _dirLoading = false);

    showMessage(text, isError: false);
    refreshExplorer();
  }

  Future<void> decryptDirectory() async {
    setState(() => _dirLoading = true);

    text = await _fakeOperation("Directory decryption");

    setState(() => _dirLoading = false);

    showMessage(text, isError: false);
    refreshExplorer();
  }

  // ============================================================
  // WIDGET BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              if (_fileLoading || _dirLoading)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Processing...',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          minHeight: 5,
                          backgroundColor: const Color.fromARGB(
                            31,
                            255,
                            255,
                            255,
                          ),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.tealAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              Expanded(
                child: !_pathsReady
                    ? const Center(child: CircularProgressIndicator())
                    : ExplorerPanel(
                        key: _explorerKey,

                        initialDirectory: _workspaceRoot,

                        onEncryptFile: (path, {bool silent = false}) async {
                          await encryptFile();
                        },

                        onDecryptFile: (path, {bool silent = false}) async {
                          await decryptFile();
                        },

                        onEncryptFolder: (path, {bool silent = false}) async {
                          await encryptDirectory();
                        },

                        onDecryptFolder: (path, {bool silent = false}) async {
                          await decryptDirectory();
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// SHARED UI WIDGETS
// ============================================================

class CustomElevatedButton extends StatelessWidget {
  final String text;
  final Color? materialColor;
  final Color? splashColor;
  final VoidCallback action;
  const CustomElevatedButton({
    super.key,
    required this.text,
    required this.materialColor,
    required this.splashColor,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 5,
      color: materialColor,
      borderRadius: BorderRadius.all(Radius.circular(10.0)),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.all(Radius.circular(10.0)),
        splashColor: splashColor,
        child: Ink(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 30.0,
            ),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
