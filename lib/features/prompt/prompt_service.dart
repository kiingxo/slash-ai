import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/gemini_service.dart';
import '../../services/openai_service.dart';
import '../../services/github_service.dart';
import '../../services/secure_storage_service.dart';
import '../file_browser/file_browser_controller.dart';

class PromptService {
  static Future<List<Map<String, String>>> fetchFiles({
    required String owner,
    required String repo,
    required String pat,
    String? branch,
  }) async {
    final url = branch != null
        ? 'https://api.github.com/repos/$owner/$repo/contents/?ref=$branch'
        : 'https://api.github.com/repos/$owner/$repo/contents';

    final res = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'token $pat',
        'Accept': 'application/vnd.github+json',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to fetch files: ${res.body}');
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

  static dynamic createAIService({
    required String model,
    String? geminiKey,
    String? openAIApiKey,
  }) {
    if (model == 'gemini') {
      if (geminiKey == null || geminiKey.isEmpty) {
        throw Exception('Gemini API key is required');
      }
      return GeminiService(geminiKey);
    } else {
      if (openAIApiKey == null || openAIApiKey.isEmpty) {
        throw Exception('OpenAI API key is required');
      }
      return OpenAIService(openAIApiKey, model: 'gpt-4o');
    }
  }

  static Future<String> processCodeEditIntent({
    required dynamic aiService,
    required String prompt,
    required List<Map<String, String>> files,
    bool useFullContext = true,
  }) async {
    final fileName = files.isNotEmpty ? files[0]['name'] : 'file';
    final contextInfo = useFullContext
        ? "Full file context available."
        : "Using summarized context.";

    final summaryPrompt = '''
You are /slash, an AI code assistant. The user requested a code change. 
Provide a brief, precise summary of what you're changing (1-2 sentences max).

User request: "$prompt"
File: $fileName
Context: $contextInfo

Be concise and specific about the change.''';

    final summary = await aiService.getCodeSuggestion(
      prompt: summaryPrompt,
      files: files,
    );

    return summary.trim();
  }

  static Future<String> processCodeContent({
    required dynamic aiService,
    required String prompt,
    required List<Map<String, String>> files,
  }) async {
    final oldContent = files.isNotEmpty ? files[0]['content']! : '';
    final fileName = files.isNotEmpty ? files[0]['name']! : 'unknown';

    final codeEditPrompt =
        'You are a code editing agent. Given the original file content and the user\'s request, output ONLY the new file content after the edit. Do NOT include any explanation, comments, or markdown. Output only the code, as it should appear in the file.\n\n'
        'File: $fileName\n'
        'Original content:\n$oldContent\n'
        'User request: $prompt';

    var newContent = await aiService.getCodeSuggestion(
      prompt: codeEditPrompt,
      files: files,
    );

    return PromptService.stripCodeFences(newContent);
  }

  static Future<String> processRepoQuestion({
    required dynamic aiService,
    required String prompt,
    required dynamic repo,
    required List<Map<String, String>> contextFiles,
    bool hasFullContext = false,
  }) async {
    final repoInfo =
        'Repo name: ${repo['name']}\nDescription: ${repo['description'] ?? 'No description.'}';

    final contextNote = hasFullContext
        ? "You have access to full file contents for detailed analysis."
        : contextFiles.isNotEmpty
            ? "You have access to file summaries. Ask user to include full context if you need more details."
            : "No file context available.";

    final answerPrompt = '''
User question: $prompt
Repo info: $repoInfo
Context: $contextNote

Answer the user's question about the repo. If you need more context, mention it.''';

    return await aiService.getCodeSuggestion(
      prompt: answerPrompt,
      files: contextFiles,
    );
  }

  static Future<String> processGeneralIntent({
    required dynamic aiService,
    required String prompt,
    required List<Map<String, String>> contextFiles,
    bool hasFullContext = false,
  }) async {
    final contextNote = hasFullContext
        ? "You have access to full file context."
        : contextFiles.isNotEmpty
            ? "You have access to file summaries."
            : "";

    final answerPrompt = '''
User: $prompt
You are /slash, an AI code assistant. Respond conversationally.
${contextNote.isNotEmpty ? "Context: $contextNote" : ""}''';

    return await aiService.getCodeSuggestion(
      prompt: answerPrompt,
      files: contextFiles,
    );
  }

  static Future<String> createPullRequest({
    required String owner,
    required String repo,
    required String fileName,
    required String newContent,
    required String prompt,
    required String summary,
    String? selectedBranch,
  }) async {
    final storage = SecureStorageService();
    final githubPat = await storage.getApiKey('github_pat');

    if (githubPat == null) {
      throw Exception('GitHub PAT is required');
    }

    final github = GitHubService(githubPat);
    final baseBranch = selectedBranch ?? 'main';
    final newBranch = 'slash/${DateTime.now().millisecondsSinceEpoch}';

    await github.createBranch(
      owner: owner,
      repo: repo,
      newBranch: newBranch,
      baseBranch: baseBranch,
    );

    await github.commitFile(
      owner: owner,
      repo: repo,
      branch: newBranch,
      path: fileName,
      content: newContent,
      message: '/SLASH: $prompt',
    );

    return await github.openPullRequest(
      owner: owner,
      repo: repo,
      head: newBranch,
      base: baseBranch,
      title: '/SLASH: $prompt',
      body: summary,
    );
  }

  static Future<List<String>> fetchBranches({
    required String owner,
    required String repo,
  }) async {
    final storage = SecureStorageService();
    final pat = await storage.getApiKey('github_pat');

    if (pat == null) {
      throw Exception('GitHub PAT is required');
    }

    final github = GitHubService(pat);
    return await github.fetchBranches(owner: owner, repo: repo);
  }

  static List<FileItem> searchContextFiles({
    required List<FileItem> files,
    required String query,
  }) {
    final lowerQuery = query.toLowerCase();
    return files.where((file) {
      return file.name.toLowerCase().contains(lowerQuery) ||
          (file.content?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  static String generateFileSummary(String fileName, String content) {
    final lines = content.split('\n');
    final totalLines = lines.length;

    final imports =
        lines.where((line) => line.trim().startsWith('import ')).take(5).toList();
    final classes = _extractMatches(content, RegExp(r'class\s+(\w+)'));
    final functions =
        _extractMatches(content, RegExp(r'(?:Future<\w+>|void|\w+)\s+(\w+)\s*\('));
    final variables =
        _extractMatches(content, RegExp(r'(?:final|var|const)\s+(\w+)'));

    final previewLines = lines.take(15).join('\n');

    return '''
=== FILE SUMMARY: $fileName ===
Lines: $totalLines
${imports.isNotEmpty ? 'Imports: ${imports.join(', ')}' : ''}
${classes.isNotEmpty ? 'Classes: ${classes.join(', ')}' : ''}
${functions.isNotEmpty ? 'Functions: ${functions.take(10).join(', ')}' : ''}
${variables.isNotEmpty ? 'Variables: ${variables.take(5).join(', ')}' : ''}

=== PREVIEW ===
$previewLines
${lines.length > 15 ? '...(${lines.length - 15} more lines)' : ''}
=== END SUMMARY ===
''';
  }

  static List<String> _extractMatches(String content, RegExp regex) {
    return regex
        .allMatches(content)
        .map((match) => match.group(1) ?? '')
        .where((match) => match.isNotEmpty)
        .toSet()
        .toList();
  }

  static bool shouldUseFullContext(String intent, String prompt) {
    if (intent == 'code_edit') return true;

    final fullContextKeywords = [
      'show me the code',
      'full implementation',
      'complete code',
      'entire file',
      'with context',
      'detailed analysis',
    ];

    final lowerPrompt = prompt.toLowerCase();
    return fullContextKeywords.any((keyword) => lowerPrompt.contains(keyword));
  }

  static Map<String, String> optimizeContextFiles(
    List<Map<String, String>> files,
    String intent,
    String prompt,
  ) {
    final optimizedFiles = <String, String>{};
    final useFullContext = shouldUseFullContext(intent, prompt);

    for (final file in files) {
      final fileName = file['name'] ?? 'unknown';
      final content = file['content'] ?? '';

      if (useFullContext) {
        optimizedFiles[fileName] = content;
      } else {
        optimizedFiles[fileName] = generateFileSummary(fileName, content);
      }
    }

    return optimizedFiles;
  }

  static String stripCodeFences(String input) {
    String output = input.trim();

    // Remove opening code fence with optional language
    output = output.replaceAll(RegExp(r'^```(?:\w+)?\s*\n?'), '');

    // Remove closing code fence
    output = output.replaceAll(RegExp(r'\n?```$'), '');

    // Remove any remaining code fences
    output = output.replaceAll(RegExp(r'```'), '');

    return output.trim();
  }
}