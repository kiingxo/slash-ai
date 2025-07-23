import 'package:flutter/material.dart';
import '../../../ui/components/slash_text_field.dart';
import '../../../ui/components/slash_button.dart';

class ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool loading;
  const ChatInput({
    super.key,
    required this.controller,
    required this.onSend,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SlashTextField(
            controller: controller,
            hint: 'Ask about this code…',
            minLines: 1,
            maxLines: 3,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 36,
          height: 36,
          child: SlashButton(
            label: '',
            onTap: loading ? () {} : onSend,
            icon: Icons.send,
          ),
        ),
      ],
    );
  }
} 