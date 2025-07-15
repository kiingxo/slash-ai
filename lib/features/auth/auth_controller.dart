import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/secure_storage_service.dart';

class AuthState {
  final bool isLoading;
  final String? error;
  final String? geminiApiKey;
  final String? githubPat;
  AuthState({this.isLoading = false, this.error, this.geminiApiKey, this.githubPat});

  AuthState copyWith({bool? isLoading, String? error, String? geminiApiKey, String? githubPat}) => AuthState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        geminiApiKey: geminiApiKey ?? this.geminiApiKey,
        githubPat: githubPat ?? this.githubPat,
      );
}

class AuthController extends StateNotifier<AuthState> {
  final SecureStorageService _storage;
  static const _geminiKey = 'gemini_api_key';
  static const _githubKey = 'github_pat';

  AuthController(this._storage) : super(AuthState()) {
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    state = state.copyWith(isLoading: true);
    try {
      final gemini = await _storage.getApiKey(_geminiKey);
      final github = await _storage.getApiKey(_githubKey);
      state = state.copyWith(isLoading: false, geminiApiKey: gemini, githubPat: github);
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

  Future<void> saveGitHubPat(String pat) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _storage.saveApiKey(_githubKey, pat);
      state = state.copyWith(isLoading: false, githubPat: pat);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(SecureStorageService());
}); 