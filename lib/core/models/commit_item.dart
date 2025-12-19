class CommitItem {
  final String hash;
  final String message;
  final String author;
  final DateTime time;

  const CommitItem({required this.hash, required this.message, required this.author, required this.time});

  factory CommitItem.fromJson(Map<String, dynamic> json) => CommitItem(
        hash: json['hash'] as String? ?? '',
        message: json['message'] as String? ?? '',
        author: json['author'] as String? ?? 'unknown',
        time: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as num? ?? 0).toInt(), isUtc: false),
      );
}
