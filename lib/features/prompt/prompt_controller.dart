import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../file_browser/file_browser_controller.dart';
import '../repo/repo_controller.dart';
import 'prompt_service.dart';

class ChatMessage {
  final bool isUser;
  final String text;
  final ReviewData? review;
  final List<ContextFileMeta>? sentContext;
  final DateTime? sentAt;
  final bool expandableContext;

  const ChatMessage({
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

class ReviewData {
  final String fileName;
  final String oldContent;
  final String newContent;
  final String summary;
  final String sourcePrompt;
  final dynamic repo;
  final String? branch;
  final String? baseSha;

  const ReviewData({
    required this.fileName,
    required this.oldContent,
    required this.newContent,
    required this.summary,
    required this.sourcePrompt,
    required this.repo,
    required this.branch,
    this.baseSha,
  });
}

class ContextFileMeta {
  final String name;
  final String preview;

  const ContextFileMeta({required this.name, required this.preview});
}

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

  const PromptState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.pendingReview,
    this.reviewExpanded = false,
    this.selectedModel = 'openai',
    this.lastIntent,
    this.repoContextFiles = const [],
    this.branches = const [],
    this.selectedBranch,
    this.selectedRepo,
  });

  PromptState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    Object? error = _promptUnset,
    Object? pendingReview = _promptUnset,
    bool? reviewExpanded,
    String? selectedModel,
    Object? lastIntent = _promptUnset,
    List<FileItem>? repoContextFiles,
    List<String>? branches,
    Object? selectedBranch = _promptUnset,
    Object? selectedRepo = _promptUnset,
  }) {
    return PromptState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _promptUnset) ? this.error : error as String?,
      pendingReview:
          identical(pendingReview, _promptUnset)
              ? this.pendingReview
              : pendingReview as ReviewData?,
      reviewExpanded: reviewExpanded ?? this.reviewExpanded,
      selectedModel: selectedModel ?? this.selectedModel,
      lastIntent:
          identical(lastIntent, _promptUnset)
              ? this.lastIntent
              : lastIntent as String?,
      repoContextFiles: repoContextFiles ?? this.repoContextFiles,
      branches: branches ?? this.branches,
      selectedBranch:
          identical(selectedBranch, _promptUnset)
              ? this.selectedBranch
              : selectedBranch as String?,
      selectedRepo:
          identical(selectedRepo, _promptUnset)
              ? this.selectedRepo
              : selectedRepo,
    );
  }
}

const Object _promptUnset = Object();

class PromptController extends StateNotifier<PromptState> {
  final Ref ref;

  PromptController(this.ref)
    : super(
        const PromptState(
          messages: [
            ChatMessage(
              isUser: false,
              text:
                  "I'm /slash. Pick a repo, attach context if you want, and I'll help plan, edit, and ship the change.",
            ),
          ],
        ),
      ) {
    _initializeModel();
  }

  void _initializeModel() {
    final authState = ref.read(authControllerProvider);
    final persisted = authState.model.trim();
    state = state.copyWith(
      selectedModel: persisted.isEmpty ? 'openai' : persisted,
    );
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
    final updatedFiles = List<FileItem>.from(state.repoContextFiles)
      ..removeWhere((candidate) => candidate.path == file.path);
    state = state.copyWith(repoContextFiles: updatedFiles);
  }

  Future<void> addRepoContext() async {
    try {
      final repo =
          state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      if (repo == null) {
        throw Exception('No repository selected.');
      }

      final params = RepoParams(
        owner: repo['owner']['login'],
        repo: repo['name'],
        branch: state.selectedBranch,
      );
      final fileBrowserController = ref.read(
        fileBrowserControllerProvider(params).notifier,
      );
      final files = await fileBrowserController.listAllFiles();
      state = state.copyWith(repoContextFiles: files);
    } catch (e) {
      _addMessage(
        ChatMessage(
          isUser: false,
          text:
              'Failed to add repo context: ${friendlyErrorMessage(e.toString())}',
        ),
      );
    }
  }

  Future<void> submitPrompt(String prompt) async {
    if (prompt.trim().isEmpty) {
      return;
    }

    final explicitContextFiles = List<FileItem>.from(state.repoContextFiles);
    state = state.copyWith(isLoading: true, error: null);

    final sentContext =
        explicitContextFiles
            .map(
              (file) => ContextFileMeta(
                name: file.name,
                preview: (file.content ?? '').split('\n').take(12).join('\n'),
              ),
            )
            .toList();

    _addMessage(
      ChatMessage(
        isUser: true,
        text: prompt,
        sentContext: sentContext.isNotEmpty ? sentContext : null,
        sentAt: DateTime.now(),
        expandableContext: sentContext.isNotEmpty,
      ),
    );

    if (explicitContextFiles.isNotEmpty) {
      state = state.copyWith(repoContextFiles: const []);
    }

    _addMessage(const ChatMessage(isUser: false, text: 'Thinking...'));

    try {
      await _processPrompt(prompt, explicitFiles: explicitContextFiles);
      _replaceLastAssistantWithFinal();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      _replaceLastAssistantWithText(friendlyErrorMessage(e.toString()));
    }
  }

  Future<void> forceCodeEdit(String prompt) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final review = await _buildReview(
        prompt: prompt,
        explicitFiles: List<FileItem>.from(state.repoContextFiles),
      );

      state = state.copyWith(
        isLoading: false,
        pendingReview: review,
        reviewExpanded: false,
      );

      _addMessage(
        ChatMessage(isUser: false, text: review.summary, review: review),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      _addMessage(
        ChatMessage(isUser: false, text: friendlyErrorMessage(e.toString())),
      );
    }
  }

  Future<void> approveReview(ReviewData review) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final repo =
          review.repo ??
          state.selectedRepo ??
          ref.read(repoControllerProvider).selectedRepo;
      if (repo == null) {
        throw Exception('No repository selected');
      }

      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      final prUrl = await PromptService.createPullRequest(
        owner: owner,
        repo: repoName,
        fileName: review.fileName,
        newContent: review.newContent,
        prompt: review.sourcePrompt,
        summary: review.summary,
        selectedBranch: review.branch ?? state.selectedBranch,
      );

      state = state.copyWith(isLoading: false, pendingReview: null);

      _addMessage(
        ChatMessage(isUser: false, text: 'Pull request created: $prUrl'),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());

      _addMessage(
        ChatMessage(isUser: false, text: friendlyErrorMessage(e.toString())),
      );
    }
  }

  void rejectReview() {
    state = state.copyWith(pendingReview: null, reviewExpanded: false);

    _addMessage(const ChatMessage(isUser: false, text: 'Suggestion rejected.'));
  }

  Future<void> _processPrompt(
    String prompt, {
    List<FileItem> explicitFiles = const [],
  }) async {
    final authState = ref.read(authControllerProvider);
    final repo =
        state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
    final aiService = _createAiService(authState);
    final hasPinnedContext =
        explicitFiles.isNotEmpty || _latestReview() != null;
    final hasContextForIntent = hasPinnedContext || repo != null;
    final intent = await PromptService.determineIntent(
      aiService: aiService,
      prompt: prompt,
      hasFileContext: hasContextForIntent,
      preferCodeEdit: hasPinnedContext,
    );
    state = state.copyWith(lastIntent: intent);

    final repoContext = await _resolveContext(
      prompt: prompt,
      repo: repo,
      explicitFiles: explicitFiles,
      maxFiles: intent == 'code_edit' ? 1 : 3,
      allowAutoDiscovery: intent != 'code_edit' || !hasPinnedContext,
      includeRepoDigest: intent != 'code_edit' || !hasPinnedContext,
      preferCachedRepoIndex: intent == 'code_edit',
    );

    final contextFiles = repoContext.files;
    final toolSummary = repoContext.toolSummary;

    String response;
    ReviewData? review;

    switch (intent) {
      case 'code_edit':
        final editPackage = await PromptService.processCodeEditPackage(
          aiService: aiService,
          prompt: prompt,
          files: contextFiles,
          toolSummary: toolSummary,
        );
        response = editPackage.summary;

        if (contextFiles.isNotEmpty) {
          review = await _buildReview(
            prompt: prompt,
            explicitFiles: explicitFiles,
            resolvedContext: repoContext,
            editOverride: editPackage,
          );
        }
        break;
      case 'repo_question':
        if (repo == null) {
          response =
              'Pick a repository first so I can answer repository-specific questions.';
        } else {
          response = await PromptService.processRepoQuestion(
            aiService: aiService,
            prompt: prompt,
            repo: repo,
            contextFiles: contextFiles,
            toolSummary: toolSummary,
          );
        }
        break;
      default:
        response = await PromptService.processGeneralIntent(
          aiService: aiService,
          prompt: prompt,
          contextFiles: contextFiles,
          toolSummary: toolSummary,
        );
        break;
    }

    state = state.copyWith(
      isLoading: false,
      pendingReview: review,
      reviewExpanded: false,
    );

    _addMessage(ChatMessage(isUser: false, text: response, review: review));
  }

  Future<ReviewData> _buildReview({
    required String prompt,
    required List<FileItem> explicitFiles,
    PromptContextResult? resolvedContext,
    CodeEditPackage? editOverride,
  }) async {
    final repo =
        state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
    final context =
        resolvedContext ??
        await _resolveContext(
          prompt: prompt,
          repo: repo,
          explicitFiles: explicitFiles,
          maxFiles: 1,
          allowAutoDiscovery: false,
          includeRepoDigest: false,
          preferCachedRepoIndex: true,
        );

    if (context.files.isEmpty) {
      throw Exception(
        'Select or discover at least one file before requesting an edit.',
      );
    }

    final editPackage =
        editOverride ??
        await (() async {
          final authState = ref.read(authControllerProvider);
          final aiService = _createAiService(authState);
          return PromptService.processCodeEditPackage(
            aiService: aiService,
            prompt: prompt,
            files: context.files,
            toolSummary: context.toolSummary,
          );
        })();

    final targetFile = context.files.firstWhere(
      (file) => (file['name'] ?? '') != '.slash/repo-map.txt',
      orElse: () => const <String, String>{},
    );
    if (targetFile.isEmpty) {
      throw Exception('No editable file context was found for this request.');
    }

    final fileName = targetFile['name'] ?? 'unknown.dart';
    final oldContent = targetFile['content'] ?? '';

    String? baseSha;
    for (final file in explicitFiles) {
      if (file.path == fileName || file.name == fileName) {
        baseSha = file.sha;
        break;
      }
    }
    baseSha ??= targetFile['sha'];

    return ReviewData(
      fileName: fileName,
      oldContent: oldContent,
      newContent: editPackage.content,
      summary: editPackage.summary,
      sourcePrompt: prompt,
      repo: repo,
      branch: state.selectedBranch,
      baseSha: baseSha,
    );
  }

  Future<PromptContextResult> _resolveContext({
    required String prompt,
    required dynamic repo,
    required List<FileItem> explicitFiles,
    int maxFiles = 3,
    bool allowAutoDiscovery = true,
    bool includeRepoDigest = true,
    bool preferCachedRepoIndex = false,
  }) async {
    if (explicitFiles.isNotEmpty) {
      return PromptService.resolveContext(
        prompt: prompt,
        repo: repo == null ? null : Map<String, dynamic>.from(repo),
        branch: state.selectedBranch,
        selectedFiles: explicitFiles,
        maxFiles: maxFiles,
        allowAutoDiscovery: allowAutoDiscovery,
        includeRepoDigest: includeRepoDigest,
        preferCachedRepoIndex: preferCachedRepoIndex,
      );
    }

    final latestReview = _latestReview();
    if (latestReview != null) {
      final reviewRepo =
          latestReview.repo == null
              ? null
              : Map<String, dynamic>.from(latestReview.repo);

      if (reviewRepo != null) {
        final resolvedRepo =
            repo == null
                ? reviewRepo
                : (_sameRepo(repo, reviewRepo)
                    ? Map<String, dynamic>.from(repo)
                    : null);

        if (resolvedRepo != null) {
          final result = await PromptService.resolveContext(
            prompt: prompt,
            repo: resolvedRepo,
            branch: state.selectedBranch ?? latestReview.branch,
            selectedFiles: [
              FileItem(
                name: latestReview.fileName.split('/').last,
                path: latestReview.fileName,
                type: 'file',
                content: latestReview.newContent,
                sha: latestReview.baseSha,
              ),
            ],
            maxFiles: maxFiles,
            allowAutoDiscovery: allowAutoDiscovery,
            includeRepoDigest: includeRepoDigest,
            preferCachedRepoIndex: preferCachedRepoIndex,
          );

          return PromptContextResult(
            files: result.files,
            toolSummary: ['carry_forward:last_review', ...result.toolSummary],
            autoDiscovered: result.autoDiscovered,
          );
        }

        if (repo != null) {
          return PromptService.resolveContext(
            prompt: prompt,
            repo: Map<String, dynamic>.from(repo),
            branch: state.selectedBranch,
            selectedFiles: const [],
            maxFiles: maxFiles,
            allowAutoDiscovery: allowAutoDiscovery,
            includeRepoDigest: includeRepoDigest,
            preferCachedRepoIndex: preferCachedRepoIndex,
          );
        }
      }

      if (repo == null) {
        return PromptContextResult(
          files: [
            {
              'name': latestReview.fileName,
              'content': latestReview.newContent,
              if ((latestReview.baseSha ?? '').isNotEmpty)
                'sha': latestReview.baseSha!,
            },
          ],
          toolSummary: const ['carry_forward:last_review'],
          autoDiscovered: false,
        );
      }
    }

    return PromptService.resolveContext(
      prompt: prompt,
      repo: repo == null ? null : Map<String, dynamic>.from(repo),
      branch: state.selectedBranch,
      selectedFiles: explicitFiles,
      maxFiles: maxFiles,
      allowAutoDiscovery: allowAutoDiscovery,
      includeRepoDigest: includeRepoDigest,
      preferCachedRepoIndex: preferCachedRepoIndex,
    );
  }

  ReviewData? _latestReview() {
    for (var index = state.messages.length - 1; index >= 0; index--) {
      final message = state.messages[index];
      if (message.review != null) {
        return message.review;
      }
    }
    return state.pendingReview;
  }

  AIService _createAiService(AuthState authState) {
    return PromptService.createAIService(
      model: state.selectedModel,
      openAIApiKey: authState.openAIApiKey,
      openAIModel: authState.openAIModel,
      openRouterApiKey: authState.openRouterApiKey,
      openRouterModel: authState.openRouterModel,
    );
  }

  bool _sameRepo(dynamic left, dynamic right) {
    final leftFullName = (left?['full_name'] ?? '').toString();
    final rightFullName = (right?['full_name'] ?? '').toString();
    if (leftFullName.isNotEmpty && rightFullName.isNotEmpty) {
      return leftFullName == rightFullName;
    }

    final leftOwner = (left?['owner']?['login'] ?? '').toString();
    final rightOwner = (right?['owner']?['login'] ?? '').toString();
    final leftName = (left?['name'] ?? '').toString();
    final rightName = (right?['name'] ?? '').toString();

    return leftOwner.isNotEmpty &&
        leftName.isNotEmpty &&
        leftOwner == rightOwner &&
        leftName == rightName;
  }

  Future<void> _fetchBranchesForRepo(dynamic repo) async {
    state = state.copyWith(branches: const [], selectedBranch: null);

    try {
      final branches = await PromptService.fetchBranches(
        owner: repo['owner']['login'],
        repo: repo['name'],
      );

      final defaultBranch = (repo['default_branch'] ?? '').toString();
      final selectedBranch =
          branches.contains(defaultBranch)
              ? defaultBranch
              : (branches.isNotEmpty ? branches.first : null);

      state = state.copyWith(
        branches: branches,
        selectedBranch: selectedBranch,
      );
    } catch (_) {
      state = state.copyWith(branches: const [], selectedBranch: null);
    }
  }

  void _addMessage(ChatMessage message) {
    final updatedMessages = List<ChatMessage>.from(state.messages)
      ..add(message);
    state = state.copyWith(messages: updatedMessages);
  }

  void _replaceLastAssistantWithText(String newText) {
    final updated = List<ChatMessage>.from(state.messages);
    for (var index = updated.length - 1; index >= 0; index--) {
      if (!updated[index].isUser) {
        updated[index] = ChatMessage(
          isUser: false,
          text: newText,
          review: updated[index].review,
        );
        break;
      }
    }
    state = state.copyWith(messages: updated);
  }

  void _replaceLastAssistantWithFinal() {
    final updated = List<ChatMessage>.from(state.messages);
    int lastAssistantIndex = -1;
    for (var index = updated.length - 1; index >= 0; index--) {
      if (!updated[index].isUser) {
        lastAssistantIndex = index;
        break;
      }
    }

    if (lastAssistantIndex > 0) {
      final placeholderIndex = lastAssistantIndex - 1;
      if (!updated[placeholderIndex].isUser &&
          updated[placeholderIndex].text.trim() == 'Thinking...') {
        updated.removeAt(placeholderIndex);
      }
    }

    state = state.copyWith(messages: updated, isLoading: false);
  }
}

final promptControllerProvider =
    StateNotifierProvider<PromptController, PromptState>((ref) {
      return PromptController(ref);
    });
