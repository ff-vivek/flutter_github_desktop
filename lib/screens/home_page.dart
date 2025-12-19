import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitdesktop/theme.dart';

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
                _buildArchitectureInfo(),
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

  Widget _buildArchitectureInfo() {
    return Expanded(
      child: Container(
        padding: AppSpacing.paddingLg,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Technical Implementation',
                style: context.textStyles.titleLarge?.semiBold,
              ),
              const SizedBox(height: AppSpacing.md),
              _buildTechSection(
                '1. GitIsolateManager',
                'All FFI calls to libgit2 execute on a background isolate. '
                'Commands are sent via SendPort, processed without blocking the UI, '
                'and results are returned as pure Dart objects.',
              ),
              _buildTechSection(
                '2. CredentialsProvider',
                'Uses NativeCallable.isolateLocal() to create C-compatible function pointers. '
                'When libgit2 needs credentials, it calls the Dart callback which supplies a PAT or SSH key.',
              ),
              _buildTechSection(
                '3. DynamicLibraryService',
                'Conditionally loads libgit2.dll (Windows), libgit2.dylib (macOS), '
                'or libgit2.so (Linux) based on Platform checks.',
              ),
              _buildTechSection(
                '4. DiffHunk & DiffLine Models',
                'Pure Dart data classes. DiffParser walks git_diff pointers on the background isolate '
                'and converts them to List<DiffHunk> for safe UI rendering.',
              ),
              _buildTechSection(
                '5. RepositoryStateNotifier',
                'Riverpod StateNotifier that watches the filesystem. Implements 500ms debounce '
                'to prevent excessive git status checks during rapid file edits.',
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Text(
                  'See architecture.md for complete details',
                  style: context.textStyles.bodySmall?.withColor(
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
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
