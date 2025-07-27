import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/services/code_database.dart';
import '../file_browser/file_browser_controller.dart';
import '../auth/auth_controller.dart';
import '../repo/repo_controller.dart';
import 'prompt_service.dart';
import 'package:slash_flutter/services/file_processing_service.dart'; // Import the file processing service

// Message model for chat
class ChatMessage {
  final bool isUser;
  final String text;
  final ReviewData? review;

  ChatMessage({
    required this.isUser,
    required this.text,
    this.review,
  });
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
  final bool isProcessingRepo; // Added to indicate if repo is being processed

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
    this.isProcessingRepo = false, // Initialize
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
    bool? isProcessingRepo, // Add to copyWith
  }) {
    return PromptState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      pendingReview:
          clearPendingReview ? null : (pendingReview ?? this.pendingReview),
      reviewExpanded: reviewExpanded ?? this.reviewExpanded,
      selectedModel: selectedModel ?? this.selectedModel,
      lastIntent: lastIntent ?? this.lastIntent,
      repoContextFiles: repoContextFiles ?? this.repoContextFiles,
      branches: branches ?? this.branches,
      selectedBranch: selectedBranch ?? this.selectedBranch,
      selectedRepo: selectedRepo ?? this.selectedRepo,
      isProcessingRepo: isProcessingRepo ?? this.isProcessingRepo, // Update
    );
  }
}

// Prompt controller
class PromptController extends StateNotifier<PromptState> {
  final Ref ref;

  PromptController(this.ref)
      : super(PromptState(
          messages: [
            ChatMessage(
              isUser: false,
              text: "Hi! I\'m /slash. How can I help you today?",
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
      _processRepoForEmbeddings(repo); // Trigger processing
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
      final repo =
          state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      if (repo == null) throw Exception('No repository selected.');

      final owner = repo['owner']['login'];
      final repoName = repo['name'];
      final params = RepoParams(owner: owner, repo: repoName);

      final fileBrowserController =
          ref.read(fileBrowserControllerProvider(params).notifier);

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

    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );

    _addMessage(ChatMessage(isUser: true, text: prompt));

    try {
      await _processPrompt(prompt);
    } catch (e, stackTrace) {
      print('[PromptController] Error: $e');
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

  Future<void> forceCodeEdit(String prompt) async {
    state = state.copyWith(isLoading: true);

    try {
      final authState = ref.read(authControllerProvider);
      final repo =
          state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;

      if (repo == null) throw Exception('No repository selected');

      final aiService = PromptService.createAIService(
        model: state.selectedModel,
        geminiKey: authState.geminiApiKey,
        openAIApiKey: authState.openAIApiKey,
      );

      final owner = repo['owner']['login'];
      final repoName = repo['name'];

      final files = state.repoContextFiles.isNotEmpty
          ? state.repoContextFiles
              .map((f) => {'name': f.name, 'content': f.content ?? ''})
              .toList()
          : await PromptService.fetchFiles(
              owner: owner,
              repo: repoName,
              pat: authState.githubPat!,
              branch: state.selectedBranch,
            );

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
      final repo =
          state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
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
    final repo =
        state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;

    // Validate API keys
    if ((state.selectedModel == 'gemini' &&
            (authState.geminiApiKey == null || authState.geminiApiKey!.isEmpty)) ||
        (state.selectedModel == 'openai' &&
            (authState.openAIApiKey == null || authState.openAIApiKey!.isEmpty)) ||
        authState.githubPat == null ||
        authState.githubPat!.isEmpty) {
      throw Exception('Missing API keys');
    }

    final aiService = PromptService.createAIService(
      model: state.selectedModel,
      geminiKey: authState.geminiApiKey,
      openAIApiKey: authState.openAIApiKey,
    );

    // Classify intent
    // You might want to classify intent *after* getting context chunks
    // as the context can influence the intent. We'll keep it here for now
    // but can revisit this.
    final intent = await aiService.classifyIntent(prompt);
    state = state.copyWith(lastIntent: intent);

    // Use vector search to get context files based on the query
    List<CodeChunk> relevantChunks = [];
    if (repo != null) {
      // Assuming the repo path is available when a repo is selected
      final repoPath = repo['local_path'] ?? '.'; // Replace with actual repo path if stored
      relevantChunks = await FileProcessingService.searchCodeChunks(prompt, 5); // Get top 5 chunks
    }


    // Prepare context for LLM
    final contextString = relevantChunks.map((chunk) {
      // Format the chunk information for the LLM
      return 'File: ${chunk.fileName}\nChunk:\n${chunk.chunkText}\n';
    }).join('\n---\n'); // Use a separator between chunks

    // Combine context with the user's prompt
    final promptWithContext = contextString.isNotEmpty
        ? 'Context:\n$contextString\nUser Query: $prompt'
        : prompt; // Use only the prompt if no relevant chunks found


    String response;
    ReviewData? review;

    switch (intent) {
      case 'code_edit':
        if (repo == null) throw Exception('No repository selected');

        // For code edit, we might need the full file content of the relevant files
        // instead of just chunks. This is a point to consider and refine.
        // For now, we'll pass the relevant chunks' text as context.

        // You'll need to adapt how you fetch/provide file content for code edits
        // based on the relevant chunks. This might involve reading the full files
        // for the files containing the relevant chunks.

        // Example (simplified - you'll need to implement the logic to get full files):
        final filesForEdit = relevantChunks.map((chunk) => {'name': chunk.fileName, 'content': chunk.chunkText}).toList(); // Simplified: using chunk text as content

        response = await PromptService.processCodeEditIntent(
          aiService: aiService,
          prompt: promptWithContext, // Pass prompt with context
          files: filesForEdit, // Pass relevant file content (or chunks)
        );

         // To get the new content for the review, you might need a separate call
         // to the AI service with the full file content and the user's request.
         // This is a more complex interaction that needs careful design.
         // For now, we'll use a placeholder or simplify the review process for code edits.

        // Placeholder for review data in code_edit case
        review = ReviewData(
          fileName: relevantChunks.isNotEmpty ? relevantChunks.first.fileName : 'unknown.dart',
          oldContent: 'Original content not available with chunking approach yet.', // Indicate limitation
          newContent: 'Generated new content not available with chunking approach yet.', // Indicate limitation
          summary: response,
        );


        break;

      case 'repo_question':
        if (repo == null) {
          response =
              "No repository selected. Please select a repository to ask questions about it.";
        } else {
          response = await PromptService.processRepoQuestion(
            aiService: aiService,
            prompt: promptWithContext, // Pass prompt with context
            repo: repo,
            contextFiles: [], // Context is now handled by vector search
          );
        }
        break;

      default:
        response = await PromptService.processGeneralIntent(
          aiService: aiService,
          prompt: promptWithContext, // Pass prompt with context
          contextFiles: [], // Context is now handled by vector search
        );
        break;
    }

    state = state.copyWith(
      isLoading: false,
      pendingReview: review, // pendingReview might need adjustment for code_edit with chunking
      reviewExpanded: false,
    );

    _addMessage(ChatMessage(
      isUser: false,
      text: response,
      review: review,
    ));
  }


  // New function to trigger repo processing for embeddings
  Future<void> _processRepoForEmbeddings(dynamic repo) async {
    if (repo == null) return;

    state = state.copyWith(isProcessingRepo: true, clearError: true);

    try {
      // Assuming the repo object contains a 'local_path' field
      final repoPath = repo['local_path']; // Get the local path of the repo

      if (repoPath == null) {
        throw Exception('Local path for the selected repository is not available.');
      }

      await FileProcessingService.processDirectoryAndStoreEmbeddings(repoPath);

      state = state.copyWith(isProcessingRepo: false);
      print('Repository processing for embeddings completed.');
       _addMessage(ChatMessage(
        isUser: false,
        text: 'Repository processed and embeddings stored for search.',
      ));

    } catch (e, stackTrace) {
      print('[PromptController] Error processing repo for embeddings: $e');
      print(stackTrace);

      state = state.copyWith(
        isProcessingRepo: false,
        error: 'Failed to process repository for embeddings: ${friendlyErrorMessage(e.toString())}',
      );
       _addMessage(ChatMessage(
        isUser: false,
        text: 'Failed to process repository for embeddings: ${friendlyErrorMessage(e.toString())}',
      ));
    }
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
}

// Provider
final promptControllerProvider =
    StateNotifierProvider<PromptController, PromptState>((ref) {
  return PromptController(ref);
});
