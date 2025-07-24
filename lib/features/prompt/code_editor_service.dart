import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/secure_storage_service.dart';
import '../../services/github_service.dart';
import '../../services/openai_service.dart';
import '../../services/gemini_service.dart';

// Service provider
final codeEditorServiceProvider = Provider<CodeEditorService>(
  (ref) => CodeEditorService(),
);

// Chat response model
class ChatResponse {
  final String response;
  final String? pendingEdit;

  ChatResponse({
    required this.response,
    this.pendingEdit,
  });
}

class CodeEditorService {
  final SecureStorageService _storage = SecureStorageService();

  /// Fetches branches for a given repository
  Future<List<String>> fetchBranches({
    required String owner,
    required String repo,
  }) async {
    try {
      final pat = await _storage.getApiKey('github_pat');
      if (pat == null) throw Exception('GitHub PAT not found');
      
      final github = GitHubService(pat);
      return await github.fetchBranches(owner: owner, repo: repo);
    } catch (e) {
      throw Exception('Failed to fetch branches: $e');
    }
  }

  /// Commits and pushes a file to GitHub
  Future<void> commitFile({
    required String owner,
    required String repo,
    required String branch,
    required String path,
    required String content,
    required String message,
  }) async {
    try {
      final pat = await _storage.getApiKey('github_pat');
      if (pat == null) throw Exception('GitHub PAT not found');
      
      final github = GitHubService(pat);
      await github.commitFile(
        owner: owner,
        repo: repo,
        branch: branch,
        path: path,
        content: content,
        message: message,
      );
    } catch (e) {
      throw Exception('Failed to commit file: $e');
    }
  }

  /// Handles chat requests with AI services
  Future<ChatResponse> handleChatRequest({
    required String prompt,
    required String codeContext,
    required String fileName,
    String? geminiKey,
    String? openAIApiKey,
    String? model,
  }) async {
    try {
      final aiService = _createAIService(
        geminiKey: geminiKey,
        openAIApiKey: openAIApiKey,
        model: model,
      );

      // Classify the user's intent
      final intent = await _classifyIntent(aiService, prompt);

      if (intent == 'code_edit') {
        return await _handleCodeEditRequest(
          aiService,
          prompt,
          codeContext,
          fileName,
        );
      } else {
        return await _handleGeneralQARequest(
          aiService,
          prompt,
          codeContext,
          fileName,
        );
      }
    } catch (e) {
      throw Exception('AI service error: $e');
    }
  }

  /// Creates appropriate AI service based on configuration
  dynamic _createAIService({
    String? geminiKey,
    String? openAIApiKey,
    String? model,
  }) {
    if (model == 'gemini' && geminiKey != null) {
      return GeminiService(geminiKey);
    } else if (openAIApiKey != null) {
      return OpenAIService(openAIApiKey, model: 'gpt-4o');
    } else {
      throw Exception('No valid AI service configuration found');
    }
  }

  /// Classifies user intent using AI
  Future<String> _classifyIntent(dynamic aiService, String prompt) async {
    try {
      return await aiService.classifyIntent(prompt);
    } catch (e) {
      // Fallback to general Q&A if classification fails
      return 'general_qa';
    }
  }

  /// Handles code editing requests
  Future<ChatResponse> _handleCodeEditRequest(
    dynamic aiService,
    String prompt,
    String codeContext,
    String fileName,
  ) async {
    // Generate user-friendly summary
    final summaryPrompt = """
You are an AI code assistant. Summarize the following code change request for the user in a friendly, conversational way. 
Do NOT include the full code or file content in your response. 
User request: $prompt
""";

    final summary = await aiService.getCodeSuggestion(
      prompt: summaryPrompt,
      files: [
        {'name': fileName, 'content': codeContext}
      ],
    );

    // Generate actual code edit
    final codeEditPrompt = """
You are a code editing agent. Given the original file content and the user's request, output ONLY the new file content after the edit. 
Do NOT include any explanation, comments, or markdown. Output only the code, as it should appear in the file.

File: $fileName
Original content:
$codeContext

User request: $prompt
""";

    var newContent = await aiService.getCodeSuggestion(
      prompt: codeEditPrompt,
      files: [
        {'name': fileName, 'content': codeContext}
      ],
    );

    // Clean up the response
    newContent = stripCodeFences(newContent);

    return ChatResponse(
      response: summary,
      pendingEdit: newContent,
    );
  }

  /// Handles general Q&A requests
  Future<ChatResponse> _handleGeneralQARequest(
    dynamic aiService,
    String prompt,
    String codeContext,
    String fileName,
  ) async {
    final answerPrompt = """
User: $prompt
You are /slash, an AI code assistant. Respond conversationally.
""";

    final answer = await aiService.getCodeSuggestion(
      prompt: answerPrompt,
      files: [
        {'name': fileName, 'content': codeContext}
      ],
    );

    return ChatResponse(response: answer);
  }

  /// Utility function to strip markdown code fences and extra text
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
}