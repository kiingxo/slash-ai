import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenAIService {
  final String apiKey;
  static const String _baseUrl = 'https://api.openai.com/v1/chat/completions';
  final String model;

  OpenAIService(this.apiKey, {this.model = 'gpt-3.5-turbo'});

  Future<String> getCodeSuggestion({required String prompt, required List<Map<String, String>> files}) async {
    final systemPrompt = files.isNotEmpty
        ? 'You are an expert code assistant. User prompt: $prompt\nRelevant files:\n' +
            files.map((f) => 'File: ${f['name']}\n${f['content']}\n---').join('\n') +
            '\nSuggest minimal, high-quality code changes. Output only the code diff and a short summary.'
        : 'You are an expert code assistant. User prompt: $prompt';
    final requestBody = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
      ],
      'max_tokens': 1024,
      'temperature': 0.2,
    };
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(requestBody),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices']?[0]?['message']?['content']?.trim() ?? '';
    } else {
      throw Exception('OpenAI error: ${response.body}');
    }
  }

  Future<String> classifyIntent(String prompt) async {
    final systemPrompt = "Classify the following user prompt as one of: [code_edit, repo_question, general]. Only return the label. Prompt: '$prompt'";
    final requestBody = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
      ],
      'max_tokens': 16,
      'temperature': 0.0,
    };
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(requestBody),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices']?[0]?['message']?['content']?.trim() ?? 'general';
    } else {
      throw Exception('OpenAI error: ${response.body}');
    }
  }
} 