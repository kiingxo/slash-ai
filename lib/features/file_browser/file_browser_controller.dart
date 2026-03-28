import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/github_service.dart';
import '../../services/secure_storage_service.dart';

class RepoParams {
  final String owner;
  final String repo;
  final String? branch;

  const RepoParams({
    required this.owner,
    required this.repo,
    this.branch,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepoParams &&
          runtimeType == other.runtimeType &&
          owner == other.owner &&
          repo == other.repo &&
          branch == other.branch;

  @override
  int get hashCode => Object.hash(owner, repo, branch);
}

class FileItem {
  final String name;
  final String path;
  final String type; // 'file' or 'dir'
  final String? content;
  final String? sha;

  const FileItem({
    required this.name,
    required this.path,
    required this.type,
    this.content,
    this.sha,
  });

  FileItem copyWith({
    String? name,
    String? path,
    String? type,
    Object? content = _unsetFileItem,
    Object? sha = _unsetFileItem,
  }) {
    return FileItem(
      name: name ?? this.name,
      path: path ?? this.path,
      type: type ?? this.type,
      content:
          identical(content, _unsetFileItem) ? this.content : content as String?,
      sha: identical(sha, _unsetFileItem) ? this.sha : sha as String?,
    );
  }

  factory FileItem.fromJson(Map<String, dynamic> json) => FileItem(
    name: (json['name'] ?? '').toString(),
    path: (json['path'] ?? '').toString(),
    type: (json['type'] ?? '').toString(),
    content: json['content'] as String?,
    sha: json['sha'] as String?,
  );
}

const Object _unsetFileItem = Object();

class FileBrowserState {
  final bool isLoading;
  final String? error;
  final List<FileItem> items;
  final List<String> pathStack;
  final List<FileItem> selectedFiles;

  const FileBrowserState({
    this.isLoading = false,
    this.error,
    this.items = const [],
    this.pathStack = const [],
    this.selectedFiles = const [],
  });

  FileBrowserState copyWith({
    bool? isLoading,
    Object? error = _unsetFileItem,
    List<FileItem>? items,
    List<String>? pathStack,
    List<FileItem>? selectedFiles,
  }) {
    return FileBrowserState(
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _unsetFileItem) ? this.error : error as String?,
      items: items ?? this.items,
      pathStack: pathStack ?? this.pathStack,
      selectedFiles: selectedFiles ?? this.selectedFiles,
    );
  }
}

class FileBrowserController extends StateNotifier<FileBrowserState> {
  final SecureStorageService _storage;
  final String owner;
  final String repo;
  final String? branch;

  FileBrowserController(
    this._storage, {
    required this.owner,
    required this.repo,
    this.branch,
  }) : super(const FileBrowserState()) {
    fetchDir();
  }

  String get currentPath =>
      state.pathStack.isEmpty ? '' : state.pathStack.join('/');

  Future<GitHubService> _gitHub() async {
    final token = await _storage.getGitHubAccessToken();
    if (token == null || token.isEmpty) {
      throw const GitHubApiException('GitHub authentication is required.');
    }
    return GitHubService(token);
  }

  Future<void> fetchDir([String? path]) async {
    final normalizedPath = (path ?? currentPath).replaceAll(RegExp(r'^/+'), '');
    state = state.copyWith(isLoading: true, error: null);

    try {
      final github = await _gitHub();
      final entries = await github.fetchDirectory(
        owner: owner,
        repo: repo,
        path: normalizedPath,
        branch: branch,
      );

      final items = entries
          .map((entry) => FileItem.fromJson(entry))
          .where((item) => item.name.isNotEmpty && item.path.isNotEmpty)
          .toList();

      state = state.copyWith(
        isLoading: false,
        items: items,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void enterDir(String dirName) {
    final newStack = List<String>.from(state.pathStack)..add(dirName);
    state = state.copyWith(pathStack: newStack);
    fetchDir();
  }

  void goUp() {
    if (state.pathStack.isEmpty) {
      return;
    }

    final newStack = List<String>.from(state.pathStack)..removeLast();
    state = state.copyWith(pathStack: newStack);
    fetchDir();
  }

  Future<void> selectFile(FileItem file) async {
    try {
      final resolvedFile =
          file.content != null && file.sha != null
              ? file
              : await fetchFile(file.path);

      final newSelected = List<FileItem>.from(state.selectedFiles);
      final selectedIndex = newSelected.indexWhere(
        (selected) => selected.path == resolvedFile.path,
      );
      if (selectedIndex == -1) {
        newSelected.add(resolvedFile);
      } else {
        newSelected[selectedIndex] = resolvedFile;
      }

      final newItems =
          state.items
              .map(
                (candidate) =>
                    candidate.path == resolvedFile.path ? resolvedFile : candidate,
              )
              .toList();

      state = state.copyWith(
        selectedFiles: newSelected,
        items: newItems,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<FileItem> fetchFile(String path) async {
    final github = await _gitHub();
    final file = await github.fetchFileContent(
      owner: owner,
      repo: repo,
      path: path,
      branch: branch,
    );

    return FileItem(
      name: file.name,
      path: file.path,
      type: 'file',
      content: file.content,
      sha: file.sha,
    );
  }

  void deselectFile(FileItem file) {
    final newSelected = List<FileItem>.from(state.selectedFiles)
      ..removeWhere((candidate) => candidate.path == file.path);
    state = state.copyWith(selectedFiles: newSelected);
  }

  Future<List<FileItem>> listAllFiles({
    int maxDepth = 5,
    int maxFiles = 200,
  }) async {
    final github = await _gitHub();
    final resolvedBranch = branch ?? 'main';
    final tree = await github.fetchRepositoryTree(
      owner: owner,
      repo: repo,
      branch: resolvedBranch,
    );

    final files = <FileItem>[];
    for (final entry in tree) {
      if (entry.type != 'blob') {
        continue;
      }

      final depth = '/'.allMatches(entry.path).length;
      if (depth > maxDepth) {
        continue;
      }

      files.add(
        FileItem(
          name: entry.path.split('/').last,
          path: entry.path,
          type: 'file',
        ),
      );

      if (files.length >= maxFiles) {
        break;
      }
    }

    return files;
  }
}

final fileBrowserControllerProvider = StateNotifierProvider.family<
  FileBrowserController,
  FileBrowserState,
  RepoParams
>((ref, params) {
  return FileBrowserController(
    SecureStorageService(),
    owner: params.owner,
    repo: params.repo,
    branch: params.branch,
  );
});
