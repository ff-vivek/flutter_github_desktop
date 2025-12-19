import 'diff_line.dart';

/// A hunk in a diff (contiguous block of changes)
///
/// Pure Dart data class with no FFI dependencies.
/// Contains multiple DiffLines that represent a logical group of changes.
class DiffHunk {
  final String header;
  final int oldStart;
  final int oldLines;
  final int newStart;
  final int newLines;
  final List<DiffLine> lines;

  const DiffHunk({
    required this.header,
    required this.oldStart,
    required this.oldLines,
    required this.newStart,
    required this.newLines,
    required this.lines,
  });

  /// Create from JSON (for isolate communication)
  factory DiffHunk.fromJson(Map<String, dynamic> json) {
    return DiffHunk(
      header: json['header'] as String,
      oldStart: json['oldStart'] as int,
      oldLines: json['oldLines'] as int,
      newStart: json['newStart'] as int,
      newLines: json['newLines'] as int,
      lines: (json['lines'] as List)
          .map((line) => DiffLine.fromJson(line as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Convert to JSON (for isolate communication)
  Map<String, dynamic> toJson() => {
        'header': header,
        'oldStart': oldStart,
        'oldLines': oldLines,
        'newStart': newStart,
        'newLines': newLines,
        'lines': lines.map((line) => line.toJson()).toList(),
      };

  /// Count added lines
  int get addedCount => lines.where((l) => l.type == DiffLineType.added).length;

  /// Count deleted lines
  int get deletedCount => lines.where((l) => l.type == DiffLineType.deleted).length;

  /// Count context lines
  int get contextCount => lines.where((l) => l.type == DiffLineType.context).length;

  /// Create a copy with modified fields
  DiffHunk copyWith({
    String? header,
    int? oldStart,
    int? oldLines,
    int? newStart,
    int? newLines,
    List<DiffLine>? lines,
  }) {
    return DiffHunk(
      header: header ?? this.header,
      oldStart: oldStart ?? this.oldStart,
      oldLines: oldLines ?? this.oldLines,
      newStart: newStart ?? this.newStart,
      newLines: newLines ?? this.newLines,
      lines: lines ?? this.lines,
    );
  }

  @override
  String toString() => 'DiffHunk($header, +$addedCount/-$deletedCount, ${lines.length} lines)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiffHunk &&
        other.header == header &&
        other.oldStart == oldStart &&
        other.oldLines == oldLines &&
        other.newStart == newStart &&
        other.newLines == newLines &&
        _listEquals(other.lines, lines);
  }

  @override
  int get hashCode => Object.hash(
        header,
        oldStart,
        oldLines,
        newStart,
        newLines,
        Object.hashAll(lines),
      );

  static bool _listEquals(List<DiffLine> a, List<DiffLine> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
