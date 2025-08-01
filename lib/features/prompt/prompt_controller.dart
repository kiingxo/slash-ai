import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'conversation_context.dart';
import 'prompt_service.dart';
import '../repo/repo_controller.dart';
import '../file_browser/file_browser_controller.dart';

import '../../services/secure_storage_service.dart';
import 'models/chat_message.dart';
import 'models/review_data.dart';

/// Agentic prompt pipeline controller:
/// - Auto-retrieves relevant context files from a folder scope (no mandatory manual selection)
/// - Allows optional manual context override (toggle)
/// - Uses improved prompts: summary, plan, code-edit (diff-first optional), and answer
/// - Persists conversational context for follow-ups
///
/// Provider stays compatible with existing UI but changes defaults:
/// - manualContextRequired = false by default (previously you enforced selection)
/// - scopeRoot defaults to 'lib' for indexing
final promptControllerProvider =
    StateNotifierProvider<PromptController, PromptState>((ref) {
  final repo = ref.read(repoControllerProvider);
  return PromptController(ref: ref, repoState: repo);
});

class PromptState {
  final bool isLoading;
  final String? error;

  // conversation messages
  final List<ChatMessage> messages;

  // Agentic options
  final String scopeRoot;
  final bool manualContextEnabled; // if true, user-chosen context overrides auto
  final List<FileItem> repoContextFiles; // optional manual override

  // Model choice and repo selection
  final String selectedModel;
  final dynamic selectedRepo;
  final List<String> branches;
  final String? selectedBranch;

  // Review UI state (preserve compatibility)
  final ReviewData? pendingReview;
  final bool reviewExpanded;

  // derived/metadata
  final String lastIntent;

  PromptState({
    this.isLoading = false,
    this.error,
    this.messages = const [],
    this.scopeRoot = 'lib',
    this.manualContextEnabled = false,
    this.repoContextFiles = const [],
    this.selectedModel = 'OpenAI',
    this.selectedRepo,
    this.branches = const [],
    this.selectedBranch,
    this.pendingReview,
    this.reviewExpanded = false,
    this.lastIntent = '',
  });

  PromptState copyWith({
    bool? isLoading,
    String? error,
    List<ChatMessage>? messages,
    String? scopeRoot,
    bool? manualContextEnabled,
    List<FileItem>? repoContextFiles,
    String? selectedModel,
    dynamic selectedRepo,
    List<String>? branches,
    String? selectedBranch,
    ReviewData? pendingReview,
    bool? reviewExpanded,
    String? lastIntent,
  }) {
    return PromptState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      messages: messages ?? this.messages,
      scopeRoot: scopeRoot ?? this.scopeRoot,
      manualContextEnabled: manualContextEnabled ?? this.manualContextEnabled,
      repoContextFiles: repoContextFiles ?? this.repoContextFiles,
      selectedModel: selectedModel ?? this.selectedModel,
      selectedRepo: selectedRepo ?? this.selectedRepo,
      branches: branches ?? this.branches,
      selectedBranch: selectedBranch ?? this.selectedBranch,
      pendingReview: pendingReview ?? this.pendingReview,
      reviewExpanded: reviewExpanded ?? this.reviewExpanded,
      lastIntent: lastIntent ?? this.lastIntent,
    );
  }
}

class PromptController extends StateNotifier<PromptState> {
  final Ref ref;
  final RepoState repoState;
  ConversationContext? _ctx;

  PromptController({required this.ref, required this.repoState})
      : super(PromptState(
          selectedModel: 'OpenAI',
        ));

  // UI toggles
  void setManualContextEnabled(bool on) {
    state = state.copyWith(manualContextEnabled: on);
  }

  // Convenience: disable manual context selection entirely
  void disableManualContext() {
    state = state.copyWith(manualContextEnabled: false, repoContextFiles: []);
  }

  void setScopeRoot(String root) async {
    state = state.copyWith(scopeRoot: root);
    _ensureContext(scopeRoot: root, rebuild: true);
  }

  void setSelectedModel(String model) {
    state = state.copyWith(selectedModel: model);
  }

  void setSelectedRepo(dynamic repo) {
    state = state.copyWith(selectedRepo: repo);
    // rebuild index for new repo/scope
    _ensureContext(scopeRoot: state.scopeRoot, rebuild: true);
  }

  void setSelectedBranch(String? branch) {
    state = state.copyWith(selectedBranch: branch);
  }

  void setRepoContextFiles(List<FileItem> files) {
    state = state.copyWith(repoContextFiles: files);
  }

  void removeContextFile(FileItem file) {
    final updated = [...state.repoContextFiles]..removeWhere((f) => f.path == file.path);
    state = state.copyWith(repoContextFiles: updated);
  }

  Future<void> submitPrompt(String prompt) async {
    try {
      // Ensure context/index ready
      await _ensureContext(scopeRoot: state.scopeRoot);

      // Optimistic UI: append user message immediately so it appears before reply
      final optimisticMessages = [...state.messages, ChatMessage(isUser: true, text: prompt)];
      state = state.copyWith(isLoading: true, error: null, messages: optimisticMessages);

      // Build AI service (use existing SecureStorageService used elsewhere)
      final storage = SecureStorageService();
      final geminiKey = await storage.getApiKey('gemini_api_key');
      final openaiKey = await storage.getApiKey('openai_api_key');
      final model = state.selectedModel.toLowerCase() == 'gemini' ? 'gemini' : 'openai';
      final aiService = PromptService.createAIService(
        model: model,
        geminiKey: geminiKey,
        openAIApiKey: openaiKey,
      );

      // Simple intent classification to avoid code-edit bias on casual chats
      final lower = prompt.toLowerCase().trim();
      final isGreeting = RegExp(r'^(hi|hello|hey)\b').hasMatch(lower);
      final looksLikeCodeEdit = RegExp(r'(replace|refactor|rename|add|remove|fix|change|edit|update|modify)\b')
          .hasMatch(lower);
      final looksRepoQ = lower.contains('repo') || lower.contains('architecture') || lower.contains('file');
      final intent = isGreeting
          ? 'general'
          : (looksLikeCodeEdit ? 'code_edit' : (looksRepoQ ? 'repo_question' : 'general'));

      // Collect context with strict manual/auto behavior:
      // - If manualContextEnabled is true:
      //     - If repoContextFiles empty: stop with friendly error.
      //     - Else: use exactly the selected files.
      // - Else (auto): use ConversationContext selection.
      List<Map<String, String>> filesForLLM = [];
      if (state.manualContextEnabled) {
        if (state.repoContextFiles.isEmpty) {
          // revert optimistic append of user message to avoid duplicate when user retries
          state = state.copyWith(
            isLoading: false,
            error: 'No manual context selected. Either select files or turn off manual context.',
          );
          return;
        }
        filesForLLM = state.repoContextFiles
            .map((f) => {'name': f.path, 'content': f.content ?? ''})
            .toList();
      } else {
        final selection = await _ctx!.selectContextFor(prompt);
        filesForLLM = selection.files;
      }

      // Add user turn to conversation memory (after optimistic UI add)
      _ctx!.addUserTurn(prompt);

      String summary = '';
      String answer = '';
      String? repoAnswer;

      // Route by intent
      if (intent == 'code_edit') {
        summary = await PromptService.processCodeEditIntent(
          aiService: aiService,
          prompt: prompt,
          files: filesForLLM,
        );
        // Provide a conversational answer too
        answer = await PromptService.processGeneralIntent(
          aiService: aiService,
          prompt: prompt,
          contextFiles: filesForLLM,
        );
      } else if (intent == 'repo_question') {
        final repo = state.selectedRepo ?? repoState.selectedRepo;
        if (repo != null) {
          repoAnswer = await PromptService.processRepoQuestion(
            aiService: aiService,
            prompt: prompt,
            repo: repo,
            contextFiles: filesForLLM,
          );
        }
        answer = await PromptService.processGeneralIntent(
          aiService: aiService,
          prompt: prompt,
          contextFiles: filesForLLM,
        );
      } else {
        // general small-talk or non-edit prompt
        answer = await PromptService.processGeneralIntent(
          aiService: aiService,
          prompt: prompt,
          contextFiles: filesForLLM,
        );
      }

      // Compose assistant text
      final assistantText = [
        if (summary.trim().isNotEmpty) summary.trim(),
        answer.trim(),
        if (repoAnswer != null && repoAnswer!.trim().isNotEmpty) repoAnswer!.trim(),
      ].where((s) => s.isNotEmpty).join('\n\n');

      _ctx!.addAssistantTurn(assistantText);

      // Append assistant message (reply appears after user's message)
      final finalMessages = [...state.messages, ChatMessage(isUser: false, text: assistantText)];
      state = state.copyWith(
        isLoading: false,
        messages: finalMessages,
        lastIntent: intent,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: friendlyErrorMessage(e.toString()));
    }
  }

  // --- Review-related stubs to satisfy existing UI until full agentic review is wired ---
  void toggleReviewExpanded() {
    state = state.copyWith(reviewExpanded: !state.reviewExpanded);
  }

  Future<void> approveReview() async {
    // In a full implementation, this would apply diffs and clear pendingReview.
    state = state.copyWith(pendingReview: null, reviewExpanded: false);
  }

  void rejectReview() {
    // Clear any pending review without applying.
    state = state.copyWith(pendingReview: null, reviewExpanded: false);
  }
  // --- end stubs ---

  Future<void> preloadBranches() async {
    try {
      final repo = state.selectedRepo ?? repoState.selectedRepo;
      if (repo == null) return;
      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      final branches = await PromptService.fetchBranches(owner: owner, repo: repoName);
      state = state.copyWith(branches: branches);
    } catch (_) {
      // ignore silently
    }
  }

  Future<void> _ensureContext({required String scopeRoot, bool rebuild = false}) async {
    _ctx ??= ConversationContext(scopeRoot: scopeRoot);
    if (rebuild) {
      await _ctx!.buildIndex();
      return;
    }
    if (_ctx!.chatTurns.isEmpty) {
      await _ctx!.buildIndex();
    }
  }
}
