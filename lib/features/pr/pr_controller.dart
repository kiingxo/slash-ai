import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/features/repo/repo_controller.dart';
import 'package:slash_flutter/services/secure_storage_service.dart';
import 'package:slash_flutter/services/github_service.dart';

class PrItem {
  final int number;
  final String title;
  final String state;
  final String author;
  final String headRef;
  final String baseRef;
  final String url;

  PrItem({
    required this.number,
    required this.title,
    required this.state,
    required this.author,
    required this.headRef,
    required this.baseRef,
    required this.url,
  });

  factory PrItem.fromJson(Map<String, dynamic> json) {
    return PrItem(
      number: json['number'] ?? 0,
      title: json['title'] ?? '',
      state: json['state'] ?? '',
      author: (json['user'] != null) ? (json['user']['login'] ?? '') : '',
      headRef: (json['head'] != null) ? (json['head']['ref'] ?? '') : '',
      baseRef: (json['base'] != null) ? (json['base']['ref'] ?? '') : '',
      url: json['html_url'] ?? '',
    );
  }
}

class PrFileChange {
  final String filename;
  final String status; // modified, added, removed, renamed
  final String patch; // unified diff if available

  PrFileChange({
    required this.filename,
    required this.status,
    required this.patch,
  });

  factory PrFileChange.fromJson(Map<String, dynamic> json) {
    return PrFileChange(
      filename: json['filename'] ?? '',
      status: json['status'] ?? '',
      patch: json['patch'] ?? '',
    );
  }
}

class PrDetail {
  final PrItem item;
  final List<PrFileChange> files;

  PrDetail({required this.item, required this.files});
}

class PrState {
  final bool loading;
  final String? error;
  final List<PrItem> prs;
  final PrDetail? selected;

  PrState({
    this.loading = false,
    this.error,
    this.prs = const [],
    this.selected,
  });

  PrState copyWith({
    bool? loading,
    String? error,
    List<PrItem>? prs,
    PrDetail? selected,
    bool clearError = false,
  }) {
    return PrState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      prs: prs ?? this.prs,
      selected: selected ?? this.selected,
    );
  }
}

class PrController extends StateNotifier<PrState> {
  final Ref ref;

  PrController(this.ref) : super(PrState());

  Future<GitHubService> _github() async {
    final storage = SecureStorageService();
    final pat = await storage.getApiKey('github_pat');
    if (pat == null || pat.isEmpty) {
      throw Exception('GitHub PAT missing');
    }
    return GitHubService(pat);
  }

  Map<String, String> _requireRepoOwnerAndName() {
    final repo = ref.read(repoControllerProvider).selectedRepo;
    if (repo == null) {
      throw Exception('No repository selected');
    }
    final owner = repo['owner']['login'];
    final name = repo['name'];
    return {'owner': owner, 'name': name};
  }

  Future<void> loadOpenPrs() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final gh = await _github();
      final repoInfo = _requireRepoOwnerAndName();
      // GitHubService might not have a direct method; using raw API
      final list = await gh.listPullRequests(
        owner: repoInfo['owner']!,
        repo: repoInfo['name']!,
        state: 'open',
      );
      final items = (list as List)
          .map((e) => PrItem.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(loading: false, prs: items);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> loadPrDetail(int number) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final gh = await _github();
      final repoInfo = _requireRepoOwnerAndName();
      final pr = await gh.getPullRequest(
        owner: repoInfo['owner']!,
        repo: repoInfo['name']!,
        number: number,
      );
      final files = await gh.getPullRequestFiles(
        owner: repoInfo['owner']!,
        repo: repoInfo['name']!,
        number: number,
      );
      final item = PrItem.fromJson(pr as Map<String, dynamic>);
      final changes = (files as List)
          .map((e) => PrFileChange.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        loading: false,
        selected: PrDetail(item: item, files: changes),
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> mergePr(int number) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final gh = await _github();
      final repoInfo = _requireRepoOwnerAndName();
      await gh.mergePullRequest(
        owner: repoInfo['owner']!,
        repo: repoInfo['name']!,
        number: number,
      );
      await loadOpenPrs();
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> closePr(int number) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final gh = await _github();
      final repoInfo = _requireRepoOwnerAndName();
      await gh.closePullRequest(
        owner: repoInfo['owner']!,
        repo: repoInfo['name']!,
        number: number,
      );
      await loadOpenPrs();
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> createPr({
    required String title,
    required String body,
    required String head,
    required String base,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final gh = await _github();
      final repoInfo = _requireRepoOwnerAndName();
      await gh.openPullRequest(
        owner: repoInfo['owner']!,
        repo: repoInfo['name']!,
        head: head,
        base: base,
        title: title,
        body: body,
      );
      await loadOpenPrs();
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

final prControllerProvider =
    StateNotifierProvider<PrController, PrState>((ref) => PrController(ref));
