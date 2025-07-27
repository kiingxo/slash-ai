import 'dart:io';
import 'dart:math'; // Import dart:math for sqrt
import 'package:path/path.dart' as p;
import 'package:slash_flutter/services/code_database.dart'; // Import the database service/ Import the embedding service
import 'package:slash_flutter/services/openai_embedding_service.dart';
import 'package:slash_flutter/services/secure_storage_service.dart'; // Import the secure storage service

class FileProcessingService {
  // List of file extensions to include
  static const List<String> allowedExtensions = [
    '.dart',
    '.js',
    '.py',
    '.md',
    '.json',
    '.yaml',
    '.xml',
    '.html',
    '.css',
    '.txt',
  ];

  // List of directory names to ignore
  static const List<String> ignoredDirectories = [
    '.git',
    'node_modules',
    'build',
    'cd', // Common directory for CI/CD
    '.dart_tool',
    '.idea', // IntelliJ/Android Studio project files
    'ios', // Usually contains build artifacts and dependencies
    'android', // Usually contains build artifacts and dependencies
  ];

  /// Recursively gets all files in a directory,
  /// filtering by allowed extensions and ignoring specified directories.
  static Future<List<File>> getCodeFiles(String directoryPath) async {
    final Directory dir = Directory(directoryPath);
    final List<File> codeFiles = [];

    if (!await dir.exists()) {
      print('Directory not found: $directoryPath');
      return [];
    }

    await for (final FileSystemEntity entity in dir.list(recursive: true)) {
      if (entity is File) {
        final filePath = entity.path;
        final fileName = p.basename(filePath);
        final fileExtension = p.extension(fileName);

        // Check if the file is in an ignored directory
        final bool isIgnoredDir = ignoredDirectories.any(
          (ignoredDir) => filePath.contains('/$ignoredDir/'),
        );

        // Check if the file has an allowed extension
        final bool isAllowedExtension =
            allowedExtensions.contains(fileExtension);

        if (!isIgnoredDir && isAllowedExtension) {
          codeFiles.add(entity);
        }
      }
    }
    return codeFiles;
  }

  /// Reads the content of a given file.
  static Future<String> readFileContent(File file) async {
    try {
      return await file.readAsString();
    } catch (e) {
      print('Error reading file ${file.path}: $e');
      return ''; // Return empty string or handle error as needed
    }
  }

  /// Splits file content into fixed-size overlapping chunks.
  static List<String> chunkCode(String code, int chunkSize, int overlap) {
    final chunks = <String>[];
    int i = 0;
    while (i < code.length) {
      final end = i + chunkSize;
      final chunk = code.substring(i, end < code.length ? end : code.length);
      chunks.add(chunk);
      i += chunkSize - overlap;
    }
    return chunks;
  }

  /// Processes a directory, reads files, chunks content,
  /// generates embeddings, and stores them in the database.
  static Future<void> processDirectoryAndStoreEmbeddings(String directoryPath) async {
    final files = await getCodeFiles(directoryPath);
    final db = CodeDatabase();
    final storage = SecureStorageService();
    final openAIApiKey = await storage.getApiKey('openai_api_key');

    if (openAIApiKey == null) {
      print('OpenAI API key not found.');
      return;
    }

    final embeddingService = OpenAIEmbeddingService(openAIApiKey);

    // Clear existing chunks for this directory if needed
    // await db.deleteAllChunks(); // Consider if you need to clear the database

    for (final file in files) {
      final content = await readFileContent(file);
      if (content.isNotEmpty) {
        final chunks = chunkCode(content, 500, 50); // Adjust chunk size and overlap as needed

        for (int i = 0; i < chunks.length; i++) {
          final chunk = chunks[i];
          try {
            final embedding = await embeddingService.generateEmbedding(chunk);
            final codeChunk = CodeChunk(
              id: '${file.path}::$i', // Unique ID for each chunk
              fileName: p.basename(file.path),
              chunkText: chunk,
              embedding: embedding,
            );
            await db.insertChunk(codeChunk);
          } catch (e) {
            print('Error processing chunk ${file.path}::$i: $e');
          }
        }
      }
    }
    print('Finished processing directory: $directoryPath');
  }

  /// Calculates the cosine similarity between two vectors.
  static double cosineSimilarity(List<double> vec1, List<double> vec2) {
    if (vec1.length != vec2.length || vec1.isEmpty) {
      return 0.0;
    }

    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < vec1.length; i++) {
      dotProduct += vec1[i] * vec2[i];
      norm1 += vec1[i] * vec1[i];
      norm2 += vec2[i] * vec2[i];
    }

    if (norm1 == 0.0 || norm2 == 0.0) {
      return 0.0;
    }

    return dotProduct / (sqrt(norm1) * sqrt(norm2));
  }

  /// Performs vector similarity search on stored code chunks.
  static Future<List<CodeChunk>> searchCodeChunks(String query, int k) async {
    final db = CodeDatabase();
    final allChunks = await db.getAllChunks();

    if (allChunks.isEmpty) {
      print('No code chunks found in the database.');
      return [];
    }

    final storage = SecureStorageService();
    final openAIApiKey = await storage.getApiKey('openai_api_key');

    if (openAIApiKey == null) {
      print('OpenAI API key not found.');
      return [];
    }

    final embeddingService = OpenAIEmbeddingService(openAIApiKey);

    try {
      final queryEmbedding = await embeddingService.generateEmbedding(query);

      final List<Map<CodeChunk, double>> rankedChunks = [];

      for (final chunk in allChunks) {
        final similarity = cosineSimilarity(queryEmbedding, chunk.embedding);
        rankedChunks.add({chunk: similarity});
      }

      // Sort by similarity in descending order
      rankedChunks.sort((a, b) => b.values.first.compareTo(a.values.first));

      // Return top k chunks
      return rankedChunks.take(k).map((e) => e.keys.first).toList();
    } catch (e) {
      print('Error during code chunk search: $e');
      return [];
    }
  }
}