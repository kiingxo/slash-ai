import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/github_service.dart';
import '../../services/secure_storage_service.dart';

class RepoState {
  final bool isLoading;
  final String? error;
  final List<dynamic> repos;
  final dynamic selectedRepo;

  const RepoState({
    this.isLoading = false,
    this.error,
    this.repos = const [],
    this.selectedRepo,
  });

  RepoState copyWith({
    bool? isLoading,
    Object? error = _repoUnset,
    List<dynamic>? repos,
    Object? selectedRepo = _repoUnset,
  }) {
    return RepoState(
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _repoUnset) ? this.error : error as String?,
      repos: repos ?? this.repos,
      selectedRepo:
          identical(selectedRepo, _repoUnset)
              ? this.selectedRepo
              : selectedRepo,
    );
  }
}

const Object _repoUnset = Object();

class RepoController extends StateNotifier<RepoState> {
  final SecureStorageService _storage;
  final Completer<void> _loaded = Completer<void>();

  Future<void> get whenLoaded => _loaded.future;

  RepoController(this._storage) : super(const RepoState()) {
    fetchRepos();
  }

  Future<GitHubService> _gitHub() async {
    final token = await _storage.getGitHubAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw const GitHubApiException('GitHub authentication is required.');
    }
    return GitHubService(token);
  }

  Future<void> fetchRepos() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final github = await _gitHub();
      final repos = await github.fetchRepositories();
      final previousSelectedFullName =
          (state.selectedRepo?['full_name'] ?? '').toString();

      dynamic selectedRepo;
      if (previousSelectedFullName.isNotEmpty) {
        for (final repo in repos) {
          if ((repo['full_name'] ?? '').toString() == previousSelectedFullName) {
            selectedRepo = repo;
            break;
          }
        }
      }

      state = state.copyWith(
        isLoading: false,
        repos: repos,
        selectedRepo: selectedRepo ?? (repos.isNotEmpty ? repos.first : null),
      );
      if (!_loaded.isCompleted) {
        _loaded.complete();
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        repos: const [],
      );
      if (!_loaded.isCompleted) {
        _loaded.complete();
      }
    }
  }

  void selectRepo(dynamic repo) {
    state = state.copyWith(selectedRepo: repo);
  }
}

final repoControllerProvider =
    StateNotifierProvider<RepoController, RepoState>((ref) {
      return RepoController(SecureStorageService());
    });
