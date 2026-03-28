import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_config.dart';
import '../../services/github_auth_service.dart';
import '../../services/secure_storage_service.dart';

const Object _unset = Object();

class AuthState {
  final bool isLoading;
  final bool isSigningInWithGitHub;
  final String? error;
  final String? openAIApiKey;
  final String? openAIModel;
  final String? openRouterApiKey;
  final String? openRouterModel;
  final String? githubAccessToken;
  final String? githubOAuthClientId;
  final GitHubUser? githubUser;
  final GitHubDeviceCodeSession? pendingGitHubSession;
  final String model; // 'openai' | 'openrouter'

  const AuthState({
    this.isLoading = false,
    this.isSigningInWithGitHub = false,
    this.error,
    this.openAIApiKey,
    this.openAIModel,
    this.openRouterApiKey,
    this.openRouterModel,
    this.githubAccessToken,
    this.githubOAuthClientId,
    this.githubUser,
    this.pendingGitHubSession,
    this.model = 'openai',
  });

  String get provider => model;

  bool get hasGitHubAuth => githubAccessToken?.isNotEmpty == true;

  bool get hasAiCredentials {
    if (model == 'openrouter') {
      return openRouterApiKey?.isNotEmpty == true;
    }
    return openAIApiKey?.isNotEmpty == true;
  }

  bool get isReady => hasGitHubAuth && hasAiCredentials;

  String? get githubPat => githubAccessToken;

  AuthState copyWith({
    bool? isLoading,
    bool? isSigningInWithGitHub,
    Object? error = _unset,
    Object? openAIApiKey = _unset,
    Object? openAIModel = _unset,
    Object? openRouterApiKey = _unset,
    Object? openRouterModel = _unset,
    Object? githubAccessToken = _unset,
    Object? githubOAuthClientId = _unset,
    Object? githubUser = _unset,
    Object? pendingGitHubSession = _unset,
    String? model,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isSigningInWithGitHub:
          isSigningInWithGitHub ?? this.isSigningInWithGitHub,
      error: identical(error, _unset) ? this.error : error as String?,
      openAIApiKey:
          identical(openAIApiKey, _unset)
              ? this.openAIApiKey
              : openAIApiKey as String?,
      openAIModel:
          identical(openAIModel, _unset)
              ? this.openAIModel
              : openAIModel as String?,
      openRouterApiKey:
          identical(openRouterApiKey, _unset)
              ? this.openRouterApiKey
              : openRouterApiKey as String?,
      openRouterModel:
          identical(openRouterModel, _unset)
              ? this.openRouterModel
              : openRouterModel as String?,
      githubAccessToken:
          identical(githubAccessToken, _unset)
              ? this.githubAccessToken
              : githubAccessToken as String?,
      githubOAuthClientId:
          identical(githubOAuthClientId, _unset)
              ? this.githubOAuthClientId
              : githubOAuthClientId as String?,
      githubUser:
          identical(githubUser, _unset)
              ? this.githubUser
              : githubUser as GitHubUser?,
      pendingGitHubSession:
          identical(pendingGitHubSession, _unset)
              ? this.pendingGitHubSession
              : pendingGitHubSession as GitHubDeviceCodeSession?,
      model: model ?? this.model,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  final SecureStorageService _storage;
  final GitHubAuthService _gitHubAuth;

  AuthController(this._storage, {GitHubAuthService? gitHubAuth})
    : _gitHubAuth = gitHubAuth ?? GitHubAuthService(),
      super(const AuthState()) {
    _load();
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final provider = await _storage.readString(StoredKeys.model) ?? 'openai';
      final openAIApiKey = await _storage.readString(StoredKeys.openAIApiKey);
      final openAIModel =
          await _storage.readString(StoredKeys.openAIModel) ??
          AppConfig.defaultOpenAIModel;
      final openRouterApiKey = await _storage.readString(
        StoredKeys.openRouterApiKey,
      );
      final openRouterModel =
          await _storage.readString(StoredKeys.openRouterModel) ??
          AppConfig.defaultOpenRouterModel;
      final githubAccessToken = await _storage.getGitHubAccessToken();
      final githubOAuthClientId =
          AppConfig.hasBundledGitHubClientId
              ? AppConfig.githubOAuthClientId.trim()
              : null;

      GitHubUser? githubUser;
      final githubLogin = await _storage.readString(StoredKeys.githubUserLogin);
      if (githubLogin != null && githubLogin.isNotEmpty) {
        githubUser = GitHubUser(
          login: githubLogin,
          name: await _storage.readString(StoredKeys.githubUserName),
          avatarUrl: await _storage.readString(StoredKeys.githubUserAvatarUrl),
          htmlUrl: await _storage.readString(StoredKeys.githubUserHtmlUrl),
        );
      }

      state = state.copyWith(
        isLoading: false,
        error: null,
        model: provider == 'openrouter' ? 'openrouter' : 'openai',
        openAIApiKey: openAIApiKey,
        openAIModel: openAIModel,
        openRouterApiKey: openRouterApiKey,
        openRouterModel: openRouterModel,
        githubAccessToken: githubAccessToken,
        githubOAuthClientId: githubOAuthClientId,
        githubUser: githubUser,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> setProvider(String provider) async {
    final normalized = provider == 'openrouter' ? 'openrouter' : 'openai';
    state = state.copyWith(model: normalized);
    await _storage.saveString(StoredKeys.model, normalized);
  }

  Future<void> saveModel(String model) => setProvider(model);

  Future<void> setModel(String model) => setProvider(model);

  Future<void> saveOpenAIApiKey(String key) async {
    await _storage.saveString(StoredKeys.openAIApiKey, key);
    state = state.copyWith(openAIApiKey: key.trim(), error: null);
  }

  Future<void> setOpenAIApiKey(String key) => saveOpenAIApiKey(key);

  Future<void> saveOpenAIModel(String model) async {
    final normalized =
        model.trim().isEmpty ? AppConfig.defaultOpenAIModel : model.trim();
    await _storage.saveString(StoredKeys.openAIModel, normalized);
    state = state.copyWith(openAIModel: normalized, error: null);
  }

  Future<void> saveOpenRouterKey(String key) async {
    await _storage.saveString(StoredKeys.openRouterApiKey, key);
    state = state.copyWith(openRouterApiKey: key.trim(), error: null);
  }

  Future<void> setOpenRouterKey(String key) => saveOpenRouterKey(key);

  Future<void> saveOpenRouterModel(String modelId) async {
    final normalized =
        modelId.trim().isEmpty
            ? AppConfig.defaultOpenRouterModel
            : modelId.trim();
    await _storage.saveString(StoredKeys.openRouterModel, normalized);
    state = state.copyWith(openRouterModel: normalized, error: null);
  }

  Future<void> setOpenRouterModel(String modelId) =>
      saveOpenRouterModel(modelId);

  Future<void> saveGitHubOAuthClientId(String ignoredClientId) async {
    await _storage.deleteApiKey(StoredKeys.githubOAuthClientId);
    state = state.copyWith(
      githubOAuthClientId:
          AppConfig.hasBundledGitHubClientId
              ? AppConfig.githubOAuthClientId.trim()
              : null,
      error: null,
    );
  }

  Future<void> saveGitHubAccessToken(String token) async {
    await _storage.saveGitHubAccessToken(token);
    state = state.copyWith(githubAccessToken: token.trim(), error: null);
  }

  Future<void> saveGitHubPat(String token) => saveGitHubAccessToken(token);

  Future<GitHubDeviceCodeSession> beginGitHubDeviceFlow() async {
    final clientId = AppConfig.githubOAuthClientId.trim();
    if (clientId.isEmpty) {
      throw GitHubAuthException(AppConfig.missingGitHubOAuthClientIdMessage);
    }

    state = state.copyWith(
      isSigningInWithGitHub: true,
      error: null,
      pendingGitHubSession: null,
    );

    try {
      final session = await _gitHubAuth.startDeviceFlow(clientId: clientId);
      state = state.copyWith(
        isSigningInWithGitHub: false,
        pendingGitHubSession: session,
      );
      return session;
    } catch (e) {
      state = state.copyWith(isSigningInWithGitHub: false, error: e.toString());
      rethrow;
    }
  }

  Future<GitHubUser> completeGitHubDeviceFlow({
    GitHubDeviceCodeSession? session,
  }) async {
    final resolvedSession = session ?? state.pendingGitHubSession;
    final clientId = AppConfig.githubOAuthClientId.trim();

    if (resolvedSession == null) {
      throw const GitHubAuthException('No GitHub sign-in session is active.');
    }
    if (clientId.isEmpty) {
      throw GitHubAuthException(AppConfig.missingGitHubOAuthClientIdMessage);
    }

    state = state.copyWith(isSigningInWithGitHub: true, error: null);

    try {
      final result = await _gitHubAuth.completeDeviceFlow(
        clientId: clientId,
        session: resolvedSession,
      );

      await _storage.saveGitHubAccessToken(result.accessToken);
      await _storage.saveString(StoredKeys.githubUserLogin, result.user.login);
      await _storage.saveString(StoredKeys.githubUserName, result.user.name);
      await _storage.saveString(
        StoredKeys.githubUserAvatarUrl,
        result.user.avatarUrl,
      );
      await _storage.saveString(
        StoredKeys.githubUserHtmlUrl,
        result.user.htmlUrl,
      );

      state = state.copyWith(
        isSigningInWithGitHub: false,
        githubAccessToken: result.accessToken,
        githubUser: result.user,
        pendingGitHubSession: null,
      );

      return result.user;
    } catch (e) {
      state = state.copyWith(isSigningInWithGitHub: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> disconnectGitHub() async {
    await _storage.clearGitHubAccessToken();
    await _storage.deleteApiKey(StoredKeys.githubUserLogin);
    await _storage.deleteApiKey(StoredKeys.githubUserName);
    await _storage.deleteApiKey(StoredKeys.githubUserAvatarUrl);
    await _storage.deleteApiKey(StoredKeys.githubUserHtmlUrl);

    state = state.copyWith(
      githubAccessToken: null,
      githubUser: null,
      pendingGitHubSession: null,
      error: null,
    );
  }

  Future<void> resetAll() async {
    await _storage.deleteAll();
    state = AuthState(
      openAIModel: AppConfig.defaultOpenAIModel,
      openRouterModel: AppConfig.defaultOpenRouterModel,
      githubOAuthClientId:
          AppConfig.hasBundledGitHubClientId
              ? AppConfig.githubOAuthClientId.trim()
              : null,
    );
  }

  Future<void> clearError() async {
    state = state.copyWith(error: null);
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(SecureStorageService());
  },
);
