import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class GitHubDeviceCodeResponse {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String verificationUriComplete;
  final int expiresIn;
  final int interval;

  GitHubDeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresIn,
    required this.interval,
  });

  factory GitHubDeviceCodeResponse.fromJson(Map<String, dynamic> json) {
    return GitHubDeviceCodeResponse(
      deviceCode: json['device_code'] as String,
      userCode: json['user_code'] as String,
      verificationUri: json['verification_uri'] as String,
      verificationUriComplete: json['verification_uri_complete'] as String? ?? '',
      expiresIn: json['expires_in'] as int,
      interval: json['interval'] as int? ?? 5,
    );
  }
}

class GitHubOAuthService {
  static const _deviceCodeUrl = 'https://github.com/login/device/code';
  static const _tokenUrl = 'https://github.com/login/oauth/access_token';

  /// Start the device authorization flow.
  /// Returns the device_code + verification URIs for the user to complete.
  static Future<GitHubDeviceCodeResponse> startDeviceFlow({
    String clientId = GITHUB_CLIENT_ID,
    List<String> scopes = GITHUB_OAUTH_SCOPES,
  }) async {
    final res = await http.post(
      Uri.parse(_deviceCodeUrl),
      headers: {
        'Accept': 'application/json',
      },
      body: {
        'client_id': clientId,
        'scope': scopes.join(' '),
      },
    );

    if (res.statusCode != 200) {
      throw Exception('GitHub device code error: ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return GitHubDeviceCodeResponse.fromJson(data);
  }

  /// Polls GitHub until the user completes the verification or the device code expires.
  /// Returns the OAuth access_token on success.
  static Future<String> pollForToken({
    required String deviceCode,
    String clientId = GITHUB_CLIENT_ID,
    int intervalSeconds = 5,
    Duration? maxWait,
  }) async {
    final start = DateTime.now();
    final maxDuration = maxWait ?? const Duration(minutes: 10);
    var interval = Duration(seconds: intervalSeconds);

    while (true) {
      if (DateTime.now().difference(start) > maxDuration) {
        throw Exception('GitHub device flow timed out');
      }

      final res = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Accept': 'application/json',
        },
        body: {
          'client_id': clientId,
          'device_code': deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('GitHub token polling error: ${res.statusCode}: ${res.body}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['access_token'] is String && (data['access_token'] as String).isNotEmpty) {
        return data['access_token'] as String;
      }

      // Handle polling states
      final error = data['error'] as String?;
      if (error == 'authorization_pending') {
        // keep polling
      } else if (error == 'slow_down') {
        // increase interval by 5 seconds per spec
        interval += const Duration(seconds: 5);
      } else if (error == 'expired_token') {
        throw Exception('GitHub device code expired. Please start again.');
      } else if (error != null) {
        throw Exception('GitHub OAuth error: $error');
      }

      await Future.delayed(interval);
    }
  }
}
