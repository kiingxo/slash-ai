import 'package:flutter/material.dart';
import '../theme/colors.dart';

class SlashDiffViewer extends StatelessWidget {
  final String oldContent;
  final String newContent;

  const SlashDiffViewer({super.key, required this.oldContent, required this.newContent});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final oldBg = isDark ? SlashColors.diffOldDark : SlashColors.diffOldLight;
    final newBg = isDark ? SlashColors.diffNewDark : SlashColors.diffNewLight;
    final oldText = isDark ? Colors.red[200] : Colors.red[900];
    final newText = isDark ? Colors.green[200] : Colors.green[900];
    // For production, use a real diff package or custom widget
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Old', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: oldText)),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: oldBg,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Text(
            oldContent,
            style: TextStyle(
              fontFamily: 'Fira Mono',
              fontSize: 13,
              color: oldText,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('/Slash ', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: newText)),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: newBg,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Text(
            newContent,
            style: TextStyle(
              fontFamily: 'Fira Mono',
              fontSize: 13,
              color: newText,
            ),
          ),
        ),
      ],
    );
  }
} 