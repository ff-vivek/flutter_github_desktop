import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitdesktop/theme.dart';
import 'package:gitdesktop/core/providers/repository_state_notifier.dart';
import 'package:gitdesktop/core/services/recent_repos_service.dart';
import 'package:gitdesktop/core/git/git_isolate_manager.dart';
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
          const SizedBox(height: AppSpacing.lg),
          Expanded(child: _RepoChanges()),
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
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _FileListCard(title: 'Modified', icon: Icons.change_circle, files: repo.modifiedFiles, onTap: null)),
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: _FileListCard(title: 'Staged', icon: Icons.task_alt, files: repo.stagedFiles, onTap: null)),
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: _FileListCard(title: 'Untracked', icon: Icons.new_releases, files: repo.untrackedFiles, onTap: null)),
        ]);
      },
    );
  }
}

class _FileListCard extends StatelessWidget {
  final String title; final IconData icon; final List<String> files; final void Function(String file)? onTap;
  const _FileListCard({required this.title, required this.icon, required this.files, this.onTap});
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
                  onTap: onTap == null ? null : () => onTap!(f),
                );
              },
            ),
          ),
      ]),
    );
  }
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

