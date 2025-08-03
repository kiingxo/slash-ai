import 'dart:convert';
import 'package:http/http.dart' as http;

/// GitHub API wrapper supporting both OAuth Device Flow tokens and PATs.
/// For simplicity we use `Authorization: token <token>` which works for user tokens.
class GitHubService {
  final String token; // OAuth access token or PAT

  GitHubService(this.token);

  Map<String, String> get _headers => {
    'Authorization': 'token $token',
    'Accept': 'application/vnd.github+json',
  };

  Future<void> createBranch({
    required String owner,
    required String repo,
    required String newBranch,
    String baseBranch = 'main',
  }) async {
    // Get the latest commit SHA of the base branch
    final refRes = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/git/ref/heads/$baseBranch'),
      headers: _headers,
    );
    if (refRes.statusCode != 200) throw Exception('Failed to get base branch ref: ${refRes.body}');
    final sha = jsonDecode(refRes.body)['object']['sha'];

    // Create the new branch
    final res = await http.post(
      Uri.parse('https://api.github.com/repos/$owner/$repo/git/refs'),
      headers: _headers,
      body: jsonEncode({
        'ref': 'refs/heads/$newBranch',
        'sha': sha,
      }),
    );
    if (res.statusCode != 201) throw Exception('Failed to create branch: ${res.body}');
  }

  Future<void> commitFile({
    required String owner,
    required String repo,
    required String branch,
    required String path,
    required String content,
    required String message,
  }) async {
    // Get the file SHA if it exists
    final fileRes = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/contents/$path?ref=$branch'),
      headers: _headers,
    );
    String? sha;
    if (fileRes.statusCode == 200) {
      sha = jsonDecode(fileRes.body)['sha'];
    }
    // Commit the file
    final res = await http.put(
      Uri.parse('https://api.github.com/repos/$owner/$repo/contents/$path'),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'content': base64Encode(utf8.encode(content)),
        'branch': branch,
        if (sha != null) 'sha': sha,
      }),
    );
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('Failed to commit file: ${res.body}');
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
    final res = await http.post(
      Uri.parse('https://api.github.com/repos/$owner/$repo/pulls'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'body': body,
        'head': head,
        'base': base,
      }),
    );
    if (res.statusCode != 201) throw Exception('Failed to open PR: ${res.body}');
    final data = jsonDecode(res.body);
    return data['html_url'] as String;
  }

  Future<List<String>> fetchBranches({
    required String owner,
    required String repo,
  }) async {
    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/branches'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch branches: ${res.body}');
    }
    final List branches = jsonDecode(res.body);
    return branches.map<String>((b) => b['name'] as String).toList();
  }
}
