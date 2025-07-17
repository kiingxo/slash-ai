import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../services/secure_storage_service.dart';

class RepoState {
  final bool isLoading;
  final String? error;
  final List<dynamic> repos;
  final dynamic selectedRepo;
  RepoState({this.isLoading = false, this.error, this.repos = const [], this.selectedRepo});

  RepoState copyWith({bool? isLoading, String? error, List<dynamic>? repos, dynamic selectedRepo}) => RepoState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        repos: repos ?? this.repos,
        selectedRepo: selectedRepo ?? this.selectedRepo,
      );
}

class RepoController extends StateNotifier<RepoState> {
  final SecureStorageService _storage;
  RepoController(this._storage) : super(RepoState()) {
    fetchRepos();
  }

  Future<void> fetchRepos() async {
    print('Fetching repos...');
    state = state.copyWith(isLoading: true, error: null);
    try {
      final patRaw = await _storage.getApiKey('github_pat');
      final pat = patRaw?.trim();
      if (pat == null || pat.isEmpty) throw Exception('GitHub PAT not found');
      final dio = Dio(BaseOptions(
        baseUrl: 'https://api.github.com/',
        headers: {'Authorization': 'token $pat'},
      ));
      final res = await dio.get('/user/repos');
      print('Repos fetched:  res.data.length repos');
      state = state.copyWith(isLoading: false, repos: res.data);
    } catch (e) {
      print('Error fetching repos: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void selectRepo(dynamic repo) {
    print('Repo selected: owner= repo[\'owner\'][\'login\'] , name= repo[\'name\'] , full object: $repo');
    state = state.copyWith(selectedRepo: repo);
  }
}

final repoControllerProvider = StateNotifierProvider<RepoController, RepoState>((ref) {
  return RepoController(SecureStorageService());
}); 