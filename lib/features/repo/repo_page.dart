import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'repo_controller.dart';
import '../file_browser/file_browser_page.dart';
import '../../common/widgets/widgets.dart';

class RepoPage extends ConsumerWidget {
  const RepoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoState = ref.watch(repoControllerProvider);
    final controller = ref.read(repoControllerProvider.notifier);

    void _onRepoTap(dynamic repo) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FileBrowserPage(
            owner: repo['owner']['login'],
            repo: repo['name'],
          ),
        ),
      );
      controller.selectRepo(repo);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Your Git Repositories')),
      body: repoState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : repoState.error != null
              ? Center(child: Text(friendlyErrorMessage(repoState.error), style: const TextStyle(color: Colors.red)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: repoState.repos.length,
                  separatorBuilder: (context, idx) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) {
                    final repo = repoState.repos[idx];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          child: Text(
                            repo['owner']['login'][0].toUpperCase(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          repo['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                          ),
                        ),
                        subtitle: repo['description'] != null && repo['description'].toString().trim().isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  repo['description'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : null,
                        trailing: const Icon(Icons.chevron_right_rounded, size: 28),
                        onTap: () => _onRepoTap(repo),
                      ),
                    );
                  },
                ),
    );
  }
} 