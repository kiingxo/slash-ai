import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repo/repo_controller.dart';
import '../file_browser/file_browser_controller.dart';
import '../../ui/screens/settings_screen.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/dart.dart';
import '../../services/secure_storage_service.dart';
import '../../services/github_service.dart';

// Provider for external edit requests
final externalEditRequestProvider = StateProvider<ExternalEditRequest?>(
  (ref) => null,
);

class ExternalEditRequest {
  final String fileName;
  final String code;
  ExternalEditRequest({required this.fileName, required this.code});
}

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

  // Add branch state
  List<String> _branches = [];
  String? _selectedBranch;
  bool _isCommitting = false;

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(text: '', language: dart);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for external edit requests
    final req = ref.read(externalEditRequestProvider);
    if (req != null) {
      setState(() {
        _selectedFilePath = req.fileName;
        _fileContent = req.code;
        _codeController.text = req.code;
      });
      // Clear the request after handling
      Future.microtask(() {
        ref.read(externalEditRequestProvider.notifier).state = null;
      });
    }
  }

  Future<void> _fetchBranchesForRepo(dynamic repo) async {
    if (repo == null) return;
    setState(() {
      _branches = [];
      _selectedBranch = null;
    });
    try {
      final storage = SecureStorageService();
      final pat = await storage.getApiKey('github_pat');
      final github = GitHubService(pat!);
      final branches = await github.fetchBranches(
        owner: repo['owner']['login'],
        repo: repo['name'],
      );
      setState(() {
        _branches = branches;
        _selectedBranch =
            branches.contains('main')
                ? 'main'
                : (branches.isNotEmpty ? branches[0] : null);
      });
    } catch (e) {
      setState(() {
        _branches = [];
        _selectedBranch = null;
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadFile(String path, RepoParams params) async {
    setState(() => _isLoading = true);
    final fileBrowserController = ref.read(
      fileBrowserControllerProvider(params).notifier,
    );
    final state = ref.read(fileBrowserControllerProvider(params));
    final file =
        state.items.where((f) => f.path == path).isNotEmpty
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
      final updatedFile =
          updatedState.items.where((f) => f.path == path).isNotEmpty
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

  Future<void> _commitAndPushFile() async {
    if (_selectedFilePath == null ||
        _fileContent == null ||
        _selectedRepo == null ||
        _selectedBranch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No file selected or missing branch/repo.'),
        ),
      );
      return;
    }
    final commitMessage = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String msg = '';
        return AlertDialog(
          title: const Text('Commit Message'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter commit message'),
            onChanged: (val) => msg = val,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(msg),
              child: const Text('Commit'),
            ),
          ],
        );
      },
    );
    if (commitMessage == null || commitMessage.trim().isEmpty) return;
    setState(() {
      _isCommitting = true;
    });
    try {
      final storage = SecureStorageService();
      final pat = await storage.getApiKey('github_pat');
      final github = GitHubService(pat!);
      final owner = _selectedRepo['owner']['login'];
      final repoName = _selectedRepo['name'];
      await github.commitFile(
        owner: owner,
        repo: repoName,
        branch: _selectedBranch!,
        path: _selectedFilePath!,
        content: _fileContent!,
        message: commitMessage,
      );
      setState(() {
        _isCommitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commit & push successful!')),
      );
    } catch (e) {
      setState(() {
        _isCommitting = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Commit failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoState = ref.watch(repoControllerProvider);
    final repos = repoState.repos;
    final selectedRepo =
        _selectedRepo ??
        repoState.selectedRepo ??
        (repos.isNotEmpty ? repos[0] : null);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final params =
        selectedRepo != null
            ? RepoParams(
              owner: selectedRepo['owner']['login'],
              repo: selectedRepo['name'],
              branch: _selectedBranch,
            )
            : null;
    final fileBrowserState =
        params != null
            ? ref.watch(fileBrowserControllerProvider(params))
            : null;
    final Widget emptyTitle = const SizedBox.shrink();
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF23232A) : Colors.white,
        elevation: 1,
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Icon(Icons.code, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 12),
              Text(
                'Code Editor',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 24),
              if (repos.isNotEmpty)
                DropdownButton<dynamic>(
                  value: selectedRepo,
                  items:
                      repos.map<DropdownMenuItem<dynamic>>((repo) {
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
                    _fetchBranchesForRepo(repo);
                  },
                  style: theme.textTheme.bodyMedium,
                  dropdownColor: theme.cardColor,
                ),
              const SizedBox(width: 12),
              // Branch dropdown removed from AppBar for mobile FAB UX
            ],
          ),
        ),
        actions: [],
      ),
      floatingActionButton:
          (_branches.isNotEmpty && selectedRepo != null)
              ? FloatingActionButton(
                heroTag: 'branch_fab',
                child: Icon(Icons.alt_route),
                tooltip: 'Switch Branch',
                onPressed: () => _showBranchPicker(context),
              )
              : null,
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
                    icon: Icon(
                      _sidebarExpanded
                          ? Icons.chevron_left
                          : Icons.chevron_right,
                      size: 22,
                    ),
                    tooltip: _sidebarExpanded ? 'Collapse' : 'Expand',
                    onPressed:
                        () => setState(
                          () => _sidebarExpanded = !_sidebarExpanded,
                        ),
                  ),
                ),
                Expanded(
                  child:
                      params == null
                          ? Container(
                            alignment: Alignment.center,
                            child: const Text('No repo selected'),
                          )
                          : fileBrowserState == null ||
                              fileBrowserState.isLoading
                          ? Container(
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(),
                          )
                          : Column(
                            children: [
                              if (fileBrowserState.pathStack.isNotEmpty)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: IconButton(
                                    icon: const Icon(Icons.arrow_back),
                                    tooltip: 'Up',
                                    onPressed: () {
                                      ref
                                          .read(
                                            fileBrowserControllerProvider(
                                              params,
                                            ).notifier,
                                          )
                                          .goUp();
                                    },
                                  ),
                                ),
                              Expanded(
                                child: ListView(
                                  shrinkWrap: true,
                                  children:
                                      fileBrowserState.items.map((item) {
                                        if (_sidebarExpanded) {
                                          return ListTile(
                                            dense: true,
                                            leading: Icon(
                                              item.type == 'dir'
                                                  ? Icons.folder
                                                  : Icons.insert_drive_file,
                                              color:
                                                  item.type == 'dir'
                                                      ? Colors.amber
                                                      : Colors.blueAccent,
                                            ),

                                            title: Text(
                                              item.name,
                                              style:
                                                  item.type == 'dir'
                                                      ? const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      )
                                                      : null,
                                            ),
                                            selected:
                                                _selectedFilePath == item.path,
                                            onTap: () {
                                              if (item.type == 'dir') {
                                                ref
                                                    .read(
                                                      fileBrowserControllerProvider(
                                                        params,
                                                      ).notifier,
                                                    )
                                                    .enterDir(item.name);
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
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 2,
                                            ),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              onTap: () {
                                                if (item.type == 'dir') {
                                                  ref
                                                      .read(
                                                        fileBrowserControllerProvider(
                                                          params,
                                                        ).notifier,
                                                      )
                                                      .enterDir(item.name);
                                                } else {
                                                  _loadFile(item.path, params);
                                                }
                                              },
                                              child: Icon(
                                                item.type == 'dir'
                                                    ? Icons.folder
                                                    : Icons.insert_drive_file,
                                                color:
                                                    item.type == 'dir'
                                                        ? Colors.amber
                                                        : Colors.blueAccent,
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
              ],
            ),
          ),
          // Editor area
          Expanded(
            child:
                _selectedFilePath == null
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isDark
                                    ? const Color(0xFF23232A)
                                    : Colors.grey[100],
                            border: Border(
                              bottom: BorderSide(
                                color:
                                    isDark
                                        ? Colors.grey[900]!
                                        : Colors.grey[300]!,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.insert_drive_file,
                                color: Colors.blueAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedFilePath ?? '',
                                  style: const TextStyle(
                                    fontFamily: 'Fira Mono',
                                    fontSize: 15,
                                  ),
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
                                textStyle: const TextStyle(
                                  fontFamily: 'Fira Mono',
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                                expands: true,
                                gutterStyle: GutterStyle.none,
                                background: Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                        // Actions bar
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isDark
                                    ? const Color(0xFF23232A)
                                    : Colors.grey[100],
                            border: Border(
                              top: BorderSide(
                                color:
                                    isDark
                                        ? Colors.grey[900]!
                                        : Colors.grey[300]!,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.keyboard_hide, size: 16),
                                label: const Text(
                                  'Hide keyboard',
                                  style: TextStyle(fontSize: 13),
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(32, 32),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                ),
                                onPressed: () {
                                  FocusScope.of(context).unfocus();
                                },
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.upload, size: 16),
                                label:
                                    _isCommitting
                                        ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Text(
                                          'Commit & Push',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(32, 32),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                ),
                                onPressed:
                                    _isCommitting ? null : _commitAndPushFile,
                              ),
                              const SizedBox(width: 12),
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

  void _showBranchPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final maxHeight = MediaQuery.of(context).size.height * 0.6;
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Switch Branch',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _branches.length,
                    itemBuilder: (context, index) {
                      final branch = _branches[index];
                      return ListTile(
                        leading:
                            branch == _selectedBranch
                                ? Icon(
                                  Icons.check,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                                : null,
                        title: Text(
                          branch,
                          style: TextStyle(
                            fontWeight:
                                branch == _selectedBranch
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                          ),
                        ),
                        onTap: () {
                          setState(() {
                            _selectedBranch = branch;
                            _selectedFilePath = null;
                            _fileContent = null;
                          });
                          // Optionally trigger a file browser refresh
                          final repo =
                              _selectedRepo ??
                              (_branches.isNotEmpty ? _selectedRepo : null);
                          if (repo != null) {
                            final params = RepoParams(
                              owner: repo['owner']['login'],
                              repo: repo['name'],
                              branch: branch,
                            );
                            ref
                                .read(
                                  fileBrowserControllerProvider(
                                    params,
                                  ).notifier,
                                )
                                .fetchDir();
                          }
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
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
