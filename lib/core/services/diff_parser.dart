import 'package:flutter/foundation.dart';
import 'package:gitdesktop/core/models/diff_hunk.dart';
import 'package:gitdesktop/core/models/diff_line.dart';

/// Parser for converting libgit2 diff pointers to Dart objects
///
/// This service walks git_diff pointers on the background isolate and converts
/// them into List<DiffHunk> containing List<DiffLine>, which are pure Dart objects
/// safe to use in the UI without touching pointers.
///
/// IMPORTANT: This must run on the background isolate where FFI calls happen.
/// The result (List<DiffHunk>) is then sent back to the main thread.
class DiffParser {
  /// Parse a git_diff into Dart objects
  ///
  /// In production, this would:
  /// 1. Call git_diff_foreach() with callbacks
  /// 2. For each hunk, call the hunk callback
  /// 3. For each line, call the line callback
  /// 4. Build DiffHunk objects with DiffLine children
  /// 5. Return List<DiffHunk>
  ///
  /// For now, returns mock data to demonstrate the API.
  static List<DiffHunk> parse(dynamic gitDiffPointer) {
    debugPrint('[DiffParser] Parsing diff...');

    // TODO: Call actual FFI functions when bindings are ready:
    // final hunks = <DiffHunk>[];
    // 
    // git_diff_foreach(
    //   gitDiffPointer,
    //   fileCallback: null,
    //   binaryCallback: null,
    //   hunkCallback: (delta, hunk, payload) {
    //     // Start new hunk
    //     final lines = <DiffLine>[];
    //     // ... process hunk header
    //   },
    //   lineCallback: (delta, hunk, line, payload) {
    //     // Add line to current hunk
    //     final diffLine = DiffLine(
    //       type: _mapLineType(line.origin),
    //       content: _pointerToString(line.content, line.content_len),
    //       oldLineNumber: line.old_lineno,
    //       newLineNumber: line.new_lineno,
    //     );
    //     lines.add(diffLine);
    //   },
    //   payload: nullptr,
    // );

    // Mock data for demonstration
    return [
      DiffHunk(
        header: '@@ -1,5 +1,6 @@',
        oldStart: 1,
        oldLines: 5,
        newStart: 1,
        newLines: 6,
        lines: [
          const DiffLine(
            type: DiffLineType.context,
            content: 'import "package:flutter/material.dart";',
            oldLineNumber: 1,
            newLineNumber: 1,
          ),
          const DiffLine(
            type: DiffLineType.added,
            content: 'import "package:flutter_riverpod/flutter_riverpod.dart";',
            oldLineNumber: -1,
            newLineNumber: 2,
          ),
          const DiffLine(
            type: DiffLineType.context,
            content: '',
            oldLineNumber: 2,
            newLineNumber: 3,
          ),
          const DiffLine(
            type: DiffLineType.deleted,
            content: 'void main() {',
            oldLineNumber: 3,
            newLineNumber: -1,
          ),
          const DiffLine(
            type: DiffLineType.added,
            content: 'void main() async {',
            oldLineNumber: -1,
            newLineNumber: 4,
          ),
          const DiffLine(
            type: DiffLineType.context,
            content: '  runApp(const MyApp());',
            oldLineNumber: 4,
            newLineNumber: 5,
          ),
          const DiffLine(
            type: DiffLineType.context,
            content: '}',
            oldLineNumber: 5,
            newLineNumber: 6,
          ),
        ],
      ),
      DiffHunk(
        header: '@@ -15,3 +16,7 @@',
        oldStart: 15,
        oldLines: 3,
        newStart: 16,
        newLines: 7,
        lines: [
          const DiffLine(
            type: DiffLineType.context,
            content: 'class MyApp extends StatelessWidget {',
            oldLineNumber: 15,
            newLineNumber: 16,
          ),
          const DiffLine(
            type: DiffLineType.context,
            content: '  const MyApp({super.key});',
            oldLineNumber: 16,
            newLineNumber: 17,
          ),
          const DiffLine(
            type: DiffLineType.context,
            content: '',
            oldLineNumber: 17,
            newLineNumber: 18,
          ),
          const DiffLine(
            type: DiffLineType.added,
            content: '  @override',
            oldLineNumber: -1,
            newLineNumber: 19,
          ),
          const DiffLine(
            type: DiffLineType.added,
            content: '  Widget build(BuildContext context) {',
            oldLineNumber: -1,
            newLineNumber: 20,
          ),
          const DiffLine(
            type: DiffLineType.added,
            content: '    return ProviderScope(',
            oldLineNumber: -1,
            newLineNumber: 21,
          ),
          const DiffLine(
            type: DiffLineType.added,
            content: '      child: MaterialApp(',
            oldLineNumber: -1,
            newLineNumber: 22,
          ),
        ],
      ),
    ];
  }

  /// Map libgit2 line origin to DiffLineType
  static DiffLineType _mapLineType(String origin) {
    switch (origin) {
      case '+':
        return DiffLineType.added;
      case '-':
        return DiffLineType.deleted;
      case ' ':
        return DiffLineType.context;
      case '@':
        return DiffLineType.header;
      default:
        return DiffLineType.context;
    }
  }

  /// Parse a diff from file paths (convenience method)
  ///
  /// This would create a git_diff by comparing two trees or
  /// the working directory to HEAD.
  static Future<List<DiffHunk>> parseFile({
    required String repoPath,
    required String filePath,
  }) async {
    debugPrint('[DiffParser] Parsing file: $filePath in $repoPath');

    // TODO: Create git_diff for the file, then call parse()
    // 1. git_repository_open(repoPath)
    // 2. git_repository_head()
    // 3. git_tree_lookup()
    // 4. git_diff_tree_to_workdir()
    // 5. Filter to specific file
    // 6. Call parse() on the diff

    // For now, return mock data
    return parse(null);
  }

  /// Parse a diff between two commits
  static Future<List<DiffHunk>> parseCommits({
    required String repoPath,
    required String oldCommit,
    required String newCommit,
    String? filePath,
  }) async {
    debugPrint('[DiffParser] Parsing commits: $oldCommit..$newCommit');

    // TODO: Create git_diff between two commits
    // 1. git_repository_open(repoPath)
    // 2. git_commit_lookup(oldCommit)
    // 3. git_commit_lookup(newCommit)
    // 4. git_commit_tree() for each
    // 5. git_diff_tree_to_tree()
    // 6. Filter to specific file if provided
    // 7. Call parse() on the diff

    return parse(null);
  }

  /// Get a summary of changes (added/deleted line counts)
  static DiffSummary summarize(List<DiffHunk> hunks) {
    var added = 0;
    var deleted = 0;
    var context = 0;

    for (final hunk in hunks) {
      added += hunk.addedCount;
      deleted += hunk.deletedCount;
      context += hunk.contextCount;
    }

    return DiffSummary(
      added: added,
      deleted: deleted,
      context: context,
      hunkCount: hunks.length,
    );
  }
}

/// Summary of diff statistics
class DiffSummary {
  final int added;
  final int deleted;
  final int context;
  final int hunkCount;

  const DiffSummary({
    required this.added,
    required this.deleted,
    required this.context,
    required this.hunkCount,
  });

  int get totalLines => added + deleted + context;

  @override
  String toString() => '+$added/-$deleted ($hunkCount hunks, $totalLines lines)';
}
