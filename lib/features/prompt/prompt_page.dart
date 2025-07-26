import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/dart.dart';
import 'package:slash_flutter/features/prompt/code_editor_controller.dart';
import 'package:slash_flutter/ui/components/option_selection.dart';
import 'package:slash_flutter/ui/components/slash_dropdown.dart';
import 'package:slash_flutter/ui/components/slash_loading.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'package:slash_flutter/ui/components/slash_toast.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';
import '../../ui/components/slash_text_field.dart';
import '../../ui/components/slash_button.dart';
import '../../ui/components/slash_diff_viewer.dart';
import '../repo/repo_controller.dart';
import '../file_browser/file_browser_controller.dart';
import 'prompt_controller.dart';

final tabIndexProvider = StateProvider<int>((ref) => 1); // 1 = prompt, 2 = code

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

    _promptTextController.clear();
    await ref.read(promptControllerProvider.notifier).submitPrompt(prompt);
  }

  void _showFilePickerModal(BuildContext context) async {
    final repoState = ref.read(repoControllerProvider);
    final promptState = ref.read(promptControllerProvider);
    final repo = promptState.selectedRepo ?? repoState.selectedRepo;

    if (repo == null) {
      SlashToast.showError(context, 'No repository selected.');
      return;
    }

    final owner = repo['owner']['login'];
    final repoName = repo['name'];
    final params = RepoParams(owner: owner, repo: repoName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _LazyFilePickerModal(
          params: params,
          initiallySelected: promptState.repoContextFiles,
          onSelected: (selected) {
            ref
                .read(promptControllerProvider.notifier)
                .setRepoContextFiles(selected);
          },
        );
      },
    );
  }

  Widget _intentTag(String? intent) {
    if (intent == null) return const SizedBox.shrink();

    Color color;
    String label;

    switch (intent) {
      case 'code_edit':
        color = Colors.blueAccent;
        label = 'Code Edit';
        break;
      case 'repo_question':
        color = Colors.orangeAccent;
        label = 'Repo Q';
        break;
      case 'general':
      default:
        color = Colors.green;
        label = 'General';
        break;
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        child: Chip(
          label: SlashText(label, color: Colors.white),
          backgroundColor: color,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        ),
      ),
    );
  }

  Widget _buildReviewBubble(ReviewData review, String summary, bool isLast) {
    final promptState = ref.watch(promptControllerProvider);
    final controller = ref.read(promptControllerProvider.notifier);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.android,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => controller.toggleReviewExpanded(),
                    child: Row(
                      children: [
                        Flexible(child: SlashText(summary)),
                        const SizedBox(width: 8),
                        Icon(
                          promptState.reviewExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (promptState.reviewExpanded && isLast) ...[
              const SizedBox(height: 12),
              SlashText(review.fileName),
              const SizedBox(height: 8),
              SlashDiffViewer(
                oldContent: review.oldContent,
                newContent: review.newContent,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blueAccent),
                    tooltip: 'Edit code',
                    onPressed:
                        promptState.isLoading
                            ? null
                            : () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder:
                                    (ctx) => AlertDialog(
                                      title: const SlashText('Manual Edit'),
                                      content: const SlashText(
                                        'You will be routed to the code editor to manually edit the AI\'s output.\n\nAfter editing, tap the green check to save your changes.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed:
                                              () =>
                                                  Navigator.of(ctx).pop(false),
                                          child: const SlashText('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed:
                                              () => Navigator.of(ctx).pop(true),
                                          child: const SlashText('Continue'),
                                        ),
                                      ],
                                    ),
                              );

                              if (confirm != true) return;

                              // Set the external edit request and switch to code tab
                              final container = ProviderScope.containerOf(
                                context,
                                listen: false,
                              );
                              container
                                  .read(externalEditRequestProvider.notifier)
                                  .state = ExternalEditRequest(
                                fileName: review.fileName,
                                code: review.newContent,
                              );
                              container.read(tabIndexProvider.notifier).state =
                                  2; // Switch to code tab
                            },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 28,
                    ),
                    tooltip: 'Approve and PR',
                    onPressed:
                        promptState.isLoading
                            ? null
                            : () => controller.approveReview(review, summary),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red, size: 28),
                    tooltip: 'Reject',
                    onPressed:
                        promptState.isLoading ? null : controller.rejectReview,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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
                  options: ["Gemini", "OpenAI"],
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
                                    fontSize: 14,
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
                                        fontSize: 14,
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
                        return _buildReviewBubble(
                          msg.review!,
                          msg.text,
                          idx == promptState.messages.length - 1,
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
                          if (isLastAgent) _intentTag(promptState.lastIntent),
                          Align(
                            alignment:
                                msg.isUser
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color:
                                    msg.isUser
                                        ? Theme.of(context).colorScheme.primary
                                            .withValues(alpha: 0.12)
                                        : Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow:
                                    msg.isUser
                                        ? []
                                        : [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.04,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!msg.isUser)
                                    Container(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: slashIconButton(
                                        asset: 'assets/icons/bot.svg',
                                        iconSize: 24,
                                        onPressed: () {},
                                      ),
                                    ),
                                  Flexible(
                                    child: Container(
                                      padding: EdgeInsets.all(
                                        !msg.isUser ? 8 : 0,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            !msg.isUser
                                                ? colors.always909090
                                                    .withValues(alpha: 0.12)
                                                : null,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: SlashText(
                                        msg.text,
                                        color:
                                            msg.isUser
                                                ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                                : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // Loading indicator
                if (promptState.isLoading)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(child: _ThinkingWidget()),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        const SlashText(
                          'Context:',
                          fontWeight: FontWeight.bold,
                        ),
                        ...promptState.repoContextFiles.map(
                          (f) => Chip(
                            label: SlashText(f.name, fontSize: 12),
                            onDeleted:
                                () => promptController.removeContextFile(f),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Add Repo Context Button
                // Padding(
                //   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                //   child: Align(
                //     alignment: Alignment.centerLeft,
                //     child: SlashButton(
                //       text: 'Add Repo Context',
                //       // icon: Icons.folder_open,
                //       onPressed:
                //           promptState.isLoading
                //               ? () {}
                //               : () => _showFilePickerModal(context),
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Creative thinking widget (animated ellipsis)
class _ThinkingWidget extends StatefulWidget {
  @override
  State<_ThinkingWidget> createState() => _ThinkingWidgetState();
}

class _ThinkingWidgetState extends State<_ThinkingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _dots;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    _dots = StepTween(begin: 0, end: 3).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dots,
      builder: (context, child) {
        final dots = '.' * _dots.value;
        return SlashText(
          'Thinking$dots',
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.primary,
        );
      },
    );
  }
}

// File picker modal widget
class _LazyFilePickerModal extends ConsumerStatefulWidget {
  final RepoParams params;
  final List<FileItem> initiallySelected;
  final void Function(List<FileItem>) onSelected;

  const _LazyFilePickerModal({
    required this.params,
    required this.initiallySelected,
    required this.onSelected,
  });

  @override
  ConsumerState<_LazyFilePickerModal> createState() =>
      _LazyFilePickerModalState();
}

class _LazyFilePickerModalState extends ConsumerState<_LazyFilePickerModal> {
  late List<FileItem> selected;
  late List<String> pathStack;

  @override
  void initState() {
    super.initState();
    selected = List<FileItem>.from(widget.initiallySelected);
    pathStack = [];
  }

  void _onFileTap(FileItem file, FileBrowserController controller) async {
    if (selected.any((f) => f.path == file.path)) {
      setState(() {
        selected.removeWhere((f) => f.path == file.path);
      });
    } else if (selected.length < 3) {
      await controller.selectFile(file);
      setState(() {
        final idx = controller.state.selectedFiles.indexWhere(
          (f) => f.path == file.path,
        );
        if (idx != -1) {
          selected.add(controller.state.selectedFiles[idx]);
        } else {
          selected.add(file);
        }
      });
    }
  }

  void _enterDir(String dirName) {
    setState(() {
      pathStack.add(dirName);
    });
  }

  void _goUp() {
    if (pathStack.isNotEmpty) {
      setState(() {
        pathStack.removeLast();
      });
    }
  }

  String get _currentPath => pathStack.isEmpty ? '' : pathStack.join('/');

  Widget _buildDir(FileBrowserController controller, FileBrowserState state) {
    if (state.isLoading) {
      return const Center(child: SlashLoading());
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListView(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        children:
            state.items.map((item) {
              if (item.type == 'dir') {
                return ListTile(
                  leading: const Icon(Icons.folder, color: Colors.amber),
                  title: SlashText(item.name, fontWeight: FontWeight.w500),
                  onTap: () {
                    _enterDir(item.name);
                    controller.fetchDir(
                      _currentPath + (pathStack.isEmpty ? '' : '/'),
                    );
                  },
                );
              } else {
                final isSelected = selected.any((f) => f.path == item.path);
                return ListTile(
                  leading: const Icon(
                    Icons.insert_drive_file,
                    color: Colors.blueAccent,
                  ),
                  title: SlashText(item.name),
                  subtitle: SlashText(
                    item.path,
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _onFileTap(item, controller),
                  ),
                  onTap: () => _onFileTap(item, controller),
                );
              }
            }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(
      fileBrowserControllerProvider(widget.params).notifier,
    );
    final state = ref.watch(fileBrowserControllerProvider(widget.params));

    // Fetch the current directory if needed
    if (state.pathStack.join('/') != _currentPath) {
      controller.fetchDir(_currentPath);
    }

    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).dialogBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with back button and breadcrumbs
            Row(
              children: [
                if (pathStack.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Up',
                    onPressed: _goUp,
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SlashText(
                      pathStack.isEmpty ? '/' : '/${pathStack.join('/')}',
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SlashText(
              'Select up to 3 files for context',
              fontWeight: FontWeight.bold,
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildDir(controller, state)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SlashButton(
                    text: 'Done',
                    // icon: Icons.check,
                    onPressed: () {
                      widget.onSelected(selected);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SlashButton(
                    text: 'Cancel',
                    // icon: Icons.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Code editor screen for manual editing
class CodeEditorScreen extends StatefulWidget {
  final String fileName;
  final String initialCode;

  const CodeEditorScreen({
    required this.fileName,
    required this.initialCode,
    super.key,
  });

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  late final CodeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CodeController(
      text: widget.initialCode,
      language: dart,
      patternMap: {
        r'\bTODO\b': const TextStyle(
          backgroundColor: Colors.yellow,
          color: Colors.black,
        ),
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC);
    final editorBg = isDark ? const Color(0xFF23232A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF333842) : Colors.grey[300]!;
    final gutterColor = isDark ? const Color(0xFF23232A) : Colors.grey[200]!;
    final lineNumberColor =
        isDark ? const Color(0xFF8B949E) : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: editorBg,
        elevation: 1,
        title: Row(
          children: [
            const Icon(Icons.code, color: Color(0xFF8B5CF6)),
            const SizedBox(width: 8),
            Flexible(
              child: SlashText(
                widget.fileName,
                fontFamily: 'Fira Mono',
                fontSize: 16,
                color: Colors.white,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 26),
            tooltip: 'Save',
            onPressed: () => Navigator.of(context).pop(_controller.text),
          ),
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.red, size: 26),
            tooltip: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
          decoration: BoxDecoration(
            color: editorBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: CodeTheme(
              data: CodeThemeData(),
              child: CodeField(
                controller: _controller,
                textStyle: const TextStyle(
                  fontFamily: 'Fira Mono',
                  fontSize: 15,
                  color: Colors.white,
                ),
                expands: true,
                lineNumberStyle: LineNumberStyle(
                  width: 32,
                  textAlign: TextAlign.right,
                  textStyle: TextStyle(
                    color: lineNumberColor,
                    fontSize: 12,
                    fontFamily: 'Fira Mono',
                  ),
                  background: gutterColor,
                  margin: 6.0,
                ),
                background: Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
