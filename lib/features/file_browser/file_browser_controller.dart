import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../services/secure_storage_service.dart';

class RepoParams {
  final String owner;
  final String repo;
  const RepoParams({required this.owner, required this.repo});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepoParams &&
          runtimeType == other.runtimeType &&
          owner == other.owner &&
          repo == other.repo;

  @override
  int get hashCode => owner.hashCode ^ repo.hashCode;
}

class FileItem {
  final String name;
  final String path;
  final String type; // 'file' or 'dir'
  final String? content;
  FileItem({required this.name, required this.path, required this.type, this.content});

  factory FileItem.fromJson(Map<String, dynamic> json) => FileItem(
    name: json['name'],
    path: json['path'],
    type: json['type'],
    content: json['content'],
  );
}

class FileBrowserState {
  final bool isLoading;
  final String? error;
  final List<FileItem> items;
  final List<String> pathStack;
  final List<FileItem> selectedFiles;
  FileBrowserState({
    this.isLoading = false,
    this.error,
    this.items = const [],
    this.pathStack = const [],
    this.selectedFiles = const [],
  });

  FileBrowserState copyWith({
    bool? isLoading,
    String? error,
    List<FileItem>? items,
    List<String>? pathStack,
    List<FileItem>? selectedFiles,
  }) => FileBrowserState(
    isLoading: isLoading ?? this.isLoading,
    error: error,
    items: items ?? this.items,
    pathStack: pathStack ?? this.pathStack,
    selectedFiles: selectedFiles ?? this.selectedFiles,
  );
}

class FileBrowserController extends StateNotifier<FileBrowserState> {
  final SecureStorageService _storage;
  final String owner;
  final String repo;
  FileBrowserController(this._storage, {required this.owner, required this.repo}) : super(FileBrowserState()) {
    fetchDir();
  }

  String get currentPath => state.pathStack.isEmpty ? '' : state.pathStack.join('/');

  Future<void> fetchDir([String? path]) async {
    print('FileBrowser: fetchDir called for owner=$owner, repo=$repo, path=${path ?? currentPath}');
    state = state.copyWith(isLoading: true, error: null);
    try {
      final pat = await _storage.getApiKey('github_pat');
      if (pat == null || pat.isEmpty) throw Exception('GitHub PAT not found');
      final dio = Dio(BaseOptions(
        baseUrl: 'https://api.github.com/',
        headers: {'Authorization': 'token $pat'},
      ));
      final endpoint = '/repos/$owner/$repo/contents/${path ?? currentPath}';
      print('FileBrowser: GET $endpoint');
      final res = await dio.get(endpoint);
      final data = res.data;
      print('FileBrowser: Response type: ${data.runtimeType}, value: ${data is List ? "List with ${data.length} items" : data.toString()}');
      if (data is List) {
        final items = data.map((e) => FileItem.fromJson(e)).toList();
        print('FileBrowser: Parsed items: ${items.map((e) => e.name).toList()}');
        state = state.copyWith(isLoading: false, items: items);
      } else if (data is Map && data['type'] == 'file') {
      
        state = state.copyWith(isLoading: false, error: 'This is a file, not a directory.');
      } else {
        print('FileBrowser: Unexpected response: $data');
        state = state.copyWith(isLoading: false, error: 'Unexpected response from GitHub API.');
      }
    } catch (e, st) {
      print('File browser error: $e');
      print('Stack trace: $st');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void enterDir(String dirName) {
    final newStack = List<String>.from(state.pathStack)..add(dirName);
    state = state.copyWith(pathStack: newStack);
    fetchDir();
  }

  void goUp() {
    if (state.pathStack.isNotEmpty) {
      final newStack = List<String>.from(state.pathStack)..removeLast();
      state = state.copyWith(pathStack: newStack);
      fetchDir();
    }
  }

  Future<void> selectFile(FileItem file) async {
    // Fetch file content if not already loaded
    if (file.content == null) {
      try {
        final pat = await _storage.getApiKey('github_pat');
        final dio = Dio(BaseOptions(
          baseUrl: 'https://api.github.com/',
          headers: {'Authorization': 'token $pat'},
        ));
        final res = await dio.get('/repos/$owner/$repo/contents/${file.path}');
        final content = res.data['content'];
        final decoded = String.fromCharCodes(
          base64Decode(content.replaceAll('\n', '')),
        );
        final updatedFile = FileItem(
          name: file.name,
          path: file.path,
          type: file.type,
          content: decoded,
        );
        final newSelected = List<FileItem>.from(state.selectedFiles)..add(updatedFile);
        state = state.copyWith(selectedFiles: newSelected);
      } catch (e, st) {
        print('File select error: $e\n$st');
        state = state.copyWith(error: e.toString());
      }
    } else {
      final newSelected = List<FileItem>.from(state.selectedFiles)..add(file);
      state = state.copyWith(selectedFiles: newSelected);
    }
  }

  void deselectFile(FileItem file) {
    final newSelected = List<FileItem>.from(state.selectedFiles)..removeWhere((f) => f.path == file.path);
    state = state.copyWith(selectedFiles: newSelected);
  }

  // Recursively list all files in the repo, with depth and file count limits
  Future<List<FileItem>> listAllFiles({int maxDepth = 5, int maxFiles = 200}) async {
    final List<FileItem> allFiles = [];
    Future<void> _recurse(String path, int depth) async {
      if (depth > maxDepth || allFiles.length > maxFiles) return;
      final pat = await _storage.getApiKey('github_pat');
      if (pat == null || pat.isEmpty) throw Exception('GitHub PAT not found');
      final dio = Dio(BaseOptions(
        baseUrl: 'https://api.github.com/',
        headers: {'Authorization': 'token $pat'},
      ));
      final endpoint = '/repos/$owner/$repo/contents/${path.isEmpty ? '' : path}';
      final res = await dio.get(endpoint);
      final data = res.data;
      if (data is List) {
        for (final e in data) {
          final item = FileItem.fromJson(e);
          if (item.type == 'file') {
            allFiles.add(item);
            if (allFiles.length >= maxFiles) return;
          } else if (item.type == 'dir') {
            await _recurse(item.path, depth + 1);
            if (allFiles.length >= maxFiles) return;
          }
        }
      }
    }
    await _recurse('', 0);
    return allFiles;
  }
}

final fileBrowserControllerProvider = StateNotifierProvider.family<FileBrowserController, FileBrowserState, RepoParams>((ref, params) {
  return FileBrowserController(
    SecureStorageService(),
    owner: params.owner,
    repo: params.repo,
  );
}); 