import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredKeys {
  static const String model = 'model';
  static const String openAIApiKey = 'openai_api_key';
  static const String openAIModel = 'openai_model';
  static const String openRouterApiKey = 'openrouter_api_key';
  static const String openRouterModel = 'openrouter_model';
  static const String githubAccessToken = 'github_access_token';
  static const String githubOAuthClientId = 'github_oauth_client_id';
  static const String githubUserLogin = 'github_user_login';
  static const String githubUserName = 'github_user_name';
  static const String githubUserAvatarUrl = 'github_user_avatar_url';
  static const String githubUserHtmlUrl = 'github_user_html_url';
  static const String vpsHost = 'vps_host';
  static const String vpsPort = 'vps_port';
  static const String vpsUsername = 'vps_username';
  static const String vpsAuthMode = 'vps_auth_mode';
  static const String vpsPassword = 'vps_password';
  static const String vpsPrivateKey = 'vps_private_key';
  static const String vpsPassphrase = 'vps_passphrase';
  static const String vpsAutoRefresh = 'vps_auto_refresh';

  // Migration fallback for older builds.
  static const String legacyGitHubPat = 'github_pat';
}

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  Future<void> saveApiKey(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> getApiKey(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> deleteApiKey(String key) async {
    await _storage.delete(key: key);
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  Future<void> saveString(String key, String? value) async {
    if (value == null || value.trim().isEmpty) {
      await deleteApiKey(key);
      return;
    }
    await _storage.write(key: key, value: value.trim());
  }

  Future<String?> readString(String key) => _storage.read(key: key);

  Future<String?> getGitHubAccessToken() async {
    return await _storage.read(key: StoredKeys.githubAccessToken) ??
        await _storage.read(key: StoredKeys.legacyGitHubPat);
  }

  Future<void> saveGitHubAccessToken(String value) async {
    await saveString(StoredKeys.githubAccessToken, value);
    await saveString(StoredKeys.legacyGitHubPat, value);
  }

  Future<void> clearGitHubAccessToken() async {
    await deleteApiKey(StoredKeys.githubAccessToken);
    await deleteApiKey(StoredKeys.legacyGitHubPat);
  }
}
