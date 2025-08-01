import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/features/pr/pr_controller.dart';
import 'package:slash_flutter/features/pr/pr_create_page.dart';
import 'package:slash_flutter/features/pr/pr_detail_page.dart';
import 'package:slash_flutter/features/repo/repo_controller.dart';
import 'package:slash_flutter/ui/components/slash_loading.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';

class PrPage extends ConsumerStatefulWidget {
  const PrPage({super.key});

  @override
  ConsumerState<PrPage> createState() => _PrPageState();
}

class _PrPageState extends ConsumerState<PrPage> {
  @override
  void initState() {
    super.initState();
    // Defer loading until a repo is selected; avoid throwing when none is selected.
    Future.microtask(() {
      final repo = ref.read(repoControllerProvider).selectedRepo;
      if (repo != null) {
        ref.read(prControllerProvider.notifier).loadOpenPrs();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prState = ref.watch(prControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.merge_type, size: 18),
            const SizedBox(width: 6),
            const SlashText('Pull Requests', fontSize: 18, fontWeight: FontWeight.bold),
            const Spacer(),
            // Inline repo selector chip
            Consumer(
              builder: (context, ref, _) {
                final repoState = ref.watch(repoControllerProvider);
                final repos = repoState.repos;
                final selectedRepo = repoState.selectedRepo;
                final label = selectedRepo != null
                    ? (selectedRepo['full_name'] ?? selectedRepo['name'])
                    : 'Select repo';
                return PopupMenuButton<dynamic>(
                  tooltip: 'Select repository',
                  itemBuilder: (ctx) => repos
                      .map<PopupMenuItem<dynamic>>(
                        (r) => PopupMenuItem<dynamic>(
                          value: r,
                          child: Text(r['full_name'] ?? r['name']),
                        ),
                      )
                      .toList(),
                  onSelected: (repo) {
                    ref.read(repoControllerProvider.notifier).selectRepo(repo);
                    ref.read(prControllerProvider.notifier).loadOpenPrs();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.source, size: 16),
                        const SizedBox(width: 6),
                        Text(label, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, size: 16),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(prControllerProvider.notifier).loadOpenPrs(),
              tooltip: 'Refresh',
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () async {
                final repo = ref.read(repoControllerProvider).selectedRepo;
                if (repo == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Select a repository first.')),
                  );
                  return;
                }
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrCreatePage()),
                );
                ref.read(prControllerProvider.notifier).loadOpenPrs();
              },
              icon: const Icon(Icons.add),
              label: const SlashText('Create PR'),
            ),
          ],
        ),
      ),
      body: Builder(
        builder: (context) {
          final repo = ref.watch(repoControllerProvider).selectedRepo;
          if (repo == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SlashText('Select a repository to view PRs.'),
                  SizedBox(height: 8),
                  SlashText('Use the repo dropdown in the top-right.', fontSize: 12),
                ],
              ),
            );
          }
          if (prState.loading) {
            return const Center(child: SlashLoading());
          }
          if (prState.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SlashText(
                  prState.error!,
                  color: theme.colorScheme.error,
                ),
              ),
            );
          }
          if (prState.prs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.inbox_outlined, size: 36),
                  SizedBox(height: 8),
                  SlashText('No open PRs', fontSize: 14),
                  SizedBox(height: 4),
                  SlashText('Create one using the button above.', fontSize: 12),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: prState.prs.length,
            separatorBuilder: (_, __) => const Divider(height: 0.5),
            itemBuilder: (context, index) {
              final pr = prState.prs[index];
              final badgeColor = pr.state == 'open'
                  ? Colors.green.withOpacity(0.12)
                  : Colors.grey.withOpacity(0.12);
              final badgeText = pr.state.toUpperCase();
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await ref.read(prControllerProvider.notifier).loadPrDetail(pr.number);
                    if (mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PrDetailPage(prNumber: pr.number),
                        ),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          child: const Icon(Icons.merge_type, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SlashText(
                                '#${pr.number}  ${pr.title}',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              const SizedBox(height: 4),
                              SlashText(
                                'by ${pr.author} • ${pr.headRef} → ${pr.baseRef}',
                                fontSize: 12,
                                color: theme.hintColor,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            badgeText,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
