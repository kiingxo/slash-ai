import 'dart:async';

/// LLMService defines a common interface for Large Language Model providers.
/// Implementations should be pure transport/serialization layers without UI logic.
///
/// Methods:
/// - getCodeSuggestion: Given a prompt and optional relevant files, return model output
///   that suggests code changes (diff or textual instructions).
/// - classifyIntent: Heuristic classification of user prompt for routing.
///
abstract class LLMService {
  /// Generates code suggestions for a given [prompt].
  /// [files] is a list of maps with keys:
  ///   - 'name': String - file name or path
  ///   - 'content': String - file content
  Future<String> getCodeSuggestion({
    required String prompt,
    required List<Map<String, String>> files,
  });

  /// Classifies a free-form [prompt] into a small set of labels used to route UX flows.
  /// Implementations should be deterministic/low-temperature and return one of:
  ///   - 'code_edit'
  ///   - 'repo_question'
  ///   - 'general'
  Future<String> classifyIntent(String prompt);
}
