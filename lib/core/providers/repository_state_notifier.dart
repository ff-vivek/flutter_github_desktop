import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watcher/watcher.dart';
import 'package:gitdesktop/core/git/git_isolate_manager.dart';
import 'package:gitdesktop/core/models/commit_item.dart';

/// State of a Git repository
class RepositoryState {
  final String path;
  final String? currentBranch;
  final List<String> modifiedFiles;
  final List<String> stagedFiles;
  final List<String> untrackedFiles;
  final List<CommitItem> commits;
  final bool isLoading;
  final String? error;

  const RepositoryState({
    required this.path,
    this.currentBranch,
    this.modifiedFiles = const [],
    this.stagedFiles = const [],
    this.untrackedFiles = const [],
    this.commits = const [],
    this.isLoading = false,
    this.error,
  });

  RepositoryState copyWith({
    String? path,
    String? currentBranch,
    List<String>? modifiedFiles,
    List<String>? stagedFiles,
    List<String>? untrackedFiles,
    List<CommitItem>? commits,
    bool? isLoading,
    String? error,
  }) {
    return RepositoryState(
      path: path ?? this.path,
      currentBranch: currentBranch ?? this.currentBranch,
      modifiedFiles: modifiedFiles ?? this.modifiedFiles,
      stagedFiles: stagedFiles ?? this.stagedFiles,
      untrackedFiles: untrackedFiles ?? this.untrackedFiles,
      commits: commits ?? this.commits,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  bool get hasChanges =>
      modifiedFiles.isNotEmpty ||
      stagedFiles.isNotEmpty ||
      untrackedFiles.isNotEmpty;

  int get changeCount =>
      modifiedFiles.length + stagedFiles.length + untrackedFiles.length;
}

/// Notifier for repository state with debounced file watching
///
/// This implements Risk #5: State Management with debounced file watching.
///
/// Features:
/// - Watches filesystem for changes using package:watcher
/// - Debounces file events by 500ms to prevent excessive git status calls
/// - Only triggers status check after file edits settle
/// - Cancels pending timers when new events arrive
/// - Uses GitIsolateManager for all git operations (non-blocking)
///
/// Flow:
/// 1. File changes → Watcher emits event
/// 2. Debounce timer starts (500ms)
/// 3. If more changes arrive, timer resets
/// 4. Timer completes → git status via GitIsolateManager
/// 5. State updates → UI rebuilds automatically
class RepositoryStateNotifier extends AsyncNotifier<RepositoryState> {
  final GitIsolateManager _gitManager = GitIsolateManager();
  StreamSubscription<WatchEvent>? _watcherSubscription;
  Timer? _debounceTimer;
  DirectoryWatcher? _watcher;
  String _repoPath = '';

  static const _debounceDuration = Duration(milliseconds: 500);

  @override
  Future<RepositoryState> build() async {
    // Initial empty state; caller must call initialize(repoPath)
    _repoPath = '';
    return RepositoryState(path: _repoPath);
  }

  /// Initialize with a specific repository path
  void initialize(String repoPath) {
    // Kept for compatibility if called manually; provider build handles normal init
    _repoPath = repoPath;
    // Ensure we have a baseline state before async work starts
    final base = state.value ?? RepositoryState(path: _repoPath);
    state = AsyncValue.data(base.copyWith(path: _repoPath, isLoading: true, error: null));
    _loadRepositoryState();
    _startWatcher();
  }

  /// Load repository state from Git
  Future<void> _loadRepositoryState() async {
    if (_repoPath.isEmpty) {
      debugPrint('[RepositoryStateNotifier] Repo path is empty. Skip load.');
      return;
    }
    final base = state.value ?? RepositoryState(path: _repoPath);
    state = AsyncValue.data(base.copyWith(isLoading: true, error: null));

    try {
      // Get repository info
      final openResult = await _gitManager.execute<Map<String, dynamic>>(
        OpenRepoCommand(_repoPath),
      );

      if (!openResult.success) {
        throw Exception(openResult.error ?? 'Failed to open repository');
      }

      final repoData = openResult.data!;

      // Get status
      final statusResult = await _gitManager.execute<Map<String, dynamic>>(
        GetStatusCommand(_repoPath),
      );

      if (!statusResult.success) {
        throw Exception(statusResult.error ?? 'Failed to get status');
      }

      final statusData = statusResult.data!;

      // Get history
      final historyResult = await _gitManager.execute<List<Map<String, dynamic>>>(
        GetHistoryCommand(_repoPath, 50),
      );
      final history = historyResult.success
          ? (historyResult.data ?? const <Map<String, dynamic>>[]).map((e) => CommitItem.fromJson(e)).toList()
          : <CommitItem>[];

      state = AsyncValue.data(RepositoryState(
        path: _repoPath,
        currentBranch: repoData['branch'] as String?,
        modifiedFiles: List<String>.from(statusData['modifiedFiles'] ?? []),
        stagedFiles: List<String>.from(statusData['stagedFiles'] ?? []),
        untrackedFiles: List<String>.from(statusData['untrackedFiles'] ?? []),
        commits: history,
        isLoading: false,
      ));

      debugPrint('[RepositoryStateNotifier] Loaded: ${state.value!.changeCount} changes');
    } catch (e) {
      debugPrint('[RepositoryStateNotifier] Load failed: $e');
      final base = state.value ?? RepositoryState(path: _repoPath);
      state = AsyncValue.data(base.copyWith(
        isLoading: false,
        error: e.toString(),
      ));
    }
  }

  /// Start watching the repository directory for changes
  void _startWatcher() {
    // Directory watching is not supported on Flutter web.
    if (kIsWeb) {
      debugPrint('[RepositoryStateNotifier] Web detected: directory watching disabled.');
      return;
    }
    try {
      if (_repoPath.isEmpty) {
        debugPrint('[RepositoryStateNotifier] Cannot start watcher: repo path is empty');
        return;
      }
      _watcher = DirectoryWatcher(_repoPath);
      _watcherSubscription = _watcher!.events.listen(
        _onFileSystemEvent,
        onError: (error) {
          debugPrint('[RepositoryStateNotifier] Watcher error: $error');
        },
      );
      debugPrint('[RepositoryStateNotifier] Watcher started');
    } catch (e) {
      debugPrint('[RepositoryStateNotifier] Failed to start watcher: $e');
    }
  }

  /// Handle filesystem events with debouncing
  ///
  /// This is the key to Risk #5: Debouncing rapid file changes.
  ///
  /// Instead of checking git status on every file change (which could be
  /// dozens per second during rapid edits), we wait for 500ms of inactivity.
  void _onFileSystemEvent(WatchEvent event) {
    debugPrint('[RepositoryStateNotifier] File event: ${event.type} ${event.path}');

    // Ignore .git directory changes (these are from git operations themselves)
    if (event.path.contains('.git')) {
      return;
    }

    // Cancel pending timer if exists
    _debounceTimer?.cancel();

    // Start new debounce timer
    _debounceTimer = Timer(_debounceDuration, () {
      debugPrint('[RepositoryStateNotifier] Debounce complete, refreshing status');
      _refreshStatus();
    });
  }

  /// Refresh repository status (called after debounce)
  Future<void> _refreshStatus() async {
    try {
      final statusResult = await _gitManager.execute<Map<String, dynamic>>(
        GetStatusCommand(_repoPath),
      );

      if (!statusResult.success) {
        throw Exception(statusResult.error ?? 'Failed to get status');
      }

      final statusData = statusResult.data!;
      final base = state.value ?? RepositoryState(path: _repoPath);
      state = AsyncValue.data(base.copyWith(
        modifiedFiles: List<String>.from(statusData['modifiedFiles'] ?? []),
        stagedFiles: List<String>.from(statusData['stagedFiles'] ?? []),
        untrackedFiles: List<String>.from(statusData['untrackedFiles'] ?? []),
        error: null,
      ));

      debugPrint('[RepositoryStateNotifier] Status refreshed: ${state.value!.changeCount} changes');
    } catch (e) {
      debugPrint('[RepositoryStateNotifier] Refresh failed: $e');
      final base = state.value ?? RepositoryState(path: _repoPath);
      state = AsyncValue.data(base.copyWith(error: e.toString()));
    }
  }

  /// Manually refresh (useful for pull/fetch operations)
  Future<void> refresh() async {
    debugPrint('[RepositoryStateNotifier] Manual refresh requested');
    await _loadRepositoryState();
  }

  /// Stage files
  Future<void> stageFiles(List<String> files) async {
    debugPrint('[RepositoryStateNotifier] Staging ${files.length} files');
    final base = state.value ?? RepositoryState(path: _repoPath);
    final newStaged = [...base.stagedFiles];
    final newModified = [...base.modifiedFiles];
    final newUntracked = [...base.untrackedFiles];
    for (final f in files) {
      if (!newStaged.contains(f)) newStaged.add(f);
      newModified.remove(f);
      newUntracked.remove(f);
    }
    state = AsyncValue.data(base.copyWith(
      stagedFiles: newStaged,
      modifiedFiles: newModified,
      untrackedFiles: newUntracked,
      error: null,
    ));
  }

  /// Unstage files
  Future<void> unstageFiles(List<String> files) async {
    debugPrint('[RepositoryStateNotifier] Unstaging ${files.length} files');
    final base = state.value ?? RepositoryState(path: _repoPath);
    final newStaged = [...base.stagedFiles];
    final newModified = [...base.modifiedFiles];
    for (final f in files) {
      newStaged.remove(f);
      if (!newModified.contains(f)) {
        newModified.add(f);
      }
    }
    state = AsyncValue.data(base.copyWith(
      stagedFiles: newStaged,
      modifiedFiles: newModified,
      error: null,
    ));
  }

  /// Commit changes
  Future<bool> commit(String message) async {
    debugPrint('[RepositoryStateNotifier] Committing: $message');

    try {
      final staged = state.value?.stagedFiles ?? const <String>[];
      final result = await _gitManager.execute<String>(
        CommitCommand(_repoPath, message, staged),
      );

      if (!result.success) {
        throw Exception(result.error ?? 'Commit failed');
      }

      debugPrint('[RepositoryStateNotifier] Commit successful: ${result.data}');
      // Refresh full repository state (status + history)
      await _loadRepositoryState();
      return true;
    } catch (e) {
      debugPrint('[RepositoryStateNotifier] Commit failed: $e');
      final base = state.value ?? RepositoryState(path: _repoPath);
      state = AsyncValue.data(base.copyWith(error: e.toString()));
      return false;
    }
  }

  /// Push to remote
  Future<bool> push({String remote = 'origin', String? branch}) async {
    final targetBranch = branch ?? state.value?.currentBranch ?? 'main';
    debugPrint('[RepositoryStateNotifier] Pushing to $remote/$targetBranch');

    try {
      final result = await _gitManager.execute<void>(
        PushCommand(_repoPath, remote, targetBranch),
      );

      if (!result.success) {
        throw Exception(result.error ?? 'Push failed');
      }

      debugPrint('[RepositoryStateNotifier] Push successful');
      return true;
    } catch (e) {
      debugPrint('[RepositoryStateNotifier] Push failed: $e');
      final base = state.value ?? RepositoryState(path: _repoPath);
      state = AsyncValue.data(base.copyWith(error: e.toString()));
      return false;
    }
  }

  /// Fetch from remote
  Future<bool> fetch({String remote = 'origin'}) async {
    debugPrint('[RepositoryStateNotifier] Fetching from $remote');

    try {
      final result = await _gitManager.execute<void>(
        FetchCommand(_repoPath, remote),
      );

      if (!result.success) {
        throw Exception(result.error ?? 'Fetch failed');
      }

      debugPrint('[RepositoryStateNotifier] Fetch successful');
      await _refreshStatus();
      return true;
    } catch (e) {
      debugPrint('[RepositoryStateNotifier] Fetch failed: $e');
      final base = state.value ?? RepositoryState(path: _repoPath);
      state = AsyncValue.data(base.copyWith(error: e.toString()));
      return false;
    }
  }

  /// Pull (fast-forward only for now)
  Future<bool> pull({String remote = 'origin', String? branch}) async {
    final targetBranch = branch ?? state.value?.currentBranch ?? 'main';
    debugPrint('[RepositoryStateNotifier] Pulling from $remote/$targetBranch');
    try {
      final result = await _gitManager.execute<void>(
        PullCommand(_repoPath, remote, targetBranch),
      );
      if (!result.success) {
        throw Exception(result.error ?? 'Pull failed');
      }
      debugPrint('[RepositoryStateNotifier] Pull successful');
      await _loadRepositoryState();
      return true;
    } catch (e) {
      debugPrint('[RepositoryStateNotifier] Pull failed: $e');
      final base = state.value ?? RepositoryState(path: _repoPath);
      state = AsyncValue.data(base.copyWith(error: e.toString()));
      return false;
    }
  }
}

/// Repository state provider (singleton; call initialize(repoPath) to use)
final repositoryStateNotifierProvider = AsyncNotifierProvider<RepositoryStateNotifier, RepositoryState>(RepositoryStateNotifier.new);
