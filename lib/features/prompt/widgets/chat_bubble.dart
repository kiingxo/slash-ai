import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final bool isUser;
  final String text;
  final String? emoji;
  const ChatBubble({
    super.key,
    required this.isUser,
    required this.text,
    this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary.withOpacity(0.12)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isUser
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && emoji != null)
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 2),
                child: Text(
                  emoji!,
                  style: TextStyle(
                    fontSize: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            Flexible(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  color: isUser ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 