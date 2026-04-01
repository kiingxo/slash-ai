import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/features/prompt/prompt_widgets.dart';
import 'package:slash_flutter/ui/components/option_selection.dart';
import 'package:slash_flutter/ui/components/slash_dropdown.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'package:slash_flutter/ui/components/slash_toast.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';
import '../../ui/components/slash_text_field.dart';
import '../../ui/components/slash_button.dart';
import '../../home_shell.dart';
import '../../ui/screens/settings_screen.dart';
import '../repo/repo_controller.dart';
import '../file_browser/file_browser_controller.dart';
import 'prompt_controller.dart';
import 'prompt_service.dart';
import '../auth/auth_controller.dart';
import '../project/workspace_setup_page.dart';

class PromptPage extends ConsumerStatefulWidget {
  const PromptPage({super.key});

  @override
  ConsumerState<PromptPage> createState() => _PromptPageState();
}

class _PromptPageState extends ConsumerState<PromptPage> {
  late TextEditingController _promptTextController;
  // Chat scroll behavior
  final ScrollController _chatController = ScrollController();

  void _autoScrollToBottom() {
    if (!_chatController.hasClients) return;
    // Only auto-scroll if user is already near the bottom to avoid hijacking when reading history.
    final pos = _chatController.position;
    final nearBottom = (pos.maxScrollExtent - pos.pixels) <= 80; // threshold
    if (!nearBottom) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatController.hasClients) return;
      _chatController.animateTo(
        _chatController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const SettingsBottomSheet(),
    );
  }

  @override
  void initState() {
    super.initState();
    _promptTextController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoScrollToBottom();
    });
  }

  @override
  void dispose() {
    _promptTextController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _handlePromptSubmit() async {
    final prompt = _promptTextController.text.trim();
    if (prompt.isEmpty) return;

    // Agentic: allow send for follow-ups without forcing repo/context here.
    _promptTextController.clear();
    await ref.read(promptControllerProvider.notifier).submitPrompt(prompt);
    // Only snap if user is already near bottom (handled inside).
    _autoScrollToBottom();
  }

  void _showFilePickerModal(BuildContext context) async {
    final repoState = ref.read(repoControllerProvider);
    final promptState = ref.read(promptControllerProvider);
    final repo = promptState.selectedRepo ?? repoState.selectedRepo;

    if (repo == null) {
      SlashToast.showError(context, 'Please select a repository first.');
      return;
    }

    final owner = repo['owner']['login'];
    final repoName = repo['name'];
    final params = RepoParams(owner: owner, repo: repoName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return LazyFilePickerModal(
          params: params,
          initiallySelected: promptState.repoContextFiles,
          onSelected: (List<FileItem> selected) {
            ref
                .read(promptControllerProvider.notifier)
                .setRepoContextFiles(selected);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final repoState = ref.watch(repoControllerProvider);
    final promptState = ref.watch(promptControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final repoController = ref.read(repoControllerProvider.notifier);
    final promptController = ref.read(promptControllerProvider.notifier);
    final errorDetails =
        promptState.error == null
            ? null
            : friendlyErrorDetails(promptState.error!);

    final repos = repoState.repos;
    final selectedRepo =
        promptState.selectedRepo ??
        repoState.selectedRepo ??
        (repos.isNotEmpty ? repos[0] : null);

    if (repoState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (repos.isEmpty) {
      return ThemeBuilder(
        builder: (context, colors, ref) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: colors.always8B5CF6.withValues(alpha: 0.1),
              leading: const SidebarMenuButton(),
              title: Image.asset('assets/slash2.png', height: 34),
              centerTitle: false,
              toolbarHeight: kToolbarHeight,
              actions: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: colors.alwaysEDEDED.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () => _showSettings(context),
                    tooltip: 'Settings',
                  ),
                ),
              ],
            ),
            body: Center(
              child: SlashText(
                auth.hasGitHubAuth
                    ? 'No repositories found.'
                    : 'Sign in with GitHub to access your repositories.',
              ),
            ),
          );
        },
      );
    }

    return ThemeBuilder(
      builder: (context, colors, ref) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: colors.always8B5CF6.withValues(alpha: 0.1),
            leading: const SidebarMenuButton(),
            title: Image.asset('assets/slash2.png', height: 34),
            centerTitle: false,
            toolbarHeight: kToolbarHeight,
            actions: [
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Workspace Identity',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WorkspaceSetupPage(),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colors.alwaysEDEDED.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: OptionSelection(
                  options: const ["OpenAI", "OpenRouter"],
                  margin: 0,
                  padding: 8,
                  unselectedColor: Colors.transparent,
                  selectedValue:
                      promptState.selectedModel.isEmpty
                          ? 'openai'
                          : promptState.selectedModel,
                  onChanged: (val) {
                    final normalized = val.toLowerCase();
                    promptController.setSelectedModel(normalized);
                    ref
                        .read(authControllerProvider.notifier)
                        .saveModel(normalized);
                  },
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Repository and branch selection
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SlashDropDown(
                          hintText: 'Select Repository',
                          value: selectedRepo,
                          items:
                              repos.map<DropdownMenuItem<dynamic>>((repo) {
                                return DropdownMenuItem<dynamic>(
                                  value: repo,
                                  child: SlashText(
                                    repo['full_name'] ?? repo['name'],
                                    fontSize: 12,
                                  ),
                                );
                              }).toList(),
                          onChanged: (repo) {
                            promptController.setSelectedRepo(repo);
                            repoController.selectRepo(repo);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (promptState.branches.isNotEmpty)
                        SlashDropDown(
                          width: 80,
                          color: colors.always8B5CF6,
                          value: promptState.selectedBranch,
                          items:
                              promptState.branches
                                  .map<DropdownMenuItem<String>>((branch) {
                                    return DropdownMenuItem<String>(
                                      value: branch,
                                      child: SlashText(
                                        branch,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  })
                                  .toList(),
                          onChanged: (branch) {
                            promptController.setSelectedBranch(branch);
                          },
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                const Divider(height: 0.5),

                // Chat messages: always keep view pinned to the latest message
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      // Let user scroll freely; we only snap if already near bottom (handled in _autoScrollToBottom).
                      return false;
                    },
                    child: NotificationListener<SizeChangedLayoutNotification>(
                      onNotification: (_) {
                        _autoScrollToBottom();
                        return false;
                      },
                      child: SizeChangedLayoutNotifier(
                        child: ListView.builder(
                          controller: _chatController,
                          padding: const EdgeInsets.all(16),
                          itemCount: promptState.messages.length,
                          itemBuilder: (context, idx) {
                            final msg = promptState.messages[idx];
                            final isLast =
                                idx == promptState.messages.length - 1;

                            if (msg.review != null) {
                              if (isLast) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  _autoScrollToBottom();
                                });
                              }
                              return ReviewBubble(
                                review: msg.review!,
                                summary: msg.text,
                                isLast: isLast,
                              );
                            }

                            final isLastAgent =
                                !msg.isUser &&
                                idx ==
                                    promptState.messages.lastIndexWhere(
                                      (m) => !m.isUser,
                                    );

                            if (isLast) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _autoScrollToBottom();
                              });
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (isLastAgent)
                                  IntentTag(intent: promptState.lastIntent),
                                ChatMessageBubble(message: msg),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // Error message
                if (errorDetails != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _PromptErrorBanner(
                      details: errorDetails,
                      onDismiss: promptController.clearError,
                    ),
                  ),

                // Input field and send button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      slashIconButton(
                        asset: 'assets/icons/attach.svg',
                        hasContainer: false,
                        color: colors.always909090.withValues(alpha: 0.2),
                        onPressed:
                            promptState.isLoading
                                ? () {}
                                : () => _showFilePickerModal(context),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SlashTextField(
                          controller: _promptTextController,
                          hint: 'Type a prompt…',
                          minLines: 4,
                          maxLines: 8,
                          suffix: Container(
                            margin: const EdgeInsets.only(bottom: 5.0),
                            child: slashIconButton(
                              icon: Icons.arrow_upward,
                              onPressed:
                                  promptState.isLoading
                                      ? () {}
                                      : _handlePromptSubmit,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                    ],
                  ),
                ),

                // Repo context files display
                if (promptState.repoContextFiles.isNotEmpty)
                  ContextFilesDisplay(
                    contextFiles: promptState.repoContextFiles,
                    onRemoveFile:
                        (file) => promptController.removeContextFile(file),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PromptErrorBanner extends StatelessWidget {
  final FriendlyErrorDetails details;
  final VoidCallback onDismiss;

  const _PromptErrorBanner({required this.details, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SlashText(
                  details.title,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 4),
                SlashText(
                  details.message,
                  color: theme.colorScheme.onErrorContainer,
                ),
                if ((details.recovery ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SlashText(
                    details.recovery!,
                    fontSize: 12,
                    color: theme.colorScheme.onErrorContainer.withValues(
                      alpha: 0.9,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: Icon(
              Icons.close_rounded,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}
