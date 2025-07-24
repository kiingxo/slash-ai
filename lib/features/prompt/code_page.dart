import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/dart.dart';
import '../repo/repo_controller.dart';
import '../file_browser/file_browser_controller.dart';
import '../../ui/components/slash_text_field.dart';
import '../../ui/components/slash_button.dart';
import 'code_editor_controller.dart';
import 'code_editor_service.dart';

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
      ref.read(codeEditorControllerProvider.notifier).handleExternalEdit(req, _codeController);
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
    final selectedRepo = codeState.selectedRepo ?? (repos.isNotEmpty ? repos[0] : null);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final params = selectedRepo != null
        ? RepoParams(
            owner: selectedRepo['owner']['login'],
            repo: selectedRepo['name'],
            branch: codeState.selectedBranch,
          )
        : null;
    
    final fileBrowserState = params != null
        ? ref.watch(fileBrowserControllerProvider(params))
        : null;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC),
      appBar: _buildAppBar(context, theme, isDark, repos, selectedRepo, codeState),
      floatingActionButton: _buildFloatingActionButton(codeState.branches, selectedRepo),
      body: Stack(
        children: [
          Row(
            children: [
              _buildSidebar(context, theme, isDark, params, fileBrowserState),
              _buildEditorArea(context, theme, isDark, codeState),
            ],
          ),
          if (_showChatOverlay) _buildChatOverlay(context, codeState),
        ],
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
            const Text(
              'Code Editor',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 24),
            if (repos.isNotEmpty)
              DropdownButton<dynamic>(
                value: selectedRepo,
                items: repos.map<DropdownMenuItem<dynamic>>((repo) {
                  return DropdownMenuItem<dynamic>(
                    value: repo,
                    child: Text(repo['full_name'] ?? repo['name']),
                  );
                }).toList(),
                onChanged: (repo) {
                  ref.read(codeEditorControllerProvider.notifier).selectRepo(repo);
                },
                style: theme.textTheme.bodyMedium,
                dropdownColor: theme.cardColor,
              ),
          ],
        ),
      ),
      actions: [
        if (codeState.branches.isNotEmpty)
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: codeState.selectedBranch,
              hint: const Text('Branch'),
              onChanged: (branch) {
                if (selectedRepo != null && branch != null) {
                  ref.read(codeEditorControllerProvider.notifier).selectBranch(branch, selectedRepo);
                }
              },
              items: codeState.branches.map((b) {
                return DropdownMenuItem(value: b, child: Text(b));
              }).toList(),
              dropdownColor: theme.cardColor,
              icon: const Icon(Icons.alt_route),
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }

  Widget? _buildFloatingActionButton(List<String> branches, dynamic selectedRepo) {
    return (branches.isNotEmpty && selectedRepo != null)
        ? FloatingActionButton(
            heroTag: 'ai_assistant_fab',
            tooltip: 'AI Assistant',
            onPressed: () {
              setState(() {
                _showChatOverlay = true;
              });
            },
            child: const Text('🤖', style: TextStyle(fontSize: 24)),
          )
        : null;
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
              onPressed: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
            ),
          ),
          Expanded(
            child: params == null
                ? Container(
                    alignment: Alignment.center,
                    child: const Text('No repo selected'),
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
            children: fileBrowserState.items.map<Widget>((item) {
              if (_sidebarExpanded) {
                return ListTile(
                  dense: true,
                  leading: Icon(
                    item.type == 'dir' ? Icons.folder : Icons.insert_drive_file,
                    color: item.type == 'dir' ? Colors.amber : Colors.blueAccent,
                  ),
                  title: Text(
                    item.name,
                    style: item.type == 'dir'
                        ? const TextStyle(fontWeight: FontWeight.w500)
                        : null,
                  ),
                  selected: ref.watch(codeEditorControllerProvider).selectedFilePath == item.path,
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
                      item.type == 'dir' ? Icons.folder : Icons.insert_drive_file,
                      color: item.type == 'dir' ? Colors.amber : Colors.blueAccent,
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
      ref.read(fileBrowserControllerProvider(params).notifier).enterDir(item.name);
    } else {
      ref.read(codeEditorControllerProvider.notifier).loadFile(item.path, params, ref, _codeController);
    }
  }

  Widget _buildEditorArea(BuildContext context, ThemeData theme, bool isDark, CodeEditorState codeState) {
    return Expanded(
      child: codeState.selectedFilePath == null
          ? Center(
              child: Text(
                'Select a file to edit',
                style: theme.textTheme.titleMedium,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFileHeader(isDark, codeState.selectedFilePath),
                _buildCodeEditor(),
                _buildActionsBar(isDark, codeState),
              ],
            ),
    );
  }

  Widget _buildFileHeader(bool isDark, String? selectedFilePath) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
            child: Text(
              selectedFilePath ?? '',
              style: const TextStyle(fontFamily: 'Fira Mono', fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeEditor() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: CodeTheme(
          data: CodeThemeData(),
          child: CodeField(
            controller: _codeController,
            textStyle: const TextStyle(
              fontFamily: 'Fira Mono',
              fontSize: 15,
              color: Colors.white,
            ),
            expands: true,
            gutterStyle: GutterStyle.none,
            background: Colors.transparent,
          ),
        ),
      ),
    );
  }

  Widget _buildActionsBar(bool isDark, CodeEditorState codeState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
          OutlinedButton.icon(
            icon: const Icon(Icons.keyboard_hide, size: 16),
            label: const Text('Hide Keyboard', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(32, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: () => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload, size: 16),
            label: codeState.isCommitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Commit & Push', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(32, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: codeState.isCommitting
                ? null
                : () => ref.read(codeEditorControllerProvider.notifier).commitAndPushFile(context, _codeController.text),
          ),
        ],
      ),
    );
  }

  Widget _buildChatOverlay(BuildContext context, CodeEditorState codeState) {
    return Positioned(
      left: _chatOverlayOffset.dx,
      top: _chatOverlayOffset.dy,
      child: Draggable(
        feedback: SizedBox(
          width: 340,
          height: 420,
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
            _chatOverlayOffset = details.offset;
          });
        },
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
    );
  }

  void _handleChatSend(CodeEditorState codeState) {
    final prompt = _chatController.text.trim();
    if (prompt.isEmpty) return;
    
    ref.read(codeEditorControllerProvider.notifier).handleChatSend(
      prompt,
      _codeController.text,
      codeState.selectedFilePath ?? 'current.dart',
      ref,
    );
    _chatController.clear();
  }
}

// Simple chat message model for overlay
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
        color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.chat_bubble, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'AI Chat',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
                color: isUser
                    ? theme.colorScheme.primary.withOpacity(0.12)
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isUser
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
                      child: Text(
                        '🤖',
                        style: TextStyle(
                          fontSize: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      msg.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: isUser ? theme.colorScheme.primary : null,
                      ),
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
          label: const Text('Apply AI Edit to Code', style: TextStyle(fontSize: 13)),
          onPressed: onApplyEdit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            child: SlashTextField(
              controller: controller,
              hint: 'Ask about this code…',
              minLines: 1,
              maxLines: 3,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 36,
            height: 36,
            child: SlashButton(
              label: '',
              onTap: loading ? () {} : onSend,
              icon: Icons.send,
            ),
          ),
        ],
      ),
    );
  }
}