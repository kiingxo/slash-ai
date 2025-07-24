import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/secure_storage_service.dart';

class AuthState {
  final bool isLoading;
  final String? error;
  final String? geminiApiKey;
  final String? openAIApiKey;
  final String? githubPat;
  final String model; // 'gemini' or 'openai'
  AuthState({
    this.isLoading = false,
    this.error,
    this.geminiApiKey,
    this.openAIApiKey,
    this.githubPat,
    this.model = 'gemini',
  });

  AuthState copyWith({
    bool? isLoading,
    String? error,
    String? geminiApiKey,
    String? openAIApiKey,
    String? githubPat,
    String? model,
  }) => AuthState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        geminiApiKey: geminiApiKey ?? this.geminiApiKey,
        openAIApiKey: openAIApiKey ?? this.openAIApiKey,
        githubPat: githubPat ?? this.githubPat,
        model: model ?? this.model,
      );
}

class AuthController extends StateNotifier<AuthState> {
  final SecureStorageService _storage;
  static const _geminiKey = 'gemini_api_key';
  static const _openAIKey = 'openai_api_key';
  static const _githubKey = 'github_pat';
  static const _modelKey = 'model';
  AuthController(this._storage) : super(AuthState()) {
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    state = state.copyWith(isLoading: true);
    try {
      final gemini = await _storage.getApiKey(_geminiKey);
      final openai = await _storage.getApiKey(_openAIKey);
      final github = await _storage.getApiKey(_githubKey);
      final model = await _storage.getApiKey(_modelKey) ?? 'gemini';
      state = state.copyWith(isLoading: false, geminiApiKey: gemini, openAIApiKey: openai, githubPat: github, model: model);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }


  Future<void> saveGeminiApiKey(String key) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _storage.saveApiKey(_geminiKey, key);
      state = state.copyWith(isLoading: false, geminiApiKey: key);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> saveOpenAIApiKey(String key) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _storage.saveApiKey(_openAIKey, key);
      state = state.copyWith(isLoading: false, openAIApiKey: key);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> saveGitHubPat(String pat) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _storage.saveApiKey(_githubKey, pat);
      state = state.copyWith(isLoading: false, githubPat: pat);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> saveModel(String model) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _storage.saveApiKey(_modelKey, model);
      state = state.copyWith(isLoading: false, model: model);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(SecureStorageService());
});