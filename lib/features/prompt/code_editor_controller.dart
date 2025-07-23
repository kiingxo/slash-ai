import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import '../file_browser/file_browser_controller.dart';
import '../../features/auth/auth_controller.dart';
import 'code_editor_service.dart';
import 'code_page.dart';

// Provider for external edit requests
final externalEditRequestProvider = StateProvider<ExternalEditRequest?>(
  (ref) => null,
);

class ExternalEditRequest {
  final String fileName;
  final String code;
  ExternalEditRequest({required this.fileName, required this.code});
}

// Main controller provider
final codeEditorControllerProvider = StateNotifierProvider<CodeEditorController, CodeEditorState>(
  (ref) => CodeEditorController(ref.read(codeEditorServiceProvider)),
);

// State class
class CodeEditorState {
  final dynamic selectedRepo;
  final String? selectedFilePath;
  final String? fileContent;
  final bool isLoading;
  final List<String> branches;
  final String? selectedBranch;
  final bool isCommitting;
  final List<ChatMessage> chatMessages;
  final bool chatLoading;
  final String? pendingEdit;

  CodeEditorState({
    this.selectedRepo,
    this.selectedFilePath,
    this.fileContent,
    this.isLoading = false,
    this.branches = const [],
    this.selectedBranch,
    this.isCommitting = false,
    this.chatMessages = const [],
    this.chatLoading = false,
    this.pendingEdit,
  });

  CodeEditorState copyWith({
    dynamic selectedRepo,
    String? selectedFilePath,
    String? fileContent,
    bool? isLoading,
    List<String>? branches,
    String? selectedBranch,
    bool? isCommitting,
    List<ChatMessage>? chatMessages,
    bool? chatLoading,
    String? pendingEdit,
  }) {
    return CodeEditorState(
      selectedRepo: selectedRepo ?? this.selectedRepo,
      selectedFilePath: selectedFilePath ?? this.selectedFilePath,
      fileContent: fileContent ?? this.fileContent,
      isLoading: isLoading ?? this.isLoading,
      branches: branches ?? this.branches,
      selectedBranch: selectedBranch ?? this.selectedBranch,
      isCommitting: isCommitting ?? this.isCommitting,
      chatMessages: chatMessages ?? this.chatMessages,
      chatLoading: chatLoading ?? this.chatLoading,
      pendingEdit: pendingEdit ?? this.pendingEdit,
    );
  }
}

// Controller class
class CodeEditorController extends StateNotifier<CodeEditorState> {
  final CodeEditorService _service;

  CodeEditorController(this._service) : super(CodeEditorState(
    chatMessages: [
      ChatMessage(isUser: false, text: "Hi! I'm /slash. Ask me about your code!"),
    ],
  ));

  void handleExternalEdit(ExternalEditRequest request, CodeController codeController) {
    state = state.copyWith(
      selectedFilePath: request.fileName,
      fileContent: request.code,
    );
    codeController.text = request.code;
  }

  void selectRepo(dynamic repo) {
    state = state.copyWith(
      selectedRepo: repo,
      selectedFilePath: null,
      fileContent: null,
      branches: [],
      selectedBranch: null,
    );
    _fetchBranchesForRepo(repo);
  }

  void selectBranch(String branch, dynamic selectedRepo) {
    state = state.copyWith(
      selectedBranch: branch,
      selectedFilePath: null,
      fileContent: null,
    );
  }

  Future<void> _fetchBranchesForRepo(dynamic repo) async {
    if (repo == null) return;
    
    state = state.copyWith(
      branches: [],
      selectedBranch: null,
    );

    try {
      final branches = await _service.fetchBranches(
        owner: repo['owner']['login'],
        repo: repo['name'],
      );
      
      final selectedBranch = branches.contains('main')
          ? 'main'
          : (branches.isNotEmpty ? branches[0] : null);

      state = state.copyWith(
        branches: branches,
        selectedBranch: selectedBranch,
      );
    } catch (e) {
      state = state.copyWith(
        branches: [],
        selectedBranch: null,
      );
    }
  }

  Future<void> loadFile(String path, RepoParams params, WidgetRef ref, CodeController codeController) async {
    state = state.copyWith(isLoading: true);
    
    final fileBrowserController = ref.read(fileBrowserControllerProvider(params).notifier);
    final fileBrowserState = ref.read(fileBrowserControllerProvider(params));
    
    final file = fileBrowserState.items.where((f) => f.path == path).isNotEmpty
        ? fileBrowserState.items.firstWhere((f) => f.path == path)
        : null;

    if (file != null && file.content != null) {
      state = state.copyWith(
        selectedFilePath: path,
        fileContent: file.content,
        isLoading: false,
      );
      codeController.text = file.content!;
    } else if (file != null) {
      // Fetch file content if not loaded
      await fileBrowserController.selectFile(file);
      
      // Get the updated file from state
      final updatedState = ref.read(fileBrowserControllerProvider(params));
      final updatedFile = updatedState.items.where((f) => f.path == path).isNotEmpty
          ? updatedState.items.firstWhere((f) => f.path == path)
          : null;
      
      final content = updatedFile?.content ?? '';
      state = state.copyWith(
        selectedFilePath: path,
        fileContent: content,
        isLoading: false,
      );
      codeController.text = content;
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> commitAndPushFile(BuildContext context, String currentContent) async {
    if (state.selectedFilePath == null ||
        state.fileContent == null ||
        state.selectedRepo == null ||
        state.selectedBranch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No file selected or missing branch/repo.'),
        ),
      );
      return;
    }

    final commitMessage = await _showCommitDialog(context);
    if (commitMessage == null || commitMessage.trim().isEmpty) return;

    state = state.copyWith(isCommitting: true);

    try {
      await _service.commitFile(
        owner: state.selectedRepo['owner']['login'],
        repo: state.selectedRepo['name'],
        branch: state.selectedBranch!,
        path: state.selectedFilePath!,
        content: currentContent,
        message: commitMessage,
      );

      state = state.copyWith(isCommitting: false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commit & push successful!')),
      );
    } catch (e) {
      state = state.copyWith(isCommitting: false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Commit failed: $e')),
      );
    }
  }

  Future<String?> _showCommitDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        String msg = '';
        return AlertDialog(
          title: const Text('Commit Message'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter commit message'),
            onChanged: (val) => msg = val,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(msg),
              child: const Text('Commit'),
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
    // Add user message
    final updatedMessages = List<ChatMessage>.from(state.chatMessages)
      ..add(ChatMessage(isUser: true, text: prompt));
    
    state = state.copyWith(
      chatMessages: updatedMessages,
      chatLoading: true,
      pendingEdit: null,
    );

    try {
      final authState = ref.read(authControllerProvider);
      final result = await _service.handleChatRequest(
        prompt: prompt,
        codeContext: codeContext,
        fileName: fileName,
        geminiKey: authState.geminiApiKey,
        openAIApiKey: authState.openAIApiKey,
        model: authState.model,
      );

      final finalMessages = List<ChatMessage>.from(state.chatMessages)
        ..add(ChatMessage(isUser: false, text: result.response));

      state = state.copyWith(
        chatMessages: finalMessages,
        chatLoading: false,
        pendingEdit: result.pendingEdit,
      );
    } catch (e) {
      final errorMessages = List<ChatMessage>.from(state.chatMessages)
        ..add(ChatMessage(isUser: false, text: 'Error: ${e.toString()}'));

      state = state.copyWith(
        chatMessages: errorMessages,
        chatLoading: false,
      );
    }
  }

  void applyAICodeEdit(CodeController codeController) {
    if (state.pendingEdit != null) {
      codeController.text = state.pendingEdit!;
      
      final updatedMessages = List<ChatMessage>.from(state.chatMessages)
        ..add(ChatMessage(isUser: false, text: '✅ Edit applied to the code!'));
      
      state = state.copyWith(
        pendingEdit: null,
        chatMessages: updatedMessages,
      );
    }
  }
}