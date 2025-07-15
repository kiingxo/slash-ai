import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repo/repo_controller.dart';
import '../review/review_page.dart';
import '../../services/secure_storage_service.dart';
import '../../services/gemini_service.dart';
import '../../services/github_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../ui/components/slash_text_field.dart';
import '../../ui/components/slash_button.dart';

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

  @override
  void initState() {
    super.initState();
    promptController = TextEditingController();
  }

  @override
  void dispose() {
    promptController.dispose();
    super.dispose();
  }

  Future<List<Map<String, String>>> _fetchFiles({required String owner, required String repo, required String pat}) async {
    // Fetch all files in the root directory for MVP
    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/contents/'),
      headers: {
        'Authorization': 'token $pat',
        'Accept': 'application/vnd.github+json',
      },
    );
    if (res.statusCode != 200) throw Exception('Failed to fetch files: ${res.body}');
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
    setState(() { _isLoading = true; _error = null; });
    try {
      // 1. Get API keys
      final storage = SecureStorageService();
      final geminiKey = await storage.getApiKey('gemini_api_key');
      final githubPat = await storage.getApiKey('github_pat');
      if (geminiKey == null || githubPat == null) throw Exception('Missing API keys');
      // 2. Get repo info
      final repo = _selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      // 3. Fetch files
      final files = await _fetchFiles(owner: owner, repo: repoName, pat: githubPat);
      // 4. Call Gemini
      final gemini = GeminiService(geminiKey);
      final suggestion = await gemini.getCodeSuggestion(prompt: prompt, files: files);
      // 5. For MVP, treat suggestion as new content for the first file
      final oldContent = files.isNotEmpty ? files[0]['content']! : '';
      final newContent = suggestion;
      final fileName = files.isNotEmpty ? files[0]['name']! : 'unknown.dart';
      final summary = "Slash's suggestion for \"$prompt\".";
      // 6. Show ReviewPage
      setState(() { _isLoading = false; });
      // ignore: use_build_context_synchronously
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReviewPage(
            diffs: [FileDiff(fileName: fileName, oldContent: oldContent, newContent: newContent)],
            summary: summary,
            onApprove: () async {
              Navigator.of(context).pop();
              setState(() { _isLoading = true; _error = null; });
              try {
                final github = GitHubService(githubPat);
                final branch = 'slash/${DateTime.now().millisecondsSinceEpoch}';
                // Create branch
                await github.createBranch(owner: owner, repo: repoName, newBranch: branch);
                // Commit file
                await github.commitFile(
                  owner: owner,
                  repo: repoName,
                  branch: branch,
                  path: fileName,
                  content: newContent,
                  message: 'AI: $prompt',
                );
                // Open PR
                final prUrl = await github.openPullRequest(
                  owner: owner,
                  repo: repoName,
                  head: branch,
                  base: 'main',
                  title: 'AI: $prompt',
                  body: summary,
                );
                setState(() { _isLoading = false; });
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Pull request created! $prUrl')),
                );
              } catch (e) {
                setState(() { _isLoading = false; _error = e.toString(); });
              }
            },
            onReject: () {
              Navigator.of(context).pop();
            },
          ),
        ),
      );
    } catch (e) {
      setState(() { _isLoading = false; _error = e.toString(); });
    }
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
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('/Slash', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (_isLoading) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Please wait while /slash updates your repo...',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                  ],
                  DropdownButton<dynamic>(
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
                  const SizedBox(height: 24),
                  SlashTextField(
                    controller: promptController,
                    hint: 'What do you want to do? (e.g. Add Firebase login to the app)',
                    minLines: 2,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 24),
                  SlashButton(
                    label: 'Submit Prompt',
onTap: _isLoading ? () {} : () { _handlePromptSubmit(); },
                    loading: _isLoading,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
} 