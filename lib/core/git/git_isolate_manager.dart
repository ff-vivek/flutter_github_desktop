import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

/// Commands that can be sent to the Git isolate
abstract class GitCommand {
  const GitCommand();
}

/// Command to open a Git repository
class OpenRepoCommand extends GitCommand {
  final String path;
  const OpenRepoCommand(this.path);
}

/// Command to get repository status
class GetStatusCommand extends GitCommand {
  final String repoPath;
  const GetStatusCommand(this.repoPath);
}

/// Command to commit changes
class CommitCommand extends GitCommand {
  final String repoPath;
  final String message;
  final List<String> files;
  const CommitCommand(this.repoPath, this.message, this.files);
}

/// Command to push to remote
class PushCommand extends GitCommand {
  final String repoPath;
  final String remote;
  final String branch;
  const PushCommand(this.repoPath, this.remote, this.branch);
}

/// Command to fetch from remote
class FetchCommand extends GitCommand {
  final String repoPath;
  final String remote;
  const FetchCommand(this.repoPath, this.remote);
}

/// Command to get diff for a file
class GetDiffCommand extends GitCommand {
  final String repoPath;
  final String filePath;
  const GetDiffCommand(this.repoPath, this.filePath);
}

/// Command to get commit history
class GetHistoryCommand extends GitCommand {
  final String repoPath;
  final int limit;
  const GetHistoryCommand(this.repoPath, this.limit);
}

/// Command to clone a repository
class CloneRepoCommand extends GitCommand {
  final String url;
  final String destinationPath;
  const CloneRepoCommand(this.url, this.destinationPath);
}

/// Command to initialize a new repository
class InitRepoCommand extends GitCommand {
  final String path;
  const InitRepoCommand(this.path);
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
          completer.complete(message);
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
    }
  }

  /// Entry point for the background isolate
  ///
  /// This runs on a separate thread and handles all FFI calls to libgit2.
  /// IMPORTANT: No Flutter UI code or BuildContext can be used here.
  static void _isolateEntryPoint(SendPort mainSendPort) {
    // Create ReceivePort for this isolate
    final isolateReceivePort = ReceivePort();

    // Send this isolate's SendPort back to main isolate
    mainSendPort.send(isolateReceivePort.sendPort);

    debugPrint('[GitWorkerIsolate] Started and ready');

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
    // TODO: Initialize libgit2 FFI bindings (once DynamicLibraryService is implemented)
    // TODO: Call actual libgit2 functions via FFI

    // For now, return mock results to demonstrate isolate communication
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
    } else if (command is GetDiffCommand) {
      return _handleGetDiff(command);
    } else if (command is GetHistoryCommand) {
      return _handleGetHistory(command);
    } else if (command is CloneRepoCommand) {
      return _handleClone(command);
    } else if (command is InitRepoCommand) {
      return _handleInit(command);
    } else if (command is ShutdownCommand) {
      debugPrint('[GitWorkerIsolate] Shutdown requested');
      return const GitResult<void>.success(null);
    }

    return GitResult<dynamic>.failure('Unknown command: ${command.runtimeType}');
  }

  // Mock handlers (will be replaced with real FFI calls)

  static GitResult<Map<String, dynamic>> _handleOpenRepo(OpenRepoCommand cmd) {
    // TODO: Call git_repository_open() via FFI
    debugPrint('[GitWorkerIsolate] Opening repo: ${cmd.path}');
    
    // Simulate FFI work
    return GitResult<Map<String, dynamic>>.success({
      'path': cmd.path,
      'branch': 'main',
      'isClean': false,
      'head': 'abc123def456',
    });
  }

  static GitResult<Map<String, dynamic>> _handleGetStatus(GetStatusCommand cmd) {
    // TODO: Call git_status_foreach() via FFI
    debugPrint('[GitWorkerIsolate] Getting status: ${cmd.repoPath}');
    
    return GitResult<Map<String, dynamic>>.success({
      'modifiedFiles': ['lib/main.dart', 'README.md'],
      'stagedFiles': ['lib/theme.dart'],
      'untrackedFiles': ['test.txt'],
    });
  }

  static GitResult<String> _handleCommit(CommitCommand cmd) {
    // TODO: Call git_commit_create() via FFI
    debugPrint('[GitWorkerIsolate] Committing: ${cmd.message}');
    
    return const GitResult<String>.success('1234567890abcdef');
  }

  static GitResult<void> _handlePush(PushCommand cmd) {
    // TODO: Call git_remote_push() via FFI (will trigger credentials callback)
    debugPrint('[GitWorkerIsolate] Pushing: ${cmd.remote}/${cmd.branch}');
    
    return const GitResult<void>.success(null);
  }

  static GitResult<void> _handleFetch(FetchCommand cmd) {
    // TODO: Call git_remote_fetch() via FFI
    debugPrint('[GitWorkerIsolate] Fetching: ${cmd.remote}');
    
    return const GitResult<void>.success(null);
  }

  static GitResult<List<Map<String, dynamic>>> _handleGetDiff(GetDiffCommand cmd) {
    // TODO: Call git_diff_foreach() via FFI and parse to DiffHunk objects
    debugPrint('[GitWorkerIsolate] Getting diff: ${cmd.filePath}');
    
    return GitResult<List<Map<String, dynamic>>>.success([
      {
        'header': '@@ -1,3 +1,4 @@',
        'lines': [
          {'type': 'context', 'content': 'import "package:flutter/material.dart";'},
          {'type': 'added', 'content': 'import "package:flutter_riverpod/flutter_riverpod.dart";'},
          {'type': 'context', 'content': ''},
        ],
      },
    ]);
  }

  static GitResult<List<Map<String, dynamic>>> _handleGetHistory(GetHistoryCommand cmd) {
    // TODO: Call git_revwalk_* functions via FFI
    debugPrint('[GitWorkerIsolate] Getting history: ${cmd.repoPath} (limit: ${cmd.limit})');
    
    return GitResult<List<Map<String, dynamic>>>.success([
      {
        'hash': 'abc123',
        'message': 'Initial commit',
        'author': 'John Doe',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    ]);
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
}
