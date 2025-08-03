import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/dart.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import '../repo/repo_controller.dart';
import '../file_browser/file_browser_controller.dart';
import '../../ui/components/slash_text_field.dart';
import '../../ui/components/slash_button.dart';
import 'code_editor_controller.dart';
import 'prompt_controller.dart';

class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key});

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  late CodeController _codeController;
  bool _sidebarExpanded = false;
  bool _showChatOverlay = false;
  Offset _chatOverlayOffset = const Offset(60, 120);
  final TextEditingController _chatController = TextEditingController();

  // UI polish: remember last editor size and clamp overlay within bounds
  Size? _lastBodySize;

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(text: '', language: dart);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for external edit requests
    final req = ref.read(externalEditRequestProvider);
    if (req != null) {
      ref
          .read(codeEditorControllerProvider.notifier)
          .handleExternalEdit(req, _codeController);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repoState = ref.watch(repoControllerProvider);
    final codeState = ref.watch(codeEditorControllerProvider);
    final repos = repoState.repos;
    final selectedRepo =
        codeState.selectedRepo ?? (repos.isNotEmpty ? repos[0] : null);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final params =
        selectedRepo != null
            ? RepoParams(
              owner: selectedRepo['owner']['login'],
              repo: selectedRepo['name'],
              branch: codeState.selectedBranch,
            )
            : null;

    final fileBrowserState =
        params != null
            ? ref.watch(fileBrowserControllerProvider(params))
            : null;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC),
      appBar: _buildAppBar(
        context,
        theme,
        isDark,
        repos,
        selectedRepo,
        codeState,
      ),
      floatingActionButton: _buildFloatingActionButton(
        codeState.branches,
        selectedRepo,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _lastBodySize = Size(constraints.maxWidth, constraints.maxHeight);
          final isNarrow = constraints.maxWidth < 720;

          return Stack(
            children: [
              Row(
                children: [
                  // On very small widths, collapse the sidebar
                  if (!isNarrow)
                    _buildSidebar(context, theme, isDark, params, fileBrowserState)
                  else
                    _buildCollapsedSidebarButton(context, params, fileBrowserState),
                  Expanded(child: _buildEditorArea(context, theme, isDark, codeState, isNarrow: isNarrow)),
                ],
              ),
              if (_showChatOverlay) _buildChatOverlay(context, codeState),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    List<dynamic> repos,
    dynamic selectedRepo,
    CodeEditorState codeState,
  ) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF23232A) : Colors.white,
      elevation: 1,
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.code, color: Color(0xFF8B5CF6)),
            const SizedBox(width: 12),
            const SlashText('Code Editor', fontWeight: FontWeight.bold),
            const SizedBox(width: 24),
            if (repos.isNotEmpty)
              DropdownButton<dynamic>(
                value: selectedRepo,
                items:
                    repos.map<DropdownMenuItem<dynamic>>((repo) {
                      return DropdownMenuItem<dynamic>(
                        value: repo,
                        child: SlashText(repo['full_name'] ?? repo['name']),
                      );
                    }).toList(),
                onChanged: (repo) {
                  ref
                      .read(codeEditorControllerProvider.notifier)
                      .selectRepo(repo);
                },
                style: theme.textTheme.bodyMedium,
                dropdownColor: theme.cardColor,
              ),
          ],
        ),
      ),
      actions: [
        // Model toggle for the code screen (Gemini / OpenRouter) — local to code editor
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black.withOpacity(0.08)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: ref.watch(codeEditorControllerProvider).codeModel,
              hint: const SlashText('AI: Gemini', fontSize: 12),
              items: const [
                DropdownMenuItem(value: 'gemini', child: SlashText('Gemini', fontSize: 12)),
                DropdownMenuItem(value: 'openrouter', child: SlashText('OpenRouter', fontSize: 12)),
              ],
              onChanged: (val) {
                if (val == null) return;
                final current = ref.read(codeEditorControllerProvider);
                ref.read(codeEditorControllerProvider.notifier)
                   .state = current.copyWith(codeModel: val);
              },
              icon: const Icon(Icons.smart_toy_outlined, size: 16),
              dropdownColor: theme.cardColor,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        if (codeState.branches.isNotEmpty)
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: codeState.selectedBranch,
              hint: const SlashText('Branch'),
              onChanged: (branch) {
                if (selectedRepo != null && branch != null) {
                  ref
                      .read(codeEditorControllerProvider.notifier)
                      .selectBranch(branch, selectedRepo);
                }
              },
              items:
                  codeState.branches.map((b) {
                    return DropdownMenuItem(value: b, child: SlashText(b));
                  }).toList(),
              dropdownColor: theme.cardColor,
              icon: const Icon(Icons.alt_route),
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }

  Widget? _buildFloatingActionButton(
    List<String> branches,
    dynamic selectedRepo,
  ) {
    return (branches.isNotEmpty && selectedRepo != null)
        ? FloatingActionButton(
          heroTag: 'ai_assistant_fab',
          tooltip: 'AI Assistant',
          onPressed: () {
            setState(() {
              _showChatOverlay = true;
            });
          },
          child: const SlashText('🤖', fontSize: 24),
        )
        : null;
  }

  // Compact sidebar launcher on small screens
  Widget _buildCollapsedSidebarButton(BuildContext context, RepoParams? params, dynamic fileBrowserState) {
    return Container(
      width: 52,
      alignment: Alignment.topCenter,
      child: IconButton(
        tooltip: 'Files',
        icon: const Icon(Icons.folder_open),
        onPressed: () {
          _openFilesBottomSheet(context, params);
        },
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    RepoParams? params,
    dynamic fileBrowserState,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: _sidebarExpanded ? 220 : 64,
      color: isDark ? const Color(0xFF23232A) : Colors.grey[100],
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: Icon(
                _sidebarExpanded ? Icons.chevron_left : Icons.chevron_right,
                size: 22,
              ),
              tooltip: _sidebarExpanded ? 'Collapse' : 'Expand',
              onPressed:
                  () => setState(() => _sidebarExpanded = !_sidebarExpanded),
            ),
          ),
          Expanded(
            child:
                params == null
                    ? Container(
                      alignment: Alignment.center,
                      child: const SlashText('No repo selected'),
                    )
                    : fileBrowserState == null || fileBrowserState.isLoading
                    ? Container(
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    )
                    : _buildFileList(params, fileBrowserState),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(RepoParams params, dynamic fileBrowserState) {
    return Column(
      children: [
        if (fileBrowserState.pathStack.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Up',
              onPressed: () {
                ref.read(fileBrowserControllerProvider(params).notifier).goUp();
              },
            ),
          ),
        Expanded(
          child: ListView(
            shrinkWrap: true,
            children:
                fileBrowserState.items.map<Widget>((item) {
                  if (_sidebarExpanded) {
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        item.type == 'dir'
                            ? Icons.folder
                            : Icons.insert_drive_file,
                        color:
                            item.type == 'dir'
                                ? Colors.amber
                                : Colors.blueAccent,
                      ),
                      title: SlashText(
                        item.name,
                        fontWeight: item.type == 'dir' ? FontWeight.w500 : null,
                      ),
                      selected:
                          ref
                              .watch(codeEditorControllerProvider)
                              .selectedFilePath ==
                          item.path,
                      onTap: () => _handleFileItemTap(item, params),
                    );
                  } else {
                    return Container(
                      width: 48,
                      height: 40,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _handleFileItemTap(item, params),
                        child: Icon(
                          item.type == 'dir'
                              ? Icons.folder
                              : Icons.insert_drive_file,
                          color:
                              item.type == 'dir'
                                  ? Colors.amber
                                  : Colors.blueAccent,
                        ),
                      ),
                    );
                  }
                }).toList(),
          ),
        ),
      ],
    );
  }

  void _handleFileItemTap(dynamic item, RepoParams params) {
    if (item.type == 'dir') {
      ref
          .read(fileBrowserControllerProvider(params).notifier)
          .enterDir(item.name);
    } else {
      ref
          .read(codeEditorControllerProvider.notifier)
          .loadFile(item.path, params, ref, _codeController);
    }
  }

  Widget _buildEditorArea(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    CodeEditorState codeState, {
    bool isNarrow = false,
  }) {
    return codeState.selectedFilePath == null
        ? Center(child: Padding(
            padding: const EdgeInsets.all(16),
            child: SlashText('Select a file to edit', fontSize: 16),
          ))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTabsHeader(codeState),
              _buildFileHeader(isDark, codeState.selectedFilePath),
              // Add safe horizontal scroll to avoid overflow on long lines
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(isNarrow ? 8 : 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: c.maxWidth),
                            child: SizedBox(
                              width: c.maxWidth,
                              child: _buildCodeEditor(isDark: isDark, compact: isNarrow),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              _buildActionsBar(isDark, codeState),
            ],
          );
  }

  Widget _buildFileHeader(bool isDark, String? selectedFilePath) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23232A) : Colors.grey[100],
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[900]! : Colors.grey[300]!,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file, color: Colors.blueAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SlashText(
              selectedFilePath ?? '',
              fontFamily: 'Fira Mono',
              fontSize: 14,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _smallChip(icon: Icons.search, label: 'Find'),
          const SizedBox(width: 6),
          _smallChip(icon: Icons.auto_fix_high, label: 'Refactor'),
        ],
      ),
    );
  }

  Widget _buildCodeEditor({required bool isDark, bool compact = false}) {
    return CodeTheme(
      data: CodeThemeData(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0E0E12) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB)),
        ),
        child: CodeField(
          controller: _codeController,
          textStyle: TextStyle(
            fontFamily: 'Fira Mono',
            fontSize: compact ? 13 : 15,
            color: isDark ? Colors.white : const Color(0xFF111827),
          ),
          expands: true,
          lineNumberStyle: LineNumberStyle(
            width: compact ? 32 : 40,
            textAlign: TextAlign.right,
          ),
          gutterStyle: GutterStyle(
            margin: compact ? 6 : 8,
          ),
          background: Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildActionsBar(bool isDark, CodeEditorState codeState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23232A) : Colors.grey[100],
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[900]! : Colors.grey[300]!,
          ),
        ),
      ),
      child: Row(
        children: [
          _iconButton(
            tooltip: 'Hide Keyboard',
            icon: Icons.keyboard_hide,
            onTap: () => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(width: 8),
          _iconButton(
            tooltip: 'AI Assistant',
            icon: Icons.smart_toy_outlined,
            onTap: () => setState(() => _showChatOverlay = true),
          ),
          const Spacer(),
          SizedBox(
            height: 32,
            child: ElevatedButton.icon(
              icon: codeState.isCommitting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload, size: 16),
              label: SlashText(codeState.isCommitting ? 'Committing…' : 'Commit & Push', fontSize: 13),
              onPressed: codeState.isCommitting
                  ? null
                  : () => ref.read(codeEditorControllerProvider.notifier).commitAndPushFile(context, _codeController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatOverlay(BuildContext context, CodeEditorState codeState) {
    final size = _lastBodySize ?? MediaQuery.of(context).size;
    final overlayW = size.width < 380 ? size.width - 24 : 320.0;
    final overlayH = size.height < 520 ? size.height * 0.6 : 360.0;

    double clampX(double x) => x.clamp(8.0, (size.width - overlayW) - 8.0);
    double clampY(double y) => y.clamp(60.0, (size.height - overlayH) - 8.0);

    // Tap outside to close keyboard, like typical chat apps
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Positioned(
        left: clampX(_chatOverlayOffset.dx),
        top: clampY(_chatOverlayOffset.dy),
        child: Draggable(
          feedback: SizedBox(
            width: overlayW,
            height: overlayH,
            child: _ChatOverlay(
              messages: codeState.chatMessages,
              loading: codeState.chatLoading,
              controller: _chatController,
              onSend: () => _handleChatSend(codeState),
              onClose: () => setState(() => _showChatOverlay = false),
              onApplyEdit: codeState.pendingEdit != null
                  ? () => ref.read(codeEditorControllerProvider.notifier).applyAICodeEdit(_codeController)
                  : null,
            ),
          ),
          childWhenDragging: const SizedBox.shrink(),
          onDragEnd: (details) {
            setState(() {
              _chatOverlayOffset = Offset(clampX(details.offset.dx), clampY(details.offset.dy));
            });
          },
          child: SizedBox(
            width: overlayW,
            height: overlayH,
            child: _ChatOverlay(
              messages: codeState.chatMessages,
              loading: codeState.chatLoading,
              controller: _chatController,
              onSend: () => _handleChatSend(codeState),
              onClose: () => setState(() => _showChatOverlay = false),
              onApplyEdit: codeState.pendingEdit != null
                  ? () => ref.read(codeEditorControllerProvider.notifier).applyAICodeEdit(_codeController)
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  void _handleChatSend(CodeEditorState codeState) {
    final prompt = _chatController.text.trim();
    if (prompt.isEmpty) return;

    ref
        .read(codeEditorControllerProvider.notifier)
        .handleChatSend(
          prompt,
          _codeController.text,
          codeState.selectedFilePath ?? 'current.dart',
          ref,
        );
    _chatController.clear();
  }

  // Simple tabs header for UX (single active file)
  Widget _buildTabsHeader(CodeEditorState codeState) {
    final filePath = codeState.selectedFilePath ?? '';
    final fileName = filePath.split('/').isNotEmpty ? filePath.split('/').last : filePath;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, size: 16),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: SlashText(fileName, fontSize: 13, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Placeholder for future tabs actions
        ],
      ),
    );
  }

  // Small UI helpers
  Widget _iconButton({required String tooltip, required IconData icon, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: Ink(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withOpacity(0.25)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _smallChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.blue),
          const SizedBox(width: 4),
          SlashText(label, fontSize: 12, color: Colors.blue),
        ],
      ),
    );
  }

  // Bottom sheet for files on small screens
  void _openFilesBottomSheet(BuildContext context, RepoParams? params) {
    if (params == null) {
      showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: SlashText('No repo selected')),
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final fbState = ref.watch(fileBrowserControllerProvider(params));
        final notifier = ref.read(fileBrowserControllerProvider(params).notifier);

        return FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Icon(Icons.folder, color: Colors.amber),
                    const SizedBox(width: 8),
                    const Expanded(child: SlashText('Files', fontWeight: FontWeight.w600)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (fbState.isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: fbState.items.length + (fbState.pathStack.isNotEmpty ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (fbState.pathStack.isNotEmpty && index == 0) {
                        return ListTile(
                          leading: const Icon(Icons.arrow_upward),
                          title: const SlashText('Up'),
                          onTap: () => notifier.goUp(),
                        );
                      }
                      final i = fbState.pathStack.isNotEmpty ? index - 1 : index;
                      final item = fbState.items[i];
                      final isDir = item.type == 'dir';

                      return ListTile(
                        dense: true,
                        leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file,
                            color: isDir ? Colors.amber : Colors.blueAccent),
                        title: SlashText(item.name, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          if (isDir) {
                            notifier.enterDir(item.name);
                          } else {
                            ref.read(codeEditorControllerProvider.notifier).loadFile(item.path, params, ref, _codeController);
                            Navigator.of(ctx).pop();
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
class ChatMessage {
  final bool isUser;
  final String text;
  ChatMessage({required this.isUser, required this.text});
}

// Floating chat overlay widget
class _ChatOverlay extends StatelessWidget {
  final List<ChatMessage> messages;
  final bool loading;
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onClose;
  final VoidCallback? onApplyEdit;

  const _ChatOverlay({
    required this.messages,
    required this.loading,
    required this.controller,
    required this.onSend,
    required this.onClose,
    this.onApplyEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 280,
        height: 340,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(blurRadius: 16, color: Colors.black26)],
        ),
        child: Column(
          children: [
            _buildHeader(context),
            _buildMessagesList(context),
            if (onApplyEdit != null) _buildApplyEditButton(),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.chat_bubble, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          const Expanded(
            child: SlashText(
              'AI Chat',
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            onPressed: onClose,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(BuildContext context) {
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: messages.length + (loading ? 1 : 0),
        itemBuilder: (context, idx) {
          if (idx == messages.length && loading) {
            return const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final msg = messages[idx];
          final isUser = msg.isUser;
          final theme = Theme.of(context);

          return Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    isUser
                        ? theme.colorScheme.primary.withOpacity(0.12)
                        : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow:
                    isUser
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
                  if (!isUser)
                    Padding(
                      padding: const EdgeInsets.only(right: 6, top: 2),
                      child: SlashText(
                        '🤖',
                        fontSize: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  Flexible(
                    child: SlashText(
                      msg.text,
                      fontSize: 13,
                      color: isUser ? theme.colorScheme.primary : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildApplyEditButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.auto_fix_high),
          label: const SlashText('Apply AI Edit to Code', fontSize: 13),
          onPressed: onApplyEdit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.newline, // Show "Return" on keyboard
              onSubmitted: (_) {}, // Return inserts newline; sending via button only
              decoration: const InputDecoration(
                hintText: 'Ask about this code…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              minLines: 1,
              maxLines: 3,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 40,
            height: 36,
            child: ElevatedButton(
              onPressed: loading ? null : onSend,
              style: ElevatedButton.styleFrom(padding: EdgeInsets.zero),
              child: const Icon(Icons.send, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
