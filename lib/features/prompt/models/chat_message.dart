import 'review_data.dart';

class ChatMessage {
  final bool isUser;
  final String text;

  // Optional: future extension points
  final DateTime? timestamp;

  // Optional review payload to support review bubbles in UI
  final ReviewData? review;

  const ChatMessage({
    required this.isUser,
    required this.text,
    this.timestamp,
    this.review,
  });

  ChatMessage copyWith({
    bool? isUser,
    String? text,
    DateTime? timestamp,
    ReviewData? review,
  }) {
    return ChatMessage(
      isUser: isUser ?? this.isUser,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      review: review ?? this.review,
    );
  }

  Map<String, dynamic> toJson() => {
        'isUser': isUser,
        'text': text,
        'timestamp': timestamp?.toIso8601String(),
        'review': review?.toJson(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        isUser: (json['isUser'] as bool?) ?? false,
        text: (json['text'] as String?) ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String)
            : null,
        review: json['review'] != null
            ? ReviewData.fromJson(json['review'] as Map<String, dynamic>)
            : null,
      );
}
