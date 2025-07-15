import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  final String apiKey;
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent';

  GeminiService(this.apiKey);

  Future<String> getCodeSuggestion({required String prompt, required List<Map<String, String>> files}) async {
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

    final response = await http.post(
      Uri.parse('$_baseUrl?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
    } else {
      throw Exception('Failed to get suggestion: ${response.body}');
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