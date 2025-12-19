import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitdesktop/theme.dart';
import 'package:gitdesktop/core/providers/repository_state_notifier.dart';
import 'package:gitdesktop/core/services/recent_repos_service.dart';
import 'package:gitdesktop/core/git/git_isolate_manager.dart';
import 'package:gitdesktop/core/git/credentials_provider.dart';
import 'package:gitdesktop/core/models/diff_hunk.dart';
import 'package:gitdesktop/core/models/diff_line.dart';
import 'package:gitdesktop/core/models/commit_item.dart';
import 'package:go_router/go_router.dart';

/// Home page showing repository list
///
/// This is a placeholder for the full GitHub Desktop UI.
/// The actual implementation would show:
/// - List of repositories (local clones)
/// - Quick actions (clone, create, add existing)
/// - Recent repositories
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _pathController = TextEditingController();
  String? _currentRepoPath;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: AppSpacing.paddingXl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: AppSpacing.xl),
                _buildWelcomeCard(),
                const SizedBox(height: AppSpacing.xl),
                _buildOpenRepoCard(),
                const SizedBox(height: AppSpacing.xl),
                _buildQuickActionsCard(),
                const SizedBox(height: AppSpacing.xl),
                Expanded(child: _buildRepoArea()),
                const SizedBox(height: AppSpacing.xl),
                _buildRecentReposCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GitDesktop',
          style: context.textStyles.displaySmall?.bold.withColor(
            Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'A modern Git client powered by Flutter + libgit2',
          style: context.textStyles.bodyLarge?.withColor(
            Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.architecture,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                'Architecture Demo',
                style: context.textStyles.headlineSmall?.semiBold,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'This project demonstrates the architectural foundation for a GitHub Desktop clone. '
            'All critical technical risks have been addressed:',
            style: context.textStyles.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildCheckItem('✅ Concurrency: GitIsolateManager for non-blocking FFI calls'),
          _buildCheckItem('✅ Authentication: CredentialsProvider with C callbacks'),
          _buildCheckItem('✅ Native Binaries: Platform-specific library loading'),
          _buildCheckItem('✅ Diff Rendering: Safe pointer marshaling to Dart objects'),
          _buildCheckItem('✅ State Management: Riverpod with debounced file watching'),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Text(
        text,
        style: context.textStyles.bodyMedium?.medium,
      ),
    );
  }

  Widget _buildOpenRepoCard() {
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.folder_open, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Text('Open Repository', style: context.textStyles.titleLarge?.semiBold),
          ]),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _pathController,
                decoration: InputDecoration(
                  hintText: '/absolute/path/to/repository',
                  prefixIcon: Icon(Icons.folder, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            FilledButton.icon(
              onPressed: () {
                final path = _pathController.text.trim();
                if (path.isEmpty) return;
                setState(() => _currentRepoPath = path);
                ref.read(repositoryStateNotifierProvider.notifier).initialize(path);
                ref.read(recentReposProvider.notifier).addOrUpdate(path);
              },
              icon: Icon(Icons.login, color: Theme.of(context).colorScheme.onPrimary),
              label: const Text('Open'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.flash_on, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text('Quick Actions', style: context.textStyles.titleLarge?.semiBold),
        ]),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: 12, runSpacing: 12, children: [
          FilledButton.icon(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: CloneRepoSheet(onComplete: _openRepoAndPersist),
              ),
            ),
            icon: Icon(Icons.download, color: scheme.onPrimary),
            label: const Text('Clone repository'),
          ),
          OutlinedButton.icon(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: CreateRepoSheet(onComplete: _openRepoAndPersist),
              ),
            ),
            icon: Icon(Icons.add_box, color: scheme.primary),
            label: const Text('Create new'),
          ),
          OutlinedButton.icon(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: AddExistingRepoSheet(onComplete: _openRepoAndPersist),
              ),
            ),
            icon: Icon(Icons.folder_copy, color: scheme.primary),
            label: const Text('Add existing'),
          ),
        ]),
      ]),
    );
  }

  void _openRepoAndPersist(String path) {
    if (path.isEmpty) return;
    setState(() => _currentRepoPath = path);
    ref.read(repositoryStateNotifierProvider.notifier).initialize(path);
    ref.read(recentReposProvider.notifier).addOrUpdate(path);
  }

  Widget _buildRecentReposCard() {
    final scheme = Theme.of(context).colorScheme;
    return Consumer(builder: (context, ref, _) {
      final async = ref.watch(recentReposProvider);
      return Container(
        padding: AppSpacing.paddingLg,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.15)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.history, color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Text('Recent repositories', style: context.textStyles.titleLarge?.semiBold),
          ]),
          const SizedBox(height: AppSpacing.md),
          async.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Failed to load recent repos', style: context.textStyles.bodySmall?.withColor(scheme.error)),
            data: (repos) {
              if (repos.isEmpty) {
                return Text('No recent repositories yet', style: context.textStyles.bodySmall?.withColor(scheme.onSurfaceVariant));
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: repos.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outline.withValues(alpha: 0.08)),
                itemBuilder: (context, index) {
                  final r = repos[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.source, color: scheme.onSurfaceVariant),
                    title: Text(r.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(r.path, overflow: TextOverflow.ellipsis, style: context.textStyles.bodySmall?.withColor(scheme.onSurfaceVariant)),
                    trailing: Wrap(spacing: 8, children: [
                      IconButton(
                        tooltip: 'Open',
                        onPressed: () => _openRepoAndPersist(r.path),
                        icon: Icon(Icons.open_in_new, color: scheme.primary),
                      ),
                      IconButton(
                        tooltip: 'Remove from list',
                        onPressed: () => ref.read(recentReposProvider.notifier).remove(r.path),
                        icon: Icon(Icons.delete_outline, color: scheme.error),
                      ),
                    ]),
                  );
                },
              );
            },
          ),
        ]),
      );
    });
  }

  Widget _buildRepoArea() {
    final path = _currentRepoPath;
    if (path == null || path.isEmpty) {
      return _buildArchitectureInfo();
    }

    final async = ref.watch(repositoryStateNotifierProvider);

    return async.when(
      loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      error: (e, _) => _buildErrorCard(e.toString(), onRetry: () => ref.read(repositoryStateNotifierProvider.notifier).refresh()),
      data: (repo) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _RepoHeader(repo: repo, onRefresh: () => ref.read(repositoryStateNotifierProvider.notifier).refresh()),
          const SizedBox(height: AppSpacing.md),
          RepoActionsToolbar(repoPath: repo.path, currentBranch: repo.currentBranch ?? 'main'),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(height: 160, child: RemotesPanelCard(repoPath: repo.path)),
          const SizedBox(height: AppSpacing.lg),
          CommitComposer(),
          const SizedBox(height: AppSpacing.lg),
          Flexible(child: _RepoChanges()),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(height: 260, child: _HistoryCard(commits: repo.commits)),
        ]);
      },
    );
  }

  Widget _buildErrorCard(String message, {VoidCallback? onRetry}) {
    return Center(
      child: Container(
        padding: AppSpacing.paddingLg,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('Failed to open repository', style: context.textStyles.titleMedium?.semiBold)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(message, style: context.textStyles.bodySmall?.withColor(Theme.of(context).colorScheme.onErrorContainer)),
          const SizedBox(height: AppSpacing.md),
          if (onRetry != null)
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.primary),
              label: const Text('Retry'),
            ),
        ]),
      ),
    );
  }

  Widget _buildArchitectureInfo() {
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Technical Implementation', style: context.textStyles.titleLarge?.semiBold),
            const SizedBox(height: AppSpacing.md),
            _buildTechSection(
              '1. GitIsolateManager',
              'All FFI calls to libgit2 execute on a background isolate. Commands are sent via SendPort, processed without blocking the UI, and results are returned as pure Dart objects.',
            ),
            _buildTechSection(
              '2. CredentialsProvider',
              'Uses NativeCallable.isolateLocal() to create C-compatible function pointers. When libgit2 needs credentials, it calls the Dart callback which supplies a PAT or SSH key.',
            ),
            _buildTechSection(
              '3. DynamicLibraryService',
              'Conditionally loads libgit2.dll (Windows), libgit2.dylib (macOS), or libgit2.so (Linux) based on Platform checks.',
            ),
            _buildTechSection(
              '4. DiffHunk & DiffLine Models',
              'Pure Dart data classes. DiffParser walks git_diff pointers on the background isolate and converts them to List<DiffHunk> for safe UI rendering.',
            ),
            _buildTechSection(
              '5. RepositoryStateNotifier',
              'Riverpod StateNotifier that watches the filesystem. Implements 500ms debounce to prevent excessive git status checks during rapid file edits.',
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Text('See architecture.md for complete details', style: context.textStyles.bodySmall?.withColor(Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechSection(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.textStyles.titleMedium?.semiBold.withColor(
              Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            description,
            style: context.textStyles.bodySmall?.withColor(
              Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RepoHeader extends StatelessWidget {
  final RepositoryState repo;
  final VoidCallback onRefresh;
  const _RepoHeader({required this.repo, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(Icons.merge_type, color: scheme.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(repo.path, style: Theme.of(context).textTheme.titleLarge?.semiBold),
          const SizedBox(height: 4),
          Wrap(spacing: 12, children: [
            _Chip(icon: Icons.account_tree, label: repo.currentBranch ?? 'unknown'),
            _Chip(icon: Icons.fiber_manual_record, label: repo.hasChanges ? 'Dirty' : 'Clean', color: repo.hasChanges ? Colors.orange : Colors.green),
            _Chip(icon: Icons.edit_note, label: '${repo.changeCount} changes'),
          ]),
        ])),
        const SizedBox(width: AppSpacing.md),
        OutlinedButton.icon(onPressed: onRefresh, icon: Icon(Icons.refresh, color: scheme.primary), label: const Text('Refresh')),
      ]),
    );
  }
}

class _RepoChanges extends ConsumerWidget {
  const _RepoChanges();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(repositoryStateNotifierProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (repo) {
        void _openDiff(String filePath) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: DiffViewerModal(repoPath: repo.path, filePath: filePath),
            ),
          );
        }

        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _FileListCard(
              title: 'Modified',
              icon: Icons.change_circle,
              files: repo.modifiedFiles,
              onTap: (f) => ref.read(repositoryStateNotifierProvider.notifier).stageFiles([f]),
              onLongPress: _openDiff,
              trailingIcon: Icons.add_task,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: _FileListCard(
              title: 'Staged',
              icon: Icons.task_alt,
              files: repo.stagedFiles,
              onTap: (f) => ref.read(repositoryStateNotifierProvider.notifier).unstageFiles([f]),
              onLongPress: _openDiff,
              trailingIcon: Icons.undo,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: _FileListCard(
              title: 'Untracked',
              icon: Icons.new_releases,
              files: repo.untrackedFiles,
              onTap: (f) => ref.read(repositoryStateNotifierProvider.notifier).stageFiles([f]),
              onLongPress: _openDiff,
              trailingIcon: Icons.add_task,
            ),
          ),
        ]);
      },
    );
  }
}

class _FileListCard extends StatelessWidget {
  final String title; final IconData icon; final List<String> files; final void Function(String file)? onTap; final void Function(String file)? onLongPress; final IconData? trailingIcon;
  const _FileListCard({required this.title, required this.icon, required this.files, this.onTap, this.onLongPress, this.trailingIcon});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.semiBold),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('${files.length}', style: Theme.of(context).textTheme.labelMedium?.withColor(scheme.onPrimaryContainer)),
          ),
        ]),
        const SizedBox(height: AppSpacing.md),
        if (files.isEmpty)
          Text('No files', style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.onSurfaceVariant))
        else
          Expanded(
            child: ListView.separated(
              itemCount: files.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outline.withValues(alpha: 0.08)),
              itemBuilder: (context, index) {
                final f = files[index];
                return ListTile(
                  dense: true,
                  leading: Icon(Icons.insert_drive_file, color: scheme.onSurfaceVariant),
                  title: Text(f, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                  trailing: trailingIcon == null ? null : Icon(trailingIcon, color: scheme.primary),
                  onTap: onTap == null ? null : () => onTap!(f),
                  onLongPress: onLongPress == null ? null : () => onLongPress!(f),
                );
              },
            ),
          ),
      ]),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final List<CommitItem> commits;
  const _HistoryCard({required this.commits});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.history_toggle_off, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text('Recent commits', style: Theme.of(context).textTheme.titleMedium?.semiBold),
          const Spacer(),
          Text('${commits.length}', style: Theme.of(context).textTheme.labelMedium?.withColor(scheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: commits.isEmpty
              ? Center(child: Text('No commits yet', style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.onSurfaceVariant)))
              : ListView.separated(
                  itemCount: commits.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outline.withValues(alpha: 0.08)),
                  itemBuilder: (context, index) {
                    final c = commits[index];
                    final date = _formatTime(c.time);
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.commit, color: scheme.onSurfaceVariant),
                      title: Text(_firstLine(c.message), overflow: TextOverflow.ellipsis),
                      subtitle: Text('${c.author} • $date', overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.onSurfaceVariant)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
                        child: Text(c.hash.substring(0, c.hash.length >= 7 ? 7 : c.hash.length), style: Theme.of(context).textTheme.labelSmall),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  String _firstLine(String s) {
    final i = s.indexOf('\n');
    return i == -1 ? s : s.substring(0, i);
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.year}-${_two(time.month)}-${_two(time.day)}';
  }

  String _two(int n) => n < 10 ? '0$n' : '$n';
}

class _Chip extends StatelessWidget {
  final IconData icon; final String label; final Color? color;
  const _Chip({required this.icon, required this.label, this.color});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = color ?? scheme.primaryContainer;
    final fg = color == null ? scheme.onPrimaryContainer : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.withColor(fg)),
      ]),
    );
  }
}

// =============================
// Bottom sheets for quick flows
// =============================

class CloneRepoSheet extends StatefulWidget {
  final void Function(String path) onComplete;
  const CloneRepoSheet({super.key, required this.onComplete});

  @override
  State<CloneRepoSheet> createState() => _CloneRepoSheetState();
}

class _CloneRepoSheetState extends State<CloneRepoSheet> {
  final _url = TextEditingController();
  final _dest = TextEditingController();
  bool _loading = false; String? _error;

  @override
  void dispose() { _url.dispose(); _dest.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final url = _url.text.trim();
    final dest = _dest.text.trim();
    if (url.isEmpty || dest.isEmpty) return setState(() => _error = 'Please provide URL and destination path');
    setState(() { _loading = true; _error = null; });
    try {
      final res = await GitIsolateManager().execute<Map<String, dynamic>>(CloneRepoCommand(url, dest));
      if (!res.success) throw Exception(res.error ?? 'Clone failed');
      widget.onComplete(dest);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.download, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text('Clone repository', style: Theme.of(context).textTheme.titleLarge?.semiBold),
        ]),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _url,
          decoration: InputDecoration(prefixIcon: Icon(Icons.link, color: scheme.onSurfaceVariant), hintText: 'https://github.com/owner/repo.git'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _dest,
          decoration: InputDecoration(prefixIcon: Icon(Icons.folder, color: scheme.onSurfaceVariant), hintText: '/destination/path'),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(_error!, style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.error))),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(onPressed: _loading ? null : _submit, icon: Icon(Icons.download, color: scheme.onPrimary), label: _loading ? const Text('Cloning...') : const Text('Clone')),
        ),
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
      ]),
    );
  }
}

class CreateRepoSheet extends StatefulWidget {
  final void Function(String path) onComplete;
  const CreateRepoSheet({super.key, required this.onComplete});

  @override
  State<CreateRepoSheet> createState() => _CreateRepoSheetState();
}

class _CreateRepoSheetState extends State<CreateRepoSheet> {
  final _path = TextEditingController();
  bool _loading = false; String? _error;

  @override
  void dispose() { _path.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final path = _path.text.trim();
    if (path.isEmpty) return setState(() => _error = 'Please provide a folder path');
    setState(() { _loading = true; _error = null; });
    try {
      final res = await GitIsolateManager().execute<Map<String, dynamic>>(InitRepoCommand(path));
      if (!res.success) throw Exception(res.error ?? 'Init failed');
      widget.onComplete(path);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.add_box, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text('Create new repository', style: Theme.of(context).textTheme.titleLarge?.semiBold),
        ]),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _path,
          decoration: InputDecoration(prefixIcon: Icon(Icons.folder, color: scheme.onSurfaceVariant), hintText: '/folder/path'),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(_error!, style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.error))),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(onPressed: _loading ? null : _submit, icon: Icon(Icons.check, color: scheme.onPrimary), label: _loading ? const Text('Creating...') : const Text('Create')),
        ),
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
      ]),
    );
  }
}

class AddExistingRepoSheet extends StatefulWidget {
  final void Function(String path) onComplete;
  const AddExistingRepoSheet({super.key, required this.onComplete});

  @override
  State<AddExistingRepoSheet> createState() => _AddExistingRepoSheetState();
}

// =============================
// Commit composer
// =============================

class CommitComposer extends ConsumerStatefulWidget {
  CommitComposer({super.key});

  @override
  ConsumerState<CommitComposer> createState() => _CommitComposerState();
}

class _CommitComposerState extends ConsumerState<CommitComposer> {
  final _controller = TextEditingController();
  bool _loading = false; String? _error;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _commit() async {
    final msg = _controller.text.trim();
    if (msg.isEmpty) return setState(() => _error = 'Enter a commit message');
    setState(() { _loading = true; _error = null; });
    final ok = await ref.read(repositoryStateNotifierProvider.notifier).commit(msg);
    if (!mounted) return;
    if (ok) {
      _controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Commit created'), backgroundColor: Theme.of(context).colorScheme.primary));
      setState(() { _loading = false; });
    } else {
      setState(() { _loading = false; _error = 'Commit failed'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.edit_note, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text('Commit message', style: Theme.of(context).textTheme.titleMedium?.semiBold),
        ]),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Describe your changes',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(_error!, style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.error))),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _loading ? null : _commit,
            icon: Icon(Icons.check, color: scheme.onPrimary),
            label: Text(_loading ? 'Committing...' : 'Commit'),
          ),
        ),
      ]),
    );
  }
}

class _AddExistingRepoSheetState extends State<AddExistingRepoSheet> {
  final _path = TextEditingController();
  bool _loading = false; String? _error;

  @override
  void dispose() { _path.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final path = _path.text.trim();
    if (path.isEmpty) return setState(() => _error = 'Please provide a repository path');
    setState(() { _loading = true; _error = null; });
    try {
      // Minimal validation via OpenRepo mock
      final res = await GitIsolateManager().execute<Map<String, dynamic>>(OpenRepoCommand(path));
      if (!res.success) throw Exception(res.error ?? 'Not a git repository');
      widget.onComplete(path);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.folder_copy, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text('Add existing repository', style: Theme.of(context).textTheme.titleLarge?.semiBold),
        ]),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _path,
          decoration: InputDecoration(prefixIcon: Icon(Icons.folder, color: scheme.onSurfaceVariant), hintText: '/repository/path'),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(_error!, style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.error))),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(onPressed: _loading ? null : _submit, icon: Icon(Icons.check, color: scheme.onPrimary), label: _loading ? const Text('Adding...') : const Text('Add')),
        ),
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
      ]),
    );
  }
}

// =============================
// Diff Viewer Modal
// =============================

class DiffViewerModal extends StatefulWidget {
  final String repoPath;
  final String filePath;
  const DiffViewerModal({super.key, required this.repoPath, required this.filePath});

  @override
  State<DiffViewerModal> createState() => _DiffViewerModalState();
}

class _DiffViewerModalState extends State<DiffViewerModal> {
  late Future<_DiffData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DiffData> _load() async {
    try {
      final res = await GitIsolateManager().execute<List<Map<String, dynamic>>>(
        GetDiffCommand(widget.repoPath, widget.filePath),
      );
      if (!res.success) throw Exception(res.error ?? 'Failed to load diff');
      final hunksJson = res.data ?? const <Map<String, dynamic>>[];
      final hunks = hunksJson.map((e) => DiffHunk.fromJson(e)).toList();
      return _DiffData(hunks: hunks);
    } catch (e) {
      debugPrint('[DiffViewerModal] Failed to load diff: $e');
      return _DiffData(error: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: AppSpacing.paddingLg,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.12))),
        ),
        child: Row(children: [
          Icon(Icons.compare, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(widget.filePath, style: Theme.of(context).textTheme.titleMedium?.semiBold)),
          IconButton(onPressed: () => context.pop(), icon: Icon(Icons.close, color: scheme.onSurfaceVariant)),
        ]),
      ),
      Expanded(
        child: FutureBuilder<_DiffData>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return Center(child: CircularProgressIndicator(color: scheme.primary));
            }
            final data = snap.data!;
            if (data.error != null) {
              return Center(
                child: Padding(
                  padding: AppSpacing.paddingLg,
                  child: Text(data.error!, style: Theme.of(context).textTheme.bodyMedium?.withColor(scheme.error)),
                ),
              );
            }
            final hunks = data.hunks;
            if (hunks.isEmpty) {
              return Center(child: Text('No changes', style: Theme.of(context).textTheme.bodyMedium));
            }
            return ListView.builder(
              padding: AppSpacing.paddingLg,
              itemCount: hunks.length,
              itemBuilder: (context, i) => _HunkView(hunks[i]),
            );
          },
        ),
      ),
    ]);
  }
}

class _DiffData {
  final List<DiffHunk> hunks; final String? error;
  _DiffData({this.hunks = const [], this.error});
}

class _HunkView extends StatelessWidget {
  final DiffHunk h;
  const _HunkView(this.h);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppRadius.md), topRight: Radius.circular(AppRadius.md)),
          ),
          child: Text(h.header, style: Theme.of(context).textTheme.labelMedium?.withColor(scheme.onSurfaceVariant)),
        ),
        ...h.lines.map((l) => _LineView(l)).toList(),
      ]),
    );
  }
}

class _LineView extends StatelessWidget {
  final DiffLine l;
  const _LineView(this.l);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    IconData icon;
    switch (l.type) {
      case DiffLineType.added:
        bg = scheme.tertiaryContainer;
        fg = scheme.onTertiaryContainer;
        icon = Icons.add;
        break;
      case DiffLineType.deleted:
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        icon = Icons.remove;
        break;
      case DiffLineType.context:
      case DiffLineType.header:
        bg = scheme.surface;
        fg = scheme.onSurfaceVariant;
        icon = Icons.drag_indicator;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.05)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 56,
          child: Text(
            '${l.oldLineNumber <= 0 ? '' : l.oldLineNumber} ${l.newLineNumber <= 0 ? '' : l.newLineNumber}'.trim(),
            style: Theme.of(context).textTheme.labelSmall?.withColor(scheme.onSurfaceVariant),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 14, color: fg),
        ),
        Expanded(child: Text(l.content, softWrap: true, overflow: TextOverflow.visible, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}


// =============================
// Repo Actions (Fetch / Pull / Push)
// =============================

class RepoActionsToolbar extends ConsumerStatefulWidget {
  final String repoPath; final String currentBranch;
  const RepoActionsToolbar({super.key, required this.repoPath, required this.currentBranch});

  @override
  ConsumerState<RepoActionsToolbar> createState() => _RepoActionsToolbarState();
}

class _RepoActionsToolbarState extends ConsumerState<RepoActionsToolbar> {
  bool _busy = false;

  Future<void> _run(String label, Future<bool> Function() task) async {
    if (_busy) return; setState(() => _busy = true);
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('$label started…'), backgroundColor: scheme.surfaceContainerHighest));
    try {
      final ok = await task();
      messenger.showSnackBar(SnackBar(content: Text(ok ? '$label completed' : '$label failed'), backgroundColor: ok ? scheme.primary : scheme.error));
    } catch (e) {
      debugPrint('[RepoActionsBar] $label error: $e');
      messenger.showSnackBar(SnackBar(content: Text('$label error: $e'), backgroundColor: scheme.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Icon(Icons.sync, color: scheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Text('Remote actions', style: Theme.of(context).textTheme.titleMedium?.semiBold),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run('Fetch', () => ref.read(repositoryStateNotifierProvider.notifier).fetch()),
          icon: Icon(Icons.download, color: scheme.primary),
          label: const Text('Fetch'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run('Pull', () => ref.read(repositoryStateNotifierProvider.notifier).pull()),
          icon: Icon(Icons.download_done, color: scheme.primary),
          label: const Text('Pull'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _busy ? null : () => _run('Push', () => ref.read(repositoryStateNotifierProvider.notifier).push(branch: widget.currentBranch)),
          icon: Icon(Icons.upload, color: scheme.onPrimary),
          label: const Text('Push'),
        ),
      ]),
    );
  }
}

// =============================
// Remotes Panel
// =============================

class RemotesPanelCard extends StatefulWidget {
  final String repoPath;
  const RemotesPanelCard({super.key, required this.repoPath});

  @override
  State<RemotesPanelCard> createState() => _RemotesPanelCardState();
}

class _RemotesPanelCardState extends State<RemotesPanelCard> {
  late Future<List<Map<String, String>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, String>>> _load() async {
    try {
      final res = await GitIsolateManager().execute<List<Map<String, String>>>(GetRemotesCommand(widget.repoPath));
      if (!res.success) throw Exception(res.error ?? 'Failed to list remotes');
      return res.data ?? const <Map<String, String>>[];
    } catch (e) {
      debugPrint('[RemotesPanel] Load error: $e');
      return Future.error(e);
    }
  }

  Future<void> _refresh() async => setState(() => _future = _load());

  void _openAdd() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: AddRemoteSheet(repoPath: widget.repoPath, onDone: () { context.pop(); _refresh(); }),
      ),
    );
  }

  void _openEdit(String name, String currentUrl) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: EditRemoteUrlSheet(repoPath: widget.repoPath, name: name, currentUrl: currentUrl, onDone: () { context.pop(); _refresh(); }),
      ),
    );
  }

  Future<void> _remove(String name) async {
    try {
      final res = await GitIsolateManager().execute<void>(RemoveRemoteCommand(widget.repoPath, name));
      if (!res.success) throw Exception(res.error ?? 'Remove failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Removed "$name"')));
        _refresh();
      }
    } catch (e) {
      debugPrint('[RemotesPanel] Remove error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Remove failed: $e'), backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  void _openCredentials() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const CredentialsPromptSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_tree, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text('Remotes', style: Theme.of(context).textTheme.titleMedium?.semiBold),
          const Spacer(),
          OutlinedButton.icon(onPressed: _openCredentials, icon: Icon(Icons.vpn_key, color: scheme.primary), label: const Text('Credentials')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _refresh, icon: Icon(Icons.refresh, color: scheme.primary), label: const Text('Refresh')),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _openAdd, icon: Icon(Icons.add, color: scheme.onPrimary), label: const Text('Add remote')),
        ]),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: FutureBuilder<List<Map<String, String>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: LinearProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Failed to load remotes', style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.error)));
              }
              final remotes = snap.data ?? const <Map<String, String>>[];
              if (remotes.isEmpty) {
                return Center(child: Text('No remotes configured', style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.onSurfaceVariant)));
              }
              return ListView.separated(
                itemCount: remotes.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outline.withValues(alpha: 0.08)),
                itemBuilder: (context, i) {
                  final r = remotes[i];
                  final name = r['name'] ?? '';
                  final url = r['url'] ?? '';
                  final isPrimary = name == 'origin';
                  return ListTile(
                    dense: true,
                    leading: Icon(isPrimary ? Icons.star : Icons.link, color: isPrimary ? Colors.amber : scheme.onSurfaceVariant),
                    title: Row(children: [
                      Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.semiBold)),
                      if (isPrimary)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(999)),
                          child: Text('primary', style: Theme.of(context).textTheme.labelSmall?.withColor(scheme.onPrimaryContainer)),
                        ),
                    ]),
                    subtitle: Text(url.isEmpty ? '—' : url, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.onSurfaceVariant)),
                    trailing: PopupMenuButton<String>(
                      icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
                      onSelected: (v) {
                        switch (v) {
                          case 'edit':
                            _openEdit(name, url);
                            break;
                          case 'remove':
                            _remove(name);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Set URL')),
                        const PopupMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// =============================
// Add/Edit Remote Sheets
// =============================

class AddRemoteSheet extends StatefulWidget {
  final String repoPath; final VoidCallback onDone;
  const AddRemoteSheet({super.key, required this.repoPath, required this.onDone});

  @override
  State<AddRemoteSheet> createState() => _AddRemoteSheetState();
}

class _AddRemoteSheetState extends State<AddRemoteSheet> {
  final _name = TextEditingController(text: 'origin');
  final _url = TextEditingController();
  bool _loading = false; String? _error;

  @override
  void dispose() { _name.dispose(); _url.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty || url.isEmpty) return setState(() => _error = 'Enter name and URL');
    setState(() { _loading = true; _error = null; });
    try {
      final res = await GitIsolateManager().execute<void>(AddRemoteCommand(widget.repoPath, name, url));
      if (!res.success) throw Exception(res.error ?? 'Add failed');
      widget.onDone();
    } catch (e) {
      debugPrint('[AddRemoteSheet] Add error: $e');
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.add_link, color: scheme.primary), const SizedBox(width: AppSpacing.sm), Text('Add remote', style: Theme.of(context).textTheme.titleLarge?.semiBold)]),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: _name, decoration: InputDecoration(prefixIcon: Icon(Icons.sell, color: scheme.onSurfaceVariant), hintText: 'origin')), 
        const SizedBox(height: AppSpacing.md),
        TextField(controller: _url, decoration: InputDecoration(prefixIcon: Icon(Icons.link, color: scheme.onSurfaceVariant), hintText: 'https://example.com/owner/repo.git')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(_error!, style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.error))),
        const SizedBox(height: AppSpacing.md),
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _loading ? null : _submit, icon: Icon(Icons.check, color: scheme.onPrimary), label: Text(_loading ? 'Adding…' : 'Add'))),
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
      ]),
    );
  }
}

class EditRemoteUrlSheet extends StatefulWidget {
  final String repoPath; final String name; final String currentUrl; final VoidCallback onDone;
  const EditRemoteUrlSheet({super.key, required this.repoPath, required this.name, required this.currentUrl, required this.onDone});

  @override
  State<EditRemoteUrlSheet> createState() => _EditRemoteUrlSheetState();
}

class _EditRemoteUrlSheetState extends State<EditRemoteUrlSheet> {
  late final TextEditingController _url = TextEditingController(text: widget.currentUrl);
  bool _loading = false; String? _error;

  @override
  void dispose() { _url.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final url = _url.text.trim();
    if (url.isEmpty) return setState(() => _error = 'Enter remote URL');
    setState(() { _loading = true; _error = null; });
    try {
      final res = await GitIsolateManager().execute<void>(SetRemoteUrlCommand(widget.repoPath, widget.name, url));
      if (!res.success) throw Exception(res.error ?? 'Update failed');
      widget.onDone();
    } catch (e) {
      debugPrint('[EditRemoteUrlSheet] Update error: $e');
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.edit, color: scheme.primary), const SizedBox(width: AppSpacing.sm), Expanded(child: Text('Set URL for ${widget.name}', style: Theme.of(context).textTheme.titleLarge?.semiBold, overflow: TextOverflow.ellipsis))]),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: _url, decoration: InputDecoration(prefixIcon: Icon(Icons.link, color: scheme.onSurfaceVariant), hintText: 'https://…')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(_error!, style: Theme.of(context).textTheme.bodySmall?.withColor(scheme.error))),
        const SizedBox(height: AppSpacing.md),
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _loading ? null : _submit, icon: Icon(Icons.check, color: scheme.onPrimary), label: Text(_loading ? 'Saving…' : 'Save'))),
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
      ]),
    );
  }
}

// =============================
// Credentials Prompt (UI only)
// =============================

class CredentialsPromptSheet extends StatefulWidget {
  const CredentialsPromptSheet({super.key});

  @override
  State<CredentialsPromptSheet> createState() => _CredentialsPromptSheetState();
}

class _CredentialsPromptSheetState extends State<CredentialsPromptSheet> {
  String _mode = 'https';
  final _username = TextEditingController();
  final _token = TextEditingController();
  final _sshKeyPath = TextEditingController();
  final _sshPassphrase = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _username.dispose(); _token.dispose(); _sshKeyPath.dispose(); _sshPassphrase.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      if (_mode == 'https') {
        final provider = await CredentialsFactory.createWithPAT(_token.text.trim(), username: _username.text.trim());
        CredentialsRegistry.registerGlobal(provider);
        debugPrint('[Credentials] HTTPS saved (session): user=${_username.text} token=${_token.text.isEmpty ? '(empty)' : '***'}');
      } else {
        final provider = await CredentialsFactory.createWithSSH(
          privateKeyPath: _sshKeyPath.text.trim(),
          passphrase: _sshPassphrase.text.trim().isEmpty ? null : _sshPassphrase.text.trim(),
        );
        CredentialsRegistry.registerGlobal(provider);
        debugPrint('[Credentials] SSH saved (session): key=${_sshKeyPath.text} passphrase=${_sshPassphrase.text.isEmpty ? '(empty)' : '***'}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Credentials saved for session (UI only)'), backgroundColor: Theme.of(context).colorScheme.primary));
      context.pop();
    } catch (e) {
      debugPrint('[CredentialsPromptSheet] Save error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.vpn_key, color: scheme.primary), const SizedBox(width: AppSpacing.sm), Text('Credentials', style: Theme.of(context).textTheme.titleLarge?.semiBold)]),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('HTTPS / PAT'), selected: _mode == 'https', onSelected: (_) => setState(() => _mode = 'https')),
          ChoiceChip(label: const Text('SSH'), selected: _mode == 'ssh', onSelected: (_) => setState(() => _mode = 'ssh')),
        ]),
        const SizedBox(height: AppSpacing.md),
        if (_mode == 'https') ...[
          TextField(controller: _username, decoration: InputDecoration(prefixIcon: Icon(Icons.person, color: scheme.onSurfaceVariant), hintText: 'Username or email')),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: _token, obscureText: true, decoration: InputDecoration(prefixIcon: Icon(Icons.password, color: scheme.onSurfaceVariant), hintText: 'Password or Personal Access Token')),
        ] else ...[
          TextField(controller: _sshKeyPath, decoration: InputDecoration(prefixIcon: Icon(Icons.key, color: scheme.onSurfaceVariant), hintText: '~/.ssh/id_ed25519')),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: _sshPassphrase, obscureText: true, decoration: InputDecoration(prefixIcon: Icon(Icons.lock, color: scheme.onSurfaceVariant), hintText: 'Passphrase (if any)')),
        ],
        const SizedBox(height: AppSpacing.md),
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _saving ? null : _save, icon: Icon(Icons.check, color: scheme.onPrimary), label: Text(_saving ? 'Saving…' : 'Save'))),
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
      ]),
    );
  }
}

