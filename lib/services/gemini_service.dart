import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  final String apiKey;
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent';

  GeminiService(this.apiKey);

  Future<String> getCodeSuggestion({required String prompt, required List<Map<String, String>> files}) async {
    print('[GeminiService] getCodeSuggestion called with prompt: $prompt');
    final requestBody = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': _composePrompt(prompt, files)}
          ]
        }
      ]
    };

    try {
    final response = await http.post(
      Uri.parse('$_baseUrl?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));
      print('[GeminiService] getCodeSuggestion response status:  [32m${response.statusCode} [0m');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
    } else {
        print('[GeminiService] getCodeSuggestion error: ${response.body}');
      throw Exception('Failed to get suggestion: ${response.body}');
      }
    } catch (e) {
      print('[GeminiService] getCodeSuggestion exception: $e');
      rethrow;
    }
  }

  Future<String> classifyIntent(String prompt) async {
    print('[GeminiService] classifyIntent called with prompt: $prompt');
    final requestBody = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': "Classify the following user prompt as one of: [code_edit, repo_question, general]. Only return the label. Prompt: '$prompt'"}
          ]
        }
      ]
    };

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));
      print('[GeminiService] classifyIntent response status:  [32m${response.statusCode} [0m');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates']?[0]?['content']?['parts']?[0]?['text']?.trim() ?? 'general';
      } else {
        print('[GeminiService] classifyIntent error: ${response.body}');
        throw Exception('Failed to classify intent:  [31m${response.body} [0m');
      }
    } catch (e) {
      print('[GeminiService] classifyIntent exception: $e');
      rethrow;
    }
  }

  String _composePrompt(String prompt, List<Map<String, String>> files) {
    final buffer = StringBuffer();
    buffer.writeln('User prompt: $prompt\n');
    if (files.isNotEmpty) {
      buffer.writeln('Relevant files:');
      for (final file in files) {
        buffer.writeln('File: ${file['name']}');
        buffer.writeln(file['content']);
        buffer.writeln('---');
      }
    }
    buffer.writeln('Suggest minimal, high-quality code changes. Output only the code diff and a short summary.');
    return buffer.toString();
  }
} 