import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/github_service.dart';
import '../../services/secure_storage_service.dart';

final codeEditorServiceProvider = Provider<CodeEditorService>(
  (ref) => CodeEditorService(),
);

class CodeEditorService {
  final SecureStorageService _storage = SecureStorageService();

  Future<GitHubService> _gitHub() async {
    final token = await _storage.getGitHubAccessToken();
    if (token == null || token.isEmpty) {
      throw const GitHubApiException('GitHub authentication is required.');
    }
    return GitHubService(token);
  }

  Future<List<String>> fetchBranches({
    required String owner,
    required String repo,
  }) async {
    final github = await _gitHub();
    return github.fetchBranches(owner: owner, repo: repo);
  }

  Future<void> commitFile({
    required String owner,
    required String repo,
    required String branch,
    required String path,
    required String content,
    required String message,
    String? expectedSha,
  }) async {
    final github = await _gitHub();
    await github.commitFile(
      owner: owner,
      repo: repo,
      branch: branch,
      path: path,
      content: content,
      message: message,
      expectedSha: expectedSha,
    );
  }

  Future<GitHubFileContent> pullLatestFile({
    required String owner,
    required String repo,
    required String branch,
    required String path,
  }) async {
    final github = await _gitHub();
    return github.fetchFileContent(
      owner: owner,
      repo: repo,
      path: path,
      branch: branch,
    );
  }
}
