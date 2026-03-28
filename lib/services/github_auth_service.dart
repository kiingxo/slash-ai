import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class GitHubAuthException implements Exception {
  final String message;

  const GitHubAuthException(this.message);

  @override
  String toString() => message;
}

class GitHubDeviceCodeSession {
  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final Uri? verificationUriComplete;
  final int expiresIn;
  final int intervalSeconds;

  const GitHubDeviceCodeSession({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresIn,
    required this.intervalSeconds,
  });
}

class GitHubUser {
  final String login;
  final String? name;
  final String? avatarUrl;
  final String? htmlUrl;

  const GitHubUser({
    required this.login,
    this.name,
    this.avatarUrl,
    this.htmlUrl,
  });

  factory GitHubUser.fromJson(Map<String, dynamic> json) {
    return GitHubUser(
      login: (json['login'] ?? '') as String,
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      htmlUrl: json['html_url'] as String?,
    );
  }
}

class GitHubAuthResult {
  final String accessToken;
  final String tokenType;
  final String scope;
  final GitHubUser user;

  const GitHubAuthResult({
    required this.accessToken,
    required this.tokenType,
    required this.scope,
    required this.user,
  });
}

class GitHubAuthService {
  static const String _deviceCodeEndpoint =
      'https://github.com/login/device/code';
  static const String _accessTokenEndpoint =
      'https://github.com/login/oauth/access_token';

  final http.Client _client;

  GitHubAuthService({http.Client? client}) : _client = client ?? http.Client();

  Future<GitHubDeviceCodeSession> startDeviceFlow({
    required String clientId,
    String scope = 'repo read:user',
  }) async {
    final response = await _client.post(
      Uri.parse(_deviceCodeEndpoint),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'client_id': clientId,
        'scope': scope,
      },
    );

    final data = _decodeJson(response);
    if (response.statusCode != 200) {
      throw GitHubAuthException(
        _extractErrorMessage(data, fallback: 'Unable to start GitHub sign-in.'),
      );
    }

    final verificationUriRaw =
        (data['verification_uri'] ?? data['verification_uri_complete'] ?? '')
            .toString();
    final verificationUriCompleteRaw =
        (data['verification_uri_complete'] ?? '').toString();

    if (verificationUriRaw.isEmpty || (data['device_code'] ?? '').toString().isEmpty) {
      throw const GitHubAuthException('GitHub sign-in returned an incomplete response.');
    }

    return GitHubDeviceCodeSession(
      deviceCode: data['device_code'] as String,
      userCode: (data['user_code'] ?? '') as String,
      verificationUri: Uri.parse(verificationUriRaw),
      verificationUriComplete:
          verificationUriCompleteRaw.isEmpty
              ? null
              : Uri.parse(verificationUriCompleteRaw),
      expiresIn: (data['expires_in'] as num?)?.toInt() ?? 900,
      intervalSeconds: (data['interval'] as num?)?.toInt() ?? 5,
    );
  }

  Future<GitHubAuthResult> completeDeviceFlow({
    required String clientId,
    required GitHubDeviceCodeSession session,
  }) async {
    final expiresAt = DateTime.now().add(
      Duration(seconds: session.expiresIn),
    );
    var pollSeconds = session.intervalSeconds;

    while (DateTime.now().isBefore(expiresAt)) {
      await Future<void>.delayed(Duration(seconds: pollSeconds));

      final response = await _client.post(
        Uri.parse(_accessTokenEndpoint),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'client_id': clientId,
          'device_code': session.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );

      final data = _decodeJson(response);
      if (response.statusCode != 200) {
        throw GitHubAuthException(
          _extractErrorMessage(data, fallback: 'GitHub sign-in failed.'),
        );
      }

      final accessToken = (data['access_token'] ?? '').toString();
      if (accessToken.isNotEmpty) {
        final user = await fetchViewer(accessToken);
        return GitHubAuthResult(
          accessToken: accessToken,
          tokenType: (data['token_type'] ?? 'bearer').toString(),
          scope: (data['scope'] ?? '').toString(),
          user: user,
        );
      }

      switch ((data['error'] ?? '').toString()) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          pollSeconds += 5;
          continue;
        case 'access_denied':
          throw const GitHubAuthException('GitHub sign-in was cancelled.');
        case 'expired_token':
          throw const GitHubAuthException('The GitHub sign-in code expired.');
        default:
          throw GitHubAuthException(
            _extractErrorMessage(data, fallback: 'GitHub sign-in failed.'),
          );
      }
    }

    throw const GitHubAuthException('GitHub sign-in timed out.');
  }

  Future<GitHubUser> fetchViewer(String accessToken) async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/user'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    final data = _decodeJson(response);
    if (response.statusCode != 200) {
      throw GitHubAuthException(
        _extractErrorMessage(
          data,
          fallback: 'GitHub authentication succeeded but the user profile could not be loaded.',
        ),
      );
    }

    return GitHubUser.fromJson(data);
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    if (response.body.trim().isEmpty) {
      return const <String, dynamic>{};
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return const <String, dynamic>{};
  }

  String _extractErrorMessage(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    final description = (data['error_description'] ?? '').toString().trim();
    final message = (data['message'] ?? '').toString().trim();
    final error = (data['error'] ?? '').toString().trim();

    if (description.isNotEmpty) {
      return description;
    }
    if (message.isNotEmpty) {
      return message;
    }
    if (error.isNotEmpty) {
      return error.replaceAll('_', ' ');
    }
    return fallback;
  }
}
