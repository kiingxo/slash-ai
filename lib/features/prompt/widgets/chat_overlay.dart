import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import 'chat_bubble.dart';
import 'chat_input.dart';

class ChatOverlay extends StatelessWidget {
  final List<ChatMessage> messages;
  final bool loading;
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onClose;
  final VoidCallback? onApplyEdit;
  const ChatOverlay({
    super.key,
    required this.messages,
    required this.loading,
    required this.controller,
    required this.onSend,
    required this.onClose,
    this.onApplyEdit,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 280,
        height: 340,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(blurRadius: 16, color: Colors.black26)],
        ),
        child: Column(
          children: [
            // Header
            Container(
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Icon(Icons.chat_bubble, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('AI Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: onClose,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            // Messages
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: messages.length + (loading ? 1 : 0),
                itemBuilder: (context, idx) {
                  if (idx == messages.length && loading) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final msg = messages[idx];
                  return ChatBubble(
                    isUser: msg.isUser,
                    text: msg.text,
                    emoji: msg.isUser ? null : '🤖',
                  );
                },
              ),
            ),
            if (onApplyEdit != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Apply AI Edit to Code', style: TextStyle(fontSize: 13)),
                    onPressed: onApplyEdit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: ChatInput(
                controller: controller,
                onSend: onSend,
                loading: loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 