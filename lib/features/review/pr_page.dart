import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'package:flutter/services.dart';

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
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    physics: const BouncingScrollPhysics(),
                    itemCount: prs.length,
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
                      final theme = Theme.of(context);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Material(
                          color: theme.cardColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.08)),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showPRDetail(context, pr),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(radius: 14, child: SlashText('#$number', fontSize: 11)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SlashText(title, fontWeight: FontWeight.w600),
                                        const SizedBox(height: 4),
                                        SlashText('$repoFull • $author • ${created.toLocal().toString().split(".").first}', fontSize: 12, color: theme.textTheme.bodySmall?.color),
                                        if (labels.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 6),
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: -8,
                                              children: labels.take(4).map((l) {
                                                final name = (l['name'] ?? '').toString();
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: theme.colorScheme.primary.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: SlashText(name, fontSize: 10, color: theme.colorScheme.primary),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                            ),
                          ),
                        ),
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
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final title = pr['title'] ?? '';
        final body = pr['body'] ?? '';
        final htmlUrl = pr['html_url'] ?? '';
        // Extract owner/repo/number and head sha
        final repoUrl = (pr['repository_url'] ?? '') as String;
        final parts = repoUrl.split('/');
        final owner = parts.length >= 2 ? parts[parts.length - 2] : '';
        final repo = parts.isNotEmpty ? parts.last : '';
        final number = pr['number']?.toString() ?? '';

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return SafeArea(
              top: false,
              child: FutureBuilder<_PRDetailData>(
                future: _fetchPRDetail(owner, repo, number),
                builder: (context, snapshot) {
                  final loading = snapshot.connectionState != ConnectionState.done;
                  final data = snapshot.data;
                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                      Wrap(
                        spacing: 6,
                        runSpacing: -8,
                        children: [
                          _chip(
                            icon: data?.isDraft == true ? Icons.hourglass_empty : Icons.flag_circle,
                            label: data?.isDraft == true ? 'Draft' : 'Ready',
                            color: data?.isDraft == true ? Colors.grey : Colors.indigo,
                          ),
                          if (data?.mergeableState != null)
                            _chip(
                              icon: data!.mergeable == true ? Icons.check_circle : Icons.block,
                              label: 'Mergeable: ${data.mergeableState}',
                              color: data.mergeable == true ? Colors.green : Colors.red,
                            ),
                          if (data?.ciState != null)
                            _chip(
                              icon: data!.ciState == 'success'
                                  ? Icons.verified
                                  : (data.ciState == 'failure' ? Icons.error : Icons.more_horiz),
                              label: 'CI: ${data.ciState}',
                              color: data.ciState == 'success'
                                  ? Colors.green
                                  : (data.ciState == 'failure' ? Colors.red : Colors.orange),
                            ),
                          _chip(icon: Icons.tag, label: '#$number', color: Colors.blueGrey),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (body is String && body.trim().isNotEmpty)
                        SlashText(body)
                      else
                        const SlashText('No description'),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const SlashText('Open in GitHub', fontSize: 12),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: htmlUrl));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: SlashText('PR link copied to clipboard')),
                              );
                            },
                          ),
                          if (!loading)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.check, size: 16),
                              label: const SlashText('Approve', fontSize: 12),
                              onPressed: () => _submitReview(context, owner, repo, number, 'APPROVE'),
                            ),
                          if (!loading)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.rate_review, size: 16),
                              label: const SlashText('Request changes', fontSize: 12),
                              onPressed: () => _submitReview(context, owner, repo, number, 'REQUEST_CHANGES'),
                            ),
                          if (!loading)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.merge, size: 16),
                              label: const SlashText('Merge', fontSize: 12),
                              onPressed: (data?.mergeable == true)
                                  ? () => _mergePR(context, owner, repo, number)
                                  : null,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!loading)
                        _ReviewCommentBox(
                          onSubmit: (text) => _submitReview(context, owner, repo, number, 'COMMENT', body: text),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _PRDetailData {
  final bool? isDraft;
  final bool? mergeable;
  final String? mergeableState; // clean, blocked, unstable, dirty, unknown
  final String? ciState; // success, failure, pending, null
  _PRDetailData({this.isDraft, this.mergeable, this.mergeableState, this.ciState});
}

Future<_PRDetailData> _fetchPRDetail(String owner, String repo, String number) async {
  final pat = await SecureStorageService().getApiKey('github_pat');
  final headers = {
    'Authorization': 'token $pat',
    'Accept': 'application/vnd.github+json',
  };
  final prRes = await http.get(
    Uri.parse('https://api.github.com/repos/$owner/$repo/pulls/$number'),
    headers: headers,
  );
  if (prRes.statusCode != 200) return _PRDetailData();
  final pr = jsonDecode(prRes.body) as Map<String, dynamic>;
  final draft = pr['draft'] == true;
  final mergeable = pr['mergeable'] as bool?;
  final mergeableState = pr['mergeable_state'] as String?; // may be null/unknown
  final sha = pr['head']?['sha'] as String?;
  String? ciState;
  if (sha != null) {
    final statusRes = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/commits/$sha/status'),
      headers: headers,
    );
    if (statusRes.statusCode == 200) {
      final status = jsonDecode(statusRes.body) as Map<String, dynamic>;
      ciState = (status['state'] as String?); // success, failure, pending
    }
  }
  return _PRDetailData(isDraft: draft, mergeable: mergeable, mergeableState: mergeableState, ciState: ciState);
}

Widget _chip({required IconData icon, required String label, required Color color}) {
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

class _ReviewCommentBox extends StatefulWidget {
  final Future<void> Function(String text) onSubmit;
  const _ReviewCommentBox({required this.onSubmit});

  @override
  State<_ReviewCommentBox> createState() => _ReviewCommentBoxState();
}

class _ReviewCommentBoxState extends State<_ReviewCommentBox> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Optional review comment…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: _submitting
                ? null
                : () async {
                    final text = _controller.text.trim();
                    setState(() => _submitting = true);
                    try {
                      await widget.onSubmit(text);
                      _controller.clear();
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: SlashText('Review submitted')),
                      );
                    } catch (e) {
                      // ignore: use_build_context_synchronously
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: SlashText('Failed: $e')),
                      );
                    } finally {
                      if (mounted) setState(() => _submitting = false);
                    }
                  },
            child: _submitting
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const SlashText('Comment'),
          ),
        ),
      ],
    );
  }
}

Future<void> _submitReview(BuildContext context, String owner, String repo, String number, String event, {String? body}) async {
  final pat = await SecureStorageService().getApiKey('github_pat');
  final headers = {
    'Authorization': 'token $pat',
    'Accept': 'application/vnd.github+json',
  };
  final res = await http.post(
    Uri.parse('https://api.github.com/repos/$owner/$repo/pulls/$number/reviews'),
    headers: headers,
    body: jsonEncode({
      if (body != null && body.isNotEmpty) 'body': body,
      'event': event,
    }),
  );
  if (res.statusCode != 200 && res.statusCode != 201) {
    throw Exception('Review failed: ${res.body}');
  }
}

Future<void> _mergePR(BuildContext context, String owner, String repo, String number) async {
  final pat = await SecureStorageService().getApiKey('github_pat');
  final headers = {
    'Authorization': 'token $pat',
    'Accept': 'application/vnd.github+json',
  };
  final res = await http.put(
    Uri.parse('https://api.github.com/repos/$owner/$repo/pulls/$number/merge'),
    headers: headers,
    body: jsonEncode({
      'merge_method': 'squash',
    }),
  );
  if (res.statusCode != 200) {
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: SlashText('Merge failed: ${res.body}')));
    return;
  }
  // ignore: use_build_context_synchronously
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: SlashText('Merged successfully')));
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


