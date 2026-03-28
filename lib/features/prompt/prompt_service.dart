import 'dart:convert';

import 'package:slash_flutter/features/prompt/prompts.dart';

import '../../services/app_config.dart';
import '../../services/cache_storage_service.dart';
import '../../services/github_service.dart';
import '../../services/openai_service.dart';
import '../../services/secure_storage_service.dart';
import '../file_browser/file_browser_controller.dart';

typedef FileContent = Map<String, String>;
typedef FileContents = List<FileContent>;
typedef RepoInfo = Map<String, dynamic>;
typedef AIService = dynamic;

const String _repoDigestFileName = '.slash/repo-map.txt';
const int _maxRepoIndexPaths = 5000;
const int _repoDigestCharBudget = 10000;

class PromptContextResult {
  final FileContents files;
  final List<String> toolSummary;
  final bool autoDiscovered;

  const PromptContextResult({
    required this.files,
    required this.toolSummary,
    required this.autoDiscovered,
  });
}

class CodeEditPackage {
  final String summary;
  final String content;

  const CodeEditPackage({required this.summary, required this.content});
}

class RepoIndexSnapshot {
  final String owner;
  final String repo;
  final String branch;
  final String commitSha;
  final List<String> paths;

  const RepoIndexSnapshot({
    required this.owner,
    required this.repo,
    required this.branch,
    required this.commitSha,
    required this.paths,
  });

  Map<String, dynamic> toJson() => {
    'owner': owner,
    'repo': repo,
    'branch': branch,
    'commitSha': commitSha,
    'paths': paths,
  };

  factory RepoIndexSnapshot.fromJson(Map<String, dynamic> json) {
    return RepoIndexSnapshot(
      owner: (json['owner'] ?? '').toString(),
      repo: (json['repo'] ?? '').toString(),
      branch: (json['branch'] ?? '').toString(),
      commitSha: (json['commitSha'] ?? '').toString(),
      paths:
          (json['paths'] as List<dynamic>? ?? const <dynamic>[])
              .map((entry) => entry.toString())
              .where((path) => path.isNotEmpty)
              .toList(),
    );
  }
}

class RepoIndexLookupResult {
  final RepoIndexSnapshot snapshot;
  final String sourceLabel;

  const RepoIndexLookupResult({
    required this.snapshot,
    required this.sourceLabel,
  });
}

class PromptService {
  static final Map<String, RepoIndexSnapshot> _repoIndexMemoryCache = {};

  static Future<FileContents> fetchFiles({
    required String owner,
    required String repo,
    required String accessToken,
    String? branch,
  }) async {
    final github = GitHubService(accessToken);
    final entries = await github.fetchDirectory(
      owner: owner,
      repo: repo,
      branch: branch,
    );

    final fileEntries =
        entries.where((entry) {
          return (entry['type'] ?? '').toString() == 'file' &&
              (entry['path'] ?? '').toString().isNotEmpty;
        }).toList();

    final files = await Future.wait(
      fileEntries.map((entry) async {
        final path = (entry['path'] ?? '').toString();
        final file = await github.fetchFileContent(
          owner: owner,
          repo: repo,
          path: path,
          branch: branch,
        );
        return <String, String>{
          'name': file.path,
          'content': file.content,
          'sha': file.sha,
        };
      }),
    );

    return files;
  }

  static AIService createAIService({
    required String model,
    String? openAIApiKey,
    String? openAIModel,
    String? openRouterApiKey,
    String? openRouterModel,
  }) {
    if (model.toLowerCase() == 'openrouter') {
      if (openRouterApiKey == null || openRouterApiKey.isEmpty) {
        throw Exception('OpenRouter API key is required');
      }

      return OpenAIService(
        openRouterApiKey,
        model:
            (openRouterModel?.trim().isNotEmpty == true)
                ? openRouterModel!.trim()
                : AppConfig.defaultOpenRouterModel,
        useOpenRouter: true,
      );
    }

    if (openAIApiKey == null || openAIApiKey.isEmpty) {
      throw Exception('OpenAI API key is required');
    }

    return OpenAIService(
      openAIApiKey,
      model:
          (openAIModel?.trim().isNotEmpty == true)
              ? openAIModel!.trim()
              : AppConfig.defaultOpenAIModel,
    );
  }

  static Future<PromptContextResult> resolveContext({
    required String prompt,
    required RepoInfo? repo,
    required String? branch,
    required List<FileItem> selectedFiles,
    int maxFiles = 3,
    bool allowAutoDiscovery = true,
    bool includeRepoDigest = true,
    bool preferCachedRepoIndex = false,
  }) async {
    final filteredSelections =
        selectedFiles
            .where((file) => file.type == 'file' && file.path.isNotEmpty)
            .toList();

    if (repo == null) {
      return PromptContextResult(
        files: _contextFilesFromSelectedFiles(
          filteredSelections.take(maxFiles),
        ),
        toolSummary:
            filteredSelections
                .take(maxFiles)
                .map((file) => 'read_file:${file.path}')
                .toList(),
        autoDiscovered: false,
      );
    }

    final storage = SecureStorageService();
    final token = await storage.getGitHubAccessToken();
    if (token == null || token.isEmpty) {
      return PromptContextResult(
        files: _contextFilesFromSelectedFiles(
          filteredSelections.take(maxFiles),
        ),
        toolSummary:
            filteredSelections
                .take(maxFiles)
                .map((file) => 'read_file:${file.path}')
                .toList(),
        autoDiscovered: false,
      );
    }

    final owner = (repo['owner']?['login'] ?? '').toString();
    final repoName = (repo['name'] ?? '').toString();
    if (owner.isEmpty || repoName.isEmpty) {
      return PromptContextResult(
        files: _contextFilesFromSelectedFiles(
          filteredSelections.take(maxFiles),
        ),
        toolSummary:
            filteredSelections
                .take(maxFiles)
                .map((file) => 'read_file:${file.path}')
                .toList(),
        autoDiscovered: false,
      );
    }

    final github = GitHubService(token);
    final selectedBranch =
        (branch?.trim().isNotEmpty == true)
            ? branch!.trim()
            : (repo['default_branch'] ?? 'main').toString();
    final toolSummary = <String>[];
    final contextFiles = <Map<String, String>>[];
    final includedPaths = <String>{};

    final selectedContextFiles = await _materializeSelectedFiles(
      selectedFiles: filteredSelections.take(maxFiles).toList(),
      github: github,
      owner: owner,
      repo: repoName,
      branch: selectedBranch,
    );
    for (final file in selectedContextFiles) {
      final path = file['name'];
      if (path == null || path.isEmpty || includedPaths.contains(path)) {
        continue;
      }
      contextFiles.add(file);
      includedPaths.add(path);
      toolSummary.add('read_file:$path');
    }

    RepoIndexLookupResult? repoIndex;
    if (allowAutoDiscovery || includeRepoDigest) {
      repoIndex = await _loadRepoIndex(
        github: github,
        owner: owner,
        repo: repoName,
        branch: selectedBranch,
        preferCached: preferCachedRepoIndex,
      );
      toolSummary.insert(
        0,
        'repo_index:${repoIndex.sourceLabel}:${_shortSha(repoIndex.snapshot.commitSha)}',
      );
    }

    final remainingSlots = maxFiles - contextFiles.length;
    final rankedPaths =
        allowAutoDiscovery && repoIndex != null && remainingSlots > 0
            ? discoverRelevantFiles(
              indexedPaths: repoIndex.snapshot.paths,
              prompt: prompt,
              anchorPaths: includedPaths.toList(),
              excludePaths: includedPaths,
              limit: remainingSlots,
            )
            : const <String>[];

    if (rankedPaths.isNotEmpty) {
      final fetchedFiles = await Future.wait(
        rankedPaths.map((path) async {
          final file = await github.fetchFileContent(
            owner: owner,
            repo: repoName,
            path: path,
            branch: selectedBranch,
          );
          return <String, String>{
            'name': file.path,
            'content': file.content,
            'sha': file.sha,
          };
        }),
      );

      for (final file in fetchedFiles) {
        final path = file['name'];
        if (path == null || path.isEmpty || includedPaths.contains(path)) {
          continue;
        }
        contextFiles.add(file);
        includedPaths.add(path);
        toolSummary.add('auto_context:$path');
      }
    }

    if (includeRepoDigest && repoIndex != null) {
      final repoDigest = _buildRepoDigest(
        repo: repo,
        branch: selectedBranch,
        prompt: prompt,
        snapshot: repoIndex.snapshot,
        selectedPaths:
            selectedContextFiles
                .map((file) => file['name'])
                .whereType<String>()
                .toList(),
        focusedPaths:
            contextFiles
                .map((file) => file['name'])
                .whereType<String>()
                .where((path) => path != _repoDigestFileName)
                .toList(),
      );
      if (repoDigest.isNotEmpty) {
        contextFiles.add({'name': _repoDigestFileName, 'content': repoDigest});
        toolSummary.add('repo_map:${repoIndex.snapshot.paths.length}_paths');
      }
    }

    return PromptContextResult(
      files: contextFiles,
      toolSummary: toolSummary,
      autoDiscovered: rankedPaths.isNotEmpty,
    );
  }

  static Future<String> determineIntent({
    required AIService aiService,
    required String prompt,
    bool hasFileContext = false,
    bool preferCodeEdit = false,
  }) async {
    final local = _inferIntentLocally(
      prompt,
      hasFileContext: hasFileContext,
      preferCodeEdit: preferCodeEdit,
    );
    if (local != null) {
      return local;
    }
    return aiService.classifyIntent(prompt);
  }

  static List<String> discoverRelevantFiles({
    required List<String> indexedPaths,
    required String prompt,
    List<String> anchorPaths = const [],
    Set<String> excludePaths = const <String>{},
    int limit = 3,
  }) {
    if (indexedPaths.isEmpty || limit <= 0) {
      return const <String>[];
    }

    final keywords = _extractKeywords(prompt);
    final anchorSet = anchorPaths.toSet();
    final candidates =
        indexedPaths.where((path) => !excludePaths.contains(path)).toList();

    candidates.sort((left, right) {
      final scoreDelta = _scorePath(
        right,
        keywords,
        anchorPaths: anchorSet,
      ).compareTo(_scorePath(left, keywords, anchorPaths: anchorSet));
      if (scoreDelta != 0) {
        return scoreDelta;
      }
      return left.compareTo(right);
    });

    final selected = <String>[];
    for (final path in candidates) {
      final score = _scorePath(path, keywords, anchorPaths: anchorSet);
      if (score <= 0 && selected.isNotEmpty) {
        continue;
      }
      selected.add(path);
      if (selected.length >= limit) {
        break;
      }
    }

    return selected;
  }

  static Future<String> processCodeEditIntent({
    required AIService aiService,
    required String prompt,
    required FileContents files,
    List<String> toolSummary = const [],
  }) async {
    final planPrompt =
        StringBuffer()
          ..writeln(systemPrompt())
          ..writeln()
          ..writeln('Mode: plan')
          ..writeln('User request: "$prompt"')
          ..writeln(
            'Write a crisp 1-2 sentence engineering plan. Mention the target file if it is obvious. Do not include headings or markdown.',
          );

    if (toolSummary.isNotEmpty) {
      planPrompt.writeln('Context tools used: ${toolSummary.join(', ')}');
    }

    return (await aiService.getCodeSuggestion(
      prompt: planPrompt.toString(),
      files: files,
    )).trim();
  }

  static Future<String> processCodeContent({
    required AIService aiService,
    required String prompt,
    required FileContents files,
    List<String> toolSummary = const [],
  }) async {
    final primaryFile = _primaryContextFile(files);
    final oldContent = primaryFile?['content'] ?? '';
    final fileName = primaryFile?['name'] ?? 'unknown';

    final codePrompt =
        StringBuffer()
          ..writeln(systemPrompt())
          ..writeln()
          ..writeln('Mode: rewrite')
          ..writeln('Target file: $fileName')
          ..writeln('User request: $prompt')
          ..writeln('Return only the full updated file contents.')
          ..writeln('Do not wrap the answer in markdown fences.')
          ..writeln('Do not explain the change.')
          ..writeln('Preserve existing behavior unless the request changes it.')
          ..writeln('Original file:')
          ..writeln(oldContent);

    if (toolSummary.isNotEmpty) {
      codePrompt.writeln('Context tools used: ${toolSummary.join(', ')}');
    }

    final newContent = await aiService.getCodeSuggestion(
      prompt: codePrompt.toString(),
      files: _editSupportFiles(files),
    );

    return stripCodeFences(newContent);
  }

  static Future<CodeEditPackage> processCodeEditPackage({
    required AIService aiService,
    required String prompt,
    required FileContents files,
    List<String> toolSummary = const [],
  }) async {
    final primaryFile = _primaryContextFile(files);
    final oldContent = primaryFile?['content'] ?? '';
    final fileName = primaryFile?['name'] ?? 'unknown';

    final packagePrompt =
        StringBuffer()
          ..writeln(systemPrompt())
          ..writeln()
          ..writeln('Mode: rewrite_with_summary')
          ..writeln('Target file: $fileName')
          ..writeln('User request: $prompt')
          ..writeln('Return exactly this format:')
          ..writeln('<slash_summary>')
          ..writeln('One or two concise engineering sentences.')
          ..writeln('</slash_summary>')
          ..writeln('<slash_file>')
          ..writeln('The complete updated file contents only.')
          ..writeln('</slash_file>')
          ..writeln('Rules:')
          ..writeln('- Do not use markdown fences.')
          ..writeln('- Do not add any text before or after these tags.')
          ..writeln('- Keep slash_summary short and practical.')
          ..writeln(
            '- Preserve existing behavior unless the request changes it.',
          )
          ..writeln('Original target file:')
          ..writeln(oldContent);

    if (toolSummary.isNotEmpty) {
      packagePrompt.writeln('Context tools used: ${toolSummary.join(', ')}');
    }

    final rawResponse = await aiService.getCodeSuggestion(
      prompt: packagePrompt.toString(),
      files: _editSupportFiles(files),
    );
    final parsed = _parseCodeEditPackage(
      rawResponse,
      fallbackSummary: _fallbackEditSummary(fileName, prompt),
    );
    if (parsed != null && parsed.content.trim().isNotEmpty) {
      return parsed;
    }

    final summary =
        parsed?.summary.trim().isNotEmpty == true
            ? parsed!.summary.trim()
            : await processCodeEditIntent(
              aiService: aiService,
              prompt: prompt,
              files: files,
              toolSummary: toolSummary,
            );
    final content = await processCodeContent(
      aiService: aiService,
      prompt: prompt,
      files: files,
      toolSummary: toolSummary,
    );

    return CodeEditPackage(summary: summary, content: content);
  }

  static Future<String> processRepoQuestion({
    required AIService aiService,
    required String prompt,
    required RepoInfo repo,
    required FileContents contextFiles,
    List<String> toolSummary = const [],
  }) async {
    final repoInfo =
        'Repository: ${repo['full_name'] ?? repo['name']}\n'
        'Description: ${repo['description'] ?? 'No description'}\n'
        'Default branch: ${repo['default_branch'] ?? 'main'}';

    final questionPrompt =
        StringBuffer()
          ..writeln(systemPrompt())
          ..writeln()
          ..writeln(repoInfo)
          ..writeln('User question: $prompt')
          ..writeln(
            'Answer clearly and directly using the repository context.',
          );

    if (toolSummary.isNotEmpty) {
      questionPrompt.writeln('Context tools used: ${toolSummary.join(', ')}');
    }

    return aiService.getCodeSuggestion(
      prompt: questionPrompt.toString(),
      files: contextFiles,
    );
  }

  static String systemPrompt() => systemPromptText;

  static Future<String> processGeneralIntent({
    required AIService aiService,
    required String prompt,
    required FileContents contextFiles,
    List<String> toolSummary = const [],
  }) async {
    final userPrompt =
        StringBuffer()
          ..writeln(systemPrompt())
          ..writeln()
          ..writeln('User: $prompt');

    if (toolSummary.isNotEmpty) {
      userPrompt.writeln('Context tools used: ${toolSummary.join(', ')}');
    }

    return aiService.getCodeSuggestion(
      prompt: userPrompt.toString(),
      files: contextFiles,
    );
  }

  static Future<String> createPullRequest({
    required String owner,
    required String repo,
    required String fileName,
    required String newContent,
    required String prompt,
    required String summary,
    String? selectedBranch,
  }) async {
    final storage = SecureStorageService();
    final accessToken = await storage.getGitHubAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('GitHub authentication is required');
    }

    final github = GitHubService(accessToken);
    final baseBranch = selectedBranch ?? 'main';
    final newBranch = 'slash/${DateTime.now().millisecondsSinceEpoch}';

    await github.createBranch(
      owner: owner,
      repo: repo,
      newBranch: newBranch,
      baseBranch: baseBranch,
    );

    await github.commitFile(
      owner: owner,
      repo: repo,
      branch: newBranch,
      path: fileName,
      content: newContent,
      message: '/slash: $prompt',
    );

    return github.openPullRequest(
      owner: owner,
      repo: repo,
      head: newBranch,
      base: baseBranch,
      title: '/slash: $prompt',
      body: summary,
    );
  }

  static Future<List<String>> fetchBranches({
    required String owner,
    required String repo,
  }) async {
    final storage = SecureStorageService();
    final accessToken = await storage.getGitHubAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('GitHub authentication is required');
    }

    final github = GitHubService(accessToken);
    return github.fetchBranches(owner: owner, repo: repo);
  }

  static List<FileItem> searchContextFiles({
    required List<FileItem> files,
    required String query,
  }) {
    final lowerQuery = query.toLowerCase();
    return files.where((file) {
      return file.name.toLowerCase().contains(lowerQuery) ||
          file.path.toLowerCase().contains(lowerQuery) ||
          (file.content?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  static Future<List<Map<String, String>>> _materializeSelectedFiles({
    required List<FileItem> selectedFiles,
    required GitHubService github,
    required String owner,
    required String repo,
    required String branch,
  }) async {
    final seen = <String>{};
    final futures = selectedFiles
        .where((file) {
          if (file.path.isEmpty || seen.contains(file.path)) {
            return false;
          }
          seen.add(file.path);
          return true;
        })
        .map((selectedFile) async {
          if (selectedFile.content != null) {
            return <String, String>{
              'name': selectedFile.path,
              'content': selectedFile.content ?? '',
              if ((selectedFile.sha ?? '').isNotEmpty) 'sha': selectedFile.sha!,
            };
          }

          final file = await github.fetchFileContent(
            owner: owner,
            repo: repo,
            path: selectedFile.path,
            branch: branch,
          );
          return <String, String>{
            'name': file.path,
            'content': file.content,
            'sha': file.sha,
          };
        });

    return Future.wait(futures);
  }

  static FileContents _contextFilesFromSelectedFiles(Iterable<FileItem> files) {
    final seen = <String>{};
    return files
        .where((file) {
          if (file.path.isEmpty || seen.contains(file.path)) {
            return false;
          }
          seen.add(file.path);
          return true;
        })
        .map((file) {
          return <String, String>{
            'name': file.path,
            'content': file.content ?? '',
            if ((file.sha ?? '').isNotEmpty) 'sha': file.sha!,
          };
        })
        .toList();
  }

  static Future<RepoIndexLookupResult> _loadRepoIndex({
    required GitHubService github,
    required String owner,
    required String repo,
    required String branch,
    bool preferCached = false,
  }) async {
    final cacheKey = _repoIndexCacheKey(
      owner: owner,
      repo: repo,
      branch: branch,
    );
    final cached =
        _repoIndexMemoryCache[cacheKey] ?? _readCachedRepoIndex(cacheKey);

    if (preferCached && cached != null && cached.paths.isNotEmpty) {
      _repoIndexMemoryCache[cacheKey] = cached;
      return RepoIndexLookupResult(snapshot: cached, sourceLabel: 'fast_cache');
    }

    String commitSha;
    try {
      commitSha = await github.fetchBranchCommitSha(
        owner: owner,
        repo: repo,
        branch: branch,
      );
    } catch (_) {
      if (cached != null) {
        _repoIndexMemoryCache[cacheKey] = cached;
        return RepoIndexLookupResult(
          snapshot: cached,
          sourceLabel: 'stale_cache',
        );
      }
      rethrow;
    }

    if (cached != null &&
        cached.commitSha == commitSha &&
        cached.paths.isNotEmpty) {
      _repoIndexMemoryCache[cacheKey] = cached;
      return RepoIndexLookupResult(snapshot: cached, sourceLabel: 'cache_hit');
    }

    final snapshot = await github.fetchRepositoryTreeSnapshot(
      owner: owner,
      repo: repo,
      branch: branch,
      commitSha: commitSha,
    );

    final usefulPaths =
        snapshot.items
            .where((entry) => entry.type == 'blob')
            .map((entry) => entry.path)
            .where(_isUsefulRepositoryFile)
            .take(_maxRepoIndexPaths)
            .toList()
          ..sort();

    final resolved = RepoIndexSnapshot(
      owner: owner,
      repo: repo,
      branch: branch,
      commitSha: snapshot.commitSha,
      paths: usefulPaths,
    );

    _repoIndexMemoryCache[cacheKey] = resolved;
    await CacheStorage.save(cacheKey, jsonEncode(resolved.toJson()));

    return RepoIndexLookupResult(snapshot: resolved, sourceLabel: 'refreshed');
  }

  static RepoIndexSnapshot? _readCachedRepoIndex(String cacheKey) {
    final raw = CacheStorage.fetchString(cacheKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final snapshot = RepoIndexSnapshot.fromJson(decoded);
      if (snapshot.owner.isEmpty ||
          snapshot.repo.isEmpty ||
          snapshot.branch.isEmpty ||
          snapshot.commitSha.isEmpty ||
          snapshot.paths.isEmpty) {
        return null;
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  static String _repoIndexCacheKey({
    required String owner,
    required String repo,
    required String branch,
  }) {
    return 'repo_index::$owner/$repo@$branch';
  }

  static String _buildRepoDigest({
    required RepoInfo repo,
    required String branch,
    required String prompt,
    required RepoIndexSnapshot snapshot,
    required List<String> selectedPaths,
    required List<String> focusedPaths,
  }) {
    final buffer =
        StringBuffer()
          ..writeln('Repo map')
          ..writeln('Repository: ${repo['full_name'] ?? repo['name']}')
          ..writeln('Branch: $branch')
          ..writeln('Indexed commit: ${snapshot.commitSha}')
          ..writeln('Indexed useful files: ${snapshot.paths.length}');

    final keywords = _extractKeywords(prompt);
    if (keywords.isNotEmpty) {
      _appendSection(
        buffer,
        title: 'Prompt keywords',
        lines: keywords.take(10).map((keyword) => '- $keyword'),
      );
    }

    if (selectedPaths.isNotEmpty) {
      _appendSection(
        buffer,
        title: 'Pinned files',
        lines: selectedPaths.map((path) => '- $path'),
      );
    }

    final topDirectories = _topDirectoryCounts(snapshot.paths);
    if (topDirectories.isNotEmpty) {
      _appendSection(
        buffer,
        title: 'Top areas',
        lines: topDirectories
            .take(10)
            .map((entry) => '- ${entry.key}: ${entry.value} files'),
      );
    }

    final notablePaths = _buildNotablePathList(
      paths: snapshot.paths,
      keywords: keywords,
      selectedPaths: selectedPaths,
      focusedPaths: focusedPaths,
    );
    if (notablePaths.isNotEmpty) {
      _appendSection(
        buffer,
        title: 'High-signal files',
        lines: notablePaths.take(18).map((path) => '- $path'),
      );
    }

    if (!_appendLine(buffer, 'Path index:', budget: _repoDigestCharBudget)) {
      return buffer.toString().trim();
    }

    var emitted = 0;
    for (final path in snapshot.paths) {
      final line = '- $path';
      if (!_appendLine(buffer, line, budget: _repoDigestCharBudget)) {
        final remaining = snapshot.paths.length - emitted;
        _appendLine(
          buffer,
          '... truncated $remaining additional paths',
          budget: _repoDigestCharBudget,
        );
        break;
      }
      emitted++;
    }

    return buffer.toString().trim();
  }

  static List<MapEntry<String, int>> _topDirectoryCounts(List<String> paths) {
    final counts = <String, int>{};
    for (final path in paths) {
      final topLevel = path.contains('/') ? path.split('/').first : '.';
      counts[topLevel] = (counts[topLevel] ?? 0) + 1;
    }

    final entries =
        counts.entries.toList()..sort((left, right) {
          final countDelta = right.value.compareTo(left.value);
          if (countDelta != 0) {
            return countDelta;
          }
          return left.key.compareTo(right.key);
        });
    return entries;
  }

  static List<String> _buildNotablePathList({
    required List<String> paths,
    required List<String> keywords,
    required List<String> selectedPaths,
    required List<String> focusedPaths,
  }) {
    final ordered = <String>[];
    final seen = <String>{};

    void addPath(String path) {
      if (path.isEmpty || seen.contains(path)) {
        return;
      }
      seen.add(path);
      ordered.add(path);
    }

    for (final path in selectedPaths) {
      addPath(path);
    }
    for (final path in focusedPaths) {
      addPath(path);
    }

    final ranked = List<String>.from(paths)..sort((left, right) {
      final scoreDelta = _scorePath(
        right,
        keywords,
        anchorPaths: selectedPaths.toSet(),
      ).compareTo(
        _scorePath(left, keywords, anchorPaths: selectedPaths.toSet()),
      );
      if (scoreDelta != 0) {
        return scoreDelta;
      }
      return left.compareTo(right);
    });

    for (final path in ranked.take(24)) {
      addPath(path);
    }

    return ordered;
  }

  static bool _appendLine(
    StringBuffer buffer,
    String line, {
    required int budget,
  }) {
    if (buffer.length + line.length + 1 > budget) {
      return false;
    }
    buffer.writeln(line);
    return true;
  }

  static void _appendSection(
    StringBuffer buffer, {
    required String title,
    required Iterable<String> lines,
  }) {
    if (!_appendLine(buffer, '$title:', budget: _repoDigestCharBudget)) {
      return;
    }
    for (final line in lines) {
      if (!_appendLine(buffer, line, budget: _repoDigestCharBudget)) {
        return;
      }
    }
  }

  static Map<String, String>? _primaryContextFile(FileContents files) {
    for (final file in files) {
      final name = file['name'] ?? '';
      if (name != _repoDigestFileName) {
        return file;
      }
    }
    return files.isNotEmpty ? files.first : null;
  }

  static FileContents _editSupportFiles(
    FileContents files, {
    int maxSupportFiles = 2,
  }) {
    final primary = _primaryContextFile(files);
    final selected = <Map<String, String>>[];
    var supportCount = 0;

    for (final file in files) {
      final name = file['name'] ?? '';
      if (name.isEmpty || file == primary) {
        continue;
      }
      if (name == _repoDigestFileName) {
        selected.add({
          'name': name,
          'content': _trimContextContent(file['content'] ?? '', maxChars: 2500),
        });
        continue;
      }
      if (supportCount >= maxSupportFiles) {
        continue;
      }
      selected.add({
        'name': name,
        'content': _trimContextContent(file['content'] ?? '', maxChars: 4000),
        if ((file['sha'] ?? '').isNotEmpty) 'sha': file['sha']!,
      });
      supportCount++;
    }

    return selected;
  }

  static CodeEditPackage? _parseCodeEditPackage(
    String raw, {
    required String fallbackSummary,
  }) {
    final summary = _extractTaggedBlock(raw, 'slash_summary')?.trim();
    final fileContent = _extractTaggedBlock(raw, 'slash_file');
    if (fileContent != null && fileContent.trim().isNotEmpty) {
      return CodeEditPackage(
        summary:
            (summary?.isNotEmpty == true) ? summary! : fallbackSummary.trim(),
        content: stripCodeFences(fileContent.trim()),
      );
    }
    return null;
  }

  static String? _extractTaggedBlock(String raw, String tag) {
    final pattern = RegExp(
      '<$tag>\\s*([\\s\\S]*?)\\s*</$tag>',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(raw);
    return match?.group(1);
  }

  static String _fallbackEditSummary(String fileName, String prompt) {
    final cleanPrompt = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    final trimmedPrompt =
        cleanPrompt.length <= 96
            ? cleanPrompt
            : '${cleanPrompt.substring(0, 96).trim()}...';
    return 'Prepared an update for $fileName based on: $trimmedPrompt';
  }

  static String _trimContextContent(String content, {required int maxChars}) {
    if (content.length <= maxChars) {
      return content;
    }
    return '${content.substring(0, maxChars)}\n...<truncated>';
  }

  static String _shortSha(String sha) {
    if (sha.length <= 7) {
      return sha;
    }
    return sha.substring(0, 7);
  }

  static List<String> _extractKeywords(String prompt) {
    const stopWords = {
      'a',
      'an',
      'and',
      'app',
      'build',
      'change',
      'create',
      'feature',
      'file',
      'fix',
      'for',
      'from',
      'help',
      'in',
      'into',
      'make',
      'need',
      'page',
      'screen',
      'some',
      'that',
      'the',
      'this',
      'with',
    };

    final parts =
        prompt
            .toLowerCase()
            .split(RegExp(r'[^a-z0-9_./-]+'))
            .map((part) => part.trim())
            .where((part) => part.length >= 3 && !stopWords.contains(part))
            .toList();

    return parts.toSet().toList();
  }

  static String? _inferIntentLocally(
    String prompt, {
    required bool hasFileContext,
    required bool preferCodeEdit,
  }) {
    final normalized = prompt.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'general';
    }

    const repoQuestionStarters = {
      'what',
      'why',
      'how',
      'where',
      'which',
      'who',
      'when',
      'explain',
      'summarize',
      'review',
      'describe',
      'walk',
    };
    const editVerbs = {
      'add',
      'change',
      'clean',
      'convert',
      'edit',
      'fix',
      'implement',
      'improve',
      'optimize',
      'patch',
      'refactor',
      'remove',
      'rename',
      'replace',
      'rewrite',
      'update',
      'wire',
    };

    final words = normalized.split(RegExp(r'[^a-z0-9_./-]+'));
    final firstWord = words.firstWhere(
      (word) => word.isNotEmpty,
      orElse: () => '',
    );
    final looksQuestion =
        normalized.endsWith('?') ||
        repoQuestionStarters.contains(firstWord) ||
        normalized.startsWith('can you explain') ||
        normalized.startsWith('help me understand') ||
        normalized.startsWith('tell me') ||
        normalized.startsWith('show me');
    if (looksQuestion) {
      return hasFileContext ? 'repo_question' : 'general';
    }

    final hasEditVerb = words.any(editVerbs.contains);
    if (hasEditVerb && hasFileContext) {
      return 'code_edit';
    }

    if (preferCodeEdit &&
        hasFileContext &&
        !normalized.contains('explain') &&
        !normalized.contains('review') &&
        !normalized.contains('why') &&
        !normalized.contains('what ')) {
      return 'code_edit';
    }

    if (hasFileContext &&
        (normalized.contains('repo') ||
            normalized.contains('repository') ||
            normalized.contains('branch') ||
            normalized.contains('workflow') ||
            normalized.contains('issue') ||
            normalized.contains('pull request') ||
            normalized.contains('pr '))) {
      return 'repo_question';
    }

    return null;
  }

  static bool _isUsefulRepositoryFile(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('/.git/') ||
        lower.startsWith('.git/') ||
        lower.contains('/node_modules/') ||
        lower.contains('/pods/') ||
        lower.contains('/build/') ||
        lower.contains('/dist/') ||
        lower.contains('/coverage/') ||
        lower.contains('/.dart_tool/') ||
        lower.contains('/.symlinks/')) {
      return false;
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.ico') ||
        lower.endsWith('.pdf') ||
        lower.endsWith('.zip') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.lock') ||
        lower.endsWith('.jar') ||
        lower.endsWith('.xcarchive')) {
      return false;
    }
    return true;
  }

  static int _scorePath(
    String path,
    List<String> keywords, {
    Set<String> anchorPaths = const <String>{},
  }) {
    final lower = path.toLowerCase();
    final fileName = lower.split('/').last;
    final fileStem =
        fileName.contains('.')
            ? fileName.substring(0, fileName.indexOf('.'))
            : fileName;
    var score = 0;

    for (final keyword in keywords) {
      if (fileName.contains(keyword)) {
        score += 12;
      }
      if (fileStem.contains(keyword)) {
        score += 8;
      }
      if (lower.contains(keyword)) {
        score += 5;
      }
    }

    for (final anchor in anchorPaths) {
      if (anchor == path) {
        score += 100;
        continue;
      }

      final anchorLower = anchor.toLowerCase();
      final anchorDir = _directoryName(anchorLower);
      final currentDir = _directoryName(lower);
      if (anchorDir.isNotEmpty && currentDir == anchorDir) {
        score += 18;
      } else if (anchorDir.isNotEmpty && currentDir.startsWith(anchorDir)) {
        score += 10;
      }

      score += _sharedPrefixDepth(anchorLower, lower) * 2;

      final anchorFileName = anchorLower.split('/').last;
      final anchorStem =
          anchorFileName.contains('.')
              ? anchorFileName.substring(0, anchorFileName.indexOf('.'))
              : anchorFileName;
      if (anchorStem.isNotEmpty && fileStem.contains(anchorStem)) {
        score += 6;
      }
    }

    if (lower.endsWith('readme.md')) {
      score += 8;
    }
    if (lower.endsWith('pubspec.yaml') ||
        lower.endsWith('package.json') ||
        lower.endsWith('podfile') ||
        lower.endsWith('androidmanifest.xml') ||
        lower.endsWith('analysis_options.yaml')) {
      score += 5;
    }
    if (lower.contains('/lib/') || lower.startsWith('lib/')) {
      score += 4;
    }
    if (lower.contains('/src/') || lower.startsWith('src/')) {
      score += 3;
    }
    if (lower.endsWith('.dart') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.tsx') ||
        lower.endsWith('.js') ||
        lower.endsWith('.jsx') ||
        lower.endsWith('.swift') ||
        lower.endsWith('.kt') ||
        lower.endsWith('.go') ||
        lower.endsWith('.rs') ||
        lower.endsWith('.py') ||
        lower.endsWith('.java') ||
        lower.endsWith('.rb')) {
      score += 2;
    }

    return score;
  }

  static String _directoryName(String path) {
    if (!path.contains('/')) {
      return '';
    }
    return path.substring(0, path.lastIndexOf('/'));
  }

  static int _sharedPrefixDepth(String left, String right) {
    final leftParts = left.split('/');
    final rightParts = right.split('/');
    final limit =
        leftParts.length < rightParts.length
            ? leftParts.length
            : rightParts.length;

    var depth = 0;
    for (var index = 0; index < limit; index++) {
      if (leftParts[index] != rightParts[index]) {
        break;
      }
      depth++;
    }
    return depth;
  }
}

String stripCodeFences(String input) {
  var output = input.trim();
  output = output.replaceAll(RegExp(r'^```[\w-]*\s*\n?'), '');
  output = output.replaceAll(RegExp(r'\n?```\s*$'), '');
  output = output.replaceAll('```', '');
  return output.trim();
}

String friendlyErrorMessage(String error) {
  if (error.contains('OpenAI API key') ||
      error.contains('OpenRouter API key')) {
    return 'Check your AI provider settings and try again.';
  }
  if (error.contains('GitHub authentication')) {
    return 'GitHub sign-in is required before the app can access your repositories.';
  }
  if (error.contains('MissingPluginException') ||
      error.contains('No implementation found for method')) {
    return 'The PDF export plugin is not loaded yet. Run a full restart or rebuild, then try again.';
  }
  if (error.contains('Unable to load asset')) {
    return 'A required PDF asset is missing from this build. Rebuild the app so the fonts and logo are bundled.';
  }
  if (error.contains('repository')) {
    return 'Repository access failed. Check your GitHub permissions and selected branch.';
  }
  if (error.contains('network') || error.contains('connection')) {
    return 'Network error. Check your connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}
