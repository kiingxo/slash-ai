// AuthService is not needed in the new client-only architecture.
// All authentication is handled via local token storage in SecureStorageService. 

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/secure_storage_service.dart';

class AuthState {
  final String model; // 'gemini' | 'openrouter'
  final String? geminiApiKey;
  final String? openRouterApiKey;
  final String? githubPat;
  final String? openRouterModel; // selected OpenRouter model id

  AuthState({
    required this.model,
    this.geminiApiKey,
    this.openRouterApiKey,
    this.githubPat,
    this.openRouterModel,
  });

  AuthState copyWith({
    String? model,
    String? geminiApiKey,
    String? openRouterApiKey,
    String? githubPat,
    String? openRouterModel,
  }) {
    return AuthState(
      model: model ?? this.model,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      openRouterApiKey: openRouterApiKey ?? this.openRouterApiKey,
      githubPat: githubPat ?? this.githubPat,
      openRouterModel: openRouterModel ?? this.openRouterModel,
    );
  }

  factory AuthState.initial() => AuthState(model: 'gemini');
}

class AuthController extends StateNotifier<AuthState> {
  final SecureStorageService _storage;

  AuthController(this._storage) : super(AuthState.initial()) {
    _load();
  }

  Future<void> _load() async {
    // Persist model and selected OpenRouter model using the same secure storage API (read/write by key).
    final model = await _storage.getApiKey('model') ?? 'gemini';
    final geminiApiKey = await _storage.getApiKey('gemini_api_key');
    final openRouterApiKey = await _storage.getApiKey('openrouter_api_key');
    final githubPat = await _storage.getApiKey('github_pat');
    final openRouterModel = await _storage.getApiKey('openrouter_model');

    state = state.copyWith(
      model: model,
      geminiApiKey: geminiApiKey,
      openRouterApiKey: openRouterApiKey,
      githubPat: githubPat,
      openRouterModel: openRouterModel,
    );
  }

  Future<void> setModel(String model) async {
    state = state.copyWith(model: model);
    await _storage.saveApiKey('model', model);
  }

  Future<void> setGeminiKey(String key) async {
    await _storage.saveApiKey('gemini_api_key', key);
    state = state.copyWith(geminiApiKey: key);
  }

  Future<void> setOpenRouterKey(String key) async {
    await _storage.saveApiKey('openrouter_api_key', key);
    state = state.copyWith(openRouterApiKey: key);
  }

  Future<void> setGitHubPat(String pat) async {
    await _storage.saveApiKey('github_pat', pat);
    state = state.copyWith(githubPat: pat);
  }

  Future<void> setOpenRouterModel(String modelId) async {
    await _storage.saveApiKey('openrouter_model', modelId);
    state = state.copyWith(openRouterModel: modelId);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(SecureStorageService());
});
