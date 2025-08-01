import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../file_browser/file_browser_controller.dart';
import '../auth/auth_controller.dart' as legacy_auth;
import '../auth/auth_service.dart';
import '../repo/repo_controller.dart';
import 'prompt_service.dart';

// Message model for chat
class ChatMessage {
  final bool isUser;
  final String text;
  final ReviewData? review;

  // Context bubble metadata for the user turn
  // Holds the exact files that were sent with that message
  final List<ContextFileMeta>? sentContext; // immutable snapshot per turn
  final DateTime? sentAt; // timestamp when the turn was sent
  final bool expandableContext; // controls UI expand/collapse

  ChatMessage({
    required this.isUser,
    required this.text,
    this.review,
    this.sentContext,
    this.sentAt,
    this.expandableContext = false,
  });

  ChatMessage copyWith({
    bool? isUser,
    String? text,
    ReviewData? review,
    List<ContextFileMeta>? sentContext,
    DateTime? sentAt,
    bool? expandableContext,
  }) {
    return ChatMessage(
      isUser: isUser ?? this.isUser,
      text: text ?? this.text,
      review: review ?? this.review,
      sentContext: sentContext ?? this.sentContext,
      sentAt: sentAt ?? this.sentAt,
      expandableContext: expandableContext ?? this.expandableContext,
    );
  }
}

// Review data for expandable review bubble
class ReviewData {
  final String fileName;
  final String oldContent;
  final String newContent;
  final String summary;
  
  ReviewData({
    required this.fileName,
    required this.oldContent,
    required this.newContent,
    required this.summary,
  });
}

class ContextFileMeta {
  final String name;
  final String preview; // first N lines snapshot for quick view

  ContextFileMeta({required this.name, required this.preview});
}

// Prompt state
class PromptState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;
  final ReviewData? pendingReview;
  final bool reviewExpanded;
  final String selectedModel;
  final String? lastIntent;
  final List<FileItem> repoContextFiles;
  final List<String> branches;
  final String? selectedBranch;
  final dynamic selectedRepo;

  PromptState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.pendingReview,
    this.reviewExpanded = false,
    this.selectedModel = 'gemini',
    this.lastIntent,
    this.repoContextFiles = const [],
    this.branches = const [],
    this.selectedBranch,
    this.selectedRepo,
  });

  PromptState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
    ReviewData? pendingReview,
    bool? reviewExpanded,
    String? selectedModel,
    String? lastIntent,
    List<FileItem>? repoContextFiles,
    List<String>? branches,
    String? selectedBranch,
    dynamic selectedRepo,
    bool clearError = false,
    bool clearPendingReview = false,
  }) {
    return PromptState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      pendingReview: clearPendingReview ? null : (pendingReview ?? this.pendingReview),
      reviewExpanded: reviewExpanded ?? this.reviewExpanded,
      selectedModel: selectedModel ?? this.selectedModel,
      lastIntent: lastIntent ?? this.lastIntent,
      repoContextFiles: repoContextFiles ?? this.repoContextFiles,
      branches: branches ?? this.branches,
      selectedBranch: selectedBranch ?? this.selectedBranch,
      selectedRepo: selectedRepo ?? this.selectedRepo,
    );
  }
}

// Prompt controller
class PromptController extends StateNotifier<PromptState> {
  final Ref ref;

  PromptController(this.ref) : super(PromptState(
    messages: [
      ChatMessage(
        isUser: false,
        text: "Hi! I'm /slash. How can I help you today?",
      ),
    ],
  )) {
    _initializeModel();
  }

  void _initializeModel() {
    final authState = ref.read(authControllerProvider);
    state = state.copyWith(selectedModel: authState.model);
  }

  void setSelectedModel(String model) {
    state = state.copyWith(selectedModel: model);
  }

  void setSelectedRepo(dynamic repo) {
    state = state.copyWith(selectedRepo: repo);
    if (repo != null) {
      _fetchBranchesForRepo(repo);
    }
  }

  void setSelectedBranch(String? branch) {
    state = state.copyWith(selectedBranch: branch);
  }

  void toggleReviewExpanded() {
    state = state.copyWith(reviewExpanded: !state.reviewExpanded);
  }

  void setRepoContextFiles(List<FileItem> files) {
    state = state.copyWith(repoContextFiles: files);
  }

  void removeContextFile(FileItem file) {
    final updatedFiles = List<FileItem>.from(state.repoContextFiles);
    updatedFiles.remove(file);
    state = state.copyWith(repoContextFiles: updatedFiles);
  }

  Future<void> addRepoContext() async {
    try {
      final repo = state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      if (repo == null) throw Exception('No repository selected.');
      
      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      final params = RepoParams(owner: owner, repo: repoName);
      
      final fileBrowserController = ref.read(
        fileBrowserControllerProvider(params).notifier,
      );
      
      final files = await fileBrowserController.listAllFiles();
      state = state.copyWith(repoContextFiles: files);
    } catch (e) {
      print('Error adding repo context: $e');
      _addMessage(ChatMessage(
        isUser: false,
        text: 'Failed to add repo context: ${friendlyErrorMessage(e.toString())}',
      ));
    }
  }
Future<void> submitPrompt(String prompt) async {
    if (prompt.trim().isEmpty) return;

    // Allow follow-ups: repo/context only required for code-edit actions inside _processPrompt.
    state = state.copyWith(isLoading: true, clearError: true);

    // Snapshot current selected context as "send-once" and then clear UI selection
    final sentContext = state.repoContextFiles
        .map((f) => ContextFileMeta(
              name: f.name,
              preview: (f.content ?? '').split('\n').take(12).join('\n'),
            ))
        .toList();

    // Add user message with compact context bubble metadata (expandable in UI)
    _addMessage(ChatMessage(
      isUser: true,
      text: prompt,
      sentContext: sentContext.isNotEmpty ? sentContext : null,
      sentAt: DateTime.now(),
      expandableContext: sentContext.isNotEmpty,
    ));

    // Clear the selected context after send (send-once behavior)
    if (state.repoContextFiles.isNotEmpty) {
      state = state.copyWith(repoContextFiles: []);
    }

    // Add inline thinking placeholder before calling the LLM
    _addMessage(ChatMessage(isUser: false, text: 'Thinking…'));

    try {
      await _processPrompt(prompt);

      // On success, replace the last assistant "Thinking…" bubble with the final response
      _replaceLastAssistantWithFinal();
    } catch (e, stackTrace) {
      print('[PromptController] Error: $e');
      print(stackTrace);

      state = state.copyWith(isLoading: false, error: e.toString());
      _replaceLastAssistantWithText(friendlyErrorMessage(e.toString()));
    }
  }
  // Future<void> submitPrompt(String prompt) async {
  //   if (prompt.trim().isEmpty) return;
    
  //   state = state.copyWith(
  //     isLoading: true,
  //     clearError: true,
  //   );
    
  //   _addMessage(ChatMessage(isUser: true, text: prompt));
    
  //   try {
  //     await _processPrompt(prompt);
  //   } catch (e, stackTrace) {
  //     print('[PromptController] Error: $e');
  //     print(stackTrace);
      
  //     state = state.copyWith(
  //       isLoading: false,
  //       error: e.toString(),
  //     );
      
  //     _addMessage(ChatMessage(
  //       isUser: false,
  //       text: friendlyErrorMessage(e.toString()),
  //     ));
  //   }
  // }

  Future<void> forceCodeEdit(String prompt) async {
    state = state.copyWith(isLoading: true);
    
    try {
      final authState = ref.read(authControllerProvider);
      final repo = state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      
      if (repo == null) throw Exception('No repository selected');
      
      final aiService = PromptService.createAIService(
        model: state.selectedModel,
        geminiKey: authState.geminiApiKey,
        openAIApiKey: null, // legacy OpenAI not used via new auth service
        openRouterApiKey: authState.openRouterApiKey,
        openRouterModel: authState.openRouterModel,
      );
      
      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      
      final contextFiles = state.repoContextFiles.isNotEmpty
          ? state.repoContextFiles
              .map((f) => {'name': f.name, 'content': f.content ?? ''})
              .toList()
          : null;

      if (contextFiles == null || contextFiles.isEmpty) {
        throw Exception('Please select at least one context file before submitting.');
      }

      final files = contextFiles;
      
      final summary = await PromptService.processCodeEditIntent(
        aiService: aiService,
        prompt: prompt,
        files: files,
      );
      
      final newContent = await PromptService.processCodeContent(
        aiService: aiService,
        prompt: prompt,
        files: files,
      );
      
      final fileName = files.isNotEmpty ? files[0]['name']! : 'unknown.dart';
      final oldContent = files.isNotEmpty ? files[0]['content']! : '';
      
      final review = ReviewData(
        fileName: fileName,
        oldContent: oldContent,
        newContent: newContent,
        summary: summary,
      );
      
      state = state.copyWith(
        isLoading: false,
        pendingReview: review,
        reviewExpanded: false,
      );
      
      _addMessage(ChatMessage(isUser: false, text: summary, review: review));
    } catch (e, stackTrace) {
      print('[PromptController] Force code edit error: $e');
      print(stackTrace);
      
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      
      _addMessage(ChatMessage(
        isUser: false,
        text: friendlyErrorMessage(e.toString()),
      ));
    }
  }

  Future<void> approveReview(ReviewData review, String prompt) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );
    
    try {
      final repo = state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      if (repo == null) throw Exception('No repository selected');
      
      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      
      final prUrl = await PromptService.createPullRequest(
        owner: owner,
        repo: repoName,
        fileName: review.fileName,
        newContent: review.newContent,
        prompt: prompt,
        summary: review.summary,
        selectedBranch: state.selectedBranch,
      );
      
      state = state.copyWith(
        isLoading: false,
        clearPendingReview: true,
      );
      
      _addMessage(ChatMessage(
        isUser: false,
        text: 'Pull request created! $prUrl',
      ));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      
      _addMessage(ChatMessage(
        isUser: false,
        text: friendlyErrorMessage(e.toString()),
      ));
    }
  }

  void rejectReview() {
    state = state.copyWith(
      clearPendingReview: true,
      reviewExpanded: false,
    );
    
    _addMessage(ChatMessage(
      isUser: false,
      text: 'Suggestion rejected.',
    ));
  }

  Future<void> _processPrompt(String prompt) async {
    final authState = ref.read(authControllerProvider);
    final repo = state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
    
    // Validate API keys (Gemini or OpenRouter)
    if ((state.selectedModel == 'gemini' &&
            (authState.geminiApiKey == null || authState.geminiApiKey!.isEmpty)) ||
        (state.selectedModel == 'openrouter' &&
            (authState.openRouterApiKey == null || authState.openRouterApiKey!.isEmpty)) ||
        authState.githubPat == null ||
        authState.githubPat!.isEmpty) {
      throw Exception('Missing API keys');
    }
    
    final aiService = PromptService.createAIService(
      model: state.selectedModel,
      geminiKey: authState.geminiApiKey,
      openAIApiKey: null, // legacy OpenAI not used via new auth service
      openRouterApiKey: authState.openRouterApiKey,
      openRouterModel: authState.openRouterModel,
    );
    
    // Classify intent
    final intent = await aiService.classifyIntent(prompt);
    state = state.copyWith(lastIntent: intent);
    
    // Construct the context to send for this turn:
    // 1) Prefer "send-once" context that was attached to this user message (last user turn).
    // 2) Else, fall back to inferred last edited file from previous ReviewData.
    // 3) Else, empty list.
    List<Map<String, String>> contextFiles = const <Map<String, String>>[];

    // Find last user message with sentContext metadata
    for (int i = state.messages.length - 1; i >= 0; i--) {
      final m = state.messages[i];
      if (m.isUser && m.sentContext != null && m.sentContext!.isNotEmpty) {
        contextFiles = m.sentContext!
            .map((c) => {'name': c.name, 'content': c.preview})
            .toList();
        break;
      }
    }

    // If nothing from sent-once context, infer from last review (use latest newContent as base)
    if (contextFiles.isEmpty) {
      String? inferredFileName;
      String? inferredOldContent;
      for (int i = state.messages.length - 1; i >= 0; i--) {
        final m = state.messages[i];
        if (!m.isUser && m.review != null) {
          inferredFileName = m.review!.fileName;
          inferredOldContent = m.review!.newContent;
          break;
        }
      }
      if (inferredFileName != null && inferredOldContent != null) {
        contextFiles = [
          {'name': inferredFileName, 'content': inferredOldContent}
        ];
      }
    }

    // Infer last edited file from the conversation if no explicit context is selected
    String? inferredFileName;
    String? inferredOldContent;
    for (int i = state.messages.length - 1; i >= 0; i--) {
      final m = state.messages[i];
      if (!m.isUser && m.review != null) {
        inferredFileName = m.review!.fileName;
        inferredOldContent = m.review!.newContent; // use last newContent as the current base
        break;
      }
    }

    if (contextFiles.isEmpty && inferredFileName != null && inferredOldContent != null) {
      contextFiles = [
        {'name': inferredFileName, 'content': inferredOldContent}
      ];
    }
    
    String response;
    ReviewData? review;
    
    switch (intent) {
      case 'code_edit':
        // Code edits require a repo to create PRs, but follow-ups can still generate previews.
        if (repo == null) {
          // Proceed in preview mode using inferred or sticky file, if available.
          final files = contextFiles;
          response = await PromptService.processCodeEditIntent(
            aiService: aiService,
            prompt: '[PREVIEW MODE] $prompt',
            files: files,
          );

          if (files.isNotEmpty) {
            final newContent = await PromptService.processCodeContent(
              aiService: aiService,
              prompt: '[PREVIEW MODE] $prompt',
              files: files,
            );
            final fileName = files[0]['name'] ?? 'unknown.dart';
            final oldContent = files[0]['content'] ?? '';
            review = ReviewData(
              fileName: fileName,
              oldContent: oldContent,
              newContent: newContent,
              summary: response,
            );
          }
          break;
        }

        // Repo present. Use sticky/inferred context if explicit selection is absent.
        final files = contextFiles;
        response = await PromptService.processCodeEditIntent(
          aiService: aiService,
          prompt: prompt,
          files: files,
        );

        if (files.isNotEmpty) {
          final newContent = await PromptService.processCodeContent(
            aiService: aiService,
            prompt: prompt,
            files: files,
          );
          final fileName = files[0]['name'] ?? 'unknown.dart';
          final oldContent = files[0]['content'] ?? '';
          review = ReviewData(
            fileName: fileName,
            oldContent: oldContent,
            newContent: newContent,
            summary: response,
          );
        } else {
          // If we still lack a concrete file, return a plan only. The user can confirm a file later.
          review = null;
        }
        break;
        
      case 'repo_question':
        if (repo == null) {
          response = "No repository selected. Please select a repository to ask questions about it.";
        } else {
          response = await PromptService.processRepoQuestion(
            aiService: aiService,
            prompt: prompt,
            repo: repo,
            contextFiles: contextFiles,
          );
        }
        break;
        
      default:
        response = await PromptService.processGeneralIntent(
          aiService: aiService,
          prompt: prompt,
          contextFiles: contextFiles,
        );
        break;
    }
    
    state = state.copyWith(
      isLoading: false,
      pendingReview: review,
      reviewExpanded: false,
    );
    
    _addMessage(ChatMessage(
      isUser: false,
      text: response,
      review: review,
    ));
  }

  Future<void> _fetchBranchesForRepo(dynamic repo) async {
    if (repo == null) return;
    
    state = state.copyWith(
      branches: [],
      selectedBranch: null,
    );
    
    try {
      final branches = await PromptService.fetchBranches(
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
      print('Error fetching branches: $e');
      state = state.copyWith(
        branches: [],
        selectedBranch: null,
      );
    }
  }

  void _addMessage(ChatMessage message) {
    final updatedMessages = List<ChatMessage>.from(state.messages);
    updatedMessages.add(message);
    state = state.copyWith(messages: updatedMessages);
  }

  // Replace the most recent assistant message (e.g., the "Thinking…" placeholder)
  void _replaceLastAssistantWithText(String newText) {
    final updated = List<ChatMessage>.from(state.messages);
    for (int i = updated.length - 1; i >= 0; i--) {
      if (!updated[i].isUser) {
        updated[i] = ChatMessage(isUser: false, text: newText, review: updated[i].review);
        break;
      }
    }
    state = state.copyWith(messages: updated);
  }

  // Convenience: replace placeholder with the final response already appended by _processPrompt
  void _replaceLastAssistantWithFinal() {
    // _processPrompt appends the final assistant message; remove the placeholder before it.
    final updated = List<ChatMessage>.from(state.messages);
    // Find the last two assistant messages: [placeholder, final]
    int lastAssistant = -1;
    for (int i = updated.length - 1; i >= 0; i--) {
      if (!updated[i].isUser) {
        lastAssistant = i;
        break;
      }
    }
    if (lastAssistant > 0) {
      // Remove the assistant bubble just before the last one if it contains "Thinking…"
      final maybePlaceholderIndex = lastAssistant - 1;
      if (maybePlaceholderIndex >= 0 && !updated[maybePlaceholderIndex].isUser && updated[maybePlaceholderIndex].text.trim() == 'Thinking…') {
        updated.removeAt(maybePlaceholderIndex);
      }
    }
    state = state.copyWith(messages: updated, isLoading: false);
  }
}

// Provider
final promptControllerProvider = StateNotifierProvider<PromptController, PromptState>((ref) {
  return PromptController(ref);
});
