import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/features/pr/pr_controller.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'package:slash_flutter/ui/components/slash_loading.dart';
import 'package:slash_flutter/ui/components/slash_diff_viewer.dart';

class PrDetailPage extends ConsumerWidget {
  final int prNumber;
  const PrDetailPage({super.key, required this.prNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prState = ref.watch(prControllerProvider);
    final controller = ref.read(prControllerProvider.notifier);
    final selected = prState.selected;

    return Scaffold(
      appBar: AppBar(
        title: SlashText('PR #$prNumber', fontWeight: FontWeight.bold, fontSize: 16),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.loadPrDetail(prNumber),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: prState.loading ? null : () => controller.mergePr(prNumber),
            child: const SlashText('Merge'),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: prState.loading ? null : () => controller.closePr(prNumber),
            child: const SlashText('Close'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: prState.loading
          ? const Center(child: SlashLoading())
          : prState.error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SlashText(
                      prState.error!,
                      color: theme.colorScheme.error,
                    ),
                  ),
                )
              : selected == null
                  ? const Center(child: SlashText('PR not loaded'))
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SlashText(
                                  selected.item.title,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                const SizedBox(height: 4),
                                SlashText(
                                  'by ${selected.item.author} • ${selected.item.state} • ${selected.item.headRef} → ${selected.item.baseRef}',
                                  fontSize: 12,
                                  color: theme.hintColor,
                                ),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () {},
                                  child: SlashText(
                                    selected.item.url,
                                    fontSize: 12,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SlashText('Files changed', fontWeight: FontWeight.bold),
                        const SizedBox(height: 8),
                        ...selected.files.map((f) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SlashText(
                                    '${f.status.toUpperCase()}  ${f.filename}',
                                    fontWeight: FontWeight.bold,
                                  ),
                                  const SizedBox(height: 8),
                                  if (f.patch.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: SelectableText(
                                          f.patch,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    SlashText(
                                      '(No diff patch available)',
                                      fontSize: 12,
                                      color: theme.hintColor,
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
    );
  }
}
