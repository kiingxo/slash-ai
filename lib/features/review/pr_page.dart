import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:slash_flutter/ui/components/slash_text.dart';

import '../../services/secure_storage_service.dart';
import '../repo/repo_controller.dart';

// Fetch all open PRs involving the authenticated user across repos
final prFilterProvider = StateProvider.autoDispose<String>((_) => 'all'); // all | author | assigned | review_requested
final prRepoScopeProvider = StateProvider.autoDispose<String?>((_) => null); // "owner/repo" or null
final prQueryProvider = StateProvider.autoDispose<String>((_) => ''); // title/body query

final prListProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final pat = await SecureStorageService().getApiKey('github_pat');
  if (pat == null || pat.isEmpty) return const [];

  // Get authenticated username
  final meRes = await http.get(
    Uri.parse('https://api.github.com/user'),
    headers: {
      'Authorization': 'token $pat',
      'Accept': 'application/vnd.github+json',
    },
  );
  if (meRes.statusCode != 200) return const [];
  final login = (jsonDecode(meRes.body) as Map<String, dynamic>)['login'];
  if (login is! String || login.isEmpty) return const [];

  final filter = ref.watch(prFilterProvider);
  final scopedRepo = ref.watch(prRepoScopeProvider);
  final query = ref.watch(prQueryProvider).trim();

  // Build search query based on filter
  String who;
  switch (filter) {
    case 'author':
      who = 'author:$login';
      break;
    case 'assigned':
      who = 'assignee:$login';
      break;
    case 'review_requested':
      who = 'review-requested:$login';
      break;
    default:
      who = 'involves:$login';
  }

  final repoQualifier = (scopedRepo != null && scopedRepo.trim().isNotEmpty)
      ? ' repo:${scopedRepo.trim()}'
      : '';

  final searchTerm = query.isEmpty ? '' : ' $query';
  final q = Uri.encodeQueryComponent('is:pr is:open $who$repoQualifier$searchTerm');
  final searchUrl = Uri.parse('https://api.github.com/search/issues?q=$q&per_page=50');
  final res = await http.get(searchUrl, headers: {
    'Authorization': 'token $pat',
    'Accept': 'application/vnd.github+json',
  });
  if (res.statusCode != 200) return const [];
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final items = (data['items'] as List).cast<Map<String, dynamic>>();
  return items;
});

class PRsPage extends ConsumerWidget {
  const PRsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPRs = ref.watch(prListProvider);
    final repoState = ref.watch(repoControllerProvider);
    final selected = repoState.selectedRepo ?? (repoState.repos.isNotEmpty ? repoState.repos.first : null);

    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Pull Requests', fontWeight: FontWeight.bold),
        centerTitle: false,
        actions: [
          // quick search
          IconButton(
            tooltip: 'Search',
            onPressed: () => _showSearchSheet(context, ref),
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_alt_outlined),
            initialValue: ref.read(prFilterProvider),
            onSelected: (v) {
              ref.read(prFilterProvider.notifier).state = v;
              ref.invalidate(prListProvider);
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'all', child: Text('All involving me')),
              PopupMenuItem(value: 'author', child: Text('Authored by me')),
              PopupMenuItem(value: 'assigned', child: Text('Assigned to me')),
              PopupMenuItem(value: 'review_requested', child: Text('Review requested')),
            ],
          ),
          IconButton(
            tooltip: 'Toggle repo scope',
            onPressed: () {
              if (selected == null) return;
              final full = '${selected['owner']['login']}/${selected['name']}';
              final current = ref.read(prRepoScopeProvider);
              ref.read(prRepoScopeProvider.notifier).state = current == full ? null : full;
              ref.invalidate(prListProvider);
            },
            icon: Icon(
              ref.watch(prRepoScopeProvider) == null ? Icons.public : Icons.source,
            ),
          ),
        ],
      ),
      body: asyncPRs.when(
              data: (prs) {
                if (prs.isEmpty) {
                  return const Center(child: SlashText('No open PRs'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(prListProvider);
                    await ref.read(prListProvider.future);
                  },
                  child: ListView.separated(
                    itemCount: prs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final pr = prs[i];
                      final title = pr['title'] ?? 'Untitled';
                      final number = pr['number'];
                      final repoUrl = (pr['repository_url'] ?? '') as String;
                      final parts = repoUrl.split('/');
                      final repoFull = parts.length >= 2 ? '${parts[parts.length - 2]}/${parts.last}' : '';
                      final author = pr['user']?['login'] ?? 'unknown';
                      final created = DateTime.tryParse(pr['created_at'] ?? '') ?? DateTime.now();
                      final labels = (pr['labels'] is List) ? (pr['labels'] as List).cast<Map<String, dynamic>>() : const <Map<String, dynamic>>[];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(child: SlashText('#$number', fontSize: 11)),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SlashText(title, fontWeight: FontWeight.w600),
                            if (labels.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: -8,
                                  children: labels.take(4).map((l) {
                                    final name = (l['name'] ?? '').toString();
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: SlashText(name, fontSize: 10, color: Colors.blue),
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        ),
                        subtitle: SlashText('$repoFull • $author • ${created.toLocal().toString().split(".").first}', fontSize: 12),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showPRDetail(context, pr),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(child: SlashText('Failed to load PRs: $e')),
            ),
    );
  }

  void _showPRDetail(BuildContext context, Map<String, dynamic> pr) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final title = pr['title'] ?? '';
        final body = pr['body'] ?? '';
        final htmlUrl = pr['html_url'] ?? '';
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.merge_type, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: SlashText(title, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 8),
                if (body is String && body.trim().isNotEmpty)
                  SlashText(body)
                else
                  const SlashText('No description'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const SlashText('Open in GitHub', fontSize: 12),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: SlashText(htmlUrl)));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

void _showSearchSheet(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController(text: ref.read(prQueryProvider));
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SlashText('Search PRs', fontWeight: FontWeight.bold),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Filter by keywords (title/body)…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) {
                  ref.read(prQueryProvider.notifier).state = controller.text;
                  ref.invalidate(prListProvider);
                  Navigator.of(ctx).pop();
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      ref.read(prQueryProvider.notifier).state = controller.text;
                      ref.invalidate(prListProvider);
                      Navigator.of(ctx).pop();
                    },
                    child: const SlashText('Apply'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      controller.clear();
                      ref.read(prQueryProvider.notifier).state = '';
                      ref.invalidate(prListProvider);
                      Navigator.of(ctx).pop();
                    },
                    child: const SlashText('Clear'),
                  )
                ],
              )
            ],
          ),
        ),
      );
    },
  );
}


