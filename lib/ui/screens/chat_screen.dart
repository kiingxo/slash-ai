import 'package:flutter/material.dart';
import '../components/slash_text_field.dart';
import '../components/slash_button.dart';
import '../theme/shadows.dart';

class ChatScreen extends StatelessWidget {
  final TextEditingController controller = TextEditingController();

  ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // TODO: Render chat bubbles/messages here
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: SlashShadows.cardShadow,
                      ),
                      child: Text('Hi! I\'m /slash. How can I help you today?', style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: SlashTextField(
                      controller: controller,
                      hint: 'Type a prompt…',
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SlashButton(
                    label: 'Send',
                    onTap: () {},
                    icon: Icons.send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 