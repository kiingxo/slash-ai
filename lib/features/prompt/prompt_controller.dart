import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/common/widgets/widgets.dart';
import '../file_browser/file_browser_controller.dart';
import '../auth/auth_controller.dart';
import '../repo/repo_controller.dart';
import 'prompt_service.dart';

// Enhanced message model with context tracking
class ChatMessage {
  final bool isUser;
  final String text;
  final ReviewData? review;
  final bool hasContext; // Track if this message included context
  final DateTime timestamp;
  
  ChatMessage({
    required this.isUser,
    required this.text,
    this.review,
    this.hasContext = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// Context management strategy enum
enum ContextStrategy {
  always,      // Send context with every message (current behavior)
  firstOnly,   // Send context only with first message
  onDemand,    // Send context only when user explicitly requests
  smart,       // Send context based on message type and conversation state
}

// Enhanced prompt state with context management
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
  
  // New context management fields
  final ContextStrategy contextStrategy;
  final bool contextSentInConversation;
  final Map<String, String> contextSummaries; // File summaries to reduce token usage
  final bool includeContextInNextMessage;

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
    this.contextStrategy = ContextStrategy.smart,
    this.contextSentInConversation = false,
    this.contextSummaries = const {},
    this.includeContextInNextMessage = false,
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
    ContextStrategy? contextStrategy,
    bool? contextSentInConversation,
    Map<String, String>? contextSummaries,
    bool? includeContextInNextMessage,
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
      contextStrategy: contextStrategy ?? this.contextStrategy,
      contextSentInConversation: contextSentInConversation ?? this.contextSentInConversation,
      contextSummaries: contextSummaries ?? this.contextSummaries,
      includeContextInNextMessage: includeContextInNextMessage ?? this.includeContextInNextMessage,
    );
  }
}

// Enhanced prompt controller with context optimization
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

  // Context strategy management
  void setContextStrategy(ContextStrategy strategy) {
    state = state.copyWith(contextStrategy: strategy);
  }

  void forceIncludeContextInNextMessage() {
    state = state.copyWith(includeContextInNextMessage: true);
  }

  void resetConversationContext() {
    state = state.copyWith(
      contextSentInConversation: false,
      contextSummaries: {},
      includeContextInNextMessage: false,
    );
  }

  // Existing methods...
  void setSelectedModel(String model) {
    state = state.copyWith(selectedModel: model);
  }

  void setSelectedRepo(dynamic repo) {
    state = state.copyWith(selectedRepo: repo);
    // Reset context state when repo changes
    resetConversationContext();
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
    // Reset context state when files change
    resetConversationContext();
    // Generate summaries for new files
    _generateContextSummaries(files);
  }

  void removeContextFile(FileItem file) {
    final updatedFiles = List<FileItem>.from(state.repoContextFiles);
    updatedFiles.remove(file);
    state = state.copyWith(repoContextFiles: updatedFiles);
    // Reset context state when files change
    resetConversationContext();
    _generateContextSummaries(updatedFiles);
  }

  // Enhanced submit method with smart context management
  Future<void> submitPrompt(String prompt) async {
    if (prompt.trim().isEmpty) return;
    
    // Validation checks
    final repo = state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
    
    if (repo == null) {
      state = state.copyWith(
        error: 'Please select a repository before sending a message.',
      );
      return;
    }

    if (state.repoContextFiles.isEmpty) {
      state = state.copyWith(
        error: 'Please select at least one context file before sending a message.',
      );
      return;
    }
    
    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );
    
    // Determine if context should be included
    final shouldIncludeContext = _shouldIncludeContext(prompt);
    
    _addMessage(ChatMessage(
      isUser: true, 
      text: prompt,
      hasContext: shouldIncludeContext,
    ));
    
    try {
      await _processPrompt(prompt, includeContext: shouldIncludeContext);
      
      // Update context state after successful processing
      if (shouldIncludeContext) {
        state = state.copyWith(
          contextSentInConversation: true,
          includeContextInNextMessage: false,
        );
      }
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

  // Smart context inclusion logic
  bool _shouldIncludeContext(String prompt) {
    switch (state.contextStrategy) {
      case ContextStrategy.always:
        return true;
        
      case ContextStrategy.firstOnly:
        return !state.contextSentInConversation;
        
      case ContextStrategy.onDemand:
        return state.includeContextInNextMessage || 
               _promptExplicitlyRequestsContext(prompt);
        
      case ContextStrategy.smart:
        // Include context if:
        // 1. First message in conversation
        // 2. User explicitly requests it
        // 3. Message seems to require code context
        // 4. Previous context is stale (repo/files changed)
        return !state.contextSentInConversation ||
               state.includeContextInNextMessage ||
               _promptExplicitlyRequestsContext(prompt) ||
               _promptRequiresCodeContext(prompt);
    }
  }

  bool _promptExplicitlyRequestsContext(String prompt) {
    final contextKeywords = [
      'show me the code',
      'look at the file',
      'check the implementation',
      'review the code',
      'with context',
      'include files',
    ];
    
    final lowerPrompt = prompt.toLowerCase();
    return contextKeywords.any((keyword) => lowerPrompt.contains(keyword));
  }

  bool _promptRequiresCodeContext(String prompt) {
    final codeKeywords = [
      'function',
      'method',
      'class',
      'variable',
      'import',
      'bug',
      'error',
      'fix',
      'implement',
      'add',
      'remove',
      'modify',
      'change',
      'update',
    ];
    
    final lowerPrompt = prompt.toLowerCase();
    return codeKeywords.any((keyword) => lowerPrompt.contains(keyword));
  }

  // Generate context summaries to reduce token usage
  Future<void> _generateContextSummaries(List<FileItem> files) async {
    final summaries = <String, String>{};
    
    for (final file in files) {
      if (file.content != null && file.content!.isNotEmpty) {
        // Simple summary: first few lines + basic structure info
        final lines = file.content!.split('\n');
        final firstLines = lines.take(10).join('\n');
        final totalLines = lines.length;
        final hasClasses = file.content!.contains('class ');
        final hasFunctions = file.content!.contains('void ') || file.content!.contains('Future<');
        
        summaries[file.name] = '''
File: ${file.name} ($totalLines lines)
${hasClasses ? 'Contains classes. ' : ''}${hasFunctions ? 'Contains functions. ' : ''}
Preview:
$firstLines
${lines.length > 10 ? '...(${lines.length - 10} more lines)' : ''}
''';
      }
    }
    
    state = state.copyWith(contextSummaries: summaries);
  }

  // Enhanced process prompt with context control
  Future<void> _processPrompt(String prompt, {required bool includeContext}) async {
    final authState = ref.read(authControllerProvider);
    final repo = state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
    
    // Validate API keys
    if ((state.selectedModel == 'gemini' && 
         (authState.geminiApiKey == null || authState.geminiApiKey!.isEmpty)) ||
        (state.selectedModel == 'openai' && 
         (authState.openAIApiKey == null || authState.openAIApiKey!.isEmpty)) ||
        authState.githubPat == null || authState.githubPat!.isEmpty) {
      throw Exception('Missing API keys');
    }
    
    final aiService = PromptService.createAIService(
      model: state.selectedModel,
      geminiKey: authState.geminiApiKey,
      openAIApiKey: authState.openAIApiKey,
    );
    
    // Classify intent
    final intent = await aiService.classifyIntent(prompt);
    state = state.copyWith(lastIntent: intent);
    
    // Prepare context based on strategy
    List<Map<String, String>> contextFiles = [];
    if (includeContext && state.repoContextFiles.isNotEmpty) {
      if (intent == 'code_edit') {
        // For code edits, always include full content
        contextFiles = state.repoContextFiles
            .map((f) => {'name': f.name, 'content': f.content ?? ''})
            .toList()
            .take(3)
            .toList();
      } else {
        // For other intents, use summaries if available
        contextFiles = state.repoContextFiles
            .map((f) => {
              'name': f.name, 
              'content': state.contextSummaries[f.name] ?? f.content ?? ''
            })
            .toList()
            .take(3)
            .toList();
      }
    }
    
    String response;
    ReviewData? review;
    
    switch (intent) {
      case 'code_edit':
        if (repo == null) throw Exception('No repository selected');
        
        final owner = repo['owner']['login'];
        final repoName = repo['name'];
        
        if (contextFiles.isEmpty) {
          throw Exception('Please select at least one context file before submitting.');
        }

        final files = contextFiles;
        
        response = await PromptService.processCodeEditIntent(
          aiService: aiService,
          prompt: prompt,
          files: files,
          useFullContext: includeContext,
        );
        
        final newContent = await PromptService.processCodeContent(
          aiService: aiService,
          prompt: prompt,
          files: files,
        );
        
        final fileName = files.isNotEmpty ? files[0]['name']! : 'unknown.dart';
        final oldContent = state.repoContextFiles
            .firstWhere((f) => f.name == fileName, orElse: () => FileItem(name: '', path: '', type: ''))
            .content ?? '';
        
        review = ReviewData(
          fileName: fileName,
          oldContent: oldContent,
          newContent: newContent,
          summary: response,
        );
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
            hasFullContext: includeContext,
          );
        }
        break;
        
      default:
        response = await PromptService.processGeneralIntent(
          aiService: aiService,
          prompt: prompt,
          contextFiles: contextFiles,
          hasFullContext: includeContext,
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
      hasContext: includeContext,
    ));
  }

  // Rest of the existing methods remain the same...
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
      resetConversationContext();
      _generateContextSummaries(files);
    } catch (e) {
      print('Error adding repo context: $e');
      _addMessage(ChatMessage(
        isUser: false,
        text: 'Failed to add repo context: ${friendlyErrorMessage(e.toString())}',
      ));
    }
  }

  Future<void> forceCodeEdit(String prompt) async {
    state = state.copyWith(isLoading: true);
    
    try {
      final authState = ref.read(authControllerProvider);
      final repo = state.selectedRepo ?? ref.read(repoControllerProvider).selectedRepo;
      
      if (repo == null) throw Exception('No repository selected');
      
      final aiService = PromptService.createAIService(
        model: state.selectedModel,
        geminiKey: authState.geminiApiKey,
        openAIApiKey: authState.openAIApiKey,
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
        useFullContext: true,
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
        contextSentInConversation: true,
      );
      
      _addMessage(ChatMessage(
        isUser: false, 
        text: summary, 
        review: review,
        hasContext: true,
      ));
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

// Review data model (unchanged)
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

// Provider
final promptControllerProvider = StateNotifierProvider<PromptController, PromptState>((ref) {
  return PromptController(ref);
});