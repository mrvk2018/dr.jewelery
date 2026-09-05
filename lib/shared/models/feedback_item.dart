/// Сообщение обратной связи от клиента.
class FeedbackItem {
  FeedbackItem({
    required this.id,
    required this.message,
    required this.languageCode,
    required this.createdAt,
  });

  final String id;
  final String message;
  final String languageCode;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'message': message,
        'languageCode': languageCode,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FeedbackItem.fromJson(Map<String, dynamic> json) {
    return FeedbackItem(
      id: json['id'] as String,
      message: json['message'] as String,
      languageCode: json['languageCode'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  String get languageBadge => languageCode.toUpperCase();

  String get formattedDateTime {
    final day = createdAt.day.toString().padLeft(2, '0');
    final month = createdAt.month.toString().padLeft(2, '0');
    final year = createdAt.year;
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '$day.$month.$year · $hour:$minute';
  }
}
