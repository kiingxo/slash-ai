import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repo/repo_controller.dart';
import '../file_browser/file_browser_controller.dart';
import '../../ui/screens/settings_screen.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/dart.dart';

class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key});

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  dynamic _selectedRepo;
  String? _selectedFilePath;
  String? _fileContent;
  bool _isLoading = false;
  late CodeController _codeController;
  bool _sidebarExpanded = false;

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(text: '', language: dart);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadFile(String path, RepoParams params) async {
    setState(() => _isLoading = true);
    final fileBrowserController = ref.read(fileBrowserControllerProvider(params).notifier);
    final state = ref.read(fileBrowserControllerProvider(params));
    final file = state.items.where((f) => f.path == path).isNotEmpty
        ? state.items.firstWhere((f) => f.path == path)
        : null;
    if (file != null && file.content != null) {
      setState(() {
        _selectedFilePath = path;
        _fileContent = file.content;
        _codeController.text = file.content!;
        _isLoading = false;
      });
    } else if (file != null) {
      // Fetch file content if not loaded
      await fileBrowserController.selectFile(file);
      // Get the updated file from state
      final updatedState = ref.read(fileBrowserControllerProvider(params));
      final updatedFile = updatedState.items.where((f) => f.path == path).isNotEmpty
          ? updatedState.items.firstWhere((f) => f.path == path)
          : null;
      setState(() {
        _selectedFilePath = path;
        _fileContent = updatedFile?.content ?? '';
        _codeController.text = updatedFile?.content ?? '';
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoState = ref.watch(repoControllerProvider);
    final repos = repoState.repos;
    final selectedRepo = _selectedRepo ?? repoState.selectedRepo ?? (repos.isNotEmpty ? repos[0] : null);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final params = selectedRepo != null ? RepoParams(owner: selectedRepo['owner']['login'], repo: selectedRepo['name']) : null;
    final fileBrowserState = params != null ? ref.watch(fileBrowserControllerProvider(params)) : null;
    final Widget _emptyTitle = const SizedBox.shrink();
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF23232A) : Colors.white,
        elevation: 1,
        title: Row(
          children: [
            const Icon(Icons.code, color: Color(0xFF8B5CF6)),
            const SizedBox(width: 12),
            Text('Code Editor', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 24),
            if (repos.isNotEmpty)
              DropdownButton<dynamic>(
                value: selectedRepo,
                items: repos.map<DropdownMenuItem<dynamic>>((repo) {
                  return DropdownMenuItem<dynamic>(
                    value: repo,
                    child: Text(repo['full_name'] ?? repo['name']),
                  );
                }).toList(),
                onChanged: (repo) {
                  setState(() {
                    _selectedRepo = repo;
                    _selectedFilePath = null;
                    _fileContent = null;
                  });
                },
                style: theme.textTheme.bodyMedium,
                dropdownColor: theme.cardColor,
              ),
          ],
        ),
      ),
      body: Row(
        children: [
          // File browser sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: _sidebarExpanded ? 220 : 64,
            color: isDark ? const Color(0xFF23232A) : Colors.grey[100],
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: Icon(_sidebarExpanded ? Icons.chevron_left : Icons.chevron_right, size: 22),
                    tooltip: _sidebarExpanded ? 'Collapse' : 'Expand',
                    onPressed: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
                  ),
                ),
                Expanded(
                  child: params == null
                      ? Container(
                          alignment: Alignment.center,
                          child: const Text('No repo selected'),
                        )
                      : fileBrowserState == null || fileBrowserState.isLoading
                          ? Container(
                              alignment: Alignment.center,
                              child: const CircularProgressIndicator(),
                            )
                          : ListView(
                              children: fileBrowserState.items.map((item) {
                                if (_sidebarExpanded) {
                                  // Expanded: ListTile with icon and name
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(
                                      item.type == 'dir' ? Icons.folder : Icons.insert_drive_file,
                                      color: item.type == 'dir' ? Colors.amber : Colors.blueAccent,
                                    ),
                                    title: Text(
                                      item.name,
                                      style: item.type == 'dir'
                                          ? const TextStyle(fontWeight: FontWeight.w500)
                                          : null,
                                    ),
                                    selected: _selectedFilePath == item.path,
                                    onTap: () {
                                      if (item.type == 'dir') {
                                        ref.read(fileBrowserControllerProvider(params).notifier).enterDir(item.name);
                                      } else {
                                        _loadFile(item.path, params);
                                      }
                                    },
                                  );
                                } else {
                                  // Collapsed: icon only, custom Container
                                  return Container(
                                    width: 48,
                                    height: 40,
                                    alignment: Alignment.center,
                                    margin: const EdgeInsets.symmetric(vertical: 2),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () {
                                        if (item.type == 'dir') {
                                          ref.read(fileBrowserControllerProvider(params).notifier).enterDir(item.name);
                                        } else {
                                          _loadFile(item.path, params);
                                        }
                                      },
                                      child: Icon(
                                        item.type == 'dir' ? Icons.folder : Icons.insert_drive_file,
                                        color: item.type == 'dir' ? Colors.amber : Colors.blueAccent,
                                      ),
                                    ),
                                  );
                                }
                              }).toList(),
                            ),
                ),
              ],
            ),
          ),
          // Editor area
          Expanded(
            child: _selectedFilePath == null
                ? Center(
                    child: Text(
                      'Select a file to edit',
                      style: theme.textTheme.titleMedium,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF23232A) : Colors.grey[100],
                          border: Border(bottom: BorderSide(color: isDark ? Colors.grey[900]! : Colors.grey[300]!)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.insert_drive_file, color: Colors.blueAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedFilePath ?? '',
                                style: const TextStyle(fontFamily: 'Fira Mono', fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: CodeTheme(
                            data: CodeThemeData(),
                            child: CodeField(
                              controller: _codeController,
                              textStyle: const TextStyle(fontFamily: 'Fira Mono', fontSize: 15, color: Colors.white),
                              expands: true,
                              lineNumberStyle: LineNumberStyle(
                                width: 32,
                                textAlign: TextAlign.right,
                                textStyle: TextStyle(color: isDark ? const Color(0xFF8B949E) : Colors.grey[600]!, fontSize: 12, fontFamily: 'Fira Mono'),
                                background: isDark ? const Color(0xFF23232A) : Colors.grey[200]!,
                                margin: 6.0,
                              ),
                              background: Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                      // Actions bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF23232A) : Colors.grey[100],
                          border: Border(top: BorderSide(color: isDark ? Colors.grey[900]! : Colors.grey[300]!)),
                        ),
                        child: Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.save),
                              label: const Text('Save'),
                              onPressed: () {
                                // TODO: Save logic (stage changes)
                              },
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.upload),
                              label: const Text('Commit & Push'),
                              onPressed: () {
                                // TODO: Commit & push logic
                              },
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.merge_type),
                              label: const Text('Open PR'),
                              onPressed: () {
                                // TODO: Open PR logic
                              },
                            ),
                            const Spacer(),
                            TextButton(
                              child: const Text('Discard Changes', style: TextStyle(color: Colors.red)),
                              onPressed: () {
                                // TODO: Discard logic
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
} 