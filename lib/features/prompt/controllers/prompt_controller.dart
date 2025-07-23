import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/review_data.dart';
import '../../../services/gemini_service.dart';
import '../../../services/openai_service.dart';
import '../../../features/auth/auth_controller.dart';

class PromptController extends ChangeNotifier {
  final List<ChatMessage> _messages = [
    ChatMessage(isUser: false, text: "Hi! I'm /slash. How can I help you today?"),
  ];
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool _loading = false;
  bool get loading => _loading;
  String? _lastIntent;
  ReviewData? _pendingReview;

  Future<void> submitPrompt({
    required String prompt,
    required dynamic authState,
    required String? codeContext,
    required String? fileName,
    required Function(ReviewData) onReview,
  }) async {
    if (prompt.isEmpty) return;
    _loading = true;
    _messages.add(ChatMessage(isUser: true, text: prompt));
    notifyListeners();
    try {
      final geminiKey = authState.geminiApiKey;
      final openAIApiKey = authState.openAIApiKey;
      final model = authState.model;
      final aiService = model == 'gemini'
          ? GeminiService(geminiKey!)
          : OpenAIService(openAIApiKey!, model: 'gpt-4o');
      final intent = await (aiService as dynamic).classifyIntent(prompt);
      _lastIntent = intent;
      if (intent == 'code_edit') {
        final summaryPrompt =
            "You are an AI code assistant. Summarize the following code change request for the user in a friendly, conversational way. Do NOT include the full code or file content in your response. User request: $prompt";
        final summary = await (aiService as dynamic).getCodeSuggestion(
          prompt: summaryPrompt,
          files: [
            {'name': fileName ?? 'current.dart', 'content': codeContext ?? ''}
          ],
        );
        final codeEditPrompt =
            'You are a code editing agent. Given the original file content and the user\'s request, output ONLY the new file content after the edit. Do NOT include any explanation, comments, or markdown. Output only the code, as it should appear in the file.\n\nFile: \\${fileName ?? 'current.dart'}\nOriginal content:\n${codeContext ?? ''}\nUser request: $prompt';
        var newContent = await (aiService as dynamic).getCodeSuggestion(
          prompt: codeEditPrompt,
          files: [
            {'name': fileName ?? 'current.dart', 'content': codeContext ?? ''}
          ],
        );
        newContent = stripCodeFences(newContent);
        final review = ReviewData(
          fileName: fileName ?? 'current.dart',
          oldContent: codeContext ?? '',
          newContent: newContent,
          summary: summary,
        );
        _pendingReview = review;
        _messages.add(ChatMessage(isUser: false, text: summary, review: review));
        onReview(review);
      } else {
        final answerPrompt =
            'User: $prompt\nYou are /slash, an AI code assistant. Respond conversationally.';
        final answer = await (aiService as dynamic).getCodeSuggestion(
          prompt: answerPrompt,
          files: [
            {'name': fileName ?? 'current.dart', 'content': codeContext ?? ''}
          ],
        );
        _messages.add(ChatMessage(isUser: false, text: answer));
      }
    } catch (e) {
      _messages.add(ChatMessage(isUser: false, text: 'Error: \\${e.toString()}'));
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

String stripCodeFences(String input) {
  final codeFenceRegex = RegExp(
    r'^```[a-zA-Z0-9]*\n|\n```|```[a-zA-Z0-9]*|```',
    multiLine: true,
  );
  var output = input.replaceAll(codeFenceRegex, '');
  output = output.trim();
  return output;
} 