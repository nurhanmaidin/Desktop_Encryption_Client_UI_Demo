import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

typedef DirectoryChangedCallback = void Function(String path);
typedef ExplorerFileCallback =
    Future<void> Function(String path, {bool silent});

class ExplorerHistoryEntry {
  final String path;
  final DateTime visitedAt;

  ExplorerHistoryEntry(this.path, this.visitedAt);
}

class ExplorerPanel extends StatefulWidget {
  final String initialDirectory;
  final ExplorerFileCallback onEncryptFile;
  final ExplorerFileCallback onDecryptFile;
  final ExplorerFileCallback onEncryptFolder;
  final ExplorerFileCallback onDecryptFolder;
  final DirectoryChangedCallback? onDirectoryChanged;

  const ExplorerPanel({
    super.key,
    required this.initialDirectory,
    this.onDirectoryChanged,
    required this.onEncryptFile,
    required this.onDecryptFile,
    required this.onEncryptFolder,
    required this.onDecryptFolder,
  });

  @override
  ExplorerPanelState createState() => ExplorerPanelState();
}

class RecentItem {
  final String path;
  final bool isDir;
  final DateTime visitedAt;

  final String action;

  RecentItem({
    required this.path,
    required this.isDir,
    required this.visitedAt,
    this.action = 'Open',
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'isDir': isDir,
    'visitedAt': visitedAt.toIso8601String(),
    'action': action,
  };

  static RecentItem? fromJson(Map<String, dynamic> m) {
    // path
    final rawPath = m['path'];
    final pth = (rawPath == null) ? '' : rawPath.toString().trim();
    if (pth.isEmpty) return null;

    final rawIsDir = m['isDir'];
    final bool isDir =
        rawIsDir == true ||
        rawIsDir == 1 ||
        (rawIsDir is String && rawIsDir.toLowerCase() == 'true');

    DateTime dt = DateTime.now();
    final rawVisited = m['visitedAt'];
    if (rawVisited is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(rawVisited);
    } else if (rawVisited != null) {
      dt = DateTime.tryParse(rawVisited.toString()) ?? DateTime.now();
    }

    final rawAction = m['action'];
    final act = (rawAction == null || rawAction.toString().trim().isEmpty)
        ? 'Open'
        : rawAction.toString();

    return RecentItem(path: pth, isDir: isDir, visitedAt: dt, action: act);
  }
}

class _CopyProgress {
  final int totalBytes;
  int copiedBytes = 0;
  String currentName = '';

  _CopyProgress({required this.totalBytes});
}

class _UserCancelled implements Exception {
  @override
  String toString() => 'User cancelled';
}

// ============================================================
// Explorer State
// Handles workspace browsing, encryption lifecycle,
// temp management, import/export and UI.
// ============================================================

class ExplorerPanelState extends State<ExplorerPanel> {
  late Directory currentDir;
  late final Directory _workspaceRootDir;
  late final String _workspaceRootPath;

  late final String _cryptoRootPath;
  late final String _tempRootPath;

  List<FileSystemEntity> entries = [];

  Timer? _fileWatcherTimer;

  String? _lastDeletedOriginalPath;
  String? _lastDeletedTrashPath;
  bool _lastDeletedWasDir = false;

  StateSetter? _progressDialogSetState;

  int _jobTotalBytes = 0;
  int _jobCopiedBytes = 0;

  double _progress = 0.0;
  String _progressTitle = '';
  String _progressDetail = '';
  DateTime _lastProgressUiPush = DateTime.fromMillisecondsSinceEpoch(0);

  bool _cancelRequested = false;
  final Stopwatch _copyWatch = Stopwatch();

  StreamSubscription<FileSystemEvent>? _dirWatchSub;
  Timer? _refreshDebounce;
  String _watchingDirPath = '';
  bool _isRenaming = false;

  void _stopAutoRefreshWatcher() {
    _refreshDebounce?.cancel();
    _refreshDebounce = null;

    _dirWatchSub?.cancel();
    _dirWatchSub = null;

    _watchingDirPath = '';
  }

  void _clearSelection() {
    if (selectedPaths.isEmpty && _lastSelectedIndex == null) return;
    setState(() {
      selectedPaths.clear();
      _lastSelectedIndex = null;
    });
  }

  void _startAutoRefreshWatcher(Directory dir) {
    if (!mounted) return;

    final absPath = Directory(dir.path).absolute.path;

    if (!_isInsideWorkspace(absPath)) return;

    if (_dirWatchSub != null && _watchingDirPath == absPath) return;

    _stopAutoRefreshWatcher();
    _watchingDirPath = absPath;

    try {
      _dirWatchSub = Directory(absPath).watch(recursive: false).listen((event) {
        if (_isRenaming) return;

        _refreshDebounce?.cancel();
        _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          if (_isRenaming) return;
          refresh();
        });
      });
    } catch (e) {
      _stopAutoRefreshWatcher();
    }
  }

  String _formatEtaSeconds(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds <= 0) return '--:--';
    final s = seconds.round();
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  final Set<String> selectedPaths = <String>{};
  int? _lastSelectedIndex;

  final TextEditingController pathController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<Directory> backHistory = [];
  final List<Directory> forwardHistory = [];
  final List<ExplorerHistoryEntry> visitHistory = [];

  static const String _kRecentKeyPrefix = 'explorer_recent_items_v2';

  static const int _kMaxRecentItems = 80;
  final List<RecentItem> recentItems = [];

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _hotAreaKeys = {};
  final Map<int, GlobalKey> _gridItemKeys = {};

  bool isListView = false;
  bool showHistoryPanel = false;

  bool _isEncryptedFilePath(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.aes256' ||
        ext == '.threefish' ||
        ext == '.chacha20' ||
        ext == '.enc';
  }

  bool _isEncryptedFolderName(String path) {
    final name = p.basename(path).toLowerCase();

    if (name.contains('_encrypted')) return true;

    return name.endsWith('.aes256') ||
        name.endsWith('.threefish') ||
        name.endsWith('.chacha20') ||
        name.endsWith('.enc');
  }

  bool _isEncryptedEntityPath(String path) {
    if (FileSystemEntity.isDirectorySync(path)) {
      return _isEncryptedFolderName(path);
    }
    return _isEncryptedFilePath(path);
  }

  Widget _encryptedLockBadge({double size = 14}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.70),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Icon(Icons.lock, size: size, color: Colors.amberAccent),
    );
  }

  Widget _iconWithEncryptedBadge({
    required FileSystemEntity ent,
    required double iconSize,
    required double opacity,
  }) {
    final isEnc = _isEncryptedEntityPath(ent.path);

    return Opacity(
      opacity: opacity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _fileIconSized(ent, iconSize),
          if (isEnc)
            Positioned(
              right: -2,
              bottom: -2,
              child: _encryptedLockBadge(size: iconSize <= 40 ? 12 : 14),
            ),
        ],
      ),
    );
  }

  String get _importBackupRoot =>
      p.join(_cryptoRootPath, 'import_backup', _userKey);

  Future<String> _makeBackupDestFilePath(String srcFilePath) async {
    final name = p.basename(srcFilePath);
    final candidate = p.join(_importBackupRoot, name);
    // prevent overwrite if user imports same name twice
    return _resolveNonConflictPath(candidate, isDir: false);
  }

  Future<String> _makeBackupDestDirPath(String srcDirPath) async {
    final name = p.basename(srcDirPath);
    final candidate = p.join(_importBackupRoot, name);
    // prevent overwrite if user imports same folder twice
    return _resolveNonConflictPath(candidate, isDir: true);
  }

  // where encrypted output should be stored (in current workspace folder)
  String _workspaceTargetDir() {
    // Put outputs where user is currently browsing
    final target = Directory(currentDir.path).absolute.path;

    // Safety: never write outside workspace
    if (_isInsideWorkspace(target)) return target;

    return _workspaceRootPath;
  }

  Future<void> _encryptFileFromBackupIntoWorkspace(
    String backupFilePath, {
    required String originalBaseName,
  }) async {
    await widget.onEncryptFile(backupFilePath);

    final backupDir = Directory(p.dirname(backupFilePath));
    final encrypted = await _findNewestEncryptedInDir(backupDir);

    if (encrypted == null) {
      throw Exception(
        'Encryption produced no encrypted output in temp backup folder.',
      );
    }

    // enforce clean output name: ORIGINAL + encryption extension
    final encExt = p.extension(encrypted.path).toLowerCase();
    final cleanOriginal = _stripTimestampPrefix(originalBaseName);
    final outName = '$cleanOriginal$encExt';

    final targetPath = await _resolveNonConflictPath(
      p.join(_workspaceTargetDir(), outName),
      isDir: false,
    );

    await File(encrypted.path).rename(targetPath);
    _recordRecentPath(targetPath, action: 'Import');
  }

  Future<void> _cleanupEncryptionOutputFoldersInBackup(
    String backupFolderPath,
  ) async {
    final suspects = <String>[
      p.join(backupFolderPath, 'encrypted'),
      p.join(backupFolderPath, 'out'),
      '${backupFolderPath}_encrypted',
      '${backupFolderPath}_out',
    ];

    for (final s in suspects) {
      try {
        final d = Directory(s);
        if (d.existsSync()) {
          await d.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<List<File>> _collectEncryptedFilesFromCandidates({
    required DateTime startedAt,
    required List<String> candidateRoots,
  }) async {
    final out = <File>[];

    for (final rootPath in candidateRoots) {
      final d = Directory(rootPath);
      if (!d.existsSync()) continue;

      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        if (!_isEncryptedFilePath(e.path)) continue;

        try {
          final st = await e.stat();
          if (st.modified.isAfter(
            startedAt.subtract(const Duration(seconds: 2)),
          )) {
            out.add(e);
          }
        } catch (_) {}
      }
    }

    return out;
  }

  Future<void> _encryptFolderFromBackupIntoWorkspace(
    String backupFolderPath, {
    required String workspaceFolderName,
  }) async {
    // run encryption
    await widget.onEncryptFolder(backupFolderPath);
    try {
      final parent = Directory(p.dirname(backupFolderPath));

      final items = parent.listSync();
      for (final e in items) {
        if (e is! Directory) continue;

        final name = p.basename(e.path).toLowerCase();

        if (name.contains('_encrypted') ||
            name == 'out' ||
            name == 'encrypted') {
          await e.delete(recursive: true);
        }
      }
    } catch (_) {}

    await _cleanupEncryptionOutputFoldersInBackup(backupFolderPath);
  }

  Future<File?> _findNewestEncryptedInDir(Directory dir) async {
    File? newest;
    DateTime newestTime = DateTime.fromMillisecondsSinceEpoch(0);

    final items = dir.listSync(followLinks: false);
    for (final e in items) {
      if (e is! File) continue;
      if (!_isEncryptedFilePath(e.path)) continue;

      final stat = await e.stat();
      final t = stat.modified;
      if (t.isAfter(newestTime)) {
        newestTime = t;
        newest = e;
      }
    }
    return newest;
  }

  // ---------- Export (decrypt-first) helpers ----------

  String get _exportTmpRoot => p.join(_tempRootPath, 'export_tmp');

  String _stripTimestampPrefix(String name) {
    return name.replaceFirst(RegExp(r'^\d{13}-'), '');
  }

  String _originalNameFromEncrypted(String encryptedPath) {
    final base = p.basenameWithoutExtension(encryptedPath);
    return _stripTimestampPrefix(base);
  }

  String _restoreOriginalFolderName(String folderPath) {
    String name = p.basename(folderPath);

    name = p.basenameWithoutExtension(name);

    name = name.replaceAll(RegExp(r'_encrypted$', caseSensitive: false), '');

    return name;
  }

  Future<String> _decryptEncryptedFileToTemp(String encryptedPath) async {
    if (!_isEncryptedFilePath(encryptedPath)) {
      throw Exception('Not an encrypted file: $encryptedPath');
    }

    // 1) ensure export temp folder exists
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final exportSessionDir = Directory(p.join(_exportTmpRoot, stamp));
    await exportSessionDir.create(recursive: true);

    // 2) decrypt using your existing logic (same one used in _openEntity)
    await widget.onDecryptFile(encryptedPath);

    final wsDir = Directory(p.dirname(encryptedPath));
    final workspacePlain = File(
      p.join(wsDir.path, _originalNameFromEncrypted(encryptedPath)),
    );

    if (workspacePlain.existsSync()) {
      try {
        final safeTemp = await _resolveNonConflictPath(
          p.join(_tempRootPath, _originalNameFromEncrypted(encryptedPath)),
          isDir: false,
        );

        await workspacePlain.rename(safeTemp);
      } catch (_) {
        try {
          workspacePlain.deleteSync();
        } catch (_) {}
      }
    }

    final decryptedName = _originalNameFromEncrypted(encryptedPath);
    final decryptedPathDefault = p.join(_tempRootPath, decryptedName);

    final possibleStamped = Directory(_tempRootPath)
        .listSync()
        .whereType<File>()
        .firstWhere(
          (f) =>
              p.basenameWithoutExtension(f.path).endsWith(decryptedName) ||
              p.basename(f.path) == decryptedName,
          orElse: () => File(''),
        );

    final actualDecrypted = File(decryptedPathDefault).existsSync()
        ? decryptedPathDefault
        : (possibleStamped.path.isNotEmpty &&
                  File(possibleStamped.path).existsSync()
              ? possibleStamped.path
              : '');

    if (actualDecrypted.isEmpty) {
      throw Exception(
        'Decrypted file not found in TEMP: $decryptedPathDefault',
      );
    }

    // 3) move decrypted file into export session folder (so we don’t clash with other exports)
    final movedPath = p.join(exportSessionDir.path, decryptedName);

    final safeMovedPath = await _resolveNonConflictPath(
      movedPath,
      isDir: false,
    );

    await File(actualDecrypted).rename(safeMovedPath);

    return safeMovedPath;
  }

  Future<List<File>> _collectEncryptedFilesUnderPath(String rootPath) async {
    final rootDir = Directory(rootPath);
    final out = <File>[];
    await for (final e in rootDir.list(recursive: true, followLinks: false)) {
      if (e is File && _isEncryptedFilePath(e.path)) out.add(e);
    }
    return out;
  }

  Future<String> _decryptEncryptedFileToSession(
    String encryptedPath, {
    required String exportSessionDir,
    required String relDir,
  }) async {
    await widget.onDecryptFile(encryptedPath);

    final wsDir = Directory(p.dirname(encryptedPath));
    final workspacePlain = File(
      p.join(wsDir.path, _originalNameFromEncrypted(encryptedPath)),
    );

    if (workspacePlain.existsSync()) {
      try {
        final movedTemp = await _resolveNonConflictPath(
          p.join(_tempRootPath, _originalNameFromEncrypted(encryptedPath)),
          isDir: false,
        );
        await workspacePlain.rename(movedTemp);
      } catch (_) {
        try {
          workspacePlain.deleteSync();
        } catch (_) {}
      }
    }

    final decryptedName = _originalNameFromEncrypted(encryptedPath);
    final decryptedPathDefault = p.join(_tempRootPath, decryptedName);

    String actual = '';
    if (File(decryptedPathDefault).existsSync()) {
      actual = decryptedPathDefault;
    } else {
      final candidates = Directory(_tempRootPath)
          .listSync()
          .whereType<File>()
          .where((f) {
            final bn = p.basename(f.path);
            return bn == decryptedName ||
                p.basenameWithoutExtension(f.path).endsWith(decryptedName);
          })
          .toList();

      if (candidates.isNotEmpty) actual = candidates.last.path;
    }

    if (actual.isEmpty || !File(actual).existsSync()) {
      throw Exception(
        'Decrypted output not found for: ${p.basename(encryptedPath)}',
      );
    }

    final targetDir = Directory(p.join(exportSessionDir, relDir));
    await targetDir.create(recursive: true);

    final movedPath = p.join(targetDir.path, decryptedName);
    final safeMovedPath = await _resolveNonConflictPath(
      movedPath,
      isDir: false,
    );

    await File(actual).rename(safeMovedPath);
    return safeMovedPath;
  }

  Future<void> _cleanupExportTmp() async {
    try {
      final d = Directory(_exportTmpRoot);
      if (d.existsSync()) {
        d.deleteSync(recursive: true);
      }
    } catch (_) {}
  }

  String get _homeDir {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:\\';
    }
    return Platform.environment['HOME'] ?? '/';
  }

  void _updateProgressUI({
    required _CopyProgress prog,
    required String detail,
  }) {
    if (!mounted) return;

    _jobTotalBytes = prog.totalBytes;
    _jobCopiedBytes = prog.copiedBytes;

    _progress = (_jobTotalBytes <= 0)
        ? 0.0
        : (_jobCopiedBytes / _jobTotalBytes).clamp(0.0, 1.0);

    _progressDetail = detail;

    _progressDialogSetState?.call(() {});
    setState(() {});
  }

  Future<T?> _runWithProgress<T>({
    required String title,
    required Future<T> Function(
      void Function(String detail, int deltaBytes) report,
    )
    task,
  }) async {
    setState(() {
      _cancelRequested = false;

      _copyWatch
        ..reset()
        ..start();

      _progress = 0.0;
      _progressTitle = title;
      _progressDetail = 'Preparing…';

      _jobTotalBytes = 0;
      _jobCopiedBytes = 0;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            _progressDialogSetState = setLocal;

            final pct = (_progress * 100).clamp(0.0, 100.0).toStringAsFixed(1);

            final elapsed = _copyWatch.elapsedMilliseconds / 1000.0;
            final speed = elapsed <= 0 ? 0.0 : (_jobCopiedBytes / elapsed);
            final remaining = (_jobTotalBytes - _jobCopiedBytes).clamp(
              0,
              _jobTotalBytes,
            );
            final etaSec = speed <= 0 ? double.nan : (remaining / speed);

            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: Text(
                _progressTitle,
                style: const TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: (_jobTotalBytes <= 0) ? null : _progress,
                      backgroundColor: Colors.white12,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Progress: $pct%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _progressDetail.isEmpty ? 'Working…' : _progressDetail,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _cancelRequested
                      ? null
                      : () {
                          _cancelRequested = true;
                          _progressDetail = 'Canceling…';
                          setLocal(() {});
                        },
                  child: Text(
                    _cancelRequested ? 'CANCELING…' : 'CANCEL',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    try {
      final result = await task((detail, deltaBytes) {
        if (deltaBytes > 0) _jobCopiedBytes += deltaBytes;

        final now = DateTime.now();
        if (now.difference(_lastProgressUiPush).inMilliseconds < 70) return;
        _lastProgressUiPush = now;

        if (!mounted) return;

        _progressDetail = detail;
        _progressDialogSetState?.call(() {});
      });

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      return result;
    } on _UserCancelled {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return null;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cancelled'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (mounted) {
        /*ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Operation failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );*/
      }
      return null;
    } finally {
      _copyWatch.stop();
      _progressDialogSetState = null;

      if (mounted) {
        setState(() {
          _progress = 0.0;
          _progressTitle = '';
          _progressDetail = '';
          _jobTotalBytes = 0;
          _jobCopiedBytes = 0;
        });
      }
    }
  }

  // ============================================================
  // INIT & LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();

    final initialAbs = Directory(widget.initialDirectory).absolute.path;
    final parts = p.split(initialAbs);

    final wsIdx = parts.lastIndexOf('workspace');

    if (wsIdx != -1 && wsIdx + 1 < parts.length) {
      final cryptoRoot = p.joinAll(parts.sublist(0, wsIdx));
      final userKey = parts[wsIdx + 1];

      _cryptoRootPath = cryptoRoot;
      _workspaceRootPath = p.join(_cryptoRootPath, 'workspace', userKey);
      _workspaceRootDir = Directory(_workspaceRootPath);

      final passedDir = Directory(initialAbs);
      currentDir = _isSameOrChildPath(_workspaceRootPath, passedDir.path)
          ? passedDir
          : _workspaceRootDir;

      _tempRootPath = p.join(_cryptoRootPath, 'temp', userKey);
    } else {
      _workspaceRootDir = Directory(initialAbs);
      _workspaceRootPath = _workspaceRootDir.path;

      final basePath = Directory(_workspaceRootPath).parent.parent.path;
      _cryptoRootPath = basePath;

      final userKey = p.basename(_workspaceRootPath);
      _tempRootPath = p.join(_cryptoRootPath, 'temp', userKey);

      currentDir = _workspaceRootDir;
    }

    final tempDir = Directory(_tempRootPath).absolute;
    if (!tempDir.existsSync()) {
      tempDir.createSync(recursive: true);
    }

    if (!_workspaceRootDir.existsSync()) {
      _workspaceRootDir.createSync(recursive: true);
    }

    currentDir = _workspaceRootDir;

    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q == _searchQuery) return;

      setState(() {
        _searchQuery = q;

        if (_searchQuery.isNotEmpty) {
          final view = _filteredEntries();
          if (view.isNotEmpty) {
            selectedPaths
              ..clear()
              ..add(view.first.path);
            _lastSelectedIndex = 0;
          }
        } else {
          selectedPaths.clear();
          _lastSelectedIndex = null;
        }
      });
    });

    _loadRecent();

    _initLockDb().then((_) {
      if (!mounted) return;
      _loadDirectory(currentDir, addToHistory: false);
      _startAutoRefreshWatcher(currentDir);
    });

    _startFileWatcher();
    _startWorkspaceAutoProtector();
  }

  Timer? _autoProtectTimer;

  // ============================================================
  // FILE SYSTEM WATCHERS
  // Auto refresh + background security enforcement
  // ============================================================

  void _startWorkspaceAutoProtector() {
    _autoProtectTimer?.cancel();

    _autoProtectTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      await _workspaceSecurityScan();
    });
  }

  // ============================================================
  // WORKSPACE SECURITY
  // Automatically encrypts plaintext files
  // ============================================================

  Future<void> _workspaceSecurityScan() async {
    final dir = Directory(_workspaceRootPath);

    final files = await dir
        .list(recursive: true, followLinks: false)
        .where((e) => e is File)
        .cast<File>()
        .toList();

    for (final file in files) {
      final path = file.path;

      if (_isEncryptedFilePath(path)) continue;

      if (path.startsWith(_tempRootPath)) continue;

      final plain = file.path;
      final siblingAes = File('$plain.aes256');
      final siblingThree = File('$plain.threefish');
      final siblingCha = File('$plain.chacha20');
      if (siblingAes.existsSync() ||
          siblingThree.existsSync() ||
          siblingCha.existsSync()) {
        continue;
      }

      await _processWorkspaceFile(file);
    }
  }

  Future<void> _processWorkspaceFile(File workspaceFile) async {
    final stat = await workspaceFile.stat();
    String tempName;
    if (_isEncryptedFilePath(workspaceFile.path)) {
      tempName = _originalNameFromEncrypted(workspaceFile.path);
    } else {
      tempName = p.basename(workspaceFile.path);
    }

    final tempVersion = File(p.join(_tempRootPath, tempName));
    if (tempVersion.existsSync()) {
      if (_isLockedPath(tempVersion.path) || _isInCooldown(tempVersion.path))
        return;
    }

    final lastModified = stat.modified;

    final lastSeen = _lastProcessedTime[workspaceFile.path];
    if (lastSeen != null && !lastModified.isAfter(lastSeen)) {
      return;
    }

    _lastProcessedTime[workspaceFile.path] = lastModified;

    if (stat.size > 1024 * 1024 * 1024) {
      // 1GB
      return;
    }

    final fileName = p.basename(workspaceFile.path);

    final tempFile = File(p.join(_tempRootPath, fileName));
    final backupFile = File(p.join(_importBackupRoot, fileName));

    // If temp version exists → use temp
    // else use import backup
    final referenceFile = tempFile.existsSync() ? tempFile : backupFile;

    // EXCEPTION LIST = files that exist in import backup
    final underException = backupFile.existsSync();

    if (underException) {
      // Compare checksum
      final same = await _isChecksumSame(workspaceFile, referenceFile);

      if (same) return;

      await _encryptAndReplace(workspaceFile);
      return;
    }

    await _encryptAndReplace(workspaceFile);
  }

  Future<bool> _isChecksumSame(File f1, File f2) async {
    if (!f1.existsSync() || !f2.existsSync()) return false;

    final b1 = await f1.readAsBytes();
    final b2 = await f2.readAsBytes();

    return const ListEquality().equals(b1, b2);
  }

  // ============================================================
  // ENCRYPT & REPLACE
  // ============================================================

  Future<void> _encryptAndReplace(File workspaceFile) async {
    try {
      final originalPath = workspaceFile.path;

      if (_isEncryptedFilePath(originalPath)) return;

      final dir = Directory(p.dirname(originalPath));

      await widget.onEncryptFile(originalPath, silent: true);

      final encrypted = await _findNewestEncryptedInDir(dir);
      if (encrypted == null) return;

      final encExt = p.extension(encrypted.path);
      final encryptedPath = originalPath + encExt;

      final targetFile = File(encryptedPath);
      if (targetFile.existsSync()) {
        await targetFile.delete();
      }

      await encrypted.rename(encryptedPath);

      if (workspaceFile.existsSync()) {
        await workspaceFile.delete();
      }

      _recordRecentPath(encryptedPath, action: 'Auto Re-Encrypt');
    } catch (_) {}
  }

  void _startFileWatcher() {
    _fileWatcherTimer?.cancel();
    _fileWatcherTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        await _runAutoReEncryptCheck();
      } catch (_) {}
    });
  }

  Future<void> _runAutoReEncryptCheck() async {
    final workspaceDir = Directory(_workspaceRootPath);
    if (!workspaceDir.existsSync()) return;

    await for (final e in workspaceDir.list(recursive: true)) {
      if (e is! File) continue;
      if (!_isEncryptedFilePath(e.path)) continue;

      final originalName = _originalNameFromEncrypted(e.path);
      final tempPath = p.join(_tempRootPath, originalName);
      if (_isInCooldown(tempPath)) continue;

      final backupPath = p.join(_importBackupRoot, originalName);

      final tempFile = File(tempPath);
      final backupFile = File(backupPath);

      if (!tempFile.existsSync() || !backupFile.existsSync()) continue;

      final isLocked = _isLockedPath(tempPath);
      if (isLocked) continue;

      final tempHash = await _sha256OfFile(tempFile);
      final backupHash = await _sha256OfFile(backupFile);

      if (tempHash == backupHash) continue;

      // file changed → re-encrypt
      await widget.onEncryptFile(tempPath, silent: true);

      final newestEncrypted = await _findNewestEncryptedInDir(
        Directory(p.dirname(tempPath)),
      );
      if (newestEncrypted == null) continue;

      await newestEncrypted.rename(e.path);

      // update backup checksum baseline
      await tempFile.copy(backupPath);
    }
  }

  Future<String> _sha256OfFile(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  // ============================================================
  // LOCK DATABASE (stored in TEMP)
  // Prevents re-encryption while file is open
  // ============================================================

  late final String _lockDbPath;
  final Set<String> _locked = <String>{};
  final Map<String, DateTime> _lastProcessedTime = {};

  final Map<String, DateTime> _cooldownUntil = {};

  bool _isInCooldown(String tempPath) {
    final until = _cooldownUntil[_normPath(tempPath)];
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  void _setCooldown(
    String tempPath, {
    Duration d = const Duration(seconds: 90),
  }) {
    _cooldownUntil[_normPath(tempPath)] = DateTime.now().add(d);
  }

  String _normPath(String path) => File(path).absolute.path.toLowerCase();

  Future<void> _initLockDb() async {
    await Directory(_tempRootPath).create(recursive: true);
    _lockDbPath = p.join(_tempRootPath, 'locks.json');
    await _loadLocksFromDisk();
  }

  Future<void> _loadLocksFromDisk() async {
    try {
      final f = File(_lockDbPath);
      if (!f.existsSync()) return;

      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      _locked
        ..clear()
        ..addAll(decoded.whereType<String>());
    } catch (_) {}
  }

  Future<void> _saveLocksToDisk() async {
    try {
      final f = File(_lockDbPath);
      await f.writeAsString(jsonEncode(_locked.toList()), flush: true);
    } catch (_) {}
  }

  bool _isLockedPath(String path) => _locked.contains(_normPath(path));

  Future<void> _setLocked(String path, bool locked) async {
    final key = _normPath(path);

    if (locked) {
      _locked.add(key);
    } else {
      _locked.remove(key);
    }

    await _saveLocksToDisk();
    if (mounted) setState(() {});
  }

  // ---------- Workspace-only security ----------

  bool _isInsideWorkspace(String path) {
    final abs = Directory(path).absolute.path;

    if (abs == _workspaceRootPath) return true;
    if (abs.startsWith('$_workspaceRootPath${p.separator}')) return true;

    if (abs == _tempRootPath) return true;
    if (abs.startsWith('$_tempRootPath${p.separator}')) return true;

    return false;
  }

  void refresh() {
    _loadDirectory(currentDir, addToHistory: false);
  }

  // ---------- Filtered view ----------

  List<FileSystemEntity> _filteredEntries() {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return entries;

    final List<FileSystemEntity> filtered = [];
    for (final e in entries) {
      final name = p.basename(e.path).toLowerCase();
      if (name.contains(q)) filtered.add(e);
    }
    return filtered;
  }

  // ============================================================
  // NAVIGATION / DIRECTORY LOADING
  // ============================================================

  void _loadDirectory(Directory dir, {bool addToHistory = true}) {
    if (!_isInsideWorkspace(dir.path)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Access blocked: Workspace only."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (addToHistory && dir.path != currentDir.path) {
      backHistory.add(currentDir);
      forwardHistory.clear();
    }

    try {
      final list =
          dir.listSync().where((e) {
            final name = p.basename(e.path);
            if (!FileSystemEntity.isDirectorySync(e.path)) {
              return _isEncryptedFilePath(e.path);
            }
            return true;
          }).toList()..sort((a, b) {
            final ad = FileSystemEntity.isDirectorySync(a.path);
            final bd = FileSystemEntity.isDirectorySync(b.path);
            if (ad && !bd) return -1;
            if (!ad && bd) return 1;
            return a.path.toLowerCase().compareTo(b.path.toLowerCase());
          });

      visitHistory.removeWhere((e) => e.path == dir.path);
      visitHistory.insert(0, ExplorerHistoryEntry(dir.path, DateTime.now()));

      setState(() {
        currentDir = dir;
        entries = list;

        selectedPaths.clear();
        _lastSelectedIndex = null;

        pathController.text = currentDir.path;
      });

      _startAutoRefreshWatcher(dir);

      widget.onDirectoryChanged?.call(currentDir.path);
    } catch (_) {
      setState(() {
        entries = [];
        currentDir = dir;
        selectedPaths.clear();
        _lastSelectedIndex = null;
        pathController.text = currentDir.path;
      });
    }
  }

  void _navigateTo(Directory dir) {
    _loadDirectory(dir, addToHistory: true);
  }

  void _goBack() {
    if (backHistory.isEmpty) return;

    final prevDir = backHistory.removeLast();
    if (!_isInsideWorkspace(prevDir.path)) return;

    forwardHistory.add(currentDir);
    _loadDirectory(prevDir, addToHistory: false);
  }

  // ---------- Selection helpers ----------

  bool _isCtrlOrCmdPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  bool _isShiftPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  // ============================================================
  // SELECTION LOGIC
  // Ctrl / Shift multi-select
  // ============================================================

  void _selectByIndex({
    required int idx,
    required List<FileSystemEntity> view,
  }) {
    if (idx < 0 || idx >= view.length) return;

    final path = view[idx].path;

    final ctrl = _isCtrlOrCmdPressed();
    final shift = _isShiftPressed();

    setState(() {
      if (shift && _lastSelectedIndex != null) {
        final start = _lastSelectedIndex!;
        final a = start < idx ? start : idx;
        final b = start < idx ? idx : start;

        if (!ctrl) selectedPaths.clear();

        for (int i = a; i <= b; i++) {
          selectedPaths.add(view[i].path);
        }
      } else if (ctrl) {
        if (selectedPaths.contains(path)) {
          selectedPaths.remove(path);
        } else {
          selectedPaths.add(path);
        }
        _lastSelectedIndex = idx;
      } else {
        selectedPaths
          ..clear()
          ..add(path);
        _lastSelectedIndex = idx;
      }
    });
  }

  String? get _primarySelectedPath {
    if (selectedPaths.isEmpty) return null;
    final view = _filteredEntries();
    if (_lastSelectedIndex != null &&
        _lastSelectedIndex! >= 0 &&
        _lastSelectedIndex! < view.length) {
      final pth = view[_lastSelectedIndex!].path;
      if (selectedPaths.contains(pth)) return pth;
    }
    return selectedPaths.first;
  }

  // ---------- Hit testing for context menu ----------

  bool _clickedOnGridItem(Offset globalPosition) {
    for (final key in _gridItemKeys.values) {
      final ctx = key.currentContext;
      if (ctx == null) continue;

      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;

      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      if (rect.contains(globalPosition)) return true;
    }
    return false;
  }

  bool _clickedOnHotArea(Offset globalPosition) {
    for (final key in _hotAreaKeys.values) {
      final ctx = key.currentContext;
      if (ctx == null) continue;

      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;

      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;

      if (rect.contains(globalPosition)) return true;
    }
    return false;
  }

  Future<void> _openExternalMedia(String path) async {
    if (!_isInsideWorkspace(path)) return;

    final isFile = !FileSystemEntity.isDirectorySync(path);

    if (isFile) {
      await _setLocked(path, true);
    }

    try {
      if (Platform.isWindows) {
        final escaped = path.replaceAll("'", "''");

        await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "Start-Process -FilePath '$escaped' -Wait",
        ]);

        if (isFile && File(path).existsSync()) {
          await widget.onEncryptFile(path, silent: true);

          final dir = Directory(p.dirname(path));
          final encrypted = await _findNewestEncryptedInDir(dir);

          if (encrypted != null) {
            final originalName = p.basename(path);
            final encExt = p.extension(encrypted.path);
            final finalEncryptedPath = p.join(
              _workspaceTargetDir(),
              '$originalName$encExt',
            );

            if (File(finalEncryptedPath).existsSync()) {
              await File(finalEncryptedPath).delete();
            }

            await encrypted.rename(finalEncryptedPath);
            await File(path).delete();
          }
        }
      }
    } finally {
      if (isFile) {
        await _setLocked(path, false);
      }
    }
  }

  // ============================================================
  // OPEN / DECRYPT / EXTERNAL LAUNCH
  // ============================================================

  Future<void> _openEntity(FileSystemEntity ent) async {
    if (!_isInsideWorkspace(ent.path)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Access blocked: Workspace only."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (FileSystemEntity.isDirectorySync(ent.path)) {
      _navigateTo(Directory(ent.path));
      return;
    }

    final ext = p.extension(ent.path).toLowerCase();
    final bool isEncrypted =
        ext == '.aes256' || ext == '.threefish' || ext == '.chacha20';

    if (isEncrypted) {
      try {
        await Directory(_tempRootPath).create(recursive: true);

        final wsDir = Directory(p.dirname(ent.path));
        final before = wsDir
            .listSync(followLinks: false)
            .whereType<File>()
            .map((f) => f.path)
            .toSet();

        await widget.onDecryptFile(ent.path);

        final decryptedName = _originalNameFromEncrypted(ent.path);
        final tempExpected = p.join(_tempRootPath, decryptedName);

        String openedPath = '';

        if (File(tempExpected).existsSync()) {
          openedPath = tempExpected;
        } else {
          final after = wsDir
              .listSync(followLinks: false)
              .whereType<File>()
              .map((f) => f.path)
              .toSet();

          final newFiles = after.difference(before);

          File? candidate;
          for (final fp in newFiles) {
            final bn = p.basename(fp);
            if (bn == decryptedName ||
                p.basenameWithoutExtension(fp).endsWith(decryptedName)) {
              candidate = File(fp);
              break;
            }
          }

          candidate ??= (() {
            File? newest;
            DateTime newestTime = DateTime.fromMillisecondsSinceEpoch(0);
            for (final fp in newFiles) {
              if (_isEncryptedFilePath(fp)) continue;
              final f = File(fp);
              if (!f.existsSync()) continue;
              final st = f.statSync();
              if (st.modified.isAfter(newestTime)) {
                newestTime = st.modified;
                newest = f;
              }
            }
            return newest;
          })();

          if (candidate != null && candidate.existsSync()) {
            final movedTemp = await _resolveNonConflictPath(
              p.join(_tempRootPath, decryptedName),
              isDir: false,
            );

            // MOVE decrypted file into TEMP
            await candidate.rename(movedTemp);

            try {
              if (File(candidate.path).existsSync()) {
                await File(candidate.path).delete();
              }
            } catch (_) {}

            openedPath = movedTemp;
          }
        }

        if (openedPath.isEmpty || !File(openedPath).existsSync()) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Decrypted output not found (TEMP/workspace).'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        _setCooldown(openedPath);

        await _openExternalMedia(openedPath);

        _recordRecentPath(ent.path, action: 'Open/Edit');

        return;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Open encrypted file failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    await _openExternalMedia(ent.path);

    _recordRecentPath(ent.path);
  }

  String get _userKey => p.basename(_workspaceRootPath);

  String get _recentPrefsKey => '$_kRecentKeyPrefix:$_userKey';

  // ---------- Recent history ----------

  bool _existsPath(String path) {
    final t = FileSystemEntity.typeSync(path);
    return t != FileSystemEntityType.notFound;
  }

  bool _isSameOrChildPath(String parent, String child) {
    final pAbs = Directory(parent).absolute.path;
    final cAbs = Directory(child).absolute.path;

    if (pAbs == cAbs) return true;
    return cAbs.startsWith('$pAbs${p.separator}');
  }

  void _removeRecentForDeletedPath(String deletedPath, {required bool wasDir}) {
    recentItems.removeWhere((ri) {
      if (ri.path == deletedPath) return true;
      if (wasDir && _isSameOrChildPath(deletedPath, ri.path)) return true;
      return false;
    });
  }

  void _pruneRecentItems() {
    recentItems.removeWhere((ri) {
      if (!_isInsideWorkspace(ri.path)) return true;

      if (!_existsPath(ri.path)) return true;

      return false;
    });
  }

  String _formatVisited(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final y = dt.year;
    final m = two(dt.month);
    final d = two(dt.day);
    final hh = two(dt.hour);
    final mm = two(dt.minute);
    final ss = two(dt.second);
    return '$y-$m-$d  $hh:$mm:$ss';
  }

  // ============================================================
  // RECENT HISTORY
  // ============================================================

  Future<void> _saveRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = recentItems
          .take(_kMaxRecentItems)
          .map((e) => e.toJson())
          .toList();

      await prefs.setString(_recentPrefsKey, jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();

    final oldKey = 'explorer_recent_items_v1:$_userKey';
    await prefs.remove(oldKey);

    final raw = prefs.getString(_recentPrefsKey);

    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        await prefs.remove(_recentPrefsKey);
        return;
      }

      final loaded = <RecentItem>[];
      for (final item in decoded) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final ri = RecentItem.fromJson(map);
          if (ri != null) loaded.add(ri);
        }
      }

      if (!mounted) return;

      setState(() {
        recentItems
          ..clear()
          ..addAll(loaded);
        _pruneRecentItems();
      });

      await _saveRecent();
    } catch (_) {
      await prefs.remove(_recentPrefsKey);
      if (!mounted) return;
      setState(() => recentItems.clear());
    }
  }

  void _recordRecentPath(String path, {String action = 'Open'}) {
    if (path.trim().isEmpty) return;
    if (!_isInsideWorkspace(path)) return;
    if (!_existsPath(path)) return;

    final type = FileSystemEntity.typeSync(path);
    final bool isDir = type == FileSystemEntityType.directory;

    recentItems.removeWhere((e) => e.path == path);

    recentItems.insert(
      0,
      RecentItem(
        path: path,
        isDir: isDir,
        visitedAt: DateTime.now(),
        action: action,
      ),
    );

    if (recentItems.length > _kMaxRecentItems) {
      recentItems.removeRange(_kMaxRecentItems, recentItems.length);
    }

    _saveRecent();
  }

  // -------------- Import / Export (Workspace Explorer) ---------------

  Future<String> _resolveNonConflictPath(
    String initial, {
    required bool isDir,
  }) async {
    bool exists(String path) =>
        isDir ? Directory(path).existsSync() : File(path).existsSync();

    if (!exists(initial)) return initial;

    final dir = p.dirname(initial);
    final base = p.basenameWithoutExtension(initial);
    final ext = p.extension(initial);

    int i = 1;
    while (true) {
      final name = isDir ? '$base ($i)' : '$base ($i)$ext';
      final candidate = p.join(dir, name);
      if (!exists(candidate)) return candidate;
      i++;
    }
  }

  Future<void> _copyFileWithProgress({
    required File src,
    required File dest,
    required void Function(String detail, int deltaBytes) report,
    required _CopyProgress prog,
  }) async {
    if (_cancelRequested) throw _UserCancelled();

    await dest.parent.create(recursive: true);

    final srcLen = await src.length();
    prog.currentName = p.basename(src.path);

    final inStream = src.openRead();
    final outSink = dest.openWrite();

    int localCopied = 0;

    try {
      await for (final chunk in inStream) {
        if (_cancelRequested) throw _UserCancelled();

        outSink.add(chunk);
        localCopied += chunk.length;
        prog.copiedBytes += chunk.length;

        final frac = prog.totalBytes == 0
            ? 0.0
            : (prog.copiedBytes / prog.totalBytes);

        final elapsed = _copyWatch.elapsedMilliseconds / 1000.0;
        final speed = elapsed <= 0 ? 0.0 : (prog.copiedBytes / elapsed);
        final remainingBytes = (prog.totalBytes - prog.copiedBytes).clamp(
          0,
          prog.totalBytes,
        );
        final etaSec = speed <= 0 ? double.nan : (remainingBytes / speed);

        final int perFilePct = (srcLen == 0)
            ? 0
            : ((localCopied / srcLen) * 100).clamp(0, 100).round();

        if (mounted) {
          setState(() => _progress = frac.clamp(0.0, 1.0));
        }

        report(
          'Copying: ${prog.currentName} • File $perFilePct% • ETA ${_formatEtaSeconds(etaSec)}',
          chunk.length,
        );
      }

      await outSink.flush();
    } catch (_) {
      try {
        await outSink.close();
      } catch (_) {}
      try {
        if (dest.existsSync()) dest.deleteSync();
      } catch (_) {}
      rethrow;
    } finally {
      try {
        await outSink.close();
      } catch (_) {}
    }
  }

  Future<void> _copyDirectoryWithProgress({
    required Directory src,
    required Directory dest,
    required void Function(String detail, int deltaBytes) report,
    required _CopyProgress prog,
  }) async {
    await dest.create(recursive: true);

    await for (final entity in src.list(recursive: false, followLinks: false)) {
      if (_cancelRequested) throw _UserCancelled();
      final name = p.basename(entity.path);
      final newPath = p.join(dest.path, name);

      if (entity is File) {
        await _copyFileWithProgress(
          src: entity,
          dest: File(newPath),
          report: report,
          prog: prog,
        );
      } else if (entity is Directory) {
        await _copyDirectoryWithProgress(
          src: entity,
          dest: Directory(newPath),
          report: report,
          prog: prog,
        );
      }
    }
  }

  Future<int> _sumBytesForFiles(List<String> filePaths) async {
    int total = 0;
    for (final fp in filePaths) {
      try {
        total += await File(fp).length();
      } catch (_) {}
    }
    return total;
  }

  Future<int> _sumBytesForDirectory(Directory dir) async {
    int total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<void> _importMenu(Offset globalPos) async {
    final action = await showMenu<String>(
      context: context,
      color: const Color(0xFF202020),
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx,
        globalPos.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'files',
          child: _menuRow(Icons.insert_drive_file, 'Import Files'),
        ),
        PopupMenuItem(
          value: 'folder',
          child: _menuRow(Icons.folder, 'Import Folder'),
        ),
      ],
    );

    if (action == 'files') await _importFiles();
    if (action == 'folder') await _importFolder();
  }

  // ============================================================
  // IMPORT FLOW
  // Copy -> Backup -> Encrypt -> Move to Workspace
  // ============================================================

  Future<void> _importFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      final srcPaths = result.files
          .map((f) => f.path)
          .whereType<String>()
          .toList();
      if (srcPaths.isEmpty) return;

      await _runWithProgress(
        title: 'Importing files…',
        task: (report) async {
          final createdBackups = <String>[];

          try {
            await Directory(_importBackupRoot).create(recursive: true);

            final totalBytes = await _sumBytesForFiles(srcPaths);
            final prog = _CopyProgress(totalBytes: totalBytes);

            _updateProgressUI(prog: prog, detail: 'Preparing…');

            for (final srcPath in srcPaths) {
              if (_cancelRequested) throw _UserCancelled();

              final backupPath = await _makeBackupDestFilePath(srcPath);

              await _copyFileWithProgress(
                src: File(srcPath),
                dest: File(backupPath),
                report: report,
                prog: prog,
              );
              createdBackups.add(backupPath);

              report('Encrypting: ${p.basename(srcPath)}', 0);
              await _encryptFileFromBackupIntoWorkspace(
                backupPath,
                originalBaseName: p.basename(srcPath),
              );
            }
          } on _UserCancelled {
            for (final pth in createdBackups) {
              try {
                final f = File(pth);
                if (f.existsSync()) f.deleteSync();
              } catch (_) {}
            }
            rethrow;
          }
        },
      );

      if (!mounted) return;
      refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'File imported and encrypted successfully',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  // ============================================================
  // IMPORT FLOW
  // Copy -> Backup -> Encrypt -> Move to Workspace
  // ============================================================

  Future<void> _importFolder() async {
    try {
      final picked = await FilePicker.platform.getDirectoryPath();
      if (picked == null || picked.trim().isEmpty) return;

      final srcDir = Directory(picked);
      if (!srcDir.existsSync()) return;

      await Directory(_importBackupRoot).create(recursive: true);

      final folderName = p.basename(srcDir.path);

      final backupRootPath = await _makeBackupDestDirPath(srcDir.path);
      final backupDir = Directory(backupRootPath);

      await _runWithProgress(
        title: 'Importing folder…',
        task: (report) async {
          try {
            final totalBytes = await _sumBytesForDirectory(srcDir);
            final prog = _CopyProgress(totalBytes: totalBytes);

            _updateProgressUI(prog: prog, detail: 'Preparing…');

            if (backupDir.existsSync()) {
              // optional: clear old backup if you want single backup per folder name
              // backupDir.deleteSync(recursive: true);
            }
            await backupDir.create(recursive: true);

            await _copyDirectoryWithProgress(
              src: srcDir,
              dest: backupDir,
              report: report,
              prog: prog,
            );

            report('Encrypting folder: $folderName', 0);

            await _encryptFolderFromBackupIntoWorkspace(
              backupDir.path,
              workspaceFolderName: folderName,
            );
          } on _UserCancelled {
            // keep backup if you want, or delete it:
            // try { if (backupDir.existsSync()) backupDir.deleteSync(recursive: true); } catch (_) {}
            rethrow;
          }
        },
      );

      if (!mounted) return;
      refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Folder imported and encrypted successfully',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import folder failed: $e')));
    }
  }

  // ============================================================
  // EXPORT FLOW
  // Decrypt -> TEMP -> Copy to user destination
  // ============================================================

  Future<void> _exportSelected() async {
    if (selectedPaths.isEmpty) return;

    // workspace-only safety
    for (final sp in selectedPaths) {
      if (!_isInsideWorkspace(sp)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export blocked: Workspace only.')),
        );
        return;
      }
    }

    final destDir = await FilePicker.platform.getDirectoryPath();
    if (destDir == null || destDir.trim().isEmpty) return;

    await _runWithProgress(
      title: 'Exporting (decrypting)…',
      task: (report) async {
        final stamp = DateTime.now().millisecondsSinceEpoch.toString();
        final sessionDir = Directory(p.join(_exportTmpRoot, stamp));
        await sessionDir.create(recursive: true);

        try {
          int idx = 0;

          for (final sp in selectedPaths) {
            idx++;
            if (_cancelRequested) throw _UserCancelled();

            final isDir = FileSystemEntity.isDirectorySync(sp);

            // EXPORT FOLDER
            if (isDir) {
              final folderName = _restoreOriginalFolderName(sp);

              // create output folder in destination
              final outFolderPath = await _resolveNonConflictPath(
                p.join(destDir, folderName),
                isDir: true,
              );
              final outFolder = Directory(outFolderPath);
              await outFolder.create(recursive: true);

              report(
                'Export folder ($idx/${selectedPaths.length}): $folderName',
                0,
              );

              _recordRecentPath(sp, action: 'Export Folder');

              final encryptedFiles = await _collectEncryptedFilesUnderPath(sp);

              // decrypt each file preserving relative structure
              for (final ef in encryptedFiles) {
                if (_cancelRequested) throw _UserCancelled();

                final rel = p.relative(p.dirname(ef.path), from: sp);
                report('Decrypting: ${p.basename(ef.path)}', 0);

                final decryptedTmp = await _decryptEncryptedFileToSession(
                  ef.path,
                  exportSessionDir: sessionDir.path,
                  relDir: rel,
                );

                final outPathInitial = p.join(
                  outFolder.path,
                  rel,
                  p.basename(decryptedTmp),
                );
                final outPath = await _resolveNonConflictPath(
                  outPathInitial,
                  isDir: false,
                );

                await Directory(p.dirname(outPath)).create(recursive: true);
                await File(decryptedTmp).copy(outPath);
              }

              try {
                final encFolder = Directory(sp);
                if (encFolder.existsSync()) {
                  await encFolder.delete(recursive: true);
                }
              } catch (_) {}

              continue;
            }

            if (!_isEncryptedFilePath(sp)) {
              throw Exception(
                'Selected file is not encrypted: ${p.basename(sp)}',
              );
            }

            report(
              'Decrypting file ($idx/${selectedPaths.length}): ${p.basename(sp)}',
              0,
            );

            final decryptedTmpPath = await _decryptEncryptedFileToTemp(sp);

            final outName = p.basename(decryptedTmpPath);
            final outPathInitial = p.join(destDir, outName);
            final outPath = await _resolveNonConflictPath(
              outPathInitial,
              isDir: false,
            );

            await File(decryptedTmpPath).copy(outPath);
            try {
              if (File(sp).existsSync()) await File(sp).delete();
            } catch (_) {}
            try {
              if (File(decryptedTmpPath).existsSync())
                await File(decryptedTmpPath).delete();
            } catch (_) {}

            try {
              final dn = _originalNameFromEncrypted(sp);
              final directTemp = File(p.join(_tempRootPath, dn));
              if (directTemp.existsSync()) await directTemp.delete();
            } catch (_) {}

            report('Saved: ${p.basename(outPath)}', 0);
            _recordRecentPath(sp, action: 'Export');
          }
        } finally {
          await _cleanupExportTmp();
        }
      },
    );

    if (!mounted) return;
    final exportedCount = selectedPaths.length;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        content: Text(
          exportedCount == 0
              ? 'Exported and decrypted successfully'
              : 'Export and decrypted successfully ($exportedCount items)',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  // ---------- Context menu actions ----------

  Future<void> _showActionDialog(FileSystemEntity ent, Offset position) async {
    final isDir = FileSystemEntity.isDirectorySync(ent.path);

    if (!selectedPaths.contains(ent.path)) {
      setState(() {
        selectedPaths
          ..clear()
          ..add(ent.path);
        _lastSelectedIndex = null;
      });
    }

    final action = await showMenu<String>(
      context: context,
      color: const Color(0xFF202020),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          height: 36,
          child: _menuHeaderRow(Icons.key, isDir ? 'Folder' : 'File'),
        ),
        const PopupMenuDivider(height: 6),
        /*if (!isDir)
          PopupMenuItem(
            value: 'encrypt',
            child: _menuRow(Icons.lock, 'Encrypt File'),
          ),*/
        if (!isDir)
          PopupMenuItem(
            value: 'decrypt',
            child: _menuRow(Icons.lock_open, 'Decrypt File'),
          ),
        /*if (isDir)
          PopupMenuItem(
            value: 'encrypt',
            child: _menuRow(Icons.folder_off_outlined, 'Encrypt Folder'),
          ),*/
        if (isDir)
          PopupMenuItem(
            value: 'decrypt',
            child: _menuRow(Icons.folder_rounded, 'Decrypt Folder'),
          ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem(
          value: 'rename',
          child: _menuRow(Icons.drive_file_rename_outline_rounded, 'Rename'),
        ),
        PopupMenuItem(
          value: 'export',
          child: _menuRow(Icons.file_download, 'Export'),
        ),
        PopupMenuItem(
          value: 'delete',
          child: SizedBox(
            height: 36,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                SizedBox(
                  width: 32,
                  child: Center(
                    child: Icon(
                      Icons.delete,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Text('Delete', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ],
    );

    if (action == null) return;

    if (action == 'export') {
      await _exportSelected();
      return;
    }

    if (isDir) {
      /*if (action == 'encrypt') {
        await widget.onEncryptFolder(ent.path);
        _recordRecentPath(ent.path);
      }*/
      if (action == 'decrypt') {
        await widget.onDecryptFolder(ent.path);
        _recordRecentPath(ent.path, action: 'Decrypt Folder');
      }
    } else {
      /*if (action == 'encrypt') {
        await widget.onEncryptFile(ent.path);
        _recordRecentPath(ent.path);
      }*/
      if (action == 'decrypt') {
        await widget.onDecryptFile(ent.path);
        _recordRecentPath(ent.path, action: 'Decrypt');
      }
    }

    if (action == 'rename') {
      _renameEntity(ent);
    }

    if (action == 'delete') {
      await _deleteSelected(ent.path);
    }
  }

  void _renameEntity(FileSystemEntity ent) async {
    if (!_isInsideWorkspace(ent.path)) return;

    final oldName = p.basename(ent.path);
    final controller = TextEditingController(text: oldName);

    setState(() => _isRenaming = true);

    String? newName;
    try {
      newName = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Rename', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isRenaming = false);
    }

    if (newName == null) return;
    newName = newName.trim();
    if (newName.isEmpty || newName == oldName) return;

    final newPath = p.join(p.dirname(ent.path), newName);
    ent.renameSync(newPath);

    refresh();
  }

  // ---------- Empty space menu ----------

  void _showEmptySpaceMenu(Offset position) async {
    final action = await showMenu<String>(
      context: context,
      color: const Color(0xFF202020),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          height: 36,
          child: Row(
            children: const [
              Icon(Icons.add, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text('Workspace', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),

        PopupMenuItem(
          value: 'import',
          child: _menuRow(Icons.file_upload, 'Import'),
        ),
        PopupMenuItem(
          value: 'refresh',
          child: _menuRow(Icons.refresh, 'Refresh'),
        ),
      ],
    );

    if (action == null) return;

    switch (action) {
      case 'import':
        await _importMenu(position);
        break;

      case 'refresh':
        refresh();
        break;

      // Workspace-only: creation disabled
      /*
  case 'new_folder':
  case 'new_text':
  case 'new_word':
  case 'new_excel':
  case 'new_ppt':
  case 'new_access':
    break;
  */
    }
  }

  // ---------- Trash / delete / undo ----------

  Directory _trashDir() {
    final userKey = p.basename(_workspaceRootPath);
    return Directory(p.join(_tempRootPath, 'trash', userKey));
  }

  Future<void> _ensureTrashDir() async {
    final d = _trashDir();
    if (!d.existsSync()) {
      await d.create(recursive: true);
    }
  }

  String _uniqueTrashName(String originalPath) {
    final name = p.basename(originalPath);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${stamp}_$name';
  }

  Future<void> _undoLastDelete() async {
    final original = _lastDeletedOriginalPath;
    final trash = _lastDeletedTrashPath;

    if (original == null || trash == null) return;

    String restorePath = original;
    if (FileSystemEntity.typeSync(restorePath) !=
        FileSystemEntityType.notFound) {
      restorePath = p.join(
        p.dirname(original),
        '${p.basenameWithoutExtension(original)} (restored)${p.extension(original)}',
      );
    }

    try {
      if (_lastDeletedWasDir) {
        await Directory(trash).rename(restorePath);
      } else {
        await File(trash).rename(restorePath);
      }

      _lastDeletedOriginalPath = null;
      _lastDeletedTrashPath = null;
      _lastDeletedWasDir = false;

      if (!mounted) return;
      refresh();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          content: Text('Restored', style: TextStyle(color: Colors.white)),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Failed to restore: $e',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  // ============================================================
  // DELETE / TRASH / UNDO
  // ============================================================

  Future<void> _deleteSelected([String? forcedPath]) async {
    final path = forcedPath ?? _primarySelectedPath;

    if (path == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No item selected')));
      return;
    }

    if (!_isInsideWorkspace(path)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delete blocked: Workspace only.')),
      );
      return;
    }

    final name = p.basename(path);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Delete', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "$name"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _ensureTrashDir();

      final isDir = FileSystemEntity.isDirectorySync(path);
      final trashPath = p.join(_trashDir().path, _uniqueTrashName(path));

      if (isDir) {
        await Directory(path).rename(trashPath);
      } else {
        await File(path).rename(trashPath);
      }

      _lastDeletedOriginalPath = path;
      _lastDeletedTrashPath = trashPath;
      _lastDeletedWasDir = isDir;

      setState(() {
        _removeRecentForDeletedPath(path, wasDir: isDir);
      });
      await _saveRecent();

      if (!mounted) return;

      setState(() {
        selectedPaths.remove(path);
        if (selectedPaths.isEmpty) _lastSelectedIndex = null;
        //_newlyCreatedPath = null;
      });

      refresh();

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();

      final controller = messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Deleted: $name',
            style: const TextStyle(color: Colors.white),
          ),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.white,
            onPressed: _undoLastDelete,
          ),
          duration: const Duration(seconds: 5),
        ),
      );

      Future.delayed(const Duration(seconds: 5), () {
        if (!mounted) return;
        controller.close();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Failed to delete: $e',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  // ---------- UI helpers ----------

  /*Widget _menuRowAssetIcon(String assetPath, String label) {
    const double leadingWidth = 32;
    const double iconSize = 24;

    return SizedBox(
      height: 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: leadingWidth,
            child: Center(
              child: Image.asset(
                assetPath,
                width: iconSize,
                height: iconSize,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }*/

  Widget _menuRow(IconData icon, String label) {
    const double leadingWidth = 32;

    return SizedBox(
      height: 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: leadingWidth,
            child: Center(child: Icon(icon, color: Colors.white70, size: 18)),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _menuHeaderRow(IconData icon, String label) {
    const double leadingWidth = 32;

    return SizedBox(
      height: 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: leadingWidth,
            child: Center(child: Icon(icon, color: Colors.white70, size: 18)),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  // ============================================================
  // ICON RENDERING
  // ============================================================

  Widget _folderIconClean3D({double size = 50}) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: size * 0.06,
            right: size * 0.06,
            bottom: size * 0.08,
            top: size * 0.32,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFC857),
                borderRadius: BorderRadius.circular(size * 0.16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFDF9A3E).withOpacity(0.3),
                    offset: Offset(0, size * 0.08),
                    blurRadius: size * 0.16,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: size * 0.1,
            top: size * 0.16,
            width: size * 0.36,
            height: size * 0.24,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFB9F2F),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(size * 0.12),
                  topRight: Radius.circular(size * 0.12),
                ),
              ),
            ),
          ),
          Positioned(
            left: size * 0.12,
            right: size * 0.12,
            top: size * 0.4,
            height: size * 0.1,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(size * 0.05),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileIconSized(FileSystemEntity ent, double size) {
    if (FileSystemEntity.isDirectorySync(ent.path)) {
      return _folderIconClean3D(size: size);
    }

    final ext = p.extension(ent.path).toLowerCase();
    IconData icon;
    Color color;

    if (['.png', '.jpg', '.jpeg', '.gif', '.bmp'].contains(ext)) {
      icon = Icons.image;
      color = const Color(0xFF42A5F5);
    } else if (['.mp3', '.wav'].contains(ext)) {
      icon = Icons.audiotrack;
      color = const Color(0xFF8E24AA);
    } else if (['.mp4', '.mkv', '.mov'].contains(ext)) {
      icon = Icons.movie;
      color = const Color(0xFFFB8C00);
    } else if (ext == '.pdf') {
      icon = Icons.picture_as_pdf;
      color = const Color(0xFFEF5350);
    } else if (ext == '.doc' || ext == '.docx') {
      return Transform.scale(
        scale: 1.65,
        child: Image.asset(
          'assets/images/icons/Word.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      );
    } else if (ext == '.xls' || ext == '.xlsx') {
      return Transform.scale(
        scale: 1.70,
        child: Image.asset(
          'assets/images/icons/Excel.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      );
    } else if (ext == '.ppt' || ext == '.pptx') {
      return Transform.scale(
        scale: 1.45,
        child: Image.asset(
          'assets/images/icons/Powerpoint.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      );
    } else if (ext == '.accdb' || ext == '.mdb') {
      return Transform.scale(
        scale: 1.70,
        child: Image.asset(
          'assets/images/icons/Access.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      );
    } else {
      icon = Icons.insert_drive_file;
      color = const Color(0xFF90CAF9);
    }

    return Icon(icon, size: size, color: color);
  }

  // ============================================================
  // EXPLORER VIEWS
  // Grid & List
  // ============================================================

  Widget _iconView() {
    final view = _filteredEntries();

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.mouse) return;

        // ✅ LEFT CLICK on empty space -> unselect
        if (event.buttons == kPrimaryMouseButton) {
          if (!_clickedOnGridItem(event.position)) {
            _clearSelection();
          }
          return;
        }

        // ✅ RIGHT CLICK on empty space -> show menu
        if (event.buttons == kSecondaryMouseButton) {
          if (_clickedOnGridItem(event.position)) return;
          _showEmptySpaceMenu(event.position);
        }
      },

      child: LayoutBuilder(
        builder: (context, constraints) {
          const double itemWidth = 120;
          final int crossAxisCount = (constraints.maxWidth / itemWidth)
              .floor()
              .clamp(2, 12);

          final bool isWide = constraints.maxWidth > 1200;
          final double iconSize = isWide ? 56 : 50;
          final double spacing = isWide ? 24 : 12;

          return GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.all(spacing),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: 0.85,
            ),
            itemCount: view.length,
            itemBuilder: (context, idx) {
              final ent = view[idx];
              final name = p.basename(ent.path);
              final isSelected = selectedPaths.contains(ent.path);
              final isLocked =
                  !FileSystemEntity.isDirectorySync(ent.path) &&
                  _isLockedPath(ent.path);
              final opacity = isLocked ? 0.35 : 1.0;

              final itemKey = _gridItemKeys[idx] ??= GlobalKey();

              return GestureDetector(
                key: itemKey,
                behavior: HitTestBehavior.translucent,
                onTap: () => _selectByIndex(idx: idx, view: view),
                onSecondaryTapDown: (details) async {
                  _selectByIndex(idx: idx, view: view);
                  await _showActionDialog(ent, details.globalPosition);
                },
                onDoubleTap: () async => await _openEntity(ent),
                child: Tooltip(
                  message: name,
                  waitDuration: const Duration(seconds: 0),
                  showDuration: const Duration(seconds: 4),
                  textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(
                      255,
                      12,
                      12,
                      12,
                    ).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white10
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: _iconWithEncryptedBadge(
                          ent: ent,
                          iconSize: iconSize,
                          opacity: opacity,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 16,
                        child: Opacity(
                          opacity: opacity,
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static const double _listRowHeight = 40.0;

  Widget _listView() {
    final view = _filteredEntries();

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.mouse) return;

        // ✅ LEFT CLICK on empty space -> unselect
        if (event.buttons == kPrimaryMouseButton) {
          if (!_clickedOnHotArea(event.position)) {
            _clearSelection();
          }
          return;
        }

        // ✅ RIGHT CLICK on empty space -> show menu
        if (event.buttons == kSecondaryMouseButton) {
          if (_clickedOnHotArea(event.position)) return;
          _showEmptySpaceMenu(event.position);
        }
      },

      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        itemExtent: _listRowHeight,
        itemCount: view.length,
        itemBuilder: (context, idx) {
          final ent = view[idx];
          final name = p.basename(ent.path);
          final isSelected = selectedPaths.contains(ent.path);
          final isLocked =
              !FileSystemEntity.isDirectorySync(ent.path) &&
              _isLockedPath(ent.path);
          final opacity = isLocked ? 0.35 : 1.0;

          final hotKey = _hotAreaKeys[idx] ??= GlobalKey();

          return Container(
            color: isSelected ? Colors.white10 : Colors.transparent,
            child: Row(
              children: [
                GestureDetector(
                  key: hotKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _selectByIndex(idx: idx, view: view),
                  onDoubleTap: () async => await _openEntity(ent),
                  onSecondaryTapDown: (details) async {
                    _selectByIndex(idx: idx, view: view);
                    await _showActionDialog(ent, details.globalPosition);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        _iconWithEncryptedBadge(
                          ent: ent,
                          iconSize: 36,
                          opacity: opacity,
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 260,
                          child: Opacity(
                            opacity: opacity,
                            child: Text(
                              name,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // HISTORY PANEL UI
  // ============================================================

  Widget _historyListView() {
    final items = recentItems;

    if (items.isEmpty) {
      return const Center(
        child: Text('No history yet', style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final name = p.basename(item.path);

        final exists = _existsPath(item.path);
        final locked = exists && !item.isDir && _isLockedPath(item.path);

        return ListTile(
          leading: item.isDir
              ? const Icon(Icons.folder, color: Colors.amber)
              : const Icon(Icons.insert_drive_file, color: Colors.white70),
          title: Text(
            name,
            style: TextStyle(
              color: exists ? Colors.white : Colors.white38,
              decoration: exists ? null : TextDecoration.lineThrough,
            ),
          ),
          subtitle: Text(
            '${item.action} • ${_formatVisited(item.visitedAt)}\n${item.path}',
            style: TextStyle(
              color: exists ? Colors.white54 : Colors.white24,
              height: 1.25,
            ),
          ),

          trailing: locked
              ? const Icon(Icons.lock, color: Colors.white38, size: 18)
              : null,
          onTap: () {
            if (!exists) {
              setState(() {
                recentItems.removeAt(i);
              });
              _saveRecent();
              return;
            }

            setState(() => showHistoryPanel = false);

            if (item.isDir) {
              _navigateTo(Directory(item.path));
            } else {
              _openEntity(File(item.path));
            }
          },
        );
      },
    );
  }

  // ---------- Breadcrumb + search UI ----------

  List<_Crumb> _buildCrumbs() {
    final List<_Crumb> crumbs = [];

    crumbs.add(_Crumb(label: 'Workspace', path: _workspaceRootPath));

    final currentAbs = Directory(currentDir.path).absolute.path;
    if (currentAbs == _workspaceRootPath) return crumbs;

    final rel = p.relative(currentAbs, from: _workspaceRootPath);
    final parts = rel
        .split(p.separator)
        .where((s) => s.trim().isNotEmpty)
        .toList();

    String walk = _workspaceRootPath;
    for (final part in parts) {
      walk = p.join(walk, part);
      crumbs.add(_Crumb(label: part, path: walk));
    }

    return crumbs;
  }

  Widget _breadcrumbBar() {
    final crumbs = _buildCrumbs();

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < crumbs.length; i++) ...[
                    _crumbChip(crumbs[i], isLast: i == crumbs.length - 1),
                    if (i != crumbs.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Colors.white38,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          IconButton(
            tooltip: 'Copy path',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: currentDir.path));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Path copied'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _crumbChip(_Crumb crumb, {required bool isLast}) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        final d = Directory(crumb.path);
        if (d.existsSync()) _navigateTo(d);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          crumb.label,
          style: TextStyle(
            color: isLast ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _searchBox({required bool compact}) {
    return SizedBox(
      height: 34,
      width: compact ? 190 : 260,
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white54),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white70,
                  ),
                  onPressed: () => _searchController.clear(),
                ),
          filled: true,
          fillColor: Colors.black.withOpacity(0.08),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 0,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ---------- Responsive position helper ----------

  Offset _globalPosFromContext(BuildContext ctx) {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.localToGlobal(Offset.zero);
  }

  // ---------- Shortcuts / build ----------

  @override
  Widget build(BuildContext context) {
    final undoIntent = VoidCallbackIntent(() => _undoLastDelete());
    final deleteIntent = VoidCallbackIntent(() => _deleteSelected());
    final exportIntent = VoidCallbackIntent(() => _exportSelected());

    return Focus(
      autofocus: true,
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
              undoIntent,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
              undoIntent,
          const SingleActivator(LogicalKeyboardKey.delete): deleteIntent,

          const SingleActivator(LogicalKeyboardKey.keyE, control: true):
              exportIntent,
          const SingleActivator(LogicalKeyboardKey.keyE, meta: true):
              exportIntent,
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            VoidCallbackIntent: CallbackAction<VoidCallbackIntent>(
              onInvoke: (intent) => intent.callback(),
            ),
          },
          child: Stack(
            children: [
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final w = MediaQuery.of(context).size.width;
                        final compact = w < 980;

                        return Row(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                              onPressed: backHistory.isNotEmpty
                                  ? _goBack
                                  : null,
                            ),
                            const SizedBox(width: 8),

                            Expanded(child: _breadcrumbBar()),

                            const SizedBox(width: 8),

                            if (!compact) _searchBox(compact: compact),

                            const SizedBox(width: 8),

                            IconButton(
                              tooltip: isListView
                                  ? 'Switch to Grid View'
                                  : 'Switch to List View',
                              icon: Icon(
                                isListView ? Icons.grid_view : Icons.view_list,
                                color: Colors.white70,
                              ),
                              onPressed: () =>
                                  setState(() => isListView = !isListView),
                            ),
                            IconButton(
                              tooltip: showHistoryPanel
                                  ? 'Back to Explorer'
                                  : 'History',
                              icon: Icon(
                                Icons.history,
                                color: showHistoryPanel
                                    ? Colors.amber
                                    : Colors.white70,
                              ),
                              onPressed: () => setState(
                                () => showHistoryPanel = !showHistoryPanel,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 10),

                  Expanded(
                    child: showHistoryPanel
                        ? _historyListView()
                        : (isListView ? _listView() : _iconView()),
                  ),
                ],
              ),

              Positioned(
                right: 12,
                bottom: 12,
                child: IgnorePointer(
                  ignoring: false,
                  child: _FloatingWorkspaceButtons(
                    selectedCount: selectedPaths.length,
                    onImport: (ctx) => _importMenu(_globalPosFromContext(ctx)),
                    onExport: _exportSelected,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DISPOSE / CLEANUP
  // ============================================================

  @override
  void dispose() {
    _stopAutoRefreshWatcher();
    _fileWatcherTimer?.cancel();
    _autoProtectTimer?.cancel();
    _scrollController.dispose();
    pathController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}

class _Crumb {
  final String label;
  final String path;

  _Crumb({required this.label, required this.path});
}

// ============================================================
// FLOATING ACTION BUTTONS
// ============================================================
class _FloatingWorkspaceButtons extends StatefulWidget {
  final int selectedCount;
  final void Function(BuildContext ctx) onImport;
  final VoidCallback onExport;

  const _FloatingWorkspaceButtons({
    required this.selectedCount,
    required this.onImport,
    required this.onExport,
  });

  @override
  State<_FloatingWorkspaceButtons> createState() =>
      _FloatingWorkspaceButtonsState();
}

class _FloatingWorkspaceButtonsState extends State<_FloatingWorkspaceButtons> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final bool expanded = hovering;

    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: expanded ? Colors.white : Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          boxShadow: expanded
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _animatedButton(
              icon: Icons.file_upload,
              label: "Import",
              expanded: expanded,
              onPressed: (ctx) => widget.onImport(ctx),
            ),
            const SizedBox(width: 6),
            _animatedButton(
              icon: Icons.file_download,
              label: "Export",
              expanded: expanded,
              enabled: widget.selectedCount > 0,
              badgeCount: widget.selectedCount,
              onPressed: (_) => widget.onExport(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _animatedButton({
    required IconData icon,
    required String label,
    required bool expanded,
    required void Function(BuildContext) onPressed,
    bool enabled = true,
    int badgeCount = 0,
  }) {
    final iconColor = expanded ? Colors.black : Colors.white.withOpacity(0.75);

    final textColor = Colors.black;

    return Builder(
      builder: (ctx) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? () => onPressed(ctx) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 20, color: iconColor),

                  if (!expanded && badgeCount > 0)
                    Positioned(
                      right: -10,
                      top: -8,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                transitionBuilder: (child, anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: SizeTransition(
                      sizeFactor: anim,
                      axis: Axis.horizontal,
                      child: child,
                    ),
                  );
                },
                child: expanded
                    ? Row(
                        key: const ValueKey('label_on'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                          if (badgeCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                '($badgeCount)',
                                style: TextStyle(
                                  color: textColor.withOpacity(0.85),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      )
                    : const SizedBox(key: ValueKey('label_off')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
