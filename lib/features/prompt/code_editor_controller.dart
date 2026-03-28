import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';

import '../../features/auth/auth_controller.dart';
import '../file_browser/file_browser_controller.dart';
import 'code_editor_service.dart';
import 'code_page.dart';
import 'prompt_service.dart' as prompt_service;

final externalEditRequestProvider = StateProvider<ExternalEditRequest?>(
  (ref) => null,
);

class ExternalEditRequest {
  final String fileName;
  final String code;
  final String? originalContent;
  final dynamic repo;
  final String? branch;
  final String? baseSha;

  const ExternalEditRequest({
    required this.fileName,
    required this.code,
    this.originalContent,
    this.repo,
    this.branch,
    this.baseSha,
  });
}

final codeEditorControllerProvider =
    StateNotifierProvider<CodeEditorController, CodeEditorState>(
      (ref) => CodeEditorController(ref.read(codeEditorServiceProvider)),
    );

class CodeEditorState {
  final dynamic selectedRepo;
  final String? selectedFilePath;
  final String? selectedFileSha;
  final String? fileContent;
  final bool isLoading;
  final List<String> branches;
  final String? selectedBranch;
  final bool isCommitting;
  final List<ChatMessage> chatMessages;
  final bool chatLoading;
  final String? pendingEdit;
  final String codeModel; // 'openai' | 'openrouter'
  final List<String> recentFiles;
  final DateTime? lastSyncedAt;

  const CodeEditorState({
    this.selectedRepo,
    this.selectedFilePath,
    this.selectedFileSha,
    this.fileContent,
    this.isLoading = false,
    this.branches = const [],
    this.selectedBranch,
    this.isCommitting = false,
    this.chatMessages = const [],
    this.chatLoading = false,
    this.pendingEdit,
    this.codeModel = 'openai',
    this.recentFiles = const [],
    this.lastSyncedAt,
  });

  CodeEditorState copyWith({
    Object? selectedRepo = _codeUnset,
    Object? selectedFilePath = _codeUnset,
    Object? selectedFileSha = _codeUnset,
    Object? fileContent = _codeUnset,
    bool? isLoading,
    List<String>? branches,
    Object? selectedBranch = _codeUnset,
    bool? isCommitting,
    List<ChatMessage>? chatMessages,
    bool? chatLoading,
    Object? pendingEdit = _codeUnset,
    String? codeModel,
    List<String>? recentFiles,
    Object? lastSyncedAt = _codeUnset,
  }) {
    return CodeEditorState(
      selectedRepo:
          identical(selectedRepo, _codeUnset)
              ? this.selectedRepo
              : selectedRepo,
      selectedFilePath:
          identical(selectedFilePath, _codeUnset)
              ? this.selectedFilePath
              : selectedFilePath as String?,
      selectedFileSha:
          identical(selectedFileSha, _codeUnset)
              ? this.selectedFileSha
              : selectedFileSha as String?,
      fileContent:
          identical(fileContent, _codeUnset)
              ? this.fileContent
              : fileContent as String?,
      isLoading: isLoading ?? this.isLoading,
      branches: branches ?? this.branches,
      selectedBranch:
          identical(selectedBranch, _codeUnset)
              ? this.selectedBranch
              : selectedBranch as String?,
      isCommitting: isCommitting ?? this.isCommitting,
      chatMessages: chatMessages ?? this.chatMessages,
      chatLoading: chatLoading ?? this.chatLoading,
      pendingEdit:
          identical(pendingEdit, _codeUnset)
              ? this.pendingEdit
              : pendingEdit as String?,
      codeModel: codeModel ?? this.codeModel,
      recentFiles: recentFiles ?? this.recentFiles,
      lastSyncedAt:
          identical(lastSyncedAt, _codeUnset)
              ? this.lastSyncedAt
              : lastSyncedAt as DateTime?,
    );
  }
}

const Object _codeUnset = Object();

class CodeEditorController extends StateNotifier<CodeEditorState> {
  final CodeEditorService _service;

  CodeEditorController(this._service)
    : super(
        const CodeEditorState(
          chatMessages: [
            ChatMessage(
              isUser: false,
              text:
                  "I'm /slash. Ask for an edit, an explanation, or pull the latest file before you push.",
            ),
          ],
        ),
      );

  void handleExternalEdit(
    ExternalEditRequest request,
    CodeController codeController,
  ) {
    state = state.copyWith(
      selectedRepo: request.repo ?? state.selectedRepo,
      selectedBranch: request.branch ?? state.selectedBranch,
      selectedFilePath: request.fileName,
      selectedFileSha: request.baseSha ?? state.selectedFileSha,
      fileContent: request.originalContent,
      pendingEdit: null,
      recentFiles: _withRecentFile(request.fileName),
      lastSyncedAt: DateTime.now(),
    );
    codeController.text = request.code;

    if (request.repo != null) {
      _fetchBranchesForRepo(request.repo, preferredBranch: request.branch);
    }
  }

  void selectRepo(dynamic repo, {String? preferredBranch}) {
    state = state.copyWith(
      selectedRepo: repo,
      selectedFilePath: null,
      selectedFileSha: null,
      fileContent: null,
      branches: const [],
      selectedBranch: preferredBranch,
      pendingEdit: null,
      recentFiles: const [],
      lastSyncedAt: null,
    );
    _fetchBranchesForRepo(repo, preferredBranch: preferredBranch);
  }

  void selectBranch(String branch, dynamic selectedRepo) {
    state = state.copyWith(
      selectedRepo: selectedRepo,
      selectedBranch: branch,
      selectedFilePath: null,
      selectedFileSha: null,
      fileContent: null,
      pendingEdit: null,
      lastSyncedAt: null,
    );
  }

  void setCodeModel(String model) {
    state = state.copyWith(
      codeModel: model == 'openrouter' ? 'openrouter' : 'openai',
    );
  }

  Future<void> _fetchBranchesForRepo(
    dynamic repo, {
    String? preferredBranch,
  }) async {
    if (repo == null) {
      return;
    }

    state = state.copyWith(branches: const [], selectedBranch: preferredBranch);

    try {
      final branches = await _service.fetchBranches(
        owner: repo['owner']['login'],
        repo: repo['name'],
      );

      final defaultBranch = (repo['default_branch'] ?? '').toString();
      final selectedBranch =
          branches.contains(preferredBranch)
              ? preferredBranch
              : (branches.contains(defaultBranch)
                  ? defaultBranch
                  : (branches.isNotEmpty ? branches.first : null));

      state = state.copyWith(
        branches: branches,
        selectedBranch: selectedBranch,
      );
    } catch (_) {
      state = state.copyWith(branches: const [], selectedBranch: null);
    }
  }

  Future<void> loadFile(
    String path,
    RepoParams params,
    WidgetRef ref,
    CodeController codeController,
  ) async {
    state = state.copyWith(isLoading: true);

    try {
      final fileBrowserController = ref.read(
        fileBrowserControllerProvider(params).notifier,
      );

      var file = ref
          .read(fileBrowserControllerProvider(params))
          .items
          .cast<FileItem?>()
          .firstWhere(
            (candidate) => candidate?.path == path,
            orElse: () => null,
          );

      file ??= await fileBrowserController.fetchFile(path);

      if (file.content == null) {
        await fileBrowserController.selectFile(file);
        final updatedState = ref.read(fileBrowserControllerProvider(params));
        file = updatedState.items.firstWhere(
          (candidate) => candidate.path == path,
        );
      }

      state = state.copyWith(
        selectedFilePath: path,
        selectedFileSha: file.sha,
        fileContent: file.content ?? '',
        isLoading: false,
        pendingEdit: null,
        recentFiles: _withRecentFile(path),
        lastSyncedAt: DateTime.now(),
      );
      codeController.text = file.content ?? '';
    } catch (e) {
      state = state.copyWith(isLoading: false);
      if (codeController.text.isEmpty) {
        codeController.text = '// Failed to load file: $e';
      }
    }
  }

  Future<void> commitAndPushFile(
    BuildContext context,
    String currentContent,
  ) async {
    if (state.selectedFilePath == null ||
        state.selectedRepo == null ||
        state.selectedBranch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: SlashText('Pick a repo, branch, and file before pushing.'),
        ),
      );
      return;
    }

    final commitMessage = await _showCommitDialog(context);
    if (commitMessage == null || commitMessage.trim().isEmpty) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    if (state.fileContent != null && currentContent == state.fileContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: SlashText('No local changes to push yet.')),
      );
      return;
    }

    state = state.copyWith(isCommitting: true);

    try {
      await _service.commitFile(
        owner: state.selectedRepo['owner']['login'],
        repo: state.selectedRepo['name'],
        branch: state.selectedBranch!,
        path: state.selectedFilePath!,
        content: currentContent,
        message: commitMessage,
        expectedSha: state.selectedFileSha,
      );

      final latest = await _service.pullLatestFile(
        owner: state.selectedRepo['owner']['login'],
        repo: state.selectedRepo['name'],
        branch: state.selectedBranch!,
        path: state.selectedFilePath!,
      );

      state = state.copyWith(
        isCommitting: false,
        selectedFileSha: latest.sha,
        fileContent: latest.content,
        pendingEdit: null,
        recentFiles: _withRecentFile(state.selectedFilePath!),
        lastSyncedAt: DateTime.now(),
      );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: SlashText('Commit and push successful.')),
      );
    } catch (e) {
      state = state.copyWith(isCommitting: false);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: SlashText('Push failed: $e')));
    }
  }

  Future<void> pullLatestIntoEditor(
    BuildContext context,
    CodeController codeController,
  ) async {
    if (state.selectedFilePath == null ||
        state.selectedRepo == null ||
        state.selectedBranch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: SlashText('Select a file before pulling.')),
      );
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final latest = await _service.pullLatestFile(
        owner: state.selectedRepo['owner']['login'],
        repo: state.selectedRepo['name'],
        branch: state.selectedBranch!,
        path: state.selectedFilePath!,
      );

      final currentBuffer = codeController.text;
      final hasUnsavedChanges = currentBuffer != (state.fileContent ?? '');
      final isAlreadyCurrent =
          latest.sha == state.selectedFileSha &&
          latest.content == (state.fileContent ?? '');

      if (isAlreadyCurrent) {
        state = state.copyWith(isLoading: false, lastSyncedAt: DateTime.now());
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: SlashText('This file is already up to date.'),
          ),
        );
        return;
      }

      var shouldReplace = true;
      if (hasUnsavedChanges && context.mounted) {
        shouldReplace =
            await showDialog<bool>(
              context: context,
              builder: (dialogContext) {
                return AlertDialog(
                  title: const SlashText('Replace local edits?'),
                  content: const SlashText(
                    'Pulling the latest version will replace your current editor buffer with the remote file.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const SlashText('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const SlashText('Replace'),
                    ),
                  ],
                );
              },
            ) ??
            false;
      }

      if (shouldReplace) {
        codeController.text = latest.content;
        state = state.copyWith(
          isLoading: false,
          fileContent: latest.content,
          selectedFileSha: latest.sha,
          pendingEdit: null,
          recentFiles: _withRecentFile(state.selectedFilePath!),
          lastSyncedAt: DateTime.now(),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: SlashText('Pulled the latest remote file.'),
            ),
          );
        }
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: SlashText('Pull failed: $e')));
    }
  }

  Future<String?> _showCommitDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final path = state.selectedFilePath ?? 'file';
        final controller = TextEditingController(
          text: 'Update ${path.split('/').last}',
        );
        return AlertDialog(
          title: const SlashText('Commit message'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Describe the change you are pushing',
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const SlashText('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const SlashText('Push'),
            ),
          ],
        );
      },
    );
  }

  Future<void> handleChatSend(
    String prompt,
    String codeContext,
    String fileName,
    WidgetRef ref,
  ) async {
    final updatedMessages = List<ChatMessage>.from(state.chatMessages)
      ..add(ChatMessage(isUser: true, text: prompt));
    state = state.copyWith(
      chatMessages: updatedMessages,
      chatLoading: true,
      pendingEdit: null,
    );

    try {
      final authState = ref.read(authControllerProvider);
      final aiService = prompt_service.PromptService.createAIService(
        model: state.codeModel,
        openAIApiKey: authState.openAIApiKey,
        openAIModel: authState.openAIModel,
        openRouterApiKey: authState.openRouterApiKey,
        openRouterModel: authState.openRouterModel,
      );
      final editorPath = state.selectedFilePath ?? fileName;
      final repoContext = await prompt_service.PromptService.resolveContext(
        prompt: prompt,
        repo:
            state.selectedRepo == null
                ? null
                : Map<String, dynamic>.from(state.selectedRepo),
        branch: state.selectedBranch,
        selectedFiles: [
          FileItem(
            name: editorPath.split('/').last,
            path: editorPath,
            type: 'file',
            content: codeContext,
            sha: state.selectedFileSha,
          ),
        ],
      );
      final contextFiles =
          repoContext.files.isNotEmpty
              ? repoContext.files
              : [
                {
                  'name': editorPath,
                  'content': codeContext,
                  if ((state.selectedFileSha ?? '').isNotEmpty)
                    'sha': state.selectedFileSha!,
                },
              ];
      final toolSummary =
          repoContext.toolSummary.isNotEmpty
              ? repoContext.toolSummary
              : const ['editor_context:current_file'];

      final intent = await aiService.classifyIntent(prompt);
      if (intent == 'code_edit') {
        final summary = await prompt_service
            .PromptService.processCodeEditIntent(
          aiService: aiService,
          prompt: prompt,
          files: contextFiles,
          toolSummary: toolSummary,
        );

        final newContent = await prompt_service
            .PromptService.processCodeContent(
          aiService: aiService,
          prompt: prompt,
          files: contextFiles,
          toolSummary: toolSummary,
        );

        final finalMessages = List<ChatMessage>.from(state.chatMessages)
          ..add(ChatMessage(isUser: false, text: summary));

        state = state.copyWith(
          chatMessages: finalMessages,
          chatLoading: false,
          pendingEdit: newContent,
        );
      } else {
        final answer = await prompt_service.PromptService.processGeneralIntent(
          aiService: aiService,
          prompt: prompt,
          contextFiles: contextFiles,
          toolSummary: toolSummary,
        );

        final finalMessages = List<ChatMessage>.from(state.chatMessages)
          ..add(ChatMessage(isUser: false, text: answer));

        state = state.copyWith(chatMessages: finalMessages, chatLoading: false);
      }
    } catch (e) {
      final finalMessages = List<ChatMessage>.from(state.chatMessages)
        ..add(ChatMessage(isUser: false, text: 'Something went wrong: $e'));

      state = state.copyWith(chatMessages: finalMessages, chatLoading: false);
    }
  }

  void applyPendingEdit(CodeController codeController) {
    if (state.pendingEdit == null) {
      return;
    }

    codeController.text = state.pendingEdit!;
    state = state.copyWith(pendingEdit: null);
  }

  void discardPendingEdit() {
    state = state.copyWith(pendingEdit: null);
  }

  void revertToLastSynced(CodeController codeController) {
    if (state.fileContent == null) {
      return;
    }

    codeController.text = state.fileContent!;
    state = state.copyWith(pendingEdit: null);
  }

  List<String> _withRecentFile(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return state.recentFiles;
    }

    return [
      normalized,
      ...state.recentFiles.where((candidate) => candidate != normalized),
    ].take(8).toList();
  }
}
