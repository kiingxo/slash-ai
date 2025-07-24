import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/dart.dart';
import 'package:slash_flutter/features/prompt/code_editor_controller.dart';
import '../../ui/components/slash_text_field.dart';
import '../../ui/components/slash_button.dart';
import '../../ui/components/slash_diff_viewer.dart';
import '../repo/repo_controller.dart';
import '../file_browser/file_browser_controller.dart';
import 'prompt_controller.dart';
import 'code_page.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No repository selected.')),
      );
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
            ref.read(promptControllerProvider.notifier).setRepoContextFiles(selected);
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
          label: Text(label, style: const TextStyle(color: Colors.white)),
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
                        Flexible(
                          child: Text(
                            summary,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
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
              Text(
                review.fileName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
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
                    onPressed: promptState.isLoading
                        ? null
                        : () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Manual Edit'),
                                content: const Text(
                                  'You will be routed to the code editor to manually edit the AI\'s output.\n\nAfter editing, tap the green check to save your changes.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    child: const Text('Continue'),
                                  ),
                                ],
                              ),
                            );
                            
                            if (confirm != true) return;
                            
                            // Set the external edit request and switch to code tab
                            final container = ProviderScope.containerOf(context, listen: false);
                            container
                                .read(externalEditRequestProvider.notifier)
                                .state = ExternalEditRequest(
                              fileName: review.fileName,
                              code: review.newContent,
                            );
                            container.read(tabIndexProvider.notifier).state = 2; // Switch to code tab
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
                    onPressed: promptState.isLoading
                        ? null
                        : () => controller.approveReview(review, summary),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red, size: 28),
                    tooltip: 'Reject',
                    onPressed: promptState.isLoading ? null : controller.rejectReview,
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
    final selectedRepo = promptState.selectedRepo ?? 
                        repoState.selectedRepo ?? 
                        (repos.isNotEmpty ? repos[0] : null);

    if (repoState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (repos.isEmpty) {
      return const Center(
        child: Text('No repositories found.', style: TextStyle(fontSize: 18)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Image.asset('assets/slash2.png', height: 100),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: promptState.selectedModel,
                items: const [
                  DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                  DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                ],
                onChanged: (val) {
                  if (val != null) promptController.setSelectedModel(val);
                },
                style: Theme.of(context).textTheme.bodyMedium,
                dropdownColor: Theme.of(context).cardColor,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Repository and branch selection
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButton<dynamic>(
                      value: selectedRepo,
                      isExpanded: true,
                      items: repos.map<DropdownMenuItem<dynamic>>((repo) {
                        return DropdownMenuItem<dynamic>(
                          value: repo,
                          child: Text(repo['full_name'] ?? repo['name']),
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
                    DropdownButton<String>(
                      value: promptState.selectedBranch,
                      items: promptState.branches
                          .map((branch) => DropdownMenuItem<String>(
                                value: branch,
                                child: Text(branch),
                              ))
                          .toList(),
                      onChanged: (branch) {
                        promptController.setSelectedBranch(branch);
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            
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
                  final isLastAgent = !msg.isUser &&
                      idx == promptState.messages.lastIndexWhere((m) => !m.isUser);
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isLastAgent) _intentTag(promptState.lastIntent),
                      Align(
                        alignment: msg.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: msg.isUser
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: msg.isUser
                                ? []
                                : [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
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
                                Padding(
                                  padding: const EdgeInsets.only(right: 8, top: 2),
                                  child: Text(
                                    '🤖',
                                    style: TextStyle(
                                      fontSize: 22,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              Flexible(
                                child: Text(
                                  msg.text,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: msg.isUser
                                        ? Theme.of(context).colorScheme.primary
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
                child: Text(
                  promptState.error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            
            // Input field and send button
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: SlashTextField(
                      controller: _promptTextController,
                      hint: 'Type a prompt…',
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SlashButton(
                      label: 'Send',
                      onTap: promptState.isLoading ? () {} : _handlePromptSubmit,
                      icon: Icons.send,
                    ),
                  ),
                ],
              ),
            ),
            
            // Repo context files display
            if (promptState.repoContextFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Wrap(
                  spacing: 6,
                  children: [
                    const Text(
                      'Context:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...promptState.repoContextFiles.map((f) => Chip(
                          label: Text(f.name, style: const TextStyle(fontSize: 12)),
                          onDeleted: () => promptController.removeContextFile(f),
                        )),
                  ],
                ),
              ),
            
            // Add Repo Context Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SlashButton(
                  label: 'Add Repo Context',
                  icon: Icons.folder_open,
                  onTap: promptState.isLoading 
                      ? () {} 
                      : () => _showFilePickerModal(context),
                ),
              ),
            ),
          ],
        ),
      ),
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
        return Text(
          'Thinking$dots',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.primary,
              ),
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
  ConsumerState<_LazyFilePickerModal> createState() => _LazyFilePickerModalState();
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
        final idx = controller.state.selectedFiles.indexWhere((f) => f.path == file.path);
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
      return const Center(child: CircularProgressIndicator());
    }
    
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListView(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        children: state.items.map((item) {
          if (item.type == 'dir') {
            return ListTile(
              leading: const Icon(Icons.folder, color: Colors.amber),
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                _enterDir(item.name);
                controller.fetchDir(_currentPath + (pathStack.isEmpty ? '' : '/'));
              },
            );
          } else {
            final isSelected = selected.any((f) => f.path == item.path);
            return ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.blueAccent),
              title: Text(item.name),
              subtitle: Text(
                item.path,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
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
    final controller = ref.read(fileBrowserControllerProvider(widget.params).notifier);
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
                    child: Text(
                      pathStack.isEmpty ? '/' : '/${pathStack.join('/')}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
            const Text(
              'Select up to 3 files for context',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildDir(controller, state)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SlashButton(
                    label: 'Done',
                    icon: Icons.check,
                    onTap: () {
                      widget.onSelected(selected);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SlashButton(
                    label: 'Cancel',
                    icon: Icons.close,
                    onTap: () => Navigator.of(context).pop(),
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
    final lineNumberColor = isDark ? const Color(0xFF8B949E) : Colors.grey[600]!;
    
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
              child: Text(
                widget.fileName,
                style: const TextStyle(fontFamily: 'Fira Mono', fontSize: 16, color: Colors.white),
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