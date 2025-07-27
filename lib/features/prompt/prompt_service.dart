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
  }) async {
    // Generate a short, precise summary for the chat bubble
    final fileName = files.isNotEmpty ? files[0]['name'] : 'file';
    final summaryPrompt =
     '''
You are /slash, an AI code assistant. The user requested a code change. 
Provide a brief, precise summary of what you're changing (1-2 sentences max).

User request: "$prompt"
File: $fileName

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
    
    return stripCodeFences(newContent);
  }

  static Future<String> processRepoQuestion({
    required dynamic aiService,
    required String prompt,
    required dynamic repo,
    required List<Map<String, String>> contextFiles,
  }) async {
    final repoInfo =
        'Repo name: ${repo['name']}\nDescription: ${repo['description'] ?? 'No description.'}';
    
    final answerPrompt =
        'User question: $prompt\nRepo info: $repoInfo\nAnswer the user\'s question about the repo.';
    
    return await aiService.getCodeSuggestion(
      prompt: answerPrompt,
      files: contextFiles,
    );
  }

  static Future<String> processGeneralIntent({
    required dynamic aiService,
    required String prompt,
    required List<Map<String, String>> contextFiles,
  }) async {
    final answerPrompt =
        'User: $prompt\nYou are /slash, an AI code assistant. Respond conversationally.';
    
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
}

// Improved utility function to strip markdown code fences
String stripCodeFences(String input) {
  String output = input.trim();
  
  // Remove opening code fence with optional language
  output = output.replaceAll(RegExp(r'^```\w*\s*\n?'), '');
  
  // Remove closing code fence
  output = output.replaceAll(RegExp(r'\n?```\s*$'), '');
  
  // Remove any remaining code fences
  output = output.replaceAll(RegExp(r'```'), '');
  
  return output.trim();
}

// Friendly error message helper
String friendlyErrorMessage(String error) {
  if (error.contains('API key')) {
    return 'Please check your API keys in settings.';
  } else if (error.contains('repository')) {
    return 'Repository access error. Please check your permissions.';
  } else if (error.contains('network') || error.contains('connection')) {
    return 'Network error. Please check your internet connection.';
  }
  return 'An error occurred. Please try again.';
}