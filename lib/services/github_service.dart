import 'dart:convert';

import 'package:http/http.dart' as http;

class GitHubApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  const GitHubApiException(this.message, {this.statusCode, this.body});

  @override
  String toString() => message;
}

class GitHubStaleFileException extends GitHubApiException {
  const GitHubStaleFileException(super.message, {super.statusCode, super.body});
}

class GitHubFileContent {
  final String name;
  final String path;
  final String sha;
  final String content;

  const GitHubFileContent({
    required this.name,
    required this.path,
    required this.sha,
    required this.content,
  });
}

class GitHubTreeItem {
  final String path;
  final String type;

  const GitHubTreeItem({required this.path, required this.type});
}

class GitHubRepositoryTreeSnapshot {
  final String commitSha;
  final String treeSha;
  final List<GitHubTreeItem> items;

  const GitHubRepositoryTreeSnapshot({
    required this.commitSha,
    required this.treeSha,
    required this.items,
  });
}

class GitHubSearchResult {
  final int totalCount;
  final List<Map<String, dynamic>> items;

  const GitHubSearchResult({required this.totalCount, required this.items});
}

class GitHubService {
  final String accessToken;
  final http.Client _client;

  GitHubService(this.accessToken, {http.Client? client})
    : _client = client ?? http.Client();

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $accessToken',
    'Accept': 'application/vnd.github+json',
    'Content-Type': 'application/json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Future<Map<String, dynamic>> fetchViewer() async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/user'),
      headers: _headers,
    );
    return _decodeMap(
      response,
      fallbackMessage: 'Failed to load the GitHub account.',
    );
  }

  Future<List<dynamic>> fetchRepositories({int perPage = 100}) async {
    final repositories = <dynamic>[];

    for (var page = 1; page <= 2; page++) {
      final response = await _client.get(
        Uri.https('api.github.com', '/user/repos', {
          'per_page': '$perPage',
          'page': '$page',
          'sort': 'updated',
          'affiliation': 'owner,collaborator,organization_member',
        }),
        headers: _headers,
      );

      final payload = _decodeResponse(
        response,
        fallbackMessage: 'Failed to load repositories from GitHub.',
      );
      if (payload is! List) {
        throw const GitHubApiException(
          'GitHub returned an unexpected repositories response.',
        );
      }

      repositories.addAll(payload);
      if (payload.length < perPage) {
        break;
      }
    }

    return repositories;
  }

  Future<List<Map<String, dynamic>>> fetchDirectory({
    required String owner,
    required String repo,
    String path = '',
    String? branch,
  }) async {
    final response = await _client.get(
      Uri.https(
        'api.github.com',
        '/repos/$owner/$repo/contents/$path',
        branch == null ? null : {'ref': branch},
      ),
      headers: _headers,
    );

    final payload = _decodeResponse(
      response,
      fallbackMessage: 'Failed to load repository contents.',
    );
    if (payload is! List) {
      throw const GitHubApiException(
        'Expected a directory response from GitHub.',
      );
    }

    return payload
        .whereType<Map<String, dynamic>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<GitHubFileContent> fetchFileContent({
    required String owner,
    required String repo,
    required String path,
    String? branch,
  }) async {
    final response = await _client.get(
      Uri.https(
        'api.github.com',
        '/repos/$owner/$repo/contents/$path',
        branch == null ? null : {'ref': branch},
      ),
      headers: _headers,
    );

    final payload = _decodeMap(
      response,
      fallbackMessage: 'Failed to load file content from GitHub.',
    );
    if ((payload['type'] ?? '').toString() != 'file') {
      throw const GitHubApiException('The selected GitHub item is not a file.');
    }

    final encoded = (payload['content'] ?? '').toString().replaceAll('\n', '');
    return GitHubFileContent(
      name: (payload['name'] ?? '').toString(),
      path: (payload['path'] ?? path).toString(),
      sha: (payload['sha'] ?? '').toString(),
      content: utf8.decode(base64Decode(encoded)),
    );
  }

  Future<List<GitHubTreeItem>> fetchRepositoryTree({
    required String owner,
    required String repo,
    required String branch,
  }) async {
    return (await fetchRepositoryTreeSnapshot(
      owner: owner,
      repo: repo,
      branch: branch,
    )).items;
  }

  Future<String> fetchBranchCommitSha({
    required String owner,
    required String repo,
    required String branch,
  }) async {
    final branchInfo = await _fetchBranchInfo(
      owner: owner,
      repo: repo,
      branch: branch,
    );

    final commitSha =
        (branchInfo['commit'] is Map<String, dynamic>)
            ? (branchInfo['commit']['sha'] ?? '').toString()
            : '';
    if (commitSha.isEmpty) {
      throw const GitHubApiException('GitHub did not return a branch commit.');
    }
    return commitSha;
  }

  Future<GitHubRepositoryTreeSnapshot> fetchRepositoryTreeSnapshot({
    required String owner,
    required String repo,
    required String branch,
    String? commitSha,
  }) async {
    final resolvedCommitSha =
        commitSha?.trim().isNotEmpty == true
            ? commitSha!.trim()
            : await fetchBranchCommitSha(
              owner: owner,
              repo: repo,
              branch: branch,
            );

    final commitInfo = _decodeMap(
      await _client.get(
        Uri.https(
          'api.github.com',
          '/repos/$owner/$repo/git/commits/$resolvedCommitSha',
        ),
        headers: _headers,
      ),
      fallbackMessage: 'Failed to load branch commit details.',
    );

    final treeSha =
        (commitInfo['tree'] is Map<String, dynamic>)
            ? (commitInfo['tree']['sha'] ?? '').toString()
            : '';
    if (treeSha.isEmpty) {
      throw const GitHubApiException(
        'GitHub did not return a tree for this branch.',
      );
    }

    final treeInfo = _decodeMap(
      await _client.get(
        Uri.https('api.github.com', '/repos/$owner/$repo/git/trees/$treeSha', {
          'recursive': '1',
        }),
        headers: _headers,
      ),
      fallbackMessage: 'Failed to load the repository tree.',
    );

    final tree = treeInfo['tree'];
    final items =
        tree is List
            ? tree
                .whereType<Map<String, dynamic>>()
                .map(
                  (entry) => GitHubTreeItem(
                    path: (entry['path'] ?? '').toString(),
                    type: (entry['type'] ?? '').toString(),
                  ),
                )
                .where((entry) => entry.path.isNotEmpty)
                .toList()
            : const <GitHubTreeItem>[];

    return GitHubRepositoryTreeSnapshot(
      commitSha: resolvedCommitSha,
      treeSha: treeSha,
      items: items,
    );
  }

  Future<void> createBranch({
    required String owner,
    required String repo,
    required String newBranch,
    String baseBranch = 'main',
  }) async {
    final refInfo = _decodeMap(
      await _client.get(
        Uri.https(
          'api.github.com',
          '/repos/$owner/$repo/git/ref/heads/${Uri.encodeComponent(baseBranch)}',
        ),
        headers: _headers,
      ),
      fallbackMessage: 'Failed to load the base branch.',
    );

    final sha =
        (refInfo['object'] is Map<String, dynamic>)
            ? (refInfo['object']['sha'] ?? '').toString()
            : '';
    if (sha.isEmpty) {
      throw const GitHubApiException(
        'GitHub did not return a base commit SHA.',
      );
    }

    final response = await _client.post(
      Uri.https('api.github.com', '/repos/$owner/$repo/git/refs'),
      headers: _headers,
      body: jsonEncode({'ref': 'refs/heads/$newBranch', 'sha': sha}),
    );

    if (response.statusCode != 201) {
      throw _toException(
        response,
        fallbackMessage: 'Failed to create the working branch.',
      );
    }
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
    final currentMetadata = await _tryFetchFileMetadata(
      owner: owner,
      repo: repo,
      branch: branch,
      path: path,
    );
    final currentSha = currentMetadata?['sha']?.toString();

    if (expectedSha != null &&
        expectedSha.isNotEmpty &&
        currentSha != null &&
        currentSha != expectedSha) {
      throw const GitHubStaleFileException(
        'The remote file changed since it was loaded. Pull the latest version before pushing your edits.',
      );
    }

    final response = await _client.put(
      Uri.https('api.github.com', '/repos/$owner/$repo/contents/$path'),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'content': base64Encode(utf8.encode(content)),
        'branch': branch,
        if (currentSha != null && currentSha.isNotEmpty) 'sha': currentSha,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _toException(
        response,
        fallbackMessage: 'Failed to commit the file to GitHub.',
      );
    }
  }

  Future<String> openPullRequest({
    required String owner,
    required String repo,
    required String head,
    required String base,
    required String title,
    required String body,
  }) async {
    final response = await _client.post(
      Uri.https('api.github.com', '/repos/$owner/$repo/pulls'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'body': body,
        'head': head,
        'base': base,
      }),
    );

    final payload = _decodeMap(
      response,
      fallbackMessage: 'Failed to open the pull request.',
    );
    return (payload['html_url'] ?? '').toString();
  }

  Future<List<String>> fetchBranches({
    required String owner,
    required String repo,
  }) async {
    final response = await _client.get(
      Uri.https('api.github.com', '/repos/$owner/$repo/branches'),
      headers: _headers,
    );

    final payload = _decodeResponse(
      response,
      fallbackMessage: 'Failed to load repository branches.',
    );
    if (payload is! List) {
      return const <String>[];
    }

    return payload
        .whereType<Map<String, dynamic>>()
        .map((entry) => (entry['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchCommits({
    required String owner,
    required String repo,
    String? branch,
    DateTime? since,
    int perPage = 100,
  }) async {
    final response = await _client.get(
      Uri.https('api.github.com', '/repos/$owner/$repo/commits', {
        'per_page': '$perPage',
        if (branch != null && branch.trim().isNotEmpty) 'sha': branch.trim(),
        if (since != null) 'since': since.toUtc().toIso8601String(),
      }),
      headers: _headers,
    );

    final payload = _decodeResponse(
      response,
      fallbackMessage: 'Failed to load recent commits.',
    );
    if (payload is! List) {
      return const <Map<String, dynamic>>[];
    }

    return payload
        .whereType<Map<String, dynamic>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchPullRequests({
    required String owner,
    required String repo,
    String state = 'open',
    String sort = 'updated',
    String direction = 'desc',
    String? base,
    int perPage = 50,
  }) async {
    final response = await _client.get(
      Uri.https('api.github.com', '/repos/$owner/$repo/pulls', {
        'state': state,
        'sort': sort,
        'direction': direction,
        'per_page': '$perPage',
        if (base != null && base.trim().isNotEmpty) 'base': base.trim(),
      }),
      headers: _headers,
    );

    final payload = _decodeResponse(
      response,
      fallbackMessage: 'Failed to load pull requests.',
    );
    if (payload is! List) {
      return const <Map<String, dynamic>>[];
    }

    return payload
        .whereType<Map<String, dynamic>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<GitHubSearchResult> searchIssuesAndPullRequests({
    required String query,
    String sort = 'updated',
    String order = 'desc',
    int perPage = 50,
  }) async {
    final response = await _client.get(
      Uri.https('api.github.com', '/search/issues', {
        'q': query,
        'sort': sort,
        'order': order,
        'per_page': '$perPage',
      }),
      headers: _headers,
    );

    final payload = _decodeMap(
      response,
      fallbackMessage: 'Failed to search GitHub issues and pull requests.',
    );

    final items =
        (payload['items'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();

    return GitHubSearchResult(
      totalCount: (payload['total_count'] as num?)?.toInt() ?? items.length,
      items: items,
    );
  }

  Future<List<Map<String, dynamic>>> fetchWorkflowRuns({
    required String owner,
    required String repo,
    String? branch,
    int perPage = 30,
  }) async {
    final payload = _decodeMap(
      await _client.get(
        Uri.https('api.github.com', '/repos/$owner/$repo/actions/runs', {
          'per_page': '$perPage',
          if (branch != null && branch.trim().isNotEmpty)
            'branch': branch.trim(),
        }),
        headers: _headers,
      ),
      fallbackMessage: 'Failed to load workflow runs.',
    );

    return (payload['workflow_runs'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchReleases({
    required String owner,
    required String repo,
    int perPage = 10,
  }) async {
    final response = await _client.get(
      Uri.https('api.github.com', '/repos/$owner/$repo/releases', {
        'per_page': '$perPage',
      }),
      headers: _headers,
    );

    final payload = _decodeResponse(
      response,
      fallbackMessage: 'Failed to load releases.',
    );
    if (payload is! List) {
      return const <Map<String, dynamic>>[];
    }

    return payload
        .whereType<Map<String, dynamic>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<Map<String, dynamic>?> _tryFetchFileMetadata({
    required String owner,
    required String repo,
    required String branch,
    required String path,
  }) async {
    final response = await _client.get(
      Uri.https('api.github.com', '/repos/$owner/$repo/contents/$path', {
        'ref': branch,
      }),
      headers: _headers,
    );

    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw _toException(
        response,
        fallbackMessage: 'Failed to validate the remote file state.',
      );
    }

    final payload = jsonDecode(response.body);
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    return null;
  }

  Future<Map<String, dynamic>> _fetchBranchInfo({
    required String owner,
    required String repo,
    required String branch,
  }) async {
    return _decodeMap(
      await _client.get(
        Uri.https(
          'api.github.com',
          '/repos/$owner/$repo/branches/${Uri.encodeComponent(branch)}',
        ),
        headers: _headers,
      ),
      fallbackMessage: 'Failed to load branch information.',
    );
  }

  dynamic _decodeResponse(
    http.Response response, {
    required String fallbackMessage,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response, fallbackMessage: fallbackMessage);
    }

    if (response.body.trim().isEmpty) {
      return null;
    }
    return jsonDecode(response.body);
  }

  Map<String, dynamic> _decodeMap(
    http.Response response, {
    required String fallbackMessage,
  }) {
    final payload = _decodeResponse(response, fallbackMessage: fallbackMessage);
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    throw GitHubApiException(fallbackMessage, statusCode: response.statusCode);
  }

  GitHubApiException _toException(
    http.Response response, {
    required String fallbackMessage,
  }) {
    String message = fallbackMessage;
    String? body;

    if (response.body.trim().isNotEmpty) {
      body = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final apiMessage = (decoded['message'] ?? '').toString();
          if (apiMessage.isNotEmpty) {
            message = apiMessage;
          }
        }
      } catch (_) {
        message = fallbackMessage;
      }
    }

    if (response.statusCode == 401) {
      message = 'GitHub authentication expired. Please sign in again.';
    }

    return GitHubApiException(
      message,
      statusCode: response.statusCode,
      body: body,
    );
  }
}
