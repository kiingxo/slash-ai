import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repo/repo_controller.dart';
import '../file_browser/file_browser_controller.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/dart.dart';
import '../../services/secure_storage_service.dart';
import '../../services/github_service.dart';
import '../../features/auth/auth_controller.dart';
import '../../services/openai_service.dart';
import '../../services/gemini_service.dart';
import '../../ui/components/slash_text_field.dart';
import '../../ui/components/slash_button.dart';

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

  bool _showChatOverlay = false;
  Offset _chatOverlayOffset = const Offset(60, 120);
  final List<_ChatMessage> _chatMessages = [
    _ChatMessage(isUser: false, text: "Hi! I'm /slash. Ask me about your code!"),
  ];
  bool _chatLoading = false;
  String? _pendingEdit;
  final TextEditingController _chatController = TextEditingController();

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
    _chatController.dispose();
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
              const SizedBox(width: 5),
              // Branch dropdown removed from AppBar for mobile FAB UX
            ],
          ),
        ),
        actions: [
          if (_branches.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedBranch,
                hint: const Text('Branch'),
                onChanged: (branch) {
                  setState(() {
                    _selectedBranch = branch;
                    _selectedFilePath = null;
                    _fileContent = null;
                  });

                  if (selectedRepo != null && branch != null) {
                    final params = RepoParams(
                      owner: selectedRepo['owner']['login'],
                      repo: selectedRepo['name'],
                      branch: branch,
                    );
                    ref
                        .read(fileBrowserControllerProvider(params).notifier)
                        .fetchDir();
                  }
                },
                items:
                    _branches.map((b) {
                      return DropdownMenuItem(value: b, child: Text(b));
                    }).toList(),
                dropdownColor: theme.cardColor,
                icon: const Icon(Icons.alt_route),
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
      floatingActionButton:
          (_branches.isNotEmpty && selectedRepo != null)
              ? FloatingActionButton(
                  heroTag: 'branch_fab',
                  tooltip: 'AI Assistant',
                  onPressed: () {
                    setState(() {
                      _showChatOverlay = true;
                    });
                  },
                  child: const Text('🤖', style: TextStyle(fontSize: 24)),
                )
              : null,
      body: Stack(
        children: [
          Row(
            children: [
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
                                      'Hide Keyboard',
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
          if (_showChatOverlay)
            Positioned(
              left: _chatOverlayOffset.dx,
              top: _chatOverlayOffset.dy,
              child: Draggable(
                feedback: SizedBox(
                  width: 340,
                  height: 420,
                  child: _ChatOverlay(
                    messages: _chatMessages,
                    loading: _chatLoading,
                    controller: _chatController,
                    onSend: _handleChatSend,
                    onClose: () => setState(() => _showChatOverlay = false),
                    onApplyEdit: _pendingEdit != null ? _applyAICodeEdit : null,
                  ),
                ),
                childWhenDragging: const SizedBox.shrink(),
                onDragEnd: (details) {
                  setState(() {
                    _chatOverlayOffset = details.offset;
                  });
                },
                child: _ChatOverlay(
                  messages: _chatMessages,
                  loading: _chatLoading,
                  controller: _chatController,
                  onSend: _handleChatSend,
                  onClose: () => setState(() => _showChatOverlay = false),
                  onApplyEdit: _pendingEdit != null ? _applyAICodeEdit : null,
                ),
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

  void _handleChatSend() async {
    final prompt = _chatController.text.trim();
    if (prompt.isEmpty) return;
    setState(() {
      _chatMessages.add(_ChatMessage(isUser: true, text: prompt));
      _chatLoading = true;
      _pendingEdit = null;
    });
    _chatController.clear();
    try {
      // Use OpenAI/Gemini as in PromptPage, with current code as context
      final authState = ref.read(authControllerProvider);
      final geminiKey = authState.geminiApiKey;
      final openAIApiKey = authState.openAIApiKey;
      final model = authState.model;
      final aiService = model == 'gemini'
          ? GeminiService(geminiKey!)
          : OpenAIService(openAIApiKey!, model: 'gpt-4o');
      final codeContext = _codeController.text;
      // Ask AI to classify intent
      final intent = await (aiService as dynamic).classifyIntent(prompt);
      if (intent == 'code_edit') {
        // Ask for code edit suggestion
        final summaryPrompt =
            "You are an AI code assistant. Summarize the following code change request for the user in a friendly, conversational way. Do NOT include the full code or file content in your response. User request: $prompt";
        final summary = await (aiService as dynamic).getCodeSuggestion(
          prompt: summaryPrompt,
          files: [
            {'name': _selectedFilePath ?? 'current.dart', 'content': codeContext}
          ],
        );
        final codeEditPrompt =
            'You are a code editing agent. Given the original file content and the user\'s request, output ONLY the new file content after the edit. Do NOT include any explanation, comments, or markdown. Output only the code, as it should appear in the file.\n\nFile: \\${_selectedFilePath ?? 'current.dart'}\nOriginal content:\n$codeContext\nUser request: $prompt';
        var newContent = await (aiService as dynamic).getCodeSuggestion(
          prompt: codeEditPrompt,
          files: [
            {'name': _selectedFilePath ?? 'current.dart', 'content': codeContext}
          ],
        );
        newContent = stripCodeFences(newContent);
        setState(() {
          _chatMessages.add(_ChatMessage(isUser: false, text: summary));
          _pendingEdit = newContent;
          _chatLoading = false;
        });
      } else {
        // General Q&A
        final answerPrompt =
            'User: $prompt\nYou are /slash, an AI code assistant. Respond conversationally.';
        final answer = await (aiService as dynamic).getCodeSuggestion(
          prompt: answerPrompt,
          files: [
            {'name': _selectedFilePath ?? 'current.dart', 'content': codeContext}
          ],
        );
        setState(() {
          _chatMessages.add(_ChatMessage(isUser: false, text: answer));
          _chatLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _chatMessages.add(_ChatMessage(isUser: false, text: 'Error: \\${e.toString()}'));
        _chatLoading = false;
      });
    }
  }

  void _applyAICodeEdit() {
    if (_pendingEdit != null) {
      setState(() {
        _codeController.text = _pendingEdit!;
        _pendingEdit = null;
        _chatMessages.add(_ChatMessage(isUser: false, text: '✅ Edit applied to the code!'));
      });
    }
  }
}

// Add this utility function to strip markdown code fences and extra text:
String stripCodeFences(String input) {
  final codeFenceRegex = RegExp(
    r'^```[a-zA-Z0-9]*\n|\n```|```[a-zA-Z0-9]*|```',
    multiLine: true,
  );
  var output = input.replaceAll(codeFenceRegex, '');
  // Remove leading/trailing whitespace
  output = output.trim();
  return output;
}

// Simple chat message model for overlay
class _ChatMessage {
  final bool isUser;
  final String text;
  _ChatMessage({required this.isUser, required this.text});
}

// Floating chat overlay widget
class _ChatOverlay extends StatelessWidget {
  final List<_ChatMessage> messages;
  final bool loading;
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onClose;
  final VoidCallback? onApplyEdit;
  const _ChatOverlay({
    required this.messages,
    required this.loading,
    required this.controller,
    required this.onSend,
    required this.onClose,
    this.onApplyEdit,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 280,
        height: 340,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(blurRadius: 16, color: Colors.black26)],
        ),
        child: Column(
          children: [
            // Header
            Container(
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Icon(Icons.chat_bubble, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('AI Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: onClose,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            // Messages
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: messages.length + (loading ? 1 : 0),
                itemBuilder: (context, idx) {
                  if (idx == messages.length && loading) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final msg = messages[idx];
                  final isUser = msg.isUser;
                  final theme = Theme.of(context);
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isUser
                            ? theme.colorScheme.primary.withOpacity(0.12)
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: isUser
                            ? []
                            : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isUser)
                            Padding(
                              padding: const EdgeInsets.only(right: 6, top: 2),
                              child: Text(
                                '🤖',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              msg.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                                color: isUser
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (onApplyEdit != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Apply AI Edit to Code', style: TextStyle(fontSize: 13)),
                    onPressed: onApplyEdit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Expanded(
                    child: SlashTextField(
                      controller: controller,
                      hint: 'Ask about this code…',
                      minLines: 1,
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: SlashButton(
                      label: '',
                      onTap: loading ? () {} : onSend,
                      icon: Icons.send,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
