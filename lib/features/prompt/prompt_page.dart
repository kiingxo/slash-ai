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
  ReviewData({required this.fileName, required this.oldContent, required this.newContent, required this.summary});
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
  List<ChatMessage> _messages = [
    ChatMessage(isUser: false, text: "Hi! I'm /slash 🤖. How can I help you today?"),
  ];
  bool _reviewExpanded = false;
  ReviewData? _pendingReview;
  String _selectedModel = 'gemini';
  String? _lastIntent;

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
    super.dispose();
  }

  Future<List<Map<String, String>>> _fetchFiles({required String owner, required String repo, required String pat}) async {
    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/contents/'),
      headers: {
        'Authorization': '900token $pat',
        'Accept': 'application/vnd.github+json',
      },
    );
    if (res.statusCode != 200) throw Exception('Failed to fetch files:  [31m${res.body} [0m');
    final List files = jsonDecode(res.body);
    List<Map<String, String>> fileContents = [];
    for (final file in files) {
      if (file['type'] == 'file') {
        final fileRes = await http.get(
          Uri.parse(file['download_url']),
        );
        if (fileRes.statusCode == 200) {
          fileContents.add({'name': file['name'], 'content': fileRes.body});
        }
      }
    }
    return fileContents;
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
          (model == 'openai' && (openAIApiKey == null || openAIApiKey.isEmpty)) ||
          githubPat == null || githubPat.isEmpty) {
        print('[PromptPage] Missing API keys');
        throw Exception('Missing API keys');
      }
      final repo = _selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
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
      if (intent == 'code_edit') {
        final owner = repo['owner']['login'];
        final repoName = repo['name'];
        print('[PromptPage] Fetching files for $owner/$repoName');
        final files = await _fetchFiles(owner: owner, repo: repoName, pat: githubPat!);
        print('[PromptPage] Calling getCodeSuggestion...');
        final suggestion = await aiService.getCodeSuggestion(prompt: prompt, files: files);
        final oldContent = files.isNotEmpty ? files[0]['content']! : '';
        final newContent = suggestion;
        final fileName = files.isNotEmpty ? files[0]['name']! : 'unknown.dart';
        final summary = "Slash's suggestion for \"$prompt\".";
        final review = ReviewData(fileName: fileName, oldContent: oldContent, newContent: newContent, summary: summary);
        setState(() {
          _isLoading = false;
          _pendingReview = review;
          _messages.add(ChatMessage(isUser: false, text: summary, review: review));
          _reviewExpanded = false;
        });
      } else if (intent == 'repo_question') {
        final repoInfo = 'Repo name: ${repo['name']}\nDescription: ${repo['description'] ?? 'No description.'}';
        final answerPrompt = 'User question: $prompt\nRepo info: $repoInfo\nAnswer the user\'s question about the repo.';
        print('[PromptPage] Calling getCodeSuggestion for repo_question...');
        final answer = await aiService.getCodeSuggestion(prompt: answerPrompt, files: const <Map<String, String>>[]);
        setState(() {
          _isLoading = false;
          _messages.add(ChatMessage(isUser: false, text: answer));
        });
      } else {
        final answerPrompt = 'User: $prompt\nYou are /slash, an AI code assistant. Respond conversationally.';
        print('[PromptPage] Calling getCodeSuggestion for general...');
        final answer = await aiService.getCodeSuggestion(prompt: answerPrompt, files: const <Map<String, String>>[]);
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
        _messages.add(ChatMessage(isUser: false, text: friendlyErrorMessage(e.toString())));
      });
    }
  }

  // Add a method to force code edit if user taps override
  Future<void> _forceCodeEdit(String prompt) async {
    setState(() { _isLoading = true; });
    try {
      final authState = ref.read(authControllerProvider);
      final geminiKey = authState.geminiApiKey;
      final openAIApiKey = authState.openAIApiKey;
      final githubPat = authState.githubPat;
      final model = _selectedModel;
      final repo = _selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      dynamic aiService;
      if (model == 'gemini') {
        aiService = GeminiService(geminiKey!);
      } else {
        aiService = OpenAIService(openAIApiKey!, model: 'gpt-4o');
      }
      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      final files = await _fetchFiles(owner: owner, repo: repoName, pat: githubPat!);
      final suggestion = await aiService.getCodeSuggestion(prompt: prompt, files: files);
      final oldContent = files.isNotEmpty ? files[0]['content']! : '';
      final newContent = suggestion;
      final fileName = files.isNotEmpty ? files[0]['name']! : 'unknown.dart';
      final summary = "Slash's suggestion for \"$prompt\".";
      final review = ReviewData(fileName: fileName, oldContent: oldContent, newContent: newContent, summary: summary);
      setState(() {
        _isLoading = false;
        _pendingReview = review;
        _messages.add(ChatMessage(isUser: false, text: summary, review: review));
        _reviewExpanded = false;
      });
    } catch (e, st) {
      print('[PromptPage] Force code edit error: $e');
      print(st);
      setState(() {
        _isLoading = false;
        _error = e.toString();
        _messages.add(ChatMessage(isUser: false, text: friendlyErrorMessage(e.toString())));
      });
    }
  }

  Future<void> _approveReview(ReviewData review, String prompt) async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final storage = SecureStorageService();
      final githubPat = await storage.getApiKey('github_pat');
      final repo = _selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      final github = GitHubService(githubPat!);
      final branch = 'slash/${DateTime.now().millisecondsSinceEpoch}';
      await github.createBranch(owner: owner, repo: repoName, newBranch: branch);
      await github.commitFile(
        owner: owner,
        repo: repoName,
        branch: branch,
        path: review.fileName,
        content: review.newContent,
        message: 'AI: $prompt',
      );
      final prUrl = await github.openPullRequest(
        owner: owner,
        repo: repoName,
        head: branch,
        base: 'main',
        title: 'AI: $prompt',
        body: review.summary,
      );
      setState(() {
        _isLoading = false;
        _messages.add(ChatMessage(isUser: false, text: 'Pull request created! $prUrl'));
        _pendingReview = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
        _messages.add(ChatMessage(isUser: false, text: friendlyErrorMessage(_error ?? '')));
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
    final selectedRepo = _selectedRepo ?? repoState.selectedRepo ?? (repos.isNotEmpty ? repos[0] : null);

    if (repos.isEmpty) {
      return Center(child: Text('No repositories found.', style: TextStyle(fontSize: 18)));
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
                },
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
                    return _buildReviewBubble(msg.review!, msg.text, idx == _messages.length - 1);
                  }
                  // Show intent tag above the latest agent message
                  final isLastAgent = !msg.isUser && idx == _messages.lastIndexWhere((m) => !m.isUser);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isLastAgent) _intentTag(_lastIntent),
                      Align(
                        alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: msg.isUser
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: msg.isUser ? [] : [
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
                                  padding: const EdgeInsets.only(right: 8, top: 2),
                                  child: Icon(Icons.android, size: 22, color: Theme.of(context).colorScheme.primary),
                                ),
                              Flexible(
                                child: Text(
                                  msg.text,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: msg.isUser ? Theme.of(context).colorScheme.primary : null,
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
                child: Center(
                  child: _ThinkingWidget(),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(friendlyErrorMessage(_error ?? ''), style: const TextStyle(color: Colors.red)),
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
                Icon(Icons.android, size: 22, color: Theme.of(context).colorScheme.primary),
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
                        Icon(_reviewExpanded ? Icons.expand_less : Icons.expand_more, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_reviewExpanded && isLast) ...[
              const SizedBox(height: 12),
              Text(review.fileName, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SlashDiffViewer(oldContent: review.oldContent, newContent: review.newContent),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SlashButton(
                      label: 'PR',
                      onTap: _isLoading ? () {} : () => _approveReview(review, summary),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SlashButton(
                      label: 'Reject',
                      onTap: _isLoading ? () {} : _rejectReview,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Creative thinking widget (animated ellipsis)
class _ThinkingWidget extends StatefulWidget {
  @override
  State<_ThinkingWidget> createState() => _ThinkingWidgetState();
}

class _ThinkingWidgetState extends State<_ThinkingWidget> with SingleTickerProviderStateMixin {
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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.primary),
        );
      },
    );
  }
} 