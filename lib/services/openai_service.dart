import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_service.dart';

class OpenAIService implements LLMService {
  final String apiKey;
  final String model;
  final bool useOpenRouter;
  final String baseUrl;
  final String appName;

  OpenAIService(
    this.apiKey, {
    required this.model,
    this.useOpenRouter = false,
    this.appName = 'Slash',
    String? baseUrl,
  }) : baseUrl =
           baseUrl ??
           (useOpenRouter
               ? 'https://openrouter.ai/api/v1/chat/completions'
               : 'https://api.openai.com/v1/chat/completions');

  @override
  Future<String> getCodeSuggestion({
    required String prompt,
    required List<Map<String, String>> files,
  }) async {
    final systemPrompt =
        'You are /slash, a production-minded software engineer. '
        'Prefer precise, actionable answers, and only output code when the user specifically asks for code.';
    final userPrompt = StringBuffer(prompt.trim());

    if (files.isNotEmpty) {
      userPrompt.writeln();
      userPrompt.writeln();
      userPrompt.writeln('Attached repository context:');
      for (final file in files) {
        userPrompt.writeln(
          _formatFileBlock(
            file['name'] ?? 'unknown',
            file['content'] ?? '',
          ),
        );
      }
    }

    return chat(
      messages: [
        {
          'role': 'system',
          'content': systemPrompt,
        },
        {
          'role': 'user',
          'content': userPrompt.toString(),
        },
      ],
      maxTokens: 4096,
      temperature: 0.2,
    );
  }

  @override
  Future<String> classifyIntent(String prompt) async {
    final response = await chat(
      messages: [
        {
          'role': 'system',
          'content':
              'Classify the user request as exactly one label: '
              'code_edit, repo_question, or general. '
              'Return only the label.',
        },
        {
          'role': 'user',
          'content': prompt,
        },
      ],
      maxTokens: 32,
      temperature: 0,
    );

    final normalized = response.trim().toLowerCase();
    if (normalized.contains('code_edit')) {
      return 'code_edit';
    }
    if (normalized.contains('repo_question')) {
      return 'repo_question';
    }
    return 'general';
  }

  Future<String> chat({
    required List<Map<String, String>> messages,
    int maxTokens = 4096,
    double temperature = 0.2,
  }) async {
    final requestBody = {
      'model': model,
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
    };

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
      if (useOpenRouter) 'HTTP-Referer': 'https://slash.local',
      if (useOpenRouter) 'X-Title': appName,
    };

    final response = await _postWithRetry(
      Uri.parse(baseUrl),
      headers,
      jsonEncode(requestBody),
    );

    if (response.statusCode != 200) {
      throw Exception(
        '${useOpenRouter ? 'OpenRouter' : 'OpenAI'} error: ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final message = data['choices'] is List && (data['choices'] as List).isNotEmpty
        ? (data['choices'] as List).first
        : null;

    if (message is! Map<String, dynamic>) {
      return '';
    }

    final content = message['message'];
    if (content is Map<String, dynamic>) {
      final rawContent = content['content'];
      if (rawContent is String) {
        return rawContent.trim();
      }
      if (rawContent is List) {
        return rawContent
            .whereType<Map<String, dynamic>>()
            .map((chunk) => chunk['text']?.toString() ?? '')
            .join()
            .trim();
      }
    }

    return '';
  }

  Future<http.Response> _postWithRetry(
    Uri uri,
    Map<String, String> headers,
    Object body, {
    int maxAttempts = 3,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http
            .post(uri, headers: headers, body: body)
            .timeout(timeout);

        if (_shouldRetry(response.statusCode) && attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
          continue;
        }

        return response;
      } on TimeoutException {
        if (attempt >= maxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
      }
    }

    throw Exception('Request failed after $maxAttempts attempts.');
  }

  bool _shouldRetry(int statusCode) {
    return const {408, 409, 429, 500, 502, 503, 504}.contains(statusCode);
  }

  String _formatFileBlock(String name, String content) {
    final safeContent = _truncateContent(content);
    return 'FILE: $name\n$safeContent\nEND FILE';
  }

  String _truncateContent(String content, {int maxChars = 12000}) {
    if (content.length <= maxChars) {
      return content;
    }
    return '${content.substring(0, maxChars)}\n...<truncated>';
  }
}
