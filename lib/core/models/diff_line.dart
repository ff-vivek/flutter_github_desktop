/// Types of diff lines
enum DiffLineType {
  context,   // Unchanged line (white)
  added,     // Added line (green)
  deleted,   // Deleted line (red)
  header,    // Diff header (gray)
}

/// A single line in a diff
///
/// Pure Dart data class with no FFI dependencies.
/// Safe to use in UI without touching pointers.
class DiffLine {
  final DiffLineType type;
  final String content;
  final int oldLineNumber;
  final int newLineNumber;

  const DiffLine({
    required this.type,
    required this.content,
    required this.oldLineNumber,
    required this.newLineNumber,
  });

  /// Create from JSON (for isolate communication)
  factory DiffLine.fromJson(Map<String, dynamic> json) {
    return DiffLine(
      type: DiffLineType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DiffLineType.context,
      ),
      content: json['content'] as String,
      oldLineNumber: json['oldLineNumber'] as int,
      newLineNumber: json['newLineNumber'] as int,
    );
  }

  /// Convert to JSON (for isolate communication)
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'content': content,
        'oldLineNumber': oldLineNumber,
        'newLineNumber': newLineNumber,
      };

  /// Create a copy with modified fields
  DiffLine copyWith({
    DiffLineType? type,
    String? content,
    int? oldLineNumber,
    int? newLineNumber,
  }) {
    return DiffLine(
      type: type ?? this.type,
      content: content ?? this.content,
      oldLineNumber: oldLineNumber ?? this.oldLineNumber,
      newLineNumber: newLineNumber ?? this.newLineNumber,
    );
  }

  @override
  String toString() => 'DiffLine($type, "$content", old: $oldLineNumber, new: $newLineNumber)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiffLine &&
        other.type == type &&
        other.content == content &&
        other.oldLineNumber == oldLineNumber &&
        other.newLineNumber == newLineNumber;
  }

  @override
  int get hashCode =>
      Object.hash(type, content, oldLineNumber, newLineNumber);
}
