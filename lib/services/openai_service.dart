import 'dart:convert';
import 'package:http/http.dart' as http;

/// Unified chat service for OpenAI-style and OpenRouter endpoints.
/// - When useOpenRouter = true, it targets OpenRouter's /chat/completions with
///   "Authorization: Bearer <OPENROUTER_API_KEY>" and supports arbitrary model ids.
/// - When useOpenRouter = false, it targets OpenAI's /chat/completions.
class OpenAIService {
  final String apiKey;
  final String model;
  final bool useOpenRouter;
  final String baseUrl;

  // Defaults maintain backward compatibility with OpenAI.
  OpenAIService(
    this.apiKey, {
    this.model = 'gpt-3.5-turbo',
    this.useOpenRouter = false,
    String? baseUrl,
  }) : baseUrl = baseUrl ??
            (useOpenRouter
                ? 'https://openrouter.ai/api/v1/chat/completions'
                : 'https://api.openai.com/v1/chat/completions');

  Future<String> getCodeSuggestion({
    required String prompt,
    required List<Map<String, String>> files,
  }) async {
    final systemPrompt = files.isNotEmpty
        ? 'You are an expert code assistant. User prompt: $prompt\nRelevant files:\n${files.map((f) => 'File: ${f['name']}\n${f['content']}\n---').join('\n')}\nSuggest minimal, high-quality code changes. Output only the code diff and a short summary.'
        : 'You are an expert code assistant. User prompt: $prompt';
    
    final requestBody = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
      ],
      'max_tokens': 4096, // Increased from 1024 to allow for complete code generation
      'temperature': 0.2,
    };
    
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
      if (useOpenRouter) 'HTTP-Referer': 'https://slash', // optional for OpenRouter analytics
      if (useOpenRouter) 'X-Title': 'Slash',               // optional
    };

    final response = await http
        .post(
          Uri.parse(baseUrl),
          headers: headers,
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 30));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices']?[0]?['message']?['content']?.trim() ?? '';
    } else {
      throw Exception('${useOpenRouter ? 'OpenRouter' : 'OpenAI'} error: ${response.body}');
    }
  }

  Future<String> classifyIntent(String prompt) async {
    final systemPrompt = "You are an expert code assistant. Classify the following user prompt as one of: [code_edit, repo_question, general].\n\n- code_edit: The user wants to change, improve, refactor, add, or fix code, or requests a code-related action.\n- repo_question: The user is asking about the repository, its purpose, files, or structure, but not requesting a code change.\n- general: The user is making small talk, greetings, or asking about you as an agent.\n\nOnly return the label.\nPrompt: '$prompt'";
    
    final requestBody = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
      ],
      'max_tokens': 16,
      'temperature': 0.0,
    };
    
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
      if (useOpenRouter) 'HTTP-Referer': 'https://slash',
      if (useOpenRouter) 'X-Title': 'Slash',
    };

    final response = await http
        .post(
          Uri.parse(baseUrl),
          headers: headers,
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 30));
    
    print('[OpenAIService] classifyIntent raw response: ${response.body}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices']?[0]?['message']?['content']?.trim() ?? 'general';
    } else {
      throw Exception('${useOpenRouter ? 'OpenRouter' : 'OpenAI'} error: ${response.body}');
    }
  }
}
