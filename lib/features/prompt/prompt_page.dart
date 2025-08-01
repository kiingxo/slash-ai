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
import '../repo/repo_controller.dart';
import '../file_browser/file_browser_controller.dart';
import 'prompt_controller.dart';

class PromptPage extends ConsumerStatefulWidget {
  const PromptPage({super.key});

  @override
  ConsumerState<PromptPage> createState() => _PromptPageState();
}

class _PromptPageState extends ConsumerState<PromptPage> {
  late TextEditingController _promptTextController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _promptTextController = TextEditingController();
  }

  @override
  void dispose() {
    _promptTextController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handlePromptSubmit() async {
    final prompt = _promptTextController.text.trim();
    if (prompt.isEmpty) return;

    // Validation checks
    final repoState = ref.read(repoControllerProvider);
    final promptState = ref.read(promptControllerProvider);
    final selectedRepo = promptState.selectedRepo ?? repoState.selectedRepo;

    // Check if repository is selected
    if (selectedRepo == null) {
      SlashToast.showError(context, 'Please select a repository before sending a message.');
      return;
    }

    // Check if at least one context file is selected
    if (promptState.repoContextFiles.isEmpty) {
      SlashToast.showError(context, 'Please select at least one context file before sending a message.');
      return;
    }

    _promptTextController.clear();
    await ref.read(promptControllerProvider.notifier).submitPrompt(prompt);
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
    final repoController = ref.read(repoControllerProvider.notifier);
    final promptController = ref.read(promptControllerProvider.notifier);

    final repos = repoState.repos;
    final selectedRepo =
        promptState.selectedRepo ??
        repoState.selectedRepo ??
        (repos.isNotEmpty ? repos[0] : null);

    if (repoState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (repos.isEmpty) {
      return const Center(child: SlashText('No repositories found.'));
    }

    return ThemeBuilder(
      builder: (context, colors, ref) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: colors.always8B5CF6.withValues(alpha: 0.1),
            title: Image.asset('assets/slash2.png', height: 100),
            centerTitle: false,
            toolbarHeight: 80,
            actions: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colors.alwaysEDEDED.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: OptionSelection(
                  options: ["Gemini", "OpenRouter"],
                  margin: 0,
                  padding: 8,
                  unselectedColor: Colors.transparent,
                  selectedValue: promptState.selectedModel,
                  onChanged: (val) {
                    promptController.setSelectedModel(val);
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

                // Chat messages
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: promptState.messages.length,
                    itemBuilder: (context, idx) {
                      final msg = promptState.messages[idx];

                      if (msg.review != null) {
                        // Review bubble
                        return ReviewBubble(
                          review: msg.review!,
                          summary: msg.text,
                          isLast: idx == promptState.messages.length - 1,
                        );
                      }

                      // Show intent tag above the latest agent message
                      final isLastAgent =
                          !msg.isUser &&
                          idx ==
                              promptState.messages.lastIndexWhere(
                                (m) => !m.isUser,
                              );

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

                // Loading indicator
                if (promptState.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: ThinkingWidget()),
                  ),

                // Error message
                if (promptState.error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SlashText(promptState.error!, color: Colors.red),
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
