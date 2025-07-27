import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenAIEmbeddingService {
  final String apiKey;
  final String baseUrl = 'https://api.openai.com/v1/embeddings';

  OpenAIEmbeddingService(this.apiKey);

  Future<List<double>> generateEmbedding(String text) async {
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'text-embedding-ada-002', // Or another suitable embedding model
          'input': text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && data['data'].isNotEmpty) {
          // Assuming the response structure has data[0]['embedding']
          return List<double>.from(data['data'][0]['embedding']);
        } else {
          throw Exception('Invalid embedding response from OpenAI');
        }
      } else {
        throw Exception(
          'Failed to generate embedding: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error generating embedding: $e');
      rethrow;
    }
  }
}