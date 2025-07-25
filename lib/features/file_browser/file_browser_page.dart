import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'file_browser_controller.dart';
import '../../common/widgets/widgets.dart';

class FileBrowserPage extends ConsumerWidget {
  final String owner;
  final String repo;
  final String? branch;
  const FileBrowserPage({
    super.key,
    required this.owner,
    required this.repo,
    this.branch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = RepoParams(owner: owner, repo: repo, branch: branch);
    final state = ref.watch(fileBrowserControllerProvider(params));
    final controller = ref.read(fileBrowserControllerProvider(params).notifier);

    return Scaffold(
      appBar: AppBar(
        title: SlashText('Browse: $repo'),
        leading:
            state.pathStack.isNotEmpty
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: controller.goUp,
                )
                : null,
      ),
      body:
          state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : state.error != null
              ? Center(
                child: SlashText(
                  friendlyErrorMessage(state.error),
                  color: Colors.red,
                ),
              )
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SlashText(
                      state.pathStack.isEmpty
                          ? '/'
                          : '/${state.pathStack.join('/')}',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: state.items.length,
                      itemBuilder: (context, idx) {
                        final item = state.items[idx];
                        if (item.type == 'dir') {
                          return ListTile(
                            leading: const Icon(Icons.folder),
                            title: SlashText(item.name),
                            onTap: () => controller.enterDir(item.name),
                          );
                        } else {
                          return ListTile(
                            leading: const Icon(Icons.insert_drive_file),
                            title: SlashText(item.name),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
    );
  }
}
