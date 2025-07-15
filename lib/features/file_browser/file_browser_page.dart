import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'file_browser_controller.dart';

class FileBrowserPage extends ConsumerWidget {
  final String owner;
  final String repo;
  const FileBrowserPage({super.key, required this.owner, required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = RepoParams(owner: owner, repo: repo);
    final state = ref.watch(fileBrowserControllerProvider(params));
    final controller = ref.read(fileBrowserControllerProvider(params).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('Browse: $repo'),
        leading: state.pathStack.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: controller.goUp,
              )
            : null,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? Center(child: Text('Error: ${state.error!}', style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        state.pathStack.isEmpty ? '/' : '/${state.pathStack.join('/')}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
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
                              title: Text(item.name),
                              onTap: () => controller.enterDir(item.name),
                            );
                          } else {
                            final isSelected = state.selectedFiles.any((f) => f.path == item.path);
                            return ListTile(
                              leading: const Icon(Icons.insert_drive_file),
                              title: Text(item.name),
                              trailing: isSelected
                                  ? IconButton(
                                      icon: const Icon(Icons.check_circle, color: Colors.green),
                                      onPressed: () => controller.deselectFile(item),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.add_circle_outline),
                                      onPressed: () => controller.selectFile(item),
                                    ),
                            );
                          }
                        },
                      ),
                    ),
                    if (state.selectedFiles.isNotEmpty)
                      Container(
                        color: Colors.blue.shade50,
                        padding: const EdgeInsets.all(8),
                        child: Wrap(
                          spacing: 8,
                          children: state.selectedFiles
                              .map((f) => Chip(
                                    label: Text(f.name),
                                    onDeleted: () => controller.deselectFile(f),
                                  ))
                              .toList(),
                        ),
                      ),
                  ],
                ),
    );
  }
} 