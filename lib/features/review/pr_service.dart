import 'dart:convert';

import 'package:http/http.dart' as http;
import '../../services/secure_storage_service.dart';

class PRDetailData {
  final bool? isDraft;
  final bool? mergeable;
  final String? mergeableState; // clean, blocked, unstable, dirty, unknown
  final String? ciState; // success, failure, pending
  const PRDetailData({this.isDraft, this.mergeable, this.mergeableState, this.ciState});
}

class PRService {
  static Future<PRDetailData> fetchPRDetail(String owner, String repo, String number) async {
    final pat = await SecureStorageService().getApiKey('github_pat');
    final headers = {
      'Authorization': 'token $pat',
      'Accept': 'application/vnd.github+json',
    };
    final prRes = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/pulls/$number'),
      headers: headers,
    );
    if (prRes.statusCode != 200) return const PRDetailData();
    final pr = jsonDecode(prRes.body) as Map<String, dynamic>;
    final draft = pr['draft'] == true;
    final mergeable = pr['mergeable'] as bool?;
    final mergeableState = pr['mergeable_state'] as String?; // may be null/unknown
    final sha = pr['head']?['sha'] as String?;
    String? ciState;
    if (sha != null) {
      final statusRes = await http.get(
        Uri.parse('https://api.github.com/repos/$owner/$repo/commits/$sha/status'),
        headers: headers,
      );
      if (statusRes.statusCode == 200) {
        final status = jsonDecode(statusRes.body) as Map<String, dynamic>;
        ciState = (status['state'] as String?); // success, failure, pending
      }
    }
    return PRDetailData(isDraft: draft, mergeable: mergeable, mergeableState: mergeableState, ciState: ciState);
  }

  static Future<void> submitReview(
    String owner,
    String repo,
    String number,
    String event, {
    String? body,
  }) async {
    final pat = await SecureStorageService().getApiKey('github_pat');
    final headers = {
      'Authorization': 'token $pat',
      'Accept': 'application/vnd.github+json',
    };
    final res = await http.post(
      Uri.parse('https://api.github.com/repos/$owner/$repo/pulls/$number/reviews'),
      headers: headers,
      body: jsonEncode({
        if (body != null && body.isNotEmpty) 'body': body,
        'event': event,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Review failed: ${res.body}');
    }
  }

  static Future<void> mergePR(String owner, String repo, String number) async {
    final pat = await SecureStorageService().getApiKey('github_pat');
    final headers = {
      'Authorization': 'token $pat',
      'Accept': 'application/vnd.github+json',
    };
    final res = await http.put(
      Uri.parse('https://api.github.com/repos/$owner/$repo/pulls/$number/merge'),
      headers: headers,
      body: jsonEncode({
        'merge_method': 'squash',
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Merge failed: ${res.body}');
    }
  }
}


