import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/dart.dart';
import 'package:slash_flutter/features/file_browser/file_browser_controller.dart';
import 'package:slash_flutter/features/prompt/code_editor_controller.dart';
import 'package:slash_flutter/features/prompt/prompt_controller.dart';
import 'package:slash_flutter/ui/components/slash_loading.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'package:slash_flutter/ui/components/slash_button.dart';
import 'package:slash_flutter/ui/components/slash_diff_viewer.dart';

// Tab index provider - moved here to be accessible by widgets
final tabIndexProvider = StateProvider<int>((ref) => 1); // 1 = prompt, 2 = code

// Intent tag widget
class IntentTag extends StatelessWidget {
  final String? intent;

  const IntentTag({
    super.key,
    required this.intent,
  });

  @override
  Widget build(BuildContext context) {
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
}

// Chat message bubble widget
class ChatMessageBubble extends ConsumerWidget {
  final dynamic message; // Replace with your Message type

  const ChatMessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msg = message;
    
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: msg.isUser
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: msg.isUser
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
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
                padding: EdgeInsets.all(!msg.isUser ? 8 : 0),
                decoration: BoxDecoration(
                  color: !msg.isUser
                      ? Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.12)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SlashText(
                  msg.text,
                  color: msg.isUser
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Review bubble widget
class ReviewBubble extends ConsumerWidget {
  final dynamic review; // Replace with your ReviewData type
  final String summary;
  final bool isLast;

  const ReviewBubble({
    super.key,
    required this.review,
    required this.summary,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              ReviewActionButtons(review: review, summary: summary),
            ],
          ],
        ),
      ),
    );
  }
}

// Review action buttons widget
class ReviewActionButtons extends ConsumerWidget {
  final dynamic review; // Replace with your ReviewData type
  final String summary;

  const ReviewActionButtons({
    super.key,
    required this.review,
    required this.summary,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promptState = ref.watch(promptControllerProvider);
    final controller = ref.read(promptControllerProvider.notifier);

    return Row(
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
                      title: const SlashText('Manual Edit'),
                      content: const SlashText(
                        'You will be routed to the code editor to manually edit the AI\'s output.\n\nAfter editing, tap the green check to save your changes.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const SlashText('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
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
    );
  }
}

// Thinking widget (animated ellipsis)
class ThinkingWidget extends StatefulWidget {
  const ThinkingWidget({super.key});

  @override
  State<ThinkingWidget> createState() => _ThinkingWidgetState();
}

class _ThinkingWidgetState extends State<ThinkingWidget>
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

// Context files display widget
class ContextFilesDisplay extends StatelessWidget {
  final List<FileItem> contextFiles; // Changed back to FileItem
  final void Function(FileItem) onRemoveFile; // Changed back to FileItem

  const ContextFilesDisplay({
    super.key,
    required this.contextFiles,
    required this.onRemoveFile,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          ...contextFiles.map(
            (f) => Chip(
              label: SlashText(f.name, fontSize: 12),
              onDeleted: () => onRemoveFile(f),
            ),
          ),
        ],
      ),
    );
  }
}

// File picker modal widget
class LazyFilePickerModal extends ConsumerStatefulWidget {
  final RepoParams params;
  final List<FileItem> initiallySelected; // Changed back to FileItem
  final void Function(List<FileItem>) onSelected; // Changed back to FileItem

  const LazyFilePickerModal({
    super.key,
    required this.params,
    required this.initiallySelected,
    required this.onSelected,
  });

  @override
  ConsumerState<LazyFilePickerModal> createState() =>
      _LazyFilePickerModalState();
}

class _LazyFilePickerModalState extends ConsumerState<LazyFilePickerModal> {
  late List<FileItem> selected; // Changed back to FileItem
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
        children: state.items.map((item) {
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