import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:gitdesktop/core/git/dynamic_library_service.dart';
import 'package:gitdesktop/core/git/libgit2_bindings.dart';
import 'package:gitdesktop/core/git/credentials_provider.dart';

/// Commands that can be sent to the Git isolate
abstract class GitCommand {
  final Map<String, GitCredentialInfo>? credentials; // host -> creds
  const GitCommand({this.credentials});
}

/// Command to open a Git repository
class OpenRepoCommand extends GitCommand {
  final String path;
  const OpenRepoCommand(this.path, {super.credentials});
}

/// Command to get repository status
class GetStatusCommand extends GitCommand {
  final String repoPath;
  const GetStatusCommand(this.repoPath, {super.credentials});
}

/// Command to commit changes
class CommitCommand extends GitCommand {
  final String repoPath;
  final String message;
  final List<String> files;
  const CommitCommand(this.repoPath, this.message, this.files, {super.credentials});
}

/// Command to push to remote
class PushCommand extends GitCommand {
  final String repoPath;
  final String remote;
  final String branch;
  final bool force;
  const PushCommand(this.repoPath, this.remote, this.branch, {this.force = false, super.credentials});
}

/// Command to fetch from remote
class FetchCommand extends GitCommand {
  final String repoPath;
  final String remote;
  const FetchCommand(this.repoPath, this.remote, {super.credentials});
}

/// Command to pull (fast-forward only)
class PullCommand extends GitCommand {
  final String repoPath;
  final String remote;
  final String branch;
  const PullCommand(this.repoPath, this.remote, this.branch, {super.credentials});
}

/// Command to get diff for a file
class GetDiffCommand extends GitCommand {
  final String repoPath;
  final String filePath;
  const GetDiffCommand(this.repoPath, this.filePath, {super.credentials});
}

/// Command to get commit history
class GetHistoryCommand extends GitCommand {
  final String repoPath;
  final int limit;
  const GetHistoryCommand(this.repoPath, this.limit, {super.credentials});
}

/// Command to list remotes (names + URLs)
class GetRemotesCommand extends GitCommand {
  final String repoPath;
  const GetRemotesCommand(this.repoPath, {super.credentials});
}

/// Command to add a remote
class AddRemoteCommand extends GitCommand {
  final String repoPath;
  final String name;
  final String url;
  const AddRemoteCommand(this.repoPath, this.name, this.url, {super.credentials});
}

/// Command to remove a remote
class RemoveRemoteCommand extends GitCommand {
  final String repoPath;
  final String name;
  const RemoveRemoteCommand(this.repoPath, this.name, {super.credentials});
}

/// Command to set a remote's URL
class SetRemoteUrlCommand extends GitCommand {
  final String repoPath;
  final String name;
  final String url;
  const SetRemoteUrlCommand(this.repoPath, this.name, this.url, {super.credentials});
}

/// Command to clone a repository
class CloneRepoCommand extends GitCommand {
  final String url;
  final String destinationPath;
  const CloneRepoCommand(this.url, this.destinationPath, {super.credentials});
}

/// Command to initialize a new repository
class InitRepoCommand extends GitCommand {
  final String path;
  const InitRepoCommand(this.path, {super.credentials});
}

/// Command to shutdown the isolate
class ShutdownCommand extends GitCommand {
  const ShutdownCommand();
}

/// Result wrapper for Git operations
class GitResult<T> {
  final T? data;
  final String? error;
  final bool success;

  const GitResult.success(this.data)
      : error = null,
        success = true;

  const GitResult.failure(this.error)
      : data = null,
        success = false;
}

/// Message sent from main isolate to background isolate
class _IsolateMessage {
  final GitCommand command;
  final SendPort replyPort;

  const _IsolateMessage(this.command, this.replyPort);
}

/// Manages a background isolate for Git operations via FFI
///
/// This is the foundation of the app's stability. All FFI calls to libgit2
/// happen on a dedicated background isolate, ensuring the UI thread never blocks.
///
/// Flow:
/// 1. Main thread calls execute() with a GitCommand
/// 2. Command is sent via SendPort to background isolate
/// 3. Background isolate processes command (FFI calls to libgit2)
/// 4. Result is sent back via ReceivePort
/// 5. Future completes with result
///
/// Example:
/// ```dart
/// final manager = GitIsolateManager();
/// await manager.initialize();
///
/// final result = await manager.execute(OpenRepoCommand('/path/to/repo'));
/// if (result.success) {
///   print('Repository opened: ${result.data}');
/// } else {
///   print('Error: ${result.error}');
/// }
/// ```
class GitIsolateManager {
  static final GitIsolateManager _instance = GitIsolateManager._internal();
  factory GitIsolateManager() => _instance;
  GitIsolateManager._internal();

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  bool _isInitialized = false;

  final _progressController = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of network and sideband progress updates from the background isolate
  Stream<Map<String, dynamic>> get progressStream => _progressController.stream;

  /// Whether the isolate is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Initialize the background isolate
  ///
  /// Must be called before executing any commands.
  /// Safe to call multiple times (idempotent).
  Future<void> initialize() async {
    // Web preview (Dreamflow) does not support dart:isolate or dart:ffi.
    // Gracefully no-op so the UI stays usable.
    if (kIsWeb) {
      debugPrint('[GitIsolateManager] Web detected: isolates/FFI disabled. Skipping initialization.');
      _isInitialized = false;
      return;
    }
    if (_isInitialized) {
      debugPrint('[GitIsolateManager] Already initialized');
      return;
    }

    try {
      debugPrint('[GitIsolateManager] Initializing background isolate...');

      // Create ReceivePort to get SendPort from spawned isolate
      _receivePort = ReceivePort();

      // Spawn the isolate
      _isolate = await Isolate.spawn(
        _isolateEntryPoint,
        _receivePort!.sendPort,
        debugName: 'GitWorkerIsolate',
      );

      // Wait for the isolate to send back its SendPort
      final completer = Completer<SendPort>();
      _receivePort!.listen((message) {
        if (message is SendPort) {
          if (!completer.isCompleted) completer.complete(message);
        } else if (message is Map && message.containsKey('type')) {
          _progressController.add(Map<String, dynamic>.from(message));
        }
      });

      _sendPort = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Failed to initialize Git isolate');
        },
      );

      _isInitialized = true;
      debugPrint('[GitIsolateManager] Initialization complete');
    } catch (e) {
      debugPrint('[GitIsolateManager] Initialization failed: $e');
      await dispose();
      // Do not rethrow to avoid crashing app startup.
    }
  }

  /// Execute a Git command on the background isolate
  ///
  /// Returns a GitResult with either success data or error message.
  /// Throws if isolate is not initialized.
  Future<GitResult<T>> execute<T>(GitCommand command) async {
    // Web fallback: report unsupported features via failure result
    if (kIsWeb) {
      debugPrint('[GitIsolateManager] Command on web is unsupported: ${command.runtimeType}');
      return GitResult<T>.failure('Git operations are unavailable in web preview. Please run on macOS/Windows/Linux.');
    }
    if (!_isInitialized || _sendPort == null) {
      debugPrint('[GitIsolateManager] Not initialized; rejecting ${command.runtimeType}');
      return GitResult<T>.failure('GitIsolateManager not initialized.');
    }

    final replyPort = ReceivePort();
    final completer = Completer<GitResult<T>>();

    // Listen for reply from isolate
    replyPort.listen((message) {
      if (message is GitResult<T>) {
        completer.complete(message);
      } else {
        completer.complete(GitResult<T>.failure('Invalid response type'));
      }
      replyPort.close();
    });

    // Send command to background isolate
    _sendPort!.send(_IsolateMessage(command, replyPort.sendPort));

    try {
      // Wait for response with timeout
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('[GitIsolateManager] Command timeout: ${command.runtimeType}');
          return GitResult<T>.failure('Operation timed out');
        },
      );
    } catch (e) {
      debugPrint('[GitIsolateManager] Command error: $e');
      return GitResult<T>.failure(e.toString());
    }
  }

  /// Shutdown the background isolate and cleanup resources
  Future<void> dispose() async {
    if (_isInitialized) {
      debugPrint('[GitIsolateManager] Shutting down...');
      
      // Send shutdown command
      if (_sendPort != null) {
        try {
          await execute(const ShutdownCommand());
        } catch (e) {
          debugPrint('[GitIsolateManager] Shutdown command failed: $e');
        }
      }

      // Kill isolate
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;

      // Close ports
      _receivePort?.close();
      _receivePort = null;
      _sendPort = null;

      _isInitialized = false;
      debugPrint('[GitIsolateManager] Shutdown complete');
      _progressController.close();
    }
  }

  /// Entry point for the background isolate
  ///
  /// This runs on a separate thread and handles all FFI calls to libgit2.
  /// IMPORTANT: No Flutter UI code or BuildContext can be used here.
  static void _isolateEntryPoint(SendPort mainSendPort) {
    _mainSendPort = mainSendPort;
    // Create ReceivePort for this isolate
    final isolateReceivePort = ReceivePort();

    // Send this isolate's SendPort back to main isolate
    mainSendPort.send(isolateReceivePort.sendPort);

    debugPrint('[GitWorkerIsolate] Started (platform=${Platform.operatingSystem}) and preparing libgit2');

    // Log current dynamic library availability before any init
    DynamicLibraryService.logAvailability(probeSymbols: false);

    // Prepare libgit2 (FFI) once for this isolate
    try {
      final ok = DynamicLibraryService.initialize();
      if (!ok) {
        debugPrint('[GitWorkerIsolate] libgit2 library unavailable. Running in degraded mode.');
        _ffiReady = false;
        // Notify main isolate about FFI availability
        mainSendPort.send({'type': 'ffi_status', 'available': false, 'reason': 'Native libgit2 library not found or blocked by sandbox.'});
      } else {
        // After load, log symbol availability quickly
        DynamicLibraryService.logAvailability(probeSymbols: true);
        // Call libgit2 global init once (also validates symbol resolution)
        final initCount = LibGit2Bindings.I.libgit2_init();
        debugPrint('[GitWorkerIsolate] libgit2 initialized (count=$initCount)');
        _ffiReady = true;
        mainSendPort.send({'type': 'ffi_status', 'available': true});
      }
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] libgit2 init failed: $e\n$st');
      _ffiReady = false;
      mainSendPort.send({'type': 'ffi_status', 'available': false, 'reason': e.toString()});
    }

    // Listen for commands from main isolate
    isolateReceivePort.listen((message) {
      if (message is _IsolateMessage) {
        final command = message.command;
        final replyPort = message.replyPort;

        debugPrint('[GitWorkerIsolate] Processing: ${command.runtimeType}');

        try {
          // Process command and send result back
          final result = _processCommand(command);
          replyPort.send(result);
        } catch (e, stackTrace) {
          debugPrint('[GitWorkerIsolate] Error processing command: $e\n$stackTrace');
          replyPort.send(GitResult<dynamic>.failure(e.toString()));
        }
      }
    });
  }

  /// Process a Git command on the background isolate
  ///
  /// This is where all FFI calls to libgit2 happen.
  /// For now, returns mock data. In production, this will call FFI bindings.
  static GitResult<dynamic> _processCommand(GitCommand command) {
    // Register any credentials provided with this command in the registry
    _registerCredentials(command.credentials);

    // Route to handlers. Some use real libgit2 via FFI.
    if (command is OpenRepoCommand) {
      return _handleOpenRepo(command);
    } else if (command is GetStatusCommand) {
      return _handleGetStatus(command);
    } else if (command is CommitCommand) {
      return _handleCommit(command);
    } else if (command is PushCommand) {
      return _handlePush(command);
    } else if (command is FetchCommand) {
      return _handleFetch(command);
    } else if (command is PullCommand) {
      return _handlePull(command);
    } else if (command is GetDiffCommand) {
      return _handleGetDiff(command);
    } else if (command is GetHistoryCommand) {
      return _handleGetHistory(command);
    } else if (command is CloneRepoCommand) {
      return _handleClone(command);
    } else if (command is InitRepoCommand) {
      return _handleInit(command);
    } else if (command is GetRemotesCommand) {
      return _handleGetRemotes(command);
    } else if (command is AddRemoteCommand) {
      return _handleAddRemote(command);
    } else if (command is RemoveRemoteCommand) {
      return _handleRemoveRemote(command);
    } else if (command is SetRemoteUrlCommand) {
      return _handleSetRemoteUrl(command);
    } else if (command is ShutdownCommand) {
      debugPrint('[GitWorkerIsolate] Shutdown requested');
      return _handleShutdown();
    }

    return GitResult<dynamic>.failure('Unknown command: ${command.runtimeType}');
  }

  static void _registerCredentials(Map<String, GitCredentialInfo>? creds) {
    if (creds == null) return;
    creds.forEach((host, info) {
      final provider = CredentialsProvider(
        personalAccessToken: info.personalAccessToken,
        username: info.username,
        sshPrivateKeyPath: info.sshPrivateKeyPath,
        sshPublicKeyPath: info.sshPublicKeyPath,
        sshPassphrase: info.sshPassphrase,
      );
      if (host == '*') {
        CredentialsRegistry.registerGlobal(provider);
      } else {
        CredentialsRegistry.registerForHost(host, provider);
      }
    });
  }

  // Isolate-scoped state and FFI helpers
  static bool _ffiReady = false;
  static SendPort? _mainSendPort;
  static final Map<String, Pointer<git_repository>> _repos = {};

  // Error helpers
  static String _formatGitError(String op, int rc, {Pointer<git_remote>? remoteHandle, String? remoteName, String? repoPath}) {
    final info = LibGit2Bindings.lastError();
    String lastMsg = info?.message.trim() ?? '';
    String host = '';
    String remoteUrl = '';
    try {
      if (remoteHandle != null && remoteHandle.address != 0) {
        final urlPtr = LibGit2Bindings.I.remote_url(remoteHandle);
        remoteUrl = urlPtr.address == 0 ? '' : urlPtr.toDartString();
        host = _extractHost(remoteUrl);
      }
    } catch (_) {}

    final b = StringBuffer();
    if (remoteName != null && remoteName.isNotEmpty) {
      b.write('$op failed for "$remoteName"');
    } else if (repoPath != null) {
      b.write('$op failed for repository at $repoPath');
    } else {
      b.write('$op failed');
    }

    if (host.isNotEmpty) b.write(' (host: $host)');
    if (lastMsg.isNotEmpty) b.write(': $lastMsg');
    b.write(' [rc=$rc]');

    // Suggestions
    final lower = lastMsg.toLowerCase();
    String? tip;
    if (lower.contains('auth') || lower.contains('permission') || lower.contains('access denied') || lower.contains('401') || lower.contains('403')) {
      tip = 'Authentication failed. For HTTPS, use a Personal Access Token; for SSH, ensure your SSH key/agent is configured and your public key is added to the host.';
    } else if (lower.contains('ssl') || lower.contains('certificate') || lower.contains('x509')) {
      tip = 'Certificate verification issue. Check corporate proxy settings or install the required CA certificate.';
    } else if (lower.contains('resolve') || lower.contains('timeout') || lower.contains('network') || lower.contains('unreachable')) {
      tip = 'Network issue. Verify connectivity and proxy settings, then retry.';
    } else if (lower.contains('not found') || lower.contains('repository not found') || lower.contains('could not read from remote')) {
      tip = 'Repository or path may be incorrect, or you lack access. Verify the remote URL and permissions.';
    }
    if (tip != null) b.write(' Tip: $tip');
    return b.toString();
  }

  static String _extractHost(String url) {
    if (url.isEmpty) return '';
    try {
      if (url.contains('://')) {
        final u = Uri.parse(url);
        return u.host;
      }
      // SCP-like: user@host:path
      final at = url.indexOf('@');
      final colon = url.indexOf(':');
      if (at != -1 && colon != -1 && colon > at) {
        return url.substring(at + 1, colon);
      }
    } catch (_) {}
    return '';
  }

  // Status callback plumbing
  static final Map<int, _StatusCollector> _collectors = {};
  static int _nextCollectorId = 1;
  static NativeCallable<GitStatusCbNative>? _statusCb;
  static const int _kStatusCbError = -1;

  static Pointer<NativeFunction<GitStatusCbNative>> _getStatusCallbackPtr() {
    if (_statusCb == null) {
      _statusCb = NativeCallable<GitStatusCbNative>.isolateLocal(
        _statusCallback,
        exceptionalReturn: _kStatusCbError,
      );
    }
    return _statusCb!.nativeFunction;
  }

  static int _statusCallback(Pointer<Utf8> pathPtr, int statusFlags, Pointer<Void> payload) {
    try {
      final idPtr = payload.cast<Int64>();
      final id = idPtr.value;
      final collector = _collectors[id];
      if (collector == null) return 0;
      final path = pathPtr.toDartString();

      // Categorize
      final s = statusFlags;
      final isStaged = (s & (GitStatusFlags.indexNew | GitStatusFlags.indexModified | GitStatusFlags.indexDeleted | GitStatusFlags.indexRenamed | GitStatusFlags.indexTypeChange)) != 0;
      final isUntracked = (s & GitStatusFlags.wtNew) != 0;
      final isModified = (s & (GitStatusFlags.wtModified | GitStatusFlags.wtDeleted | GitStatusFlags.wtTypeChange | GitStatusFlags.wtRenamed)) != 0;

      if (isStaged) collector.staged.add(path);
      if (isUntracked) collector.untracked.add(path);
      if (isModified) collector.modified.add(path);
      return 0; // continue
    } catch (e) {
      debugPrint('[GitWorkerIsolate] status callback error: $e');
      return -1; // signal error to libgit2
    }
  }

  // Diff callbacks plumbing
  static final Map<int, _DiffCollector> _diffCollectors = {};
  static NativeCallable<GitDiffLineCbNative>? _diffLineCb;
  static const int _kDiffCbError = -1;

  static Pointer<NativeFunction<GitDiffLineCbNative>> _getDiffLineCallbackPtr() {
    if (_diffLineCb == null) {
      _diffLineCb = NativeCallable<GitDiffLineCbNative>.isolateLocal(
        _diffLineCallback,
        exceptionalReturn: _kDiffCbError,
      );
    }
    return _diffLineCb!.nativeFunction;
  }

  static int _diffLineCallback(Pointer<Void> delta, Pointer<Void> hunk, Pointer<git_diff_line> linePtr, Pointer<Void> payload) {
    try {
      final idPtr = payload.cast<Int64>();
      final id = idPtr.value;
      final coll = _diffCollectors[id];
      if (coll == null) return 0;

      final line = linePtr.ref;
      final originCode = line.origin;
      final origin = String.fromCharCode(originCode);
      final len = line.content_len;
      String content = '';
      if (line.content.address != 0 && len > 0) {
        final bytes = line.content.cast<Uint8>().asTypedList(len);
        content = utf8.decode(bytes, allowMalformed: true);
        if (content.endsWith('\n')) content = content.substring(0, content.length - 1);
        if (content.endsWith('\r')) content = content.substring(0, content.length - 1);
      }

      if (origin == 'H' || content.startsWith('@@')) {
        coll.startHunk(content);
        return 0;
      }

      String type = 'context';
      if (origin == '+') {
        type = 'added';
      } else if (origin == '-') {
        type = 'deleted';
      } else if (origin == ' ') {
        type = 'context';
      }
      coll.addLine(type, content, line.old_lineno, line.new_lineno);
      return 0;
    } catch (e) {
      debugPrint('[GitWorkerIsolate] diff line callback error: $e');
      return -1;
    }
  }

  // Network progress callbacks
  static NativeCallable<GitTransferProgressCbNative>? _transferProgressCb;
  static NativeCallable<GitSidebandProgressCbNative>? _sidebandProgressCb;

  static const int _kNetworkCbError = -1;

  static Pointer<NativeFunction<GitTransferProgressCbNative>> _getTransferProgressCallbackPtr() {
    _transferProgressCb ??= NativeCallable<GitTransferProgressCbNative>.isolateLocal(
      _transferProgressCallback,
      exceptionalReturn: _kNetworkCbError,
    );
    return _transferProgressCb!.nativeFunction;
  }

  static Pointer<NativeFunction<GitSidebandProgressCbNative>> _getSidebandProgressCallbackPtr() {
    _sidebandProgressCb ??= NativeCallable<GitSidebandProgressCbNative>.isolateLocal(
      _sidebandProgressCallback,
      exceptionalReturn: _kNetworkCbError,
    );
    return _sidebandProgressCb!.nativeFunction;
  }

  static int _transferProgressCallback(Pointer<git_transfer_progress> stats, Pointer<Void> payload) {
    if (_mainSendPort != null) {
      final s = stats.ref;
      // Send a side-channel message (not the final result)
      _mainSendPort!.send({
        'type': 'network_progress',
        'total_objects': s.total_objects,
        'indexed_objects': s.indexed_objects,
        'received_objects': s.received_objects,
        'received_bytes': s.received_bytes,
      });
    }
    return 0;
  }

  static int _sidebandProgressCallback(Pointer<Int8> str, int len, Pointer<Void> payload) {
    if (_mainSendPort != null && str.address != 0 && len > 0) {
      final bytes = str.cast<Uint8>().asTypedList(len);
      final message = utf8.decode(bytes, allowMalformed: true).trim();
      if (message.isNotEmpty) {
        _mainSendPort!.send({
          'type': 'sideband_progress',
          'message': message,
        });
      }
    }
    return 0;
  }

  // Error helpers


  /// Collector for status categories (use sets to avoid duplicates)

  // Handlers (real FFI-backed for OpenRepo/GetStatus)
  static GitResult<Map<String, dynamic>> _handleOpenRepo(OpenRepoCommand cmd) {
    debugPrint('[GitWorkerIsolate] Opening repo (FFI): ${cmd.path}');
    if (!_ffiReady) {
      return GitResult<Map<String, dynamic>>.failure('libgit2 is not initialized');
    }

    // If already opened, return ok
    final existing = _repos[cmd.path];
    if (existing != null) {
      return GitResult<Map<String, dynamic>>.success({'path': cmd.path});
    }

    final repoOut = calloc<Pointer<git_repository>>();
    final pathPtr = cmd.path.toNativeUtf8();
    try {
      final rc = LibGit2Bindings.I.repository_open(repoOut, pathPtr);
      if (rc != 0) {
        final msg = _formatGitError('Open repository', rc, repoPath: cmd.path);
        debugPrint('[GitWorkerIsolate] repository_open error rc=$rc: ${LibGit2Bindings.lastError()?.message}');
        return GitResult<Map<String, dynamic>>.failure(msg);
      }
      final repo = repoOut.value;
      _repos[cmd.path] = repo;
      return GitResult<Map<String, dynamic>>.success({'path': cmd.path});
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] OpenRepo error: $e\n$st');
      return GitResult<Map<String, dynamic>>.failure(e.toString());
    } finally {
      calloc.free(repoOut);
      malloc.free(pathPtr);
    }
  }

  static GitResult<Map<String, dynamic>> _handleGetStatus(GetStatusCommand cmd) {
    debugPrint('[GitWorkerIsolate] Getting status (FFI): ${cmd.repoPath}');
    if (!_ffiReady) {
      return GitResult<Map<String, dynamic>>.failure('libgit2 is not initialized');
    }
    var repo = _repos[cmd.repoPath];
    if (repo == null) {
      // Try to open on the fly
      final openRes = _handleOpenRepo(OpenRepoCommand(cmd.repoPath));
      if (!openRes.success) return GitResult<Map<String, dynamic>>.failure(openRes.error ?? 'open failed');
      repo = _repos[cmd.repoPath];
      if (repo == null) return GitResult<Map<String, dynamic>>.failure('Repository handle missing');
    }

    final collector = _StatusCollector();
    final id = _nextCollectorId++;
    final idPtr = calloc<Int64>();
    idPtr.value = id;
    _collectors[id] = collector;

    try {
      final cbPtr = _getStatusCallbackPtr();
      final rc = LibGit2Bindings.I.status_foreach(repo, cbPtr, idPtr.cast());
      if (rc != 0) {
        final msg = _formatGitError('Enumerate status', rc, repoPath: cmd.repoPath);
        debugPrint('[GitWorkerIsolate] status_foreach error rc=$rc: ${LibGit2Bindings.lastError()?.message}');
        return GitResult<Map<String, dynamic>>.failure(msg);
      }

      return GitResult<Map<String, dynamic>>.success({
        'modifiedFiles': collector.modified.toList(),
        'stagedFiles': collector.staged.toList(),
        'untrackedFiles': collector.untracked.toList(),
      });
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] GetStatus error: $e\n$st');
      return GitResult<Map<String, dynamic>>.failure(e.toString());
    } finally {
      _collectors.remove(id);
      calloc.free(idPtr);
    }
  }

  static GitResult<String> _handleCommit(CommitCommand cmd) {
    debugPrint('[GitWorkerIsolate] Committing (FFI): ${cmd.repoPath} :: ${cmd.files.length} files');
    if (!_ffiReady) {
      return GitResult<String>.failure('libgit2 is not initialized');
    }
    if (cmd.message.trim().isEmpty) {
      return GitResult<String>.failure('Commit message cannot be empty');
    }

    var repo = _repos[cmd.repoPath];
    if (repo == null) {
      final openRes = _handleOpenRepo(OpenRepoCommand(cmd.repoPath));
      if (!openRes.success) return GitResult<String>.failure(openRes.error ?? 'open failed');
      repo = _repos[cmd.repoPath];
      if (repo == null) return GitResult<String>.failure('Repository handle missing');
    }

    Pointer<git_index> index = Pointer.fromAddress(0);
    Pointer<git_tree> tree = Pointer.fromAddress(0);
    Pointer<git_commit> parent = Pointer.fromAddress(0);
    Pointer<git_signature> author = Pointer.fromAddress(0);
    Pointer<git_signature> committer = Pointer.fromAddress(0);

    final oidOut = calloc<git_oid>();
    final treeOid = calloc<git_oid>();
    final updateRef = 'HEAD'.toNativeUtf8();
    final messagePtr = cmd.message.toNativeUtf8();
    final namePtr = 'GitDesktop'.toNativeUtf8();
    final emailPtr = 'gitdesktop@example.com'.toNativeUtf8();

    try {
      // Index
      final indexOut = calloc<Pointer<git_index>>();
      try {
        var rc = LibGit2Bindings.I.repository_index(indexOut, repo);
        if (rc != 0) return GitResult<String>.failure(_formatGitError('Open index', rc, repoPath: cmd.repoPath));
        index = indexOut.value;

        // Stage provided files
        for (final f in cmd.files) {
          final p = f.toNativeUtf8();
          try {
            rc = LibGit2Bindings.I.index_add_bypath(index, p);
            if (rc != 0) return GitResult<String>.failure(_formatGitError('Stage file "$f"', rc, repoPath: cmd.repoPath));
          } finally {
            malloc.free(p);
          }
        }

        // Write index to disk and create tree
        rc = LibGit2Bindings.I.index_write(index);
        if (rc != 0) return GitResult<String>.failure(_formatGitError('Write index', rc, repoPath: cmd.repoPath));
        rc = LibGit2Bindings.I.index_write_tree(treeOid, index);
        if (rc != 0) return GitResult<String>.failure(_formatGitError('Write tree', rc, repoPath: cmd.repoPath));
      } finally {
        calloc.free(indexOut);
      }

      // Lookup tree object from OID
      final treeOut = calloc<Pointer<git_tree>>();
      try {
        final rc = LibGit2Bindings.I.tree_lookup(treeOut, repo, treeOid);
        if (rc != 0) return GitResult<String>.failure(_formatGitError('Lookup tree', rc, repoPath: cmd.repoPath));
        tree = treeOut.value;
      } finally {
        calloc.free(treeOut);
      }

      // Optional parent from HEAD (may be unborn)
      final headOid = calloc<git_oid>();
      final headName = 'HEAD'.toNativeUtf8();
      try {
        final rcHead = LibGit2Bindings.I.reference_name_to_id(headOid, repo, headName);
        if (rcHead == 0) {
          final parentOut = calloc<Pointer<git_commit>>();
          try {
            final rcPL = LibGit2Bindings.I.commit_lookup(parentOut, repo, headOid);
            if (rcPL == 0) parent = parentOut.value;
          } finally {
            calloc.free(parentOut);
          }
        }
      } finally {
        malloc.free(headName);
        calloc.free(headOid);
      }

      // Signatures
      final authorOut = calloc<Pointer<git_signature>>();
      final committerOut = calloc<Pointer<git_signature>>();
      try {
        var rc = LibGit2Bindings.I.signature_now(authorOut, namePtr, emailPtr);
        if (rc != 0) return GitResult<String>.failure(_formatGitError('Create author signature', rc));
        author = authorOut.value;
        rc = LibGit2Bindings.I.signature_now(committerOut, namePtr, emailPtr);
        if (rc != 0) return GitResult<String>.failure(_formatGitError('Create committer signature', rc));
        committer = committerOut.value;
      } finally {
        calloc.free(authorOut);
        calloc.free(committerOut);
      }

      // Parents array (0 or 1)
      int parentCount = 0;
      Pointer<Pointer<git_commit>> parentsPtr = Pointer.fromAddress(0);
      if (parent.address != 0) {
        parentCount = 1;
        parentsPtr = calloc<Pointer<git_commit>>(1);
        parentsPtr[0] = parent;
      }

      try {
        final rc = LibGit2Bindings.I.commit_create(
          oidOut,
          repo,
          updateRef,
          author,
          committer,
          Pointer.fromAddress(0), // messageEncoding = NULL (UTF-8)
          messagePtr,
          tree,
          parentCount,
          parentsPtr,
        );
        if (rc != 0) return GitResult<String>.failure(_formatGitError('Create commit', rc, repoPath: cmd.repoPath));
      } finally {
        if (parentCount > 0) calloc.free(parentsPtr);
      }

      // Convert OID to hex
      final hex = _oidToHex(oidOut);
      return GitResult<String>.success(hex);
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] Commit error: $e\n$st');
      return GitResult<String>.failure(e.toString());
    } finally {
      // Free all
      if (author.address != 0) { try { LibGit2Bindings.I.signature_free(author); } catch (_) {} }
      if (committer.address != 0) { try { LibGit2Bindings.I.signature_free(committer); } catch (_) {} }
      if (parent.address != 0) { try { LibGit2Bindings.I.commit_free(parent); } catch (_) {} }
      if (tree.address != 0) { try { LibGit2Bindings.I.tree_free(tree); } catch (_) {} }
      if (index.address != 0) { try { LibGit2Bindings.I.index_free(index); } catch (_) {} }
      malloc.free(updateRef);
      malloc.free(messagePtr);
      malloc.free(namePtr);
      malloc.free(emailPtr);
      calloc.free(oidOut);
      calloc.free(treeOid);
    }
  }

  static GitResult<void> _handlePush(PushCommand cmd) {
    debugPrint('[GitWorkerIsolate] Push start (FFI): ${cmd.repoPath} :: ${cmd.remote}/${cmd.branch} force=${cmd.force}');
    if (!_ffiReady) return GitResult<void>.failure('libgit2 is not initialized');
    var repo = _repos[cmd.repoPath];
    if (repo == null) {
      final openRes = _handleOpenRepo(OpenRepoCommand(cmd.repoPath));
      if (!openRes.success) return GitResult<void>.failure(openRes.error ?? 'open failed');
      repo = _repos[cmd.repoPath];
      if (repo == null) return GitResult<void>.failure('Repository handle missing');
    }

    final remoteOut = calloc<Pointer<git_remote>>();
    final remoteName = cmd.remote.toNativeUtf8();
    Pointer<Utf8> specPtr = Pointer.fromAddress(0);
    Pointer<Pointer<Int8>> stringsPtr = Pointer.fromAddress(0);
    final arr = calloc<git_strarray>();
    Pointer<git_reference> headRef = Pointer.fromAddress(0);
    try {
      final rcL = LibGit2Bindings.I.remote_lookup(remoteOut, repo!, remoteName);
      if (rcL != 0) return GitResult<void>.failure(_formatGitError('Lookup remote', rcL, remoteName: cmd.remote));
      final remote = remoteOut.value;

      // Log auth context
      _logAuthContextForRemote(remote);

      final refspec = (cmd.force ? '+' : '') + 'refs/heads/${cmd.branch}:refs/heads/${cmd.branch}';
      specPtr = refspec.toNativeUtf8();
      stringsPtr = calloc<Pointer<Int8>>(1);
      stringsPtr[0] = specPtr.cast<Int8>();
      arr.ref
        ..strings = stringsPtr
        ..count = 1;

      debugPrint('[GitWorkerIsolate] Push refspec: $refspec');
      
      final pushOpts = calloc<git_push_options>();
      try {
        LibGit2Bindings.I.push_init_options(pushOpts, 1);
        pushOpts.ref.callbacks.credentials = CredentialsProvider.getSharedCallbackPointer();
        pushOpts.ref.callbacks.version = 1;

        final rcP = LibGit2Bindings.I.remote_push(remote, arr, pushOpts);
        if (rcP != 0) return GitResult<void>.failure(_formatGitError('Push', rcP, remoteHandle: remote, remoteName: cmd.remote));
      } finally {
        calloc.free(pushOpts);
      }

      // Basic progress summary if available
      try {
        final stats = LibGit2Bindings.I.remote_stats(remote);
        if (stats.address != 0) {
          debugPrint('[GitWorkerIsolate] Push stats: sentObjects=${stats.ref.indexed_objects}/${stats.ref.total_objects} deltas=${stats.ref.indexed_deltas}/${stats.ref.total_deltas} bytes=${stats.ref.received_bytes}');
        }
      } catch (e) {
        debugPrint('[GitWorkerIsolate] Push stats unavailable: $e');
      }

      // Ensure current branch tracks remote if missing (post-push)
      final headOut = calloc<Pointer<git_reference>>();
      try {
        final rcHead = LibGit2Bindings.I.repository_head(headOut, repo);
        if (rcHead == 0 && headOut.value.address != 0) {
          headRef = headOut.value;
          final fullNamePtr = LibGit2Bindings.I.reference_name(headRef);
          final fullName = fullNamePtr.address == 0 ? '' : fullNamePtr.toDartString();
          const prefix = 'refs/heads/';
          if (fullName.startsWith(prefix)) {
            final branch = fullName.substring(prefix.length);
            final upOut = calloc<Pointer<git_reference>>();
            try {
              final rcUp = LibGit2Bindings.I.branch_upstream(upOut, headRef);
              if (rcUp != 0) {
                final upstreamName = '${cmd.remote}/$branch'.toNativeUtf8();
                try {
                  final rcSet = LibGit2Bindings.I.branch_set_upstream(headRef, upstreamName);
                  if (rcSet == 0) {
                    debugPrint('[GitWorkerIsolate] Set upstream after push: $branch -> ${cmd.remote}/$branch');
                  } else {
                    debugPrint('[GitWorkerIsolate] Failed to set upstream post-push (rc=$rcSet): ${LibGit2Bindings.lastError()?.message}');
                  }
                } finally {
                  malloc.free(upstreamName);
                }
              }
            } finally {
              if (upOut.value.address != 0) {
                try { LibGit2Bindings.I.reference_free(upOut.value); } catch (_) {}
              }
              calloc.free(upOut);
            }
          }
        }
      } finally {
        if (headRef.address != 0) {
          try { LibGit2Bindings.I.reference_free(headRef); } catch (_) {}
        }
        calloc.free(headOut);
      }

      debugPrint('[GitWorkerIsolate] Push done: ${cmd.remote}/${cmd.branch}');
      return const GitResult<void>.success(null);
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] Push error: $e\n$st');
      return GitResult<void>.failure(e.toString());
    } finally {
      if (remoteOut.value.address != 0) {
        try { LibGit2Bindings.I.remote_free(remoteOut.value); } catch (_) {}
      }
      calloc.free(remoteOut);
      if (specPtr.address != 0) malloc.free(specPtr);
      if (stringsPtr.address != 0) calloc.free(stringsPtr);
      calloc.free(arr);
      malloc.free(remoteName);
    }
  }

  static GitResult<void> _handleFetch(FetchCommand cmd) {
    debugPrint('[GitWorkerIsolate] Fetching (FFI): ${cmd.repoPath} :: ${cmd.remote}');
    if (!_ffiReady) {
      return GitResult<void>.failure('libgit2 is not initialized');
    }
    var repo = _repos[cmd.repoPath];
    if (repo == null) {
      final openRes = _handleOpenRepo(OpenRepoCommand(cmd.repoPath));
      if (!openRes.success) return GitResult<void>.failure(openRes.error ?? 'open failed');
      repo = _repos[cmd.repoPath];
      if (repo == null) return GitResult<void>.failure('Repository handle missing');
    }

    final remoteOut = calloc<Pointer<git_remote>>();
    final namePtr = cmd.remote.toNativeUtf8();
    Pointer<git_reference> headRef = Pointer.fromAddress(0);
    try {
      final rcLookup = LibGit2Bindings.I.remote_lookup(remoteOut, repo!, namePtr);
      if (rcLookup != 0) return GitResult<void>.failure(_formatGitError('Lookup remote', rcLookup, remoteName: cmd.remote));
      final remote = remoteOut.value;

      // Log auth context
      _logAuthContextForRemote(remote);

      final fetchOpts = calloc<git_fetch_options>();
      try {
        LibGit2Bindings.I.fetch_init_options(fetchOpts, 1);
        fetchOpts.ref.callbacks.credentials = CredentialsProvider.getSharedCallbackPointer();
        fetchOpts.ref.callbacks.version = 1;

        debugPrint('[GitWorkerIsolate] Fetch start: remote=${cmd.remote}');
        final rcFetch = LibGit2Bindings.I.remote_fetch(
          remote,
          Pointer.fromAddress(0),
          fetchOpts,
          Pointer.fromAddress(0),
        );
        if (rcFetch != 0) {
          return GitResult<void>.failure(_formatGitError('Fetch', rcFetch, remoteHandle: remote, remoteName: cmd.remote));
        }
      } finally {
        calloc.free(fetchOpts);
      }
      // Basic progress summary
      try {
        final stats = LibGit2Bindings.I.remote_stats(remote);
        if (stats.address != 0) {
          debugPrint('[GitWorkerIsolate] Fetch stats: receivedObjects=${stats.ref.received_objects}/${stats.ref.total_objects} deltas=${stats.ref.indexed_deltas}/${stats.ref.total_deltas} bytes=${stats.ref.received_bytes}');
        }
      } catch (e) {
        debugPrint('[GitWorkerIsolate] Fetch stats unavailable: $e');
      }

      // Ensure current branch tracks remote if missing
      final headOut = calloc<Pointer<git_reference>>();
      try {
        final rcHead = LibGit2Bindings.I.repository_head(headOut, repo);
        if (rcHead == 0 && headOut.value.address != 0) {
          headRef = headOut.value;
          final fullNamePtr = LibGit2Bindings.I.reference_name(headRef);
          final fullName = fullNamePtr.address == 0 ? '' : fullNamePtr.toDartString();
          // Expect refs/heads/<branch>
          const prefix = 'refs/heads/';
          if (fullName.startsWith(prefix)) {
            final branch = fullName.substring(prefix.length);
            // Check if upstream already set
            final upOut = calloc<Pointer<git_reference>>();
            try {
              final rcUp = LibGit2Bindings.I.branch_upstream(upOut, headRef);
              if (rcUp != 0) {
                final upstreamName = '${cmd.remote}/$branch'.toNativeUtf8();
                try {
                  final rcSet = LibGit2Bindings.I.branch_set_upstream(headRef, upstreamName);
                  if (rcSet == 0) {
                    debugPrint('[GitWorkerIsolate] Set upstream: $branch -> ${cmd.remote}/$branch');
                  } else {
                    debugPrint('[GitWorkerIsolate] Failed to set upstream (rc=$rcSet): ${LibGit2Bindings.lastError()?.message}');
                  }
                } finally {
                  malloc.free(upstreamName);
                }
              } else {
                debugPrint('[GitWorkerIsolate] Upstream already configured for $branch');
              }
            } finally {
              if (upOut.value.address != 0) {
                try { LibGit2Bindings.I.reference_free(upOut.value); } catch (_) {}
              }
              calloc.free(upOut);
            }
          } else {
            debugPrint('[GitWorkerIsolate] HEAD is not a local branch: $fullName');
          }
        } else {
          debugPrint('[GitWorkerIsolate] repository_head failed (rc=$rcHead) – unborn HEAD?');
        }
      } finally {
        if (headRef.address != 0) {
          try { LibGit2Bindings.I.reference_free(headRef); } catch (_) {}
        }
        calloc.free(headOut);
      }

      debugPrint('[GitWorkerIsolate] Fetch done: remote=${cmd.remote}');
      return const GitResult<void>.success(null);
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] Fetch error: $e\n$st');
      return GitResult<void>.failure(e.toString());
    } finally {
      if (remoteOut.value.address != 0) {
        try { LibGit2Bindings.I.remote_free(remoteOut.value); } catch (_) {}
      }
      calloc.free(remoteOut);
      malloc.free(namePtr);
    }
  }

  /// Logs which credentials (if any) are available for the given remote.
  static void _logAuthContextForRemote(Pointer<git_remote> remote) {
    try {
      final urlPtr = LibGit2Bindings.I.remote_url(remote);
      final url = urlPtr.address == 0 ? '' : urlPtr.toDartString();
      final host = _extractHost(url);
      final hasProvider = CredentialsRegistry.resolveForHost(host) != null;
      if (hasProvider) {
        debugPrint('[GitWorkerIsolate] Auth available for host=$host (url=$url)');
      } else {
        debugPrint('[GitWorkerIsolate] No auth registered for host=$host (url=$url)');
      }
    } catch (e) {
      debugPrint('[GitWorkerIsolate] Auth context check failed: $e');
    }
  }

  static GitResult<void> _handlePull(PullCommand cmd) {
    debugPrint('[GitWorkerIsolate] Pull (FF-only, FFI): ${cmd.repoPath} :: ${cmd.remote}/${cmd.branch}');
    if (!_ffiReady) return GitResult<void>.failure('libgit2 is not initialized');
    var repo = _repos[cmd.repoPath];
    if (repo == null) {
      final openRes = _handleOpenRepo(OpenRepoCommand(cmd.repoPath));
      if (!openRes.success) return GitResult<void>.failure(openRes.error ?? 'open failed');
      repo = _repos[cmd.repoPath];
      if (repo == null) return GitResult<void>.failure('Repository handle missing');
    }

    final remoteOut = calloc<Pointer<git_remote>>();
    final remoteName = cmd.remote.toNativeUtf8();
    final localRef = 'refs/heads/${cmd.branch}'.toNativeUtf8();
    final remoteRef = 'refs/remotes/${cmd.remote}/${cmd.branch}'.toNativeUtf8();
    final oidLocal = calloc<git_oid>();
    final oidRemote = calloc<git_oid>();
    final oidBase = calloc<git_oid>();
    Pointer<git_commit> remoteCommit = Pointer.fromAddress(0);
    try {
      // Fetch first
      final rcL = LibGit2Bindings.I.remote_lookup(remoteOut, repo!, remoteName);
      if (rcL != 0) return GitResult<void>.failure(_formatGitError('Lookup remote', rcL, remoteName: cmd.remote));
      final remote = remoteOut.value;

      final fetchOpts = calloc<git_fetch_options>();
      try {
        LibGit2Bindings.I.fetch_init_options(fetchOpts, 1);
        fetchOpts.ref.callbacks.credentials = CredentialsProvider.getSharedCallbackPointer();
        fetchOpts.ref.callbacks.version = 1;

        final rcF = LibGit2Bindings.I.remote_fetch(remote, Pointer.fromAddress(0), fetchOpts, Pointer.fromAddress(0));
        if (rcF != 0) return GitResult<void>.failure(_formatGitError('Fetch', rcF, remoteHandle: remote, remoteName: cmd.remote));
      } finally {
        calloc.free(fetchOpts);
      }

      // Resolve OIDs
      final rcLocal = LibGit2Bindings.I.reference_name_to_id(oidLocal, repo, localRef);
      if (rcLocal != 0) return GitResult<void>.failure(_formatGitError('Resolve local branch', rcLocal, repoPath: cmd.repoPath));
      final rcRemote = LibGit2Bindings.I.reference_name_to_id(oidRemote, repo, remoteRef);
      if (rcRemote != 0) return GitResult<void>.failure(_formatGitError('Resolve remote tracking branch', rcRemote, remoteName: cmd.remote));

      // Check fast-forward: merge_base(local, remote) == local
      final rcBase = LibGit2Bindings.I.merge_base(oidBase, repo, oidLocal, oidRemote);
      if (rcBase != 0) return GitResult<void>.failure(_formatGitError('Compute merge base', rcBase, repoPath: cmd.repoPath));

      final isFF = _oidEquals(oidBase, oidLocal);
      if (!isFF) {
        return GitResult<void>.failure('Non-fast-forward update. Please rebase or merge.');
      }

      // Reset --hard to remote commit
      final cOut = calloc<Pointer<git_commit>>();
      try {
        final rcCL = LibGit2Bindings.I.commit_lookup(cOut, repo, oidRemote);
        if (rcCL != 0) return GitResult<void>.failure(_formatGitError('Lookup remote commit', rcCL));
        remoteCommit = cOut.value;
      } finally {
        calloc.free(cOut);
      }
      final rcReset = LibGit2Bindings.I.reset(repo, remoteCommit.cast<git_object>(), 2, Pointer.fromAddress(0)); // HARD=2
      if (rcReset != 0) return GitResult<void>.failure(_formatGitError('Reset to remote', rcReset, remoteName: cmd.remote));

      return const GitResult<void>.success(null);
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] Pull error: $e\n$st');
      return GitResult<void>.failure(e.toString());
    } finally {
      if (remoteOut.value.address != 0) {
        try { LibGit2Bindings.I.remote_free(remoteOut.value); } catch (_) {}
      }
      calloc.free(remoteOut);
      malloc.free(remoteName);
      malloc.free(localRef);
      malloc.free(remoteRef);
      calloc.free(oidLocal);
      calloc.free(oidRemote);
      calloc.free(oidBase);
      if (remoteCommit.address != 0) {
        try { LibGit2Bindings.I.commit_free(remoteCommit); } catch (_) {}
      }
    }
  }

  static GitResult<List<Map<String, dynamic>>> _handleGetDiff(GetDiffCommand cmd) {
    debugPrint('[GitWorkerIsolate] Getting diff (FFI): ${cmd.repoPath} :: ${cmd.filePath}');
    if (!_ffiReady) {
      return GitResult<List<Map<String, dynamic>>>.failure('libgit2 is not initialized');
    }
    var repo = _repos[cmd.repoPath];
    if (repo == null) {
      final openRes = _handleOpenRepo(OpenRepoCommand(cmd.repoPath));
      if (!openRes.success) return GitResult<List<Map<String, dynamic>>>.failure(openRes.error ?? 'open failed');
      repo = _repos[cmd.repoPath];
      if (repo == null) return GitResult<List<Map<String, dynamic>>>.failure('Repository handle missing');
    }

    final pathPtr = cmd.filePath.toNativeUtf8();
    Pointer<git_blob> oldBlob = Pointer.fromAddress(0);
    Pointer<git_blob> newBlob = Pointer.fromAddress(0);

    // Resolve HEAD blob for file (may fail on unborn HEAD or file added)
    final oidOut = calloc<git_oid>();
    final commitOut = calloc<Pointer<git_commit>>();
    final treeOut = calloc<Pointer<git_tree>>();
    final entryOut = calloc<Pointer<git_tree_entry>>();
    try {
      final headName = 'HEAD'.toNativeUtf8();
      try {
        final rcOid = LibGit2Bindings.I.reference_name_to_id(oidOut, repo, headName);
        if (rcOid == 0) {
          final rcCommit = LibGit2Bindings.I.commit_lookup(commitOut, repo, oidOut);
          if (rcCommit == 0) {
            final rcTree = LibGit2Bindings.I.commit_tree(treeOut, commitOut.value);
            if (rcTree == 0) {
              final rcEntry = LibGit2Bindings.I.tree_entry_bypath(entryOut, treeOut.value, pathPtr);
              if (rcEntry == 0) {
                final entryOid = LibGit2Bindings.I.tree_entry_id(entryOut.value);
                final oldBlobOut = calloc<Pointer<git_blob>>();
                try {
                  final rcBlob = LibGit2Bindings.I.blob_lookup(oldBlobOut, repo, entryOid);
                  if (rcBlob == 0) {
                    oldBlob = oldBlobOut.value;
                  }
                } finally {
                  calloc.free(oldBlobOut);
                }
              } else {
                debugPrint('[GitWorkerIsolate] tree_entry_bypath failed (file may be new): rc=$rcEntry');
              }
            }
          }
        } else {
          debugPrint('[GitWorkerIsolate] reference_name_to_id(HEAD) failed: rc=$rcOid');
        }
      } finally {
        malloc.free(headName);
      }

      // Working directory blob for file (may fail if deleted)
      final newBlobOut = calloc<Pointer<git_blob>>();
      try {
        final rcNew = LibGit2Bindings.I.blob_create_fromworkdir(newBlobOut, repo, pathPtr);
        if (rcNew == 0) {
          newBlob = newBlobOut.value;
        } else {
          debugPrint('[GitWorkerIsolate] blob_create_fromworkdir failed (file may be deleted): rc=$rcNew');
        }
      } finally {
        calloc.free(newBlobOut);
      }

      // Prepare collector and native callback
      final coll = _DiffCollector();
      final id = _nextCollectorId++;
      final idPtr = calloc<Int64>();
      idPtr.value = id;
      _diffCollectors[id] = coll;

      try {
        final lineCb = _getDiffLineCallbackPtr();
        final rc = LibGit2Bindings.I.diff_blobs(
          oldBlob,
          pathPtr,
          newBlob,
          pathPtr,
          Pointer.fromAddress(0), // options = NULL
          Pointer.fromAddress(0), // file_cb = NULL
          Pointer.fromAddress(0), // binary_cb = NULL
          Pointer.fromAddress(0), // hunk_cb = NULL
          lineCb,
          idPtr.cast(),
        );

        if (rc != 0) {
          return GitResult<List<Map<String, dynamic>>>.failure(_formatGitError('Diff blobs', rc, repoPath: cmd.repoPath));
        }

        // Flush any pending hunk
        coll.finishCurrentHunkIfAny();
        return GitResult<List<Map<String, dynamic>>>.success(coll.toJson());
      } catch (e, st) {
        debugPrint('[GitWorkerIsolate] GetDiff error: $e\n$st');
        return GitResult<List<Map<String, dynamic>>>.failure(e.toString());
      } finally {
        _diffCollectors.remove(id);
        calloc.free(idPtr);
      }
    } finally {
      // Free resources
      if (oldBlob.address != 0) {
        try { LibGit2Bindings.I.blob_free(oldBlob); } catch (_) {}
      }
      if (newBlob.address != 0) {
        try { LibGit2Bindings.I.blob_free(newBlob); } catch (_) {}
      }
      if (entryOut.value.address != 0) {
        try { LibGit2Bindings.I.tree_entry_free(entryOut.value); } catch (_) {}
      }
      if (treeOut.value.address != 0) {
        try { LibGit2Bindings.I.tree_free(treeOut.value); } catch (_) {}
      }
      if (commitOut.value.address != 0) {
        try { LibGit2Bindings.I.commit_free(commitOut.value); } catch (_) {}
      }
      calloc.free(oidOut);
      calloc.free(commitOut);
      calloc.free(treeOut);
      calloc.free(entryOut);
      malloc.free(pathPtr);
    }
  }

  static GitResult<List<Map<String, dynamic>>> _handleGetHistory(GetHistoryCommand cmd) {
    debugPrint('[GitWorkerIsolate] Getting history (FFI): ${cmd.repoPath} (limit: ${cmd.limit})');
    if (!_ffiReady) {
      return GitResult<List<Map<String, dynamic>>>.failure('libgit2 is not initialized');
    }
    var repo = _repos[cmd.repoPath];
    if (repo == null) {
      final openRes = _handleOpenRepo(OpenRepoCommand(cmd.repoPath));
      if (!openRes.success) return GitResult<List<Map<String, dynamic>>>.failure(openRes.error ?? 'open failed');
      repo = _repos[cmd.repoPath];
      if (repo == null) return GitResult<List<Map<String, dynamic>>>.failure('Repository handle missing');
    }

    final walkOut = calloc<Pointer<git_revwalk>>();
    final oid = calloc<git_oid>();
    final items = <Map<String, dynamic>>[];
    try {
      var rc = LibGit2Bindings.I.revwalk_new(walkOut, repo);
      if (rc != 0) return GitResult<List<Map<String, dynamic>>>.failure(_formatGitError('Start revision walk', rc, repoPath: cmd.repoPath));
      final walk = walkOut.value;
      // Sort by time, then topo
      LibGit2Bindings.I.revwalk_sorting(walk, GitSortMode.time | GitSortMode.topological);
      rc = LibGit2Bindings.I.revwalk_push_head(walk);
      if (rc != 0) return GitResult<List<Map<String, dynamic>>>.failure(_formatGitError('Walk from HEAD', rc, repoPath: cmd.repoPath));

      int count = 0;
      while (count < cmd.limit) {
        rc = LibGit2Bindings.I.revwalk_next(oid, walk);
        if (rc != 0) break; // 0 on success, non-zero when done

        final commitOut = calloc<Pointer<git_commit>>();
        try {
          final rc2 = LibGit2Bindings.I.commit_lookup(commitOut, repo, oid);
          if (rc2 != 0) break;
          final commit = commitOut.value;
          final hex = _oidToHex(oid);
          final msgPtr = LibGit2Bindings.I.commit_message(commit);
          final msg = msgPtr.address == 0 ? '' : msgPtr.toDartString();
          final authorPtr = LibGit2Bindings.I.commit_author(commit);
          String author = 'unknown';
          if (authorPtr.address != 0) {
            final namePtr = authorPtr.ref.name;
            final emailPtr = authorPtr.ref.email;
            final name = namePtr.address == 0 ? '' : namePtr.cast<Utf8>().toDartString();
            final email = emailPtr.address == 0 ? '' : emailPtr.cast<Utf8>().toDartString();
            author = email.isEmpty ? name : '$name <$email>';
          }
          final when = LibGit2Bindings.I.commit_time(commit);

          items.add({
            'hash': hex,
            'message': msg,
            'author': author,
            'timestamp': when * 1000, // seconds -> ms
          });
          count++;
        } finally {
          if (commitOut.value.address != 0) {
            try { LibGit2Bindings.I.commit_free(commitOut.value); } catch (_) {}
          }
          calloc.free(commitOut);
        }
      }

      return GitResult<List<Map<String, dynamic>>>.success(items);
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] GetHistory error: $e\n$st');
      return GitResult<List<Map<String, dynamic>>>.failure(e.toString());
    } finally {
      if (walkOut.value.address != 0) {
        try { LibGit2Bindings.I.revwalk_free(walkOut.value); } catch (_) {}
      }
      calloc.free(walkOut);
      calloc.free(oid);
    }
  }

  static GitResult<Map<String, dynamic>> _handleClone(CloneRepoCommand cmd) {
    // TODO: Call git_clone() via FFI with progress + credentials callbacks
    debugPrint('[GitWorkerIsolate] Cloning ${cmd.url} -> ${cmd.destinationPath}');
    // Simulate success
    return GitResult<Map<String, dynamic>>.success({
      'url': cmd.url,
      'path': cmd.destinationPath,
      'branch': 'main',
    });
  }

  static GitResult<Map<String, dynamic>> _handleInit(InitRepoCommand cmd) {
    // TODO: Call git_repository_init() via FFI
    debugPrint('[GitWorkerIsolate] Initializing new repo at ${cmd.path}');
    return GitResult<Map<String, dynamic>>.success({
      'path': cmd.path,
      'branch': 'main',
      'empty': true,
    });
  }

  static GitResult<List<Map<String, String>>> _handleGetRemotes(GetRemotesCommand cmd) {
    debugPrint('[GitWorkerIsolate] Listing remotes (FFI): ${cmd.repoPath}');
    if (!_ffiReady) {
      return GitResult<List<Map<String, String>>>.failure('libgit2 is not initialized');
    }
    var repo = _repos[cmd.repoPath];
    if (repo == null) {
      final openRes = _handleOpenRepo(OpenRepoCommand(cmd.repoPath));
      if (!openRes.success) return GitResult<List<Map<String, String>>>.failure(openRes.error ?? 'open failed');
      repo = _repos[cmd.repoPath];
      if (repo == null) return GitResult<List<Map<String, String>>>.failure('Repository handle missing');
    }

    final arr = calloc<git_strarray>();
    final results = <Map<String, String>>[];
    try {
      final rc = LibGit2Bindings.I.remote_list(arr, repo);
      if (rc != 0) {
        final msg = _formatGitError('List remotes', rc, repoPath: cmd.repoPath);
        debugPrint('[GitWorkerIsolate] remote_list error rc=$rc: ${LibGit2Bindings.lastError()?.message}');
        return GitResult<List<Map<String, String>>>.failure(msg);
      }
      final count = arr.ref.count;
      final basePtr = arr.ref.strings;
      for (var i = 0; i < count; i++) {
        final namePtr = basePtr.elementAt(i).value;
        final name = namePtr.address == 0 ? '' : namePtr.cast<Utf8>().toDartString();
        if (name.isEmpty) continue;
        final remoteOut = calloc<Pointer<git_remote>>();
        final nameC = name.toNativeUtf8();
        try {
          final rcL = LibGit2Bindings.I.remote_lookup(remoteOut, repo, nameC);
          if (rcL == 0) {
            final remote = remoteOut.value;
            final urlPtr = LibGit2Bindings.I.remote_url(remote);
            final url = urlPtr.address == 0 ? '' : urlPtr.toDartString();
            results.add({'name': name, 'url': url});
            try { LibGit2Bindings.I.remote_free(remote); } catch (_) {}
          } else {
            results.add({'name': name, 'url': ''});
          }
        } finally {
          calloc.free(remoteOut);
          malloc.free(nameC);
        }
      }
      return GitResult<List<Map<String, String>>>.success(results);
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] GetRemotes error: $e\n$st');
      return GitResult<List<Map<String, String>>>.failure(e.toString());
    } finally {
      try { LibGit2Bindings.I.strarray_dispose(arr); } catch (_) {}
      calloc.free(arr);
    }
  }

  static GitResult<void> _handleAddRemote(AddRemoteCommand cmd) {
    debugPrint('[GitWorkerIsolate] Adding remote (FFI): ${cmd.repoPath} :: ${cmd.name} -> ${cmd.url}');
    if (!_ffiReady) {
      return GitResult<void>.failure('libgit2 is not initialized');
    }
    var repo = _repos[cmd.repoPath];
    if (repo == null) {
      final openRes = _handleOpenRepo(OpenRepoCommand(cmd.repoPath));
      if (!openRes.success) return GitResult<void>.failure(openRes.error ?? 'open failed');
      repo = _repos[cmd.repoPath];
      if (repo == null) return GitResult<void>.failure('Repository handle missing');
    }

    final out = calloc<Pointer<git_remote>>();
    final namePtr = cmd.name.toNativeUtf8();
    final urlPtr = cmd.url.toNativeUtf8();
    try {
      final rc = LibGit2Bindings.I.remote_create(out, repo!, namePtr, urlPtr);
      if (rc != 0) return GitResult<void>.failure('git_remote_create failed (rc=$rc)');
      // Free the created remote handle
      if (out.value.address != 0) {
        try { LibGit2Bindings.I.remote_free(out.value); } catch (_) {}
      }
      return const GitResult<void>.success(null);
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] AddRemote error: $e\n$st');
      return GitResult<void>.failure(e.toString());
    } finally {
      calloc.free(out);
      malloc.free(namePtr);
      malloc.free(urlPtr);
    }
  }

  static GitResult<void> _handleRemoveRemote(RemoveRemoteCommand cmd) {
    debugPrint('[GitWorkerIsolate] Removing remote (FFI): ${cmd.repoPath} :: ${cmd.name}');
    if (!_ffiReady) {
      return GitResult<void>.failure('libgit2 is not initialized');
    }
    var repo = _repos[cmd.repoPath];
    if (repo == null) {
      final openRes = _handleOpenRepo(OpenRepoCommand(cmd.repoPath));
      if (!openRes.success) return GitResult<void>.failure(openRes.error ?? 'open failed');
      repo = _repos[cmd.repoPath];
      if (repo == null) return GitResult<void>.failure('Repository handle missing');
    }

    final namePtr = cmd.name.toNativeUtf8();
    try {
      final rc = LibGit2Bindings.I.remote_delete(repo!, namePtr);
      if (rc != 0) return GitResult<void>.failure('git_remote_delete failed (rc=$rc)');
      return const GitResult<void>.success(null);
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] RemoveRemote error: $e\n$st');
      return GitResult<void>.failure(e.toString());
    } finally {
      malloc.free(namePtr);
    }
  }

  static GitResult<void> _handleSetRemoteUrl(SetRemoteUrlCommand cmd) {
    debugPrint('[GitWorkerIsolate] Setting remote URL (FFI): ${cmd.repoPath} :: ${cmd.name} -> ${cmd.url}');
    if (!_ffiReady) {
      return GitResult<void>.failure('libgit2 is not initialized');
    }
    var repo = _repos[cmd.repoPath];
    if (repo == null) {
      final openRes = _handleOpenRepo(OpenRepoCommand(cmd.repoPath));
      if (!openRes.success) return GitResult<void>.failure(openRes.error ?? 'open failed');
      repo = _repos[cmd.repoPath];
      if (repo == null) return GitResult<void>.failure('Repository handle missing');
    }

    final namePtr = cmd.name.toNativeUtf8();
    final urlPtr = cmd.url.toNativeUtf8();
    try {
      final rc = LibGit2Bindings.I.remote_set_url(repo!, namePtr, urlPtr);
      if (rc != 0) return GitResult<void>.failure('git_remote_set_url failed (rc=$rc)');
      return const GitResult<void>.success(null);
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] SetRemoteUrl error: $e\n$st');
      return GitResult<void>.failure(e.toString());
    } finally {
      malloc.free(namePtr);
      malloc.free(urlPtr);
    }
  }

  // Cleanup on shutdown: free repositories and shutdown libgit2
  static GitResult<void> _handleShutdown() {
    try {
      for (final entry in _repos.entries) {
        try {
          LibGit2Bindings.I.repository_free(entry.value);
        } catch (_) {}
      }
      _repos.clear();
      if (_ffiReady) {
        try {
          LibGit2Bindings.I.libgit2_shutdown();
        } catch (e) {
          debugPrint('[GitWorkerIsolate] libgit2 shutdown error: $e');
        }
        _ffiReady = false;
      }
      // Release dynamic library reference
      DynamicLibraryService.dispose();
      return const GitResult<void>.success(null);
    } catch (e, st) {
      debugPrint('[GitWorkerIsolate] Shutdown error: $e\n$st');
      return GitResult<void>.failure(e.toString());
    }
  }
}

// Top-level helper container for collecting status entries
class _StatusCollector {
  final Set<String> modified = <String>{};
  final Set<String> staged = <String>{};
  final Set<String> untracked = <String>{};
}

// Diff collection structures and callbacks
class _DiffCollector {
  final List<Map<String, dynamic>> hunks = [];
  Map<String, dynamic>? _currentHunk;
  final List<Map<String, dynamic>> _currentLines = [];

  void startHunk(String header) {
    finishCurrentHunkIfAny();
    _currentHunk = {
      'header': header,
      'oldStart': _parseHeader(header, 1),
      'oldLines': _parseHeader(header, 2),
      'newStart': _parseHeader(header, 3),
      'newLines': _parseHeader(header, 4),
      'lines': _currentLines,
    };
  }

  static int _parseHeader(String header, int groupIndex) {
    final re = RegExp(r'^@@ -(?<oStart>\d+)(?:,(?<oCnt>\d+))? \+(?<nStart>\d+)(?:,(?<nCnt>\d+))? @@');
    final m = re.firstMatch(header.trim());
    if (m == null) return 0;
    switch (groupIndex) {
      case 1:
        return int.tryParse(m.namedGroup('oStart') ?? '') ?? 0;
      case 2:
        return int.tryParse(m.namedGroup('oCnt') ?? '') ?? 0;
      case 3:
        return int.tryParse(m.namedGroup('nStart') ?? '') ?? 0;
      case 4:
        return int.tryParse(m.namedGroup('nCnt') ?? '') ?? 0;
    }
    return 0;
  }

  void addLine(String type, String content, int oldLno, int newLno) {
    _currentLines.add({
      'type': type,
      'content': content,
      'oldLineNumber': oldLno,
      'newLineNumber': newLno,
    });
  }

  void finishCurrentHunkIfAny() {
    if (_currentHunk != null) {
      hunks.add({
        'header': _currentHunk!['header'],
        'oldStart': _currentHunk!['oldStart'],
        'oldLines': _currentHunk!['oldLines'],
        'newStart': _currentHunk!['newStart'],
        'newLines': _currentHunk!['newLines'],
        'lines': List<Map<String, dynamic>>.from(_currentLines),
      });
      _currentLines.clear();
      _currentHunk = null;
    }
  }

  List<Map<String, dynamic>> toJson() => hunks;
}

// Convert a libgit2 OID to a hex string
String _oidToHex(Pointer<git_oid> oidPtr) {
  final b = StringBuffer();
  for (var i = 0; i < 20; i++) {
    final v = oidPtr.ref.id[i];
    if (v < 16) b.write('0');
    b.write(v.toRadixString(16));
  }
  return b.toString();
}

bool _oidEquals(Pointer<git_oid> a, Pointer<git_oid> b) {
  for (var i = 0; i < 20; i++) {
    if (a.ref.id[i] != b.ref.id[i]) return false;
  }
  return true;
}

