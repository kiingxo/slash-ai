import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repo/repo_controller.dart';
import '../../services/secure_storage_service.dart';
import '../../services/gemini_service.dart';
import '../../services/github_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../ui/components/slash_text_field.dart';
import '../../ui/components/slash_button.dart';
import '../../ui/components/slash_diff_viewer.dart';
import '../../common/widgets/widgets.dart';
import '../../features/auth/auth_controller.dart';
import '../../services/openai_service.dart';
import '../../features/file_browser/file_browser_controller.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'code_screen.dart';
final tabIndexProvider = StateProvider<int>((ref) => 1); // 1 = prompt, 2 = code

// Message model for chat
class ChatMessage {
  final bool isUser;
  final String text;
  final ReviewData? review;
  ChatMessage({required this.isUser, required this.text, this.review});
}

// Review data for expandable review bubble
class ReviewData {
  final String fileName;
  final String oldContent;
  final String newContent;
  final String summary;
  ReviewData({
    required this.fileName,
    required this.oldContent,
    required this.newContent,
    required this.summary,
  });
}

class PromptPage extends ConsumerStatefulWidget {
  const PromptPage({super.key});

  @override
  ConsumerState<PromptPage> createState() => _PromptPageState();
}

class _PromptPageState extends ConsumerState<PromptPage> {
  late TextEditingController promptController;
  dynamic _selectedRepo;
  bool _isLoading = false;
  String? _error;
  final List<ChatMessage> _messages = [
    ChatMessage(
      isUser: false,
      text: "Hi! I'm /slash 🤖. How can I help you today?",
    ),
  ];
  bool _reviewExpanded = false;
  ReviewData? _pendingReview;
  String _selectedModel = 'gemini';
  String? _lastIntent;
  List<FileItem> _repoContextFiles = [];
  final String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];
  final TextEditingController _searchController = TextEditingController();

  // Add branch state
  List<String> _branches = [];
  String? _selectedBranch;

  @override
  void initState() {
    super.initState();
    promptController = TextEditingController();
    // Default to the model in auth state
    final authState = ref.read(authControllerProvider);
    _selectedModel = authState.model;
  }

  @override
  void dispose() {
    promptController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, String>>> _fetchFiles({
    required String owner,
    required String repo,
    required String pat,
  }) async {
    final branch = _selectedBranch;
    final url = branch != null
        ? 'https://api.github.com/repos/$owner/$repo/contents/?ref=$branch'
        : 'https//api.github.com/repos/$owner/$repo/contents';
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': '900token $pat',
        'Accept': 'application/vnd.github+json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch files:  [31m${res.body} [0m');
    }
    final List files = jsonDecode(res.body);
    List<Map<String, String>> fileContents = [];
    for (final file in files) {
      if (file['type'] == 'file') {
        final fileRes = await http.get(Uri.parse(file['download_url']));
        if (fileRes.statusCode == 200) {
          fileContents.add({'name': file['name'], 'content': fileRes.body});
        }
      }
    }
    return fileContents;
  }

  Future<void> _addRepoContext() async {
    setState(() {});
    try {
      final repo =
          _selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      if (repo == null) throw Exception('No repository selected.');
      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      final params = RepoParams(owner: owner, repo: repoName);
      final fileBrowserController = ref.read(
        fileBrowserControllerProvider(params).notifier,
      );
      final files = await fileBrowserController.listAllFiles();
      setState(() {
        _repoContextFiles = files;
      });
    } catch (e) {
      print('Error adding repo context: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add repo context: $e')));
    }
  }

  Future<void> _handlePromptSubmit() async {
    final prompt = promptController.text.trim();
    if (prompt.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _messages.add(ChatMessage(isUser: true, text: prompt));
    });
    promptController.clear();
    String? detectedIntent;
    try {
      print('[PromptPage] Submitting prompt: $prompt');
      final authState = ref.read(authControllerProvider);
      final geminiKey = authState.geminiApiKey;
      final openAIApiKey = authState.openAIApiKey;
      final githubPat = authState.githubPat;
      final model = _selectedModel;
      print('[PromptPage] Using model: $model');
      if ((model == 'gemini' && (geminiKey == null || geminiKey.isEmpty)) ||
          (model == 'openai' &&
              (openAIApiKey == null || openAIApiKey.isEmpty)) ||
          githubPat == null ||
          githubPat.isEmpty) {
        print('[PromptPage] Missing API keys');
        throw Exception('Missing API keys');
      }
      final repo =
          _selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      dynamic aiService;
      if (model == 'gemini') {
        aiService = GeminiService(geminiKey!);
      } else {
        aiService = OpenAIService(openAIApiKey!, model: 'gpt-4o');
      }
      print('[PromptPage] Calling classifyIntent...');
      final intent = await aiService.classifyIntent(prompt);
      detectedIntent = intent;
      _lastIntent = intent;
      print('[PromptPage] Intent: $intent');
      // Use repo context files if present
      final contextFiles =
          _repoContextFiles.isNotEmpty
              ? _repoContextFiles
                  .map((f) => {'name': f.name, 'content': f.content ?? ''})
                  .toList()
                  .take(3)
                  .toList()
              : const <Map<String, String>>[];
      if (intent == 'code_edit') {
        final owner = repo['owner']['login'];
        final repoName = repo['name'];
        print('[PromptPage] Fetching files for $owner/$repoName');
        final files =
            contextFiles.isNotEmpty
                ? contextFiles
                : await _fetchFiles(
                  owner: owner,
                  repo: repoName,
                  pat: githubPat,
                );
        // 1. Get summary/explanation for chat bubble
        final summaryPrompt =
            "You are an AI code assistant. Summarize the following code change request for the user in a friendly, conversational way. Do NOT include the full code or file content in your response. "
            "User request: $prompt";
        final summary = await aiService.getCodeSuggestion(
          prompt: summaryPrompt,
          files: files,
        );
        // 2. Get code-only output for review/commit
        final oldContent = files.isNotEmpty ? files[0]['content']! : '';
        final codeEditPrompt =
            'You are a code editing agent. Given the original file content and the user\'s request, output ONLY the new file content after the edit. Do NOT include any explanation, comments, or markdown. Output only the code, as it should appear in the file.\n\n' 'File: ${files.isNotEmpty ? files[0]['name']! : 'unknown.dart'}\n' +
            'Original content:\n$oldContent\n' +
            'User request: $prompt';
        var newContent = await aiService.getCodeSuggestion(
          prompt: codeEditPrompt,
          files: files,
        );
        newContent = stripCodeFences(newContent);
        final fileName = files.isNotEmpty ? files[0]['name']! : 'unknown.dart';
        final review = ReviewData(
          fileName: fileName,
          oldContent: oldContent,
          newContent: newContent,
          summary: summary,
        );
        setState(() {
          _isLoading = false;
          _pendingReview = review;
          _messages.add(
            ChatMessage(isUser: false, text: summary, review: review),
          );
          _reviewExpanded = false;
        });
      } else if (intent == 'repo_question') {
        if (repo == null) {
          setState(() {
            _isLoading = false;
            _messages.add(
              ChatMessage(
                isUser: false,
                text:
                    "No repository selected. Please select a repository to ask questions about it.",
              ),
            );
          });
          return;
        }
        final repoInfo =
            'Repo name: ${repo['name']}\nDescription: ${repo['description'] ?? 'No description.'}';
        final answerPrompt =
            'User question: $prompt\nRepo info: $repoInfo\nAnswer the user\'s question about the repo.';
        print('[PromptPage] Calling getCodeSuggestion for repo_question...');
        final answer = await aiService.getCodeSuggestion(
          prompt: answerPrompt,
          files: contextFiles,
        );
        setState(() {
          _isLoading = false;
          _messages.add(ChatMessage(isUser: false, text: answer));
        });
      } else {
        final answerPrompt =
            'User: $prompt\nYou are /slash, an AI code assistant. Respond conversationally.';
        print('[PromptPage] Calling getCodeSuggestion for general...');
        final answer = await aiService.getCodeSuggestion(
          prompt: answerPrompt,
          files: contextFiles,
        );
        setState(() {
          _isLoading = false;
          _messages.add(ChatMessage(isUser: false, text: answer));
        });
      }
    } catch (e, st) {
      print('[PromptPage] Error: $e');
      print(st);
      setState(() {
        _isLoading = false;
        _error = e.toString();
        _messages.add(
          ChatMessage(isUser: false, text: friendlyErrorMessage(e.toString())),
        );
      });
    }
  }

  // Add a method to force code edit if user taps override
  Future<void> _forceCodeEdit(String prompt) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final authState = ref.read(authControllerProvider);
      final geminiKey = authState.geminiApiKey;
      final openAIApiKey = authState.openAIApiKey;
      final githubPat = authState.githubPat;
      final model = _selectedModel;
      final repo =
          _selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      dynamic aiService;
      if (model == 'gemini') {
        aiService = GeminiService(geminiKey!);
      } else {
        aiService = OpenAIService(openAIApiKey!, model: 'gpt-4o');
      }
      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      final files = await _fetchFiles(
        owner: owner,
        repo: repoName,
        pat: githubPat!,
      );
      // 1. Get summary/explanation for chat bubble
      final summaryPrompt =
          "You are an AI code assistant. Summarize the following code change request for the user in a friendly, conversational way. Do NOT include the full code or file content in your response. "
          "User request: $prompt";
      final summary = await aiService.getCodeSuggestion(
        prompt: summaryPrompt,
        files: files,
      );
      // 2. Get code-only output for review/commit
      final oldContent = files.isNotEmpty ? files[0]['content']! : '';
      final codeEditPrompt =
          'You are a code editing agent. Given the original file content and the user\'s request, output ONLY the new file content after the edit. Do NOT include any explanation, comments, or markdown. Output only the code, as it should appear in the file.\n\n' 'File: ${files.isNotEmpty ? files[0]['name']! : 'unknown.dart'}\n' +
          'Original content:\n$oldContent\n' +
          'User request: $prompt';
      var newContent = await aiService.getCodeSuggestion(
        prompt: codeEditPrompt,
        files: files,
      );
      newContent = stripCodeFences(newContent);
      final fileName = files.isNotEmpty ? files[0]['name']! : 'unknown.dart';
      final review = ReviewData(
        fileName: fileName,
        oldContent: oldContent,
        newContent: newContent,
            summary: summary,
      );
      setState(() {
        _isLoading = false;
        _pendingReview = review;
        _messages.add(
          ChatMessage(isUser: false, text: summary, review: review),
        );
        _reviewExpanded = false;
      });
    } catch (e, st) {
      print('[PromptPage] Force code edit error: $e');
      print(st);
      setState(() {
        _isLoading = false;
        _error = e.toString();
        _messages.add(
          ChatMessage(isUser: false, text: friendlyErrorMessage(e.toString())),
        );
      });
    }
  }

  Future<void> _approveReview(ReviewData review, String prompt) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
              try {
      final storage = SecureStorageService();
      final githubPat = await storage.getApiKey('github_pat');
      final repo =
          _selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      final github = GitHubService(githubPat!);
      final baseBranch = _selectedBranch ?? 'main';
      final newBranch = 'slash/${DateTime.now().millisecondsSinceEpoch}';
      await github.createBranch(
        owner: owner,
        repo: repoName,
        newBranch: newBranch,
        baseBranch: baseBranch,
      );
      await github.commitFile(
        owner: owner,
        repo: repoName,
        branch: newBranch,
        path: review.fileName,
        content: review.newContent,
        message: '/SLASH: $prompt',
      );
      final prUrl = await github.openPullRequest(
        owner: owner,
        repo: repoName,
        head: newBranch,
        base: baseBranch,
        title: '/SLASH: $prompt',
        body: review.summary,
      );
      setState(() {
        _isLoading = false;
        _messages.add(
          ChatMessage(isUser: false, text: 'Pull request created! $prUrl'),
                );
        _pendingReview = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
        _messages.add(
          ChatMessage(isUser: false, text: friendlyErrorMessage(_error ?? '')),
        );
      });
    }
  }

  void _rejectReview() {
    setState(() {
      _pendingReview = null;
      _reviewExpanded = false;
      _messages.add(ChatMessage(isUser: false, text: 'Suggestion rejected.'));
    });
  }

  void _searchRepoContextFiles(String query) {
    final lowerQuery = query.toLowerCase();
    final results = <Map<String, dynamic>>[];
    for (final file in _repoContextFiles) {
      if (file.name.toLowerCase().contains(lowerQuery) ||
          (file.content?.toLowerCase().contains(lowerQuery) ?? false)) {
        results.add({
          'path': file.path,
          'name': file.name,
          'snippet':
              file.content != null && file.content!.length > 200
                  ? '${file.content!.substring(0, 200)}...'
                  : file.content,
        });
    }
    }
    setState(() {
      _searchResults = results;
    });
  }

  Future<void> _fetchBranchesForRepo(dynamic repo) async {
    if (repo == null) return;
    setState(() { _branches = []; _selectedBranch = null; });
    try {
      final storage = SecureStorageService();
      final pat = await storage.getApiKey('github_pat');
      final github = GitHubService(pat!);
      final branches = await github.fetchBranches(owner: repo['owner']['login'], repo: repo['name']);
      setState(() {
        _branches = branches;
        _selectedBranch = branches.contains('main') ? 'main' : (branches.isNotEmpty ? branches[0] : null);
      });
    } catch (e) {
      setState(() { _branches = []; _selectedBranch = null; });
    }
  }

  Widget _intentTag(String? intent) {
    if (intent == null) return const SizedBox.shrink();
    Color color;
    String label;
    switch (intent) {
      case 'code_edit':
        color = Colors.blueAccent;
        label = 'Code Edit';
        break;
      case 'repo_question':
        color = Colors.orangeAccent;
        label = 'Repo Q';
        break;
      case 'general':
      default:
        color = Colors.green;
        label = 'General';
        break;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        child: Chip(
          label: Text(label, style: const TextStyle(color: Colors.white)),
          backgroundColor: color,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repoState = ref.watch(repoControllerProvider);
    final controller = ref.read(repoControllerProvider.notifier);
    final repos = repoState.repos;
    final selectedRepo =
        _selectedRepo ??
        repoState.selectedRepo ??
        (repos.isNotEmpty ? repos[0] : null);

    if (repoState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (repos.isEmpty) {
      return Center(
        child: Text('No repositories found.', style: TextStyle(fontSize: 18)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Image.asset('assets/slash2.png', height: 100),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedModel,
                items: const [
                  DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                  DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedModel = val);
                },
                            style: Theme.of(context).textTheme.bodyMedium,
                dropdownColor: Theme.of(context).cardColor,
              ),
            ),
                          ),
                        ],
                      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButton<dynamic>(
                      value: selectedRepo,
                      isExpanded: true,
                      items: repos.map<DropdownMenuItem<dynamic>>((repo) {
                        return DropdownMenuItem<dynamic>(
                          value: repo,
                          child: Text(repo['full_name'] ?? repo['name']),
                        );
                      }).toList(),
                      onChanged: (repo) {
                        setState(() => _selectedRepo = repo);
                        controller.selectRepo(repo);
                        _fetchBranchesForRepo(repo);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_branches.isNotEmpty)
                    DropdownButton<String>(
                      value: _selectedBranch,
                      items: _branches.map((branch) => DropdownMenuItem<String>(
                        value: branch,
                        child: Text(branch),
                      )).toList(),
                      onChanged: (branch) {
                        setState(() { _selectedBranch = branch; });
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, idx) {
                  final msg = _messages[idx];
                  if (msg.review != null) {
                    // Review bubble
                    return _buildReviewBubble(
                      msg.review!,
                      msg.text,
                      idx == _messages.length - 1,
                    );
                  }
                  // Show intent tag above the latest agent message
                  final isLastAgent =
                      !msg.isUser &&
                      idx == _messages.lastIndexWhere((m) => !m.isUser);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isLastAgent) _intentTag(_lastIntent),
                      Align(
                        alignment:
                            msg.isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color:
                                msg.isUser
                                    ? Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.12)
                                    : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow:
                                msg.isUser
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
                              if (!msg.isUser)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    top: 2,
                                  ),
                                  child: Icon(
                                    Icons.android,
                                    size: 22,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              Flexible(
                                child: Text(
                                  msg.text,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(
                                    color:
                                        msg.isUser
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                            : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Center(child: _ThinkingWidget()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  friendlyErrorMessage(_error ?? ''),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: SlashTextField(
                    controller: promptController,
                      hint: 'Type a prompt…',
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SlashButton(
                      label: 'Send',
                      onTap: _isLoading ? () {} : _handlePromptSubmit,
                      icon: Icons.send,
                    ),
                  ),
                ],
              ),
            ),
            // Show repo context summary and file picker
            if (_repoContextFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Wrap(
                  spacing: 6,
                  children: [
                    const Text(
                      'Context:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ..._repoContextFiles.map(
                      (f) => Chip(
                        label: Text(
                          f.name,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onDeleted:
                            () => setState(() => _repoContextFiles.remove(f)),
                      ),
                    ),
                  ],
                ),
              ),
            // Add Repo Context Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SlashButton(
                  label: 'Add Repo Context',
                  icon: Icons.folder_open,
                  onTap:
                      _isLoading ? () {} : () => _showFilePickerModal(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewBubble(ReviewData review, String summary, bool isLast) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.android,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _reviewExpanded = !_reviewExpanded);
                    },
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            summary,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _reviewExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_reviewExpanded && isLast) ...[
              const SizedBox(height: 12),
              Text(
                review.fileName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SlashDiffViewer(
                oldContent: review.oldContent,
                newContent: review.newContent,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blueAccent),
                    tooltip: 'Edit code',
                    onPressed: _isLoading
                        ? null
                        : () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Manual Edit'),
                                content: const Text(
                                  'You will be routed to the code editor to manually edit the AI\'s output.\n\nAfter editing, tap the green check to save your changes.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    child: const Text('Continue'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm != true) return;
                            // Set the external edit request and switch to code tab
                            final container = ProviderScope.containerOf(context, listen: false);
                            container.read(externalEditRequestProvider.notifier).state = ExternalEditRequest(
                              fileName: review.fileName,
                              code: review.newContent,
                            );
                            container.read(tabIndexProvider.notifier).state = 2; // Switch to code tab
                          },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 28,
                    ),
                    tooltip: 'Approve and PR',
                    onPressed:
                        _isLoading
                            ? null
                            : () => _approveReview(review, summary),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red, size: 28),
                    tooltip: 'Reject',
                    onPressed: _isLoading ? null : _rejectReview,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFilePickerModal(BuildContext context) async {
    final repo = _selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
    if (repo == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No repository selected.')));
      return;
    }
    final owner = repo['owner']['login'];
    final repoName = repo['name'];
    final params = RepoParams(owner: owner, repo: repoName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _LazyFilePickerModal(
          params: params,
          initiallySelected: _repoContextFiles,
          onSelected: (selected) {
            setState(() {
              _repoContextFiles = selected;
            });
          },
        );
      },
    );
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

// Creative thinking widget (animated ellipsis)
class _ThinkingWidget extends StatefulWidget {
  @override
  State<_ThinkingWidget> createState() => _ThinkingWidgetState();
}

class _ThinkingWidgetState extends State<_ThinkingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _dots;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    _dots = StepTween(begin: 0, end: 3).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dots,
      builder: (context, child) {
        final dots = '.' * _dots.value;
        return Text(
          'Thinking$dots',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}

class _LazyFilePickerModal extends ConsumerStatefulWidget {
  final RepoParams params;
  final List<FileItem> initiallySelected;
  final void Function(List<FileItem>) onSelected;
  const _LazyFilePickerModal({
    required this.params,
    required this.initiallySelected,
    required this.onSelected,
  });
  @override
  ConsumerState<_LazyFilePickerModal> createState() =>
      _LazyFilePickerModalState();
}

class _LazyFilePickerModalState extends ConsumerState<_LazyFilePickerModal> {
  late List<FileItem> selected;
  late List<String> pathStack;

  @override
  void initState() {
    super.initState();
    selected = List<FileItem>.from(widget.initiallySelected);
    pathStack = [];
  }

  void _onFileTap(FileItem file, FileBrowserController controller) async {
    if (selected.any((f) => f.path == file.path)) {
      setState(() {
        selected.removeWhere((f) => f.path == file.path);
      });
    } else if (selected.length < 3) {
      await controller.selectFile(file);
      setState(() {
        final idx = controller.state.selectedFiles.indexWhere(
          (f) => f.path == file.path,
        );
        if (idx != -1) {
          selected.add(controller.state.selectedFiles[idx]);
        } else {
          selected.add(file);
        }
      });
    }
  }

  void _enterDir(String dirName) {
    setState(() {
      pathStack.add(dirName);
    });
  }

  void _goUp() {
    if (pathStack.isNotEmpty) {
      setState(() {
        pathStack.removeLast();
      });
    }
  }

  String get _currentPath => pathStack.isEmpty ? '' : pathStack.join('/');

  Widget _buildDir(FileBrowserController controller, FileBrowserState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListView(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        children:
            state.items.map((item) {
              if (item.type == 'dir') {
                return ListTile(
                  leading: const Icon(Icons.folder, color: Colors.amber),
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  onTap: () {
                    _enterDir(item.name);
                    controller.fetchDir(
                      _currentPath + (pathStack.isEmpty ? '' : '/'),
                    ); // fetch new dir
                  },
                );
              } else {
                final isSelected = selected.any((f) => f.path == item.path);
                return ListTile(
                  leading: const Icon(
                    Icons.insert_drive_file,
                    color: Colors.blueAccent,
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    item.path,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _onFileTap(item, controller),
                  ),
                  onTap: () => _onFileTap(item, controller),
                );
              }
            }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(
      fileBrowserControllerProvider(widget.params).notifier,
    );
    final state = ref.watch(fileBrowserControllerProvider(widget.params));
    // Fetch the current directory if needed
    if (state.pathStack.join('/') != _currentPath) {
      controller.fetchDir(_currentPath);
    }
    final maxHeight = MediaQuery.of(context).size.height * 0.7;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).dialogBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with back button and breadcrumbs
            Row(
              children: [
                if (pathStack.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Up',
                    onPressed: _goUp,
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      pathStack.isEmpty ? '/' : '/${pathStack.join('/')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Select up to 3 files for context',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildDir(controller, state)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SlashButton(
                    label: 'Done',
                    icon: Icons.check,
                    onTap: () {
                      widget.onSelected(selected);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SlashButton(
                    label: 'Cancel',
                    icon: Icons.close,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CodeEditorScreen extends StatefulWidget {
  final String fileName;
  final String initialCode;
  const CodeEditorScreen({
    required this.fileName,
    required this.initialCode,
    super.key,
  });
  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  late final CodeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CodeController(
      text: widget.initialCode,
      language: dart,
      patternMap: {
        r'\bTODO\b': const TextStyle(
          backgroundColor: Colors.yellow,
          color: Colors.black,
        ),
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC);
    final editorBg = isDark ? const Color(0xFF23232A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF333842) : Colors.grey[300]!;
    final gutterColor = isDark ? const Color(0xFF23232A) : Colors.grey[200]!;
    final lineNumberColor =
        isDark ? const Color(0xFF8B949E) : Colors.grey[600]!;
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: editorBg,
        elevation: 1,
        title: Row(
          children: [
            const Icon(Icons.code, color: Color(0xFF8B5CF6)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.fileName,
                style: const TextStyle(
                  fontFamily: 'Fira Mono',
                  fontSize: 16,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 26),
            tooltip: 'Save',
            onPressed: () => Navigator.of(context).pop(_controller.text),
          ),
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.red, size: 26),
            tooltip: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
          decoration: BoxDecoration(
            color: editorBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: CodeTheme(
              data: CodeThemeData(),
              child: CodeField(
                controller: _controller,
                textStyle: const TextStyle(
                  fontFamily: 'Fira Mono',
                  fontSize: 15,
                  color: Colors.white,
                ),
                expands: true,
                lineNumberStyle: LineNumberStyle(
                  width: 32,
                  textAlign: TextAlign.right,
                  textStyle: TextStyle(
                    color: lineNumberColor,
                    fontSize: 12,
                    fontFamily: 'Fira Mono',
                  ),
                  background: gutterColor,
                  margin: 6.0,
                ),
                background: Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
} 
