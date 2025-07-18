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
    return Card(
      color: isDark ? const Color(0xFF23232A) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: isDark ? Colors.grey[900]! : Colors.grey[300]!)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.remove_circle, color: oldText, size: 18),
                const SizedBox(width: 6),
                Text('Original', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: oldText, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: oldBg,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              child: _buildCodeBlock(oldContent, oldText, isDark),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.add_circle, color: newText, size: 18),
                const SizedBox(width: 6),
                Text('Edited', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: newText, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: newBg,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              child: _buildCodeBlock(newContent, newText, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeBlock(String content, Color? textColor, bool isDark) {
    final lines = content.split('\n');
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < lines.length; i++)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: isDark ? Colors.grey[600] : Colors.grey[500],
                            fontSize: 11,
                            fontFamily: 'Fira Mono',
                          ),
                        ),
                      ),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          lines[i],
                          style: TextStyle(
                            fontFamily: 'Fira Mono',
                            fontSize: 13,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
} 