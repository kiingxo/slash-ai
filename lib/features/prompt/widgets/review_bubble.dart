import 'package:flutter/material.dart';
import '../models/review_data.dart';
import '../../../ui/components/slash_diff_viewer.dart';

class ReviewBubble extends StatelessWidget {
  final ReviewData review;
  final String summary;
  final bool isLast;
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback? onEdit;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  const ReviewBubble({
    super.key,
    required this.review,
    required this.summary,
    required this.isLast,
    required this.expanded,
    required this.onExpand,
    this.onEdit,
    this.onApprove,
    this.onReject,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.android,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: onExpand,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            summary,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (expanded && isLast) ...[
              const SizedBox(height: 8),
              Text(
                review.fileName,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              SlashDiffViewer(
                oldContent: review.oldContent,
                newContent: review.newContent,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blueAccent),
                      tooltip: 'Edit code',
                      onPressed: onEdit,
                    ),
                  if (onApprove != null)
                    IconButton(
                      icon: const Icon(Icons.check_circle, color: Colors.green, size: 22),
                      tooltip: 'Approve and PR',
                      onPressed: onApprove,
                    ),
                  if (onReject != null)
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red, size: 22),
                      tooltip: 'Reject',
                      onPressed: onReject,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
} 