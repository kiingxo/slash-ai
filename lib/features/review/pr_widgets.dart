import 'package:flutter/material.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';

Widget prLabelChip(BuildContext context, String name) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: theme.colorScheme.primary.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: SlashText(name, fontSize: 10, color: theme.colorScheme.primary),
  );
}

Widget statusChip({required IconData icon, required String label, required Color color}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        SlashText(label, fontSize: 11, color: color),
      ],
    ),
  );
}


