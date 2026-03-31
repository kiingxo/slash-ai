import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_service.dart';

class AnthropicService implements LLMService {
  final String apiKey;
  final String model;
  final String _baseUrl = 'https://api.anthropic.com/v1/messages';
  final String _anthropicVersion = '2023-06-01';

  AnthropicService(this.apiKey, {required this.model});

  @override
  Future<String> getCodeSuggestion({
    required String prompt,
    required List<Map<String, String>> files,
  }) async {
    const systemPrompt =
        'You are /slash, a production-minded software engineer. '
        'Prefer precise, actionable answers, and only output code when the user specifically asks for code.';

    final userPrompt = StringBuffer(prompt.trim());
    if (files.isNotEmpty) {
      userPrompt.writeln();
      userPrompt.writeln();
      userPrompt.writeln('Attached repository context:');
      for (final file in files) {
        userPrompt.writeln(
          _formatFileBlock(file['name'] ?? 'unknown', file['content'] ?? ''),
        );
      }
    }

    return _chat(
      system: systemPrompt,
      messages: [
        {'role': 'user', 'content': userPrompt.toString()},
      ],
      maxTokens: 4096,
      temperature: 0.2,
    );
  }

  @override
  Future<String> classifyIntent(String prompt) async {
    const system =
        'Classify the user request as exactly one label: '
        'code_edit, repo_question, or general. '
        'Return only the label.';

    final response = await _chat(
      system: system,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      maxTokens: 32,
      temperature: 0,
      timeout: const Duration(seconds: 12),
      maxAttempts: 1,
    );

    final normalized = response.trim().toLowerCase();
    if (normalized.contains('code_edit')) return 'code_edit';
    if (normalized.contains('repo_question')) return 'repo_question';
    return 'general';
  }

  Future<String> _chat({
    required String system,
    required List<Map<String, String>> messages,
    int maxTokens = 4096,
    double temperature = 0.2,
    Duration timeout = const Duration(seconds: 60),
    int maxAttempts = 2,
  }) async {
    final requestBody = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'system': system,
      'messages': messages,
    };

    final headers = {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': _anthropicVersion,
    };

    final response = await _postWithRetry(
      Uri.parse(_baseUrl),
      headers,
      jsonEncode(requestBody),
      timeout: timeout,
      maxAttempts: maxAttempts,
    );

    if (response.statusCode != 200) {
      throw Exception(_buildErrorMessage(response));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = data['content'];
    if (content is List && content.isNotEmpty) {
      final first = content.first;
      if (first is Map<String, dynamic> && first['type'] == 'text') {
        return (first['text'] ?? '').toString().trim();
      }
    }
    return '';
  }

  Future<http.Response> _postWithRetry(
    Uri uri,
    Map<String, String> headers,
    Object body, {
    int maxAttempts = 2,
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
        if (attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
      }
    }
    throw Exception('Request failed after $maxAttempts attempts.');
  }

  bool _shouldRetry(int statusCode) =>
      const {408, 409, 429, 500, 502, 503, 504}.contains(statusCode);

  String _buildErrorMessage(http.Response response) {
    String detail = '';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          detail = (error['message'] ?? '').toString().trim();
        }
        if (detail.isEmpty) {
          detail = (decoded['message'] ?? '').toString().trim();
        }
      }
    } catch (_) {}

    if (detail.isEmpty) detail = response.body.trim();
    if (detail.isEmpty) detail = 'Request failed.';
    if (detail.length > 320) detail = '${detail.substring(0, 320)}...';
    return 'Anthropic error ${response.statusCode}: $detail';
  }

  String _formatFileBlock(String name, String content) {
    final safeContent = _truncateContent(content);
    return 'FILE: $name\n$safeContent\nEND FILE';
  }

  String _truncateContent(String content, {int maxChars = 12000}) {
    if (content.length <= maxChars) return content;
    return '${content.substring(0, maxChars)}\n...<truncated>';
  }
}
