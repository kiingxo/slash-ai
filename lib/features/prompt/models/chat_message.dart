// ChatMessage model for chat bubbles
import 'review_data.dart';

class ChatMessage {
  final bool isUser;
  final String text;
  final ReviewData? review;
  ChatMessage({required this.isUser, required this.text, this.review});
} 