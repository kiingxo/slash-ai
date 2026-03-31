import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight/languages/all.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';

import '../file_browser/file_browser_controller.dart';
import '../repo/repo_controller.dart';
import '../../home_shell.dart';
import 'code_editor_controller.dart';

class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key});

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  late final CodeController _codeController;
  late final FocusNode _editorFocusNode;
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _findController = TextEditingController();

  bool _sidebarExpanded = true;
  double _sidebarWidth = 280;
  bool _showChatOverlay = false;
  bool _showFindBar = false;
  bool _wrapLines = false;
  Offset _chatOverlayOffset = const Offset(56, 104);
  Size? _lastBodySize;
  String _sidebarQuery = '';
  String _activeLanguageId = 'plaintext';
  List<int> _findMatches = const [];
  int _activeFindMatchIndex = 0;
  String _lastIndexedFindText = '';

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(
      text: '',
      language: builtinLanguages[_activeLanguageId],
      analyzer: const DefaultLocalAnalyzer(),
    );
    _editorFocusNode = FocusNode();
    _findController.addListener(_refreshFindMatches);
    _codeController.addListener(_handleEditorControllerChanged);
    ref.listenManual<ExternalEditRequest?>(externalEditRequestProvider, (
      previous,
      next,
    ) {
      if (next == null || !mounted) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        final latest = ref.read(externalEditRequestProvider);
        if (latest == null) {
          return;
        }

        ref
            .read(codeEditorControllerProvider.notifier)
            .handleExternalEdit(latest, _codeController);
        _applyLanguageForPath(latest.fileName);
        ref.read(externalEditRequestProvider.notifier).state = null;
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _codeController.removeListener(_handleEditorControllerChanged);
    _findController.removeListener(_refreshFindMatches);
    _codeController.dispose();
    _editorFocusNode.dispose();
    _chatController.dispose();
    _findController.dispose();
    super.dispose();
  }

  void _handleEditorControllerChanged() {
    if (_findController.text.trim().isEmpty) {
      return;
    }

    final currentText = _codeController.text;
    if (currentText == _lastIndexedFindText) {
      return;
    }

    _refreshFindMatches();
  }

  void _applyLanguageForPath(String path) {
    final nextLanguage = _resolveLanguageId(path);
    final mode =
        builtinLanguages[nextLanguage] ?? builtinLanguages['plaintext'];
    if (_activeLanguageId != nextLanguage) {
      setState(() {
        _activeLanguageId = nextLanguage;
      });
    } else {
      _activeLanguageId = nextLanguage;
    }
    _codeController.language = mode;
  }

  String _resolveLanguageId(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return 'plaintext';
    }

    final fileName = normalized.split('/').last.toLowerCase();
    final exactMatch = _namedLanguageMap[fileName];
    if (exactMatch != null) {
      return exactMatch;
    }

    for (final entry in _extensionLanguageMap.entries) {
      if (fileName.endsWith(entry.key)) {
        return entry.value;
      }
    }

    return 'plaintext';
  }

  String _languageLabel(String languageId) {
    return _languageLabels[languageId] ?? languageId.toUpperCase();
  }

  void _refreshFindMatches() {
    final query = _findController.text.trim().toLowerCase();
    final source = _codeController.text;
    _lastIndexedFindText = source;

    if (query.isEmpty || source.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _findMatches = const [];
        _activeFindMatchIndex = 0;
      });
      return;
    }

    final haystack = source.toLowerCase();
    final matches = <int>[];
    var offset = 0;

    while (offset <= haystack.length - query.length) {
      final index = haystack.indexOf(query, offset);
      if (index == -1) {
        break;
      }
      matches.add(index);
      offset = index + query.length;
    }

    final currentSelection = _codeController.selection;
    var nextIndex = 0;
    if (matches.isNotEmpty && currentSelection.isValid) {
      final activeIndex = matches.indexWhere(
        (start) =>
            start == currentSelection.start &&
            start + query.length == currentSelection.end,
      );
      if (activeIndex != -1) {
        nextIndex = activeIndex;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _findMatches = matches;
      _activeFindMatchIndex =
          matches.isEmpty ? 0 : nextIndex.clamp(0, matches.length - 1);
    });

    if (matches.isNotEmpty) {
      _selectFindMatch(_activeFindMatchIndex, focusEditor: false);
    }
  }

  void _selectFindMatch(int index, {bool focusEditor = true}) {
    if (_findMatches.isEmpty) {
      return;
    }

    final clamped = index.clamp(0, _findMatches.length - 1);
    final queryLength = _findController.text.length;
    final start = _findMatches[clamped];
    final end = start + queryLength;

    _codeController.selection = TextSelection(
      baseOffset: start,
      extentOffset: end,
    );
    if (focusEditor) {
      _editorFocusNode.requestFocus();
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _activeFindMatchIndex = clamped;
    });
  }

  void _jumpToFindMatch(int delta) {
    if (_findMatches.isEmpty) {
      return;
    }

    final nextIndex = (_activeFindMatchIndex + delta) % _findMatches.length;
    _selectFindMatch(nextIndex < 0 ? _findMatches.length - 1 : nextIndex);
  }

  void _toggleFindBar() {
    if (_showFindBar) {
      setState(() {
        _showFindBar = false;
        _findController.clear();
      });
      _editorFocusNode.requestFocus();
      return;
    }

    setState(() {
      _showFindBar = true;
    });
  }

  Future<void> _copyPathToClipboard(String path) async {
    if (path.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: SlashText('Copied $path')));
  }

  void _dismissSheet(BuildContext sheetContext) {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!sheetContext.mounted) {
        return;
      }
      Navigator.of(sheetContext).pop();
    });
  }

  Future<void> _showRepoSelectorSheet(
    List<dynamic> repos,
    dynamic selectedRepo,
  ) async {
    if (repos.isEmpty) {
      return;
    }

    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered =
                repos.where((repo) {
                  final label =
                      (repo['full_name'] ?? repo['name'] ?? '').toString();
                  return label.toLowerCase().contains(query.toLowerCase());
                }).toList();

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.74,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.dividerColor.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: SlashText(
                              'Select Repository',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => _dismissSheet(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        onChanged:
                            (value) => setSheetState(() => query = value),
                        decoration: InputDecoration(
                          hintText: 'Search repositories',
                          prefixIcon: const Icon(Icons.search_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child:
                            filtered.isEmpty
                                ? const Center(
                                  child: SlashText('No repositories found.'),
                                )
                                : ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder:
                                      (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (_, index) {
                                    final repo = filtered[index];
                                    final isSelected =
                                        selectedRepo != null &&
                                        (selectedRepo['full_name'] ??
                                                    selectedRepo['name'])
                                                .toString() ==
                                            (repo['full_name'] ?? repo['name'])
                                                .toString();

                                    return InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        ref
                                            .read(
                                              codeEditorControllerProvider
                                                  .notifier,
                                            )
                                            .selectRepo(repo);
                                        Navigator.of(context).pop();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color:
                                              isSelected
                                                  ? theme.colorScheme.primary
                                                      .withValues(alpha: 0.10)
                                                  : theme.cardColor,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color:
                                                isSelected
                                                    ? theme.colorScheme.primary
                                                    : theme.dividerColor
                                                        .withValues(alpha: 0.5),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.primary
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                Icons.folder_open_rounded,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  SlashText(
                                                    (repo['full_name'] ??
                                                            repo['name'] ??
                                                            '')
                                                        .toString(),
                                                    fontWeight: FontWeight.w600,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  if ((repo['description'] ??
                                                          '')
                                                      .toString()
                                                      .trim()
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    SlashText(
                                                      (repo['description'] ??
                                                              '')
                                                          .toString(),
                                                      fontSize: 12,
                                                      color:
                                                          theme
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (isSelected)
                                              Icon(
                                                Icons.check_circle_rounded,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openQuickOpenSheet(
    RepoParams params,
    CodeEditorState codeState,
  ) async {
    final queryController = TextEditingController();
    final future = ref
        .read(fileBrowserControllerProvider(params).notifier)
        .listAllFiles(maxDepth: 12, maxFiles: 1500);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FractionallySizedBox(
              heightFactor: 0.82,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: SlashText(
                            'Quick Open',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => _dismissSheet(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: queryController,
                      autofocus: true,
                      onChanged: (value) => setSheetState(() => query = value),
                      decoration: InputDecoration(
                        hintText: 'Quick open by file name or path',
                        prefixIcon: const Icon(Icons.travel_explore_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: FutureBuilder<List<FileItem>>(
                        future: future,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError) {
                            return Center(
                              child: SlashText(
                                'Quick open failed: ${snapshot.error}',
                              ),
                            );
                          }

                          final allFiles = snapshot.data ?? const <FileItem>[];
                          final recentIndex = <String, int>{
                            for (
                              var i = 0;
                              i < codeState.recentFiles.length;
                              i++
                            )
                              codeState.recentFiles[i]: i,
                          };
                          final filtered =
                              allFiles.where((item) {
                                  final searchTarget =
                                      '${item.name} ${item.path}'.toLowerCase();
                                  return query.trim().isEmpty ||
                                      searchTarget.contains(
                                        query.trim().toLowerCase(),
                                      );
                                }).toList()
                                ..sort((left, right) {
                                  final leftSelected =
                                      left.path == codeState.selectedFilePath
                                          ? 0
                                          : 1;
                                  final rightSelected =
                                      right.path == codeState.selectedFilePath
                                          ? 0
                                          : 1;
                                  if (leftSelected != rightSelected) {
                                    return leftSelected.compareTo(
                                      rightSelected,
                                    );
                                  }

                                  final leftRecent =
                                      recentIndex[left.path] ?? 9999;
                                  final rightRecent =
                                      recentIndex[right.path] ?? 9999;
                                  if (leftRecent != rightRecent) {
                                    return leftRecent.compareTo(rightRecent);
                                  }

                                  return left.path.compareTo(right.path);
                                });

                          if (filtered.isEmpty) {
                            return const Center(
                              child: SlashText('No files match that query.'),
                            );
                          }

                          return ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final isSelected =
                                  item.path == codeState.selectedFilePath;
                              final isRecent = recentIndex.containsKey(
                                item.path,
                              );

                              return InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () async {
                                  final navigator = Navigator.of(context);
                                  await ref
                                      .read(
                                        codeEditorControllerProvider.notifier,
                                      )
                                      .loadFile(
                                        item.path,
                                        params,
                                        ref,
                                        _codeController,
                                      );
                                  _applyLanguageForPath(item.path);
                                  navigator.pop();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.10)
                                            : Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                              : Theme.of(context).dividerColor
                                                  .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.10),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          _iconForPath(item.path),
                                          size: 18,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SlashText(
                                              item.name,
                                              fontWeight: FontWeight.w600,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            SlashText(
                                              item.path,
                                              fontSize: 12,
                                              color:
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isRecent)
                                        _MetaPill(
                                          label: 'Recent',
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.10),
                                          foregroundColor:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        ),
                                      if (isSelected) ...[
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    queryController.dispose();
  }

  Future<void> _openFilesBottomSheet(RepoParams? params) async {
    if (params == null) {
      await showModalBottomSheet<void>(
        context: context,
        builder:
            (_) => const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: SlashText('Select a repository first.')),
              ),
            ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Consumer(
              builder: (context, modalRef, _) {
                final fileBrowserState = modalRef.watch(
                  fileBrowserControllerProvider(params),
                );
                final notifier = modalRef.read(
                  fileBrowserControllerProvider(params).notifier,
                );
                final visibleItems = _visibleSidebarItems(
                  fileBrowserState.items,
                  query,
                );

                return FractionallySizedBox(
                  heightFactor: 0.88,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.folder_open_rounded),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: SlashText(
                                'Files',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (fileBrowserState.pathStack.isNotEmpty)
                              IconButton(
                                tooltip: 'Up',
                                onPressed: notifier.goUp,
                                icon: const Icon(Icons.arrow_upward_rounded),
                              ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => _dismissSheet(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                            IconButton(
                              tooltip: 'Quick open',
                              onPressed:
                                  () => _openQuickOpenSheet(
                                    params,
                                    modalRef.read(codeEditorControllerProvider),
                                  ),
                              icon: const Icon(Icons.travel_explore_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          onChanged:
                              (value) => setSheetState(() => query = value),
                          decoration: InputDecoration(
                            hintText: 'Filter current folder',
                            prefixIcon: const Icon(Icons.search_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child:
                              fileBrowserState.isLoading
                                  ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                  : visibleItems.isEmpty
                                  ? const Center(
                                    child: SlashText('No files here.'),
                                  )
                                  : ListView.separated(
                                    itemCount: visibleItems.length,
                                    separatorBuilder:
                                        (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final item = visibleItems[index];
                                      final isDir = item.type == 'dir';

                                      return InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () async {
                                          final navigator = Navigator.of(
                                            context,
                                          );
                                          if (isDir) {
                                            notifier.enterDir(item.name);
                                            return;
                                          }

                                          await modalRef
                                              .read(
                                                codeEditorControllerProvider
                                                    .notifier,
                                              )
                                              .loadFile(
                                                item.path,
                                                params,
                                                modalRef,
                                                _codeController,
                                              );
                                          _applyLanguageForPath(item.path);
                                          navigator.pop();
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).cardColor,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .dividerColor
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                isDir
                                                    ? Icons.folder_rounded
                                                    : _iconForPath(item.path),
                                                color:
                                                    isDir
                                                        ? Colors.amber[700]
                                                        : Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    SlashText(
                                                      item.name,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    if (!isDir) ...[
                                                      const SizedBox(height: 4),
                                                      SlashText(
                                                        item.path,
                                                        fontSize: 12,
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                isDir
                                                    ? Icons
                                                        .chevron_right_rounded
                                                    : Icons.north_east_rounded,
                                                size: 18,
                                                color:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  List<FileItem> _visibleSidebarItems(List<FileItem> items, String query) {
    final filtered =
        items.where((item) {
            final matchTarget = '${item.name} ${item.path}'.toLowerCase();
            return query.trim().isEmpty ||
                matchTarget.contains(query.trim().toLowerCase());
          }).toList()
          ..sort((left, right) {
            if (left.type != right.type) {
              return left.type == 'dir' ? -1 : 1;
            }
            return left.name.toLowerCase().compareTo(right.name.toLowerCase());
          });

    return filtered;
  }

  Future<void> _handleFileTap(FileItem item, RepoParams params) async {
    if (item.type == 'dir') {
      ref
          .read(fileBrowserControllerProvider(params).notifier)
          .enterDir(item.name);
      return;
    }

    await ref
        .read(codeEditorControllerProvider.notifier)
        .loadFile(item.path, params, ref, _codeController);
    _applyLanguageForPath(item.path);
    _editorFocusNode.requestFocus();
  }

  void _handleChatSend(CodeEditorState codeState) {
    final prompt = _chatController.text.trim();
    if (prompt.isEmpty) {
      return;
    }

    _sendAssistantPrompt(codeState, prompt);
    _chatController.clear();
  }

  void _sendAssistantPrompt(CodeEditorState codeState, String prompt) {
    if (prompt.trim().isEmpty || codeState.selectedFilePath == null) {
      return;
    }

    setState(() {
      _showChatOverlay = true;
    });

    ref
        .read(codeEditorControllerProvider.notifier)
        .handleChatSend(
          prompt,
          _codeController.text,
          codeState.selectedFilePath!,
          ref,
        );
  }

  void _seedAssistantPrompt(String prompt) {
    setState(() {
      _showChatOverlay = true;
      _chatController.text = prompt;
      _chatController.selection = TextSelection.collapsed(
        offset: _chatController.text.length,
      );
    });
  }

  String _assistantPromptForAction(String action, String filePath) {
    switch (action) {
      case 'Explain':
        return 'Explain how $filePath works, including the important control flow and any risky edge cases.';
      case 'Review':
        return 'Review $filePath for bugs, regressions, and missing edge cases. Keep it concrete.';
      case 'Refactor':
        return 'Refactor $filePath to improve clarity and maintainability without changing behavior.';
      default:
        return 'Help me improve $filePath.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoState = ref.watch(repoControllerProvider);
    final codeState = ref.watch(codeEditorControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final repos = repoState.repos;
    final selectedRepo =
        codeState.selectedRepo ??
        repoState.selectedRepo ??
        (repos.isNotEmpty ? repos.first : null);

    final params =
        selectedRepo == null
            ? null
            : RepoParams(
              owner: selectedRepo['owner']['login'],
              repo: selectedRepo['name'],
              branch: codeState.selectedBranch,
            );

    final fileBrowserState =
        params == null
            ? null
            : ref.watch(fileBrowserControllerProvider(params));

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B1020) : const Color(0xFFF3F6FB),
      appBar: _buildAppBar(
        context: context,
        theme: theme,
        selectedRepo: selectedRepo,
        repos: repos,
        params: params,
        codeState: codeState,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _lastBodySize = Size(constraints.maxWidth, constraints.maxHeight);
          final isNarrow = constraints.maxWidth < 860;

          return Stack(
            children: [
              Row(
                children: [
                  if (!isNarrow)
                    _buildSidebar(
                      theme: theme,
                      codeState: codeState,
                      params: params,
                      fileBrowserState: fileBrowserState,
                      isDark: isDark,
                    )
                  else
                    _buildCollapsedSidebarRail(
                      params: params,
                      codeState: codeState,
                    ),
                  if (!isNarrow) _buildSidebarDragHandle(theme),
                  Expanded(
                    child: _buildEditorArea(
                      context: context,
                      theme: theme,
                      codeState: codeState,
                      selectedRepo: selectedRepo,
                      params: params,
                      isDark: isDark,
                      isNarrow: isNarrow,
                    ),
                  ),
                ],
              ),
              if (_showChatOverlay)
                _buildChatOverlay(
                  context: context,
                  theme: theme,
                  codeState: codeState,
                ),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar({
    required BuildContext context,
    required ThemeData theme,
    required dynamic selectedRepo,
    required List<dynamic> repos,
    required RepoParams? params,
    required CodeEditorState codeState,
  }) {
    return AppBar(
      backgroundColor:
          theme.brightness == Brightness.dark
              ? const Color(0xFF111827)
              : Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: const SidebarMenuButton(),
      titleSpacing: 12,
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.memory_rounded, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SlashText('Pocket Engineer', fontWeight: FontWeight.w700),
                SlashText(
                  'Edit, reason, and ship with repo context',
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ],
            ),
          ),
          if (repos.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _showRepoSelectorSheet(repos, selectedRepo),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: SlashText(
                        (selectedRepo?['full_name'] ??
                                selectedRepo?['name'] ??
                                'Select repo')
                            .toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.expand_more_rounded, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        if (params != null)
          IconButton(
            tooltip: 'Quick open',
            onPressed: () => _openQuickOpenSheet(params, codeState),
            icon: const Icon(Icons.travel_explore_rounded),
          ),
        if (codeState.branches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButtonHideUnderline(
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
                    codeState.branches.map((branch) {
                      return DropdownMenuItem<String>(
                        value: branch,
                        child: SlashText(branch),
                      );
                    }).toList(),
                icon: const Icon(Icons.alt_route_rounded),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCollapsedSidebarRail({
    required RepoParams? params,
    required CodeEditorState codeState,
  }) {
    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          IconButton(
            tooltip: 'Browse files',
            onPressed: () => _openFilesBottomSheet(params),
            icon: const Icon(Icons.folder_open_rounded),
          ),
          IconButton(
            tooltip: 'Quick open',
            onPressed:
                params == null
                    ? null
                    : () => _openQuickOpenSheet(params, codeState),
            icon: const Icon(Icons.travel_explore_rounded),
          ),
          if (codeState.selectedFilePath != null)
            IconButton(
              tooltip: 'Find in file',
              onPressed: _toggleFindBar,
              icon: const Icon(Icons.search_rounded),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebar({
    required ThemeData theme,
    required CodeEditorState codeState,
    required RepoParams? params,
    required FileBrowserState? fileBrowserState,
    required bool isDark,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: _sidebarExpanded ? _sidebarWidth.clamp(220, 420) : 74,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.account_tree_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (_sidebarExpanded) ...[
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SlashText('Explorer', fontWeight: FontWeight.w700),
                        SlashText(
                          'Browse current branch',
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ],
                    ),
                  ),
                ],
                IconButton(
                  tooltip: _sidebarExpanded ? 'Collapse' : 'Expand',
                  onPressed:
                      () =>
                          setState(() => _sidebarExpanded = !_sidebarExpanded),
                  icon: Icon(
                    _sidebarExpanded
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                  ),
                ),
              ],
            ),
          ),
          if (_sidebarExpanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                onChanged: (value) => setState(() => _sidebarQuery = value),
                decoration: InputDecoration(
                  hintText: 'Filter folder',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon:
                      _sidebarQuery.isEmpty
                          ? null
                          : IconButton(
                            tooltip: 'Clear',
                            onPressed: () => setState(() => _sidebarQuery = ''),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_sidebarExpanded &&
              params != null &&
              codeState.recentFiles.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SlashText(
                  'Recent Files',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    codeState.recentFiles.take(4).map((path) {
                      return ActionChip(
                        label: Text(
                          path.split('/').last,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () {
                          _handleFileTap(
                            FileItem(
                              name: path.split('/').last,
                              path: path,
                              type: 'file',
                            ),
                            params,
                          );
                        },
                      );
                    }).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child:
                params == null
                    ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: SlashText('Pick a repository to browse files.'),
                      ),
                    )
                    : fileBrowserState == null || fileBrowserState.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildFileList(
                      params: params,
                      fileBrowserState: fileBrowserState,
                      selectedPath: codeState.selectedFilePath,
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarDragHandle(ThemeData theme) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) {
        setState(() {
          _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(220, 420);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 6,
          decoration: BoxDecoration(
            color: theme.dividerColor.withValues(alpha: 0.15),
          ),
        ),
      ),
    );
  }

  Widget _buildFileList({
    required RepoParams params,
    required FileBrowserState fileBrowserState,
    required String? selectedPath,
  }) {
    final visibleItems = _visibleSidebarItems(
      fileBrowserState.items,
      _sidebarQuery,
    );

    if (visibleItems.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: SlashText('Nothing matches this filter.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_sidebarExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                if (fileBrowserState.pathStack.isNotEmpty)
                  IconButton(
                    tooltip: 'Up',
                    onPressed:
                        () =>
                            ref
                                .read(
                                  fileBrowserControllerProvider(
                                    params,
                                  ).notifier,
                                )
                                .goUp(),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                Expanded(
                  child: SlashText(
                    fileBrowserState.pathStack.isEmpty
                        ? '/'
                        : '/${fileBrowserState.pathStack.join('/')}',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            itemCount: visibleItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final item = visibleItems[index];
              final isSelected = selectedPath == item.path;
              final isDir = item.type == 'dir';

              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _handleFileTap(item, params),
                child: Container(
                  padding:
                      _sidebarExpanded
                          ? const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          )
                          : const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.10)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        isSelected
                            ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                            )
                            : null,
                  ),
                  child:
                      _sidebarExpanded
                          ? Row(
                            children: [
                              Icon(
                                isDir
                                    ? Icons.folder_rounded
                                    : _iconForPath(item.path),
                                color:
                                    isDir
                                        ? Colors.amber[700]
                                        : Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SlashText(
                                      item.name,
                                      fontWeight:
                                          isDir
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (!isDir && _sidebarQuery.isNotEmpty)
                                      SlashText(
                                        item.path,
                                        fontSize: 11,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                isDir
                                    ? Icons.chevron_right_rounded
                                    : Icons.north_east_rounded,
                                size: 18,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ],
                          )
                          : Center(
                            child: Icon(
                              isDir
                                  ? Icons.folder_rounded
                                  : _iconForPath(item.path),
                              color:
                                  isDir
                                      ? Colors.amber[700]
                                      : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditorArea({
    required BuildContext context,
    required ThemeData theme,
    required CodeEditorState codeState,
    required dynamic selectedRepo,
    required RepoParams? params,
    required bool isDark,
    required bool isNarrow,
  }) {
    if (codeState.selectedFilePath == null) {
      return _buildEmptyState(
        theme: theme,
        selectedRepo: selectedRepo,
        params: params,
        codeState: codeState,
      );
    }

    return Column(
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _codeController,
          builder: (context, value, _) {
            final snapshot = _EditorSnapshot.fromValue(
              value,
              syncedContent: codeState.fileContent,
            );
            return _buildEditorHeader(
              theme: theme,
              codeState: codeState,
              snapshot: snapshot,
              params: params,
            );
          },
        ),
        if (_showFindBar) _buildFindBar(theme),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: _buildCodeEditor(isDark: isDark),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _codeController,
          builder: (context, value, _) {
            final snapshot = _EditorSnapshot.fromValue(
              value,
              syncedContent: codeState.fileContent,
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (codeState.pendingEdit != null)
                  _buildPendingEditBanner(
                    theme: theme,
                    currentContent: value.text,
                    pendingEdit: codeState.pendingEdit!,
                  ),
                _buildStatusBar(
                  theme: theme,
                  codeState: codeState,
                  snapshot: snapshot,
                ),
                _buildActionsBar(
                  theme: theme,
                  codeState: codeState,
                  snapshot: snapshot,
                  isNarrow: isNarrow,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required ThemeData theme,
    required dynamic selectedRepo,
    required RepoParams? params,
    required CodeEditorState codeState,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.terminal_rounded,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 18),
                const SlashText(
                  'Ready to edit with full repo context',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
                const SizedBox(height: 10),
                SlashText(
                  selectedRepo == null
                      ? 'Pick a repository, then open a file. Quick open searches the whole branch, and the assistant will work with repo-aware context instead of a single isolated file.'
                      : 'Open a file from ${selectedRepo['full_name'] ?? selectedRepo['name']} and the editor will track unsaved changes, quick-open matches, AI drafts, and branch-aware pull/push actions.',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed:
                          params == null
                              ? null
                              : () => _openQuickOpenSheet(params, codeState),
                      icon: const Icon(Icons.travel_explore_rounded),
                      label: const SlashText('Quick Open'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openFilesBottomSheet(params),
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const SlashText('Browse Files'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorHeader({
    required ThemeData theme,
    required CodeEditorState codeState,
    required _EditorSnapshot snapshot,
    required RepoParams? params,
  }) {
    final filePath = codeState.selectedFilePath ?? '';
    final fileName = filePath.isEmpty ? 'Untitled' : filePath.split('/').last;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeader = constraints.maxWidth < 430;

          Widget buildSyncPill() {
            return _MetaPill(
              label: snapshot.isDirty ? 'Modified' : 'Synced',
              color:
                  snapshot.isDirty
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.14)
                      : const Color(0xFF10B981).withValues(alpha: 0.14),
              foregroundColor:
                  snapshot.isDirty
                      ? const Color(0xFFB45309)
                      : const Color(0xFF047857),
            );
          }

          Widget buildHeaderSummary({required bool compact}) {
            return LayoutBuilder(
              builder: (context, summaryConstraints) {
                final stackSyncPill =
                    compact || summaryConstraints.maxWidth < 180;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stackSyncPill) ...[
                      SlashText(
                        fileName,
                        fontWeight: FontWeight.w700,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      buildSyncPill(),
                    ] else
                      Row(
                        children: [
                          Expanded(
                            child: SlashText(
                              fileName,
                              fontWeight: FontWeight.w700,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(child: buildSyncPill()),
                        ],
                      ),
                    const SizedBox(height: 4),
                    SlashText(
                      filePath,
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );
              },
            );
          }

          final headerIcon = Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _iconForPath(filePath),
              color: theme.colorScheme.primary,
            ),
          );

          final actionButtons = <Widget>[
            IconButton(
              tooltip: 'Copy file path',
              onPressed: () => _copyPathToClipboard(filePath),
              icon: const Icon(Icons.content_copy_rounded),
            ),
            IconButton(
              tooltip: _showFindBar ? 'Hide find' : 'Find in file',
              onPressed: _toggleFindBar,
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              tooltip: _wrapLines ? 'Disable wrap' : 'Enable wrap',
              onPressed: () => setState(() => _wrapLines = !_wrapLines),
              icon: Icon(
                _wrapLines ? Icons.wrap_text_rounded : Icons.segment_rounded,
              ),
            ),
            if (params != null)
              IconButton(
                tooltip: 'Quick open',
                onPressed: () => _openQuickOpenSheet(params, codeState),
                icon: const Icon(Icons.travel_explore_rounded),
              ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compactHeader) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    headerIcon,
                    const SizedBox(width: 12),
                    Expanded(child: buildHeaderSummary(compact: true)),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 4, runSpacing: 4, children: actionButtons),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    headerIcon,
                    const SizedBox(width: 12),
                    Expanded(child: buildHeaderSummary(compact: false)),
                    ...actionButtons,
                  ],
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaPill(
                    label: _languageLabel(_activeLanguageId),
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    foregroundColor: theme.colorScheme.primary,
                  ),
                  if ((codeState.selectedBranch ?? '').isNotEmpty)
                    _MetaPill(
                      label: codeState.selectedBranch!,
                      color: theme.colorScheme.secondary.withValues(
                        alpha: 0.12,
                      ),
                      foregroundColor: theme.colorScheme.secondary,
                    ),
                  if (codeState.pendingEdit != null)
                    _MetaPill(
                      label: 'AI draft ready',
                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      foregroundColor: const Color(0xFF1D4ED8),
                    ),
                  if (codeState.lastSyncedAt != null)
                    _MetaPill(
                      label:
                          'Updated ${_formatRelativeTime(codeState.lastSyncedAt!)}',
                      color: theme.colorScheme.surfaceContainerHighest,
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFindBar(ThemeData theme) {
    final matchCount = _findMatches.length;
    final activeMatch =
        matchCount == 0 ? 0 : (_activeFindMatchIndex + 1).clamp(1, matchCount);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactFindBar = constraints.maxWidth < 420;

          final findField = TextField(
            controller: _findController,
            autofocus: true,
            onSubmitted: (_) => _jumpToFindMatch(1),
            decoration: InputDecoration(
              hintText: 'Find in file',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );

          final findActions = <Widget>[
            _MetaPill(
              label: '$activeMatch/$matchCount',
              color: theme.colorScheme.surfaceContainerHighest,
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
            IconButton(
              tooltip: 'Previous match',
              onPressed: matchCount == 0 ? null : () => _jumpToFindMatch(-1),
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              tooltip: 'Next match',
              onPressed: matchCount == 0 ? null : () => _jumpToFindMatch(1),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            IconButton(
              tooltip: 'Close find',
              onPressed: _toggleFindBar,
              icon: const Icon(Icons.close_rounded),
            ),
          ];

          if (compactFindBar) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                findField,
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: findActions,
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: findField),
              const SizedBox(width: 12),
              ...[
                findActions.first,
                const SizedBox(width: 8),
                ...findActions.skip(1),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCodeEditor({required bool isDark}) {
    return CodeTheme(
      data: CodeThemeData(styles: isDark ? _darkCodeTheme : _lightCodeTheme),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFDDE5F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: CodeField(
          controller: _codeController,
          focusNode: _editorFocusNode,
          wrap: _wrapLines,
          textStyle: TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: const [
              'SF Mono',
              'Menlo',
              'Consolas',
              'Courier New',
            ],
            fontSize: 15,
            height: 1.45,
            color: isDark ? const Color(0xFFE5E7EB) : const Color(0xFF0F172A),
          ),
          gutterStyle: GutterStyle(
            width: 48,
            margin: 8,
            textStyle: TextStyle(
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
            showLineNumbers: true,
            showErrors: false,
            showFoldingHandles: true,
          ),
          background: Colors.transparent,
          onChanged: (_) {
            if (_findController.text.trim().isNotEmpty) {
              _refreshFindMatches();
            }
          },
        ),
      ),
    );
  }

  Widget _buildPendingEditBanner({
    required ThemeData theme,
    required String currentContent,
    required String pendingEdit,
  }) {
    final summary = _PendingEditSummary.fromTexts(
      currentContent: currentContent,
      pendingContent: pendingEdit,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactBanner = constraints.maxWidth < 480;

          final bannerSummary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SlashText(
                'Assistant draft ready to apply',
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D4ED8),
              ),
              const SizedBox(height: 4),
              SlashText(
                '${summary.lineDeltaLabel}  •  ${summary.characterDeltaLabel}',
                fontSize: 12,
                color: const Color(0xFF1E3A8A),
              ),
            ],
          );

          final dismissButton = TextButton(
            onPressed:
                () =>
                    ref
                        .read(codeEditorControllerProvider.notifier)
                        .discardPendingEdit(),
            child: const SlashText('Dismiss'),
          );

          final applyButton = ElevatedButton.icon(
            onPressed: () {
              ref
                  .read(codeEditorControllerProvider.notifier)
                  .applyPendingEdit(_codeController);
              _editorFocusNode.requestFocus();
            },
            icon: const Icon(Icons.check_rounded),
            label: const SlashText('Apply'),
          );

          if (compactBanner) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.auto_fix_high_rounded,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: bannerSummary),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [dismissButton, applyButton],
                ),
              ],
            );
          }

          return Row(
            children: [
              const Icon(Icons.auto_fix_high_rounded, color: Color(0xFF1D4ED8)),
              const SizedBox(width: 12),
              Expanded(child: bannerSummary),
              dismissButton,
              const SizedBox(width: 8),
              applyButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBar({
    required ThemeData theme,
    required CodeEditorState codeState,
    required _EditorSnapshot snapshot,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _StatusLabel(
            label: snapshot.isDirty ? 'Unsaved changes' : 'Synced to remote',
            accent:
                snapshot.isDirty
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF10B981),
          ),
          _StatusLabel(label: 'Ln ${snapshot.line}, Col ${snapshot.column}'),
          _StatusLabel(label: '${snapshot.lineCount} lines'),
          _StatusLabel(label: '${snapshot.characterCount} chars'),
          if (snapshot.selectionLength > 0)
            _StatusLabel(label: 'Sel ${snapshot.selectionLength}'),
          if (codeState.lastSyncedAt != null)
            _StatusLabel(
              label: 'Updated ${_formatRelativeTime(codeState.lastSyncedAt!)}',
            ),
        ],
      ),
    );
  }

  Widget _buildActionsBar({
    required ThemeData theme,
    required CodeEditorState codeState,
    required _EditorSnapshot snapshot,
    required bool isNarrow,
  }) {
    final primaryActions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed:
              codeState.chatLoading
                  ? null
                  : () => setState(() => _showChatOverlay = true),
          icon: const Icon(Icons.smart_toy_outlined),
          label: const SlashText('AI Assistant'),
        ),
        _ActionChip(
          label: 'Explain',
          onTap:
              codeState.chatLoading || codeState.selectedFilePath == null
                  ? null
                  : () => _sendAssistantPrompt(
                    codeState,
                    _assistantPromptForAction(
                      'Explain',
                      codeState.selectedFilePath!,
                    ),
                  ),
        ),
        _ActionChip(
          label: 'Review',
          onTap:
              codeState.chatLoading || codeState.selectedFilePath == null
                  ? null
                  : () => _sendAssistantPrompt(
                    codeState,
                    _assistantPromptForAction(
                      'Review',
                      codeState.selectedFilePath!,
                    ),
                  ),
        ),
        _ActionChip(
          label: 'Refactor',
          onTap:
              codeState.chatLoading || codeState.selectedFilePath == null
                  ? null
                  : () => _sendAssistantPrompt(
                    codeState,
                    _assistantPromptForAction(
                      'Refactor',
                      codeState.selectedFilePath!,
                    ),
                  ),
        ),
        OutlinedButton.icon(
          onPressed: _openModelSelectorSheet,
          icon: const Icon(Icons.model_training_rounded),
          label: SlashText(
            codeState.codeModel == 'openrouter' ? 'OpenRouter' : 'OpenAI',
          ),
        ),
      ],
    );

    final fileActions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed:
              snapshot.isDirty
                  ? () => ref
                      .read(codeEditorControllerProvider.notifier)
                      .revertToLastSynced(_codeController)
                  : null,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const SlashText('Discard'),
        ),
        OutlinedButton.icon(
          onPressed:
              codeState.selectedFilePath == null || codeState.isLoading
                  ? null
                  : () => ref
                      .read(codeEditorControllerProvider.notifier)
                      .pullLatestIntoEditor(context, _codeController),
          icon: const Icon(Icons.sync_rounded),
          label: const SlashText('Pull'),
        ),
        ElevatedButton.icon(
          onPressed:
              codeState.isCommitting
                  ? null
                  : () => ref
                      .read(codeEditorControllerProvider.notifier)
                      .commitAndPushFile(context, _codeController.text),
          icon:
              codeState.isCommitting
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.cloud_upload_rounded),
          label: SlashText(codeState.isCommitting ? 'Pushing...' : 'Push'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child:
          isNarrow
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  primaryActions,
                  const SizedBox(height: 10),
                  fileActions,
                ],
              )
              : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: primaryActions),
                  const SizedBox(width: 12),
                  fileActions,
                ],
              ),
    );
  }

  void _openModelSelectorSheet() {
    final current = ref.read(codeEditorControllerProvider).codeModel;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SlashText(
                    'Select AI provider',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _ModelOptionTile(
                  label: 'OpenAI',
                  value: 'openai',
                  selected: current == 'openai',
                  onTap: () {
                    ref
                        .read(codeEditorControllerProvider.notifier)
                        .setCodeModel('openai');
                    Navigator.of(context).pop();
                  },
                ),
                _ModelOptionTile(
                  label: 'OpenRouter',
                  value: 'openrouter',
                  selected: current == 'openrouter',
                  onTap: () {
                    ref
                        .read(codeEditorControllerProvider.notifier)
                        .setCodeModel('openrouter');
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatOverlay({
    required BuildContext context,
    required ThemeData theme,
    required CodeEditorState codeState,
  }) {
    final size = _lastBodySize ?? MediaQuery.of(context).size;
    final overlayWidth = size.width < 520 ? size.width - 20 : 380.0;
    final overlayHeight = size.height < 720 ? size.height * 0.68 : 460.0;

    double clampX(double value) {
      return value.clamp(8.0, (size.width - overlayWidth) - 8.0);
    }

    double clampY(double value) {
      return value.clamp(8.0, (size.height - overlayHeight) - 8.0);
    }

    return Positioned(
      left: clampX(_chatOverlayOffset.dx),
      top: clampY(_chatOverlayOffset.dy),
      child: Draggable(
        feedback: SizedBox(
          width: overlayWidth,
          height: overlayHeight,
          child: _ChatOverlay(
            messages: codeState.chatMessages,
            loading: codeState.chatLoading,
            controller: _chatController,
            fileLabel: codeState.selectedFilePath,
            onClose: () => setState(() => _showChatOverlay = false),
            onSend: () => _handleChatSend(codeState),
            onSeedPrompt: _seedAssistantPrompt,
            onApplyEdit:
                codeState.pendingEdit == null
                    ? null
                    : () => ref
                        .read(codeEditorControllerProvider.notifier)
                        .applyPendingEdit(_codeController),
            onDismissEdit:
                codeState.pendingEdit == null
                    ? null
                    : () =>
                        ref
                            .read(codeEditorControllerProvider.notifier)
                            .discardPendingEdit(),
          ),
        ),
        childWhenDragging: const SizedBox.shrink(),
        onDragEnd: (details) {
          setState(() {
            _chatOverlayOffset = Offset(
              clampX(details.offset.dx),
              clampY(details.offset.dy),
            );
          });
        },
        child: SizedBox(
          width: overlayWidth,
          height: overlayHeight,
          child: _ChatOverlay(
            messages: codeState.chatMessages,
            loading: codeState.chatLoading,
            controller: _chatController,
            fileLabel: codeState.selectedFilePath,
            onClose: () => setState(() => _showChatOverlay = false),
            onSend: () => _handleChatSend(codeState),
            onSeedPrompt: _seedAssistantPrompt,
            onApplyEdit:
                codeState.pendingEdit == null
                    ? null
                    : () => ref
                        .read(codeEditorControllerProvider.notifier)
                        .applyPendingEdit(_codeController),
            onDismissEdit:
                codeState.pendingEdit == null
                    ? null
                    : () =>
                        ref
                            .read(codeEditorControllerProvider.notifier)
                            .discardPendingEdit(),
          ),
        ),
      ),
    );
  }

  IconData _iconForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.dart')) {
      return Icons.flutter_dash_rounded;
    }
    if (lower.endsWith('.json') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml')) {
      return Icons.data_object_rounded;
    }
    if (lower.endsWith('.md')) {
      return Icons.description_rounded;
    }
    if (lower.endsWith('.swift') ||
        lower.endsWith('.kt') ||
        lower.endsWith('.java')) {
      return Icons.phone_iphone_rounded;
    }
    if (lower.endsWith('.js') ||
        lower.endsWith('.jsx') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.tsx')) {
      return Icons.javascript_rounded;
    }
    if (lower.endsWith('.css') ||
        lower.endsWith('.scss') ||
        lower.endsWith('.html') ||
        lower.endsWith('.xml')) {
      return Icons.palette_outlined;
    }
    if (lower.endsWith('.sh') || lower == 'makefile' || lower == 'dockerfile') {
      return Icons.terminal_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  String _formatRelativeTime(DateTime timestamp) {
    final delta = DateTime.now().difference(timestamp);
    if (delta.inSeconds < 10) {
      return 'just now';
    }
    if (delta.inMinutes < 1) {
      return '${delta.inSeconds}s ago';
    }
    if (delta.inHours < 1) {
      return '${delta.inMinutes}m ago';
    }
    if (delta.inDays < 1) {
      return '${delta.inHours}h ago';
    }
    return '${delta.inDays}d ago';
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color foregroundColor;

  const _MetaPill({
    required this.label,
    required this.color,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: SlashText(
        label,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: foregroundColor,
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final String label;
  final Color? accent;

  const _StatusLabel({required this.label, this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color:
                accent ??
                Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        SlashText(
          label,
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _ActionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      avatar: const Icon(Icons.bolt_rounded, size: 16),
    );
  }
}

class _EditorSnapshot {
  final int line;
  final int column;
  final int lineCount;
  final int characterCount;
  final int selectionLength;
  final bool isDirty;

  const _EditorSnapshot({
    required this.line,
    required this.column,
    required this.lineCount,
    required this.characterCount,
    required this.selectionLength,
    required this.isDirty,
  });

  factory _EditorSnapshot.fromValue(
    TextEditingValue value, {
    required String? syncedContent,
  }) {
    final text = value.text;
    final selection = value.selection;
    final cursor =
        selection.isValid ? selection.extentOffset.clamp(0, text.length) : 0;
    final beforeCursor = text.substring(0, cursor);
    final lineBreaks = '\n'.allMatches(beforeCursor).length;
    final lastBreak = beforeCursor.lastIndexOf('\n');
    final column = cursor - (lastBreak == -1 ? 0 : lastBreak + 1) + 1;

    return _EditorSnapshot(
      line: lineBreaks + 1,
      column: column,
      lineCount: text.isEmpty ? 1 : '\n'.allMatches(text).length + 1,
      characterCount: text.length,
      selectionLength:
          selection.isValid ? (selection.end - selection.start).abs() : 0,
      isDirty:
          syncedContent == null
              ? text.trim().isNotEmpty
              : text != syncedContent,
    );
  }
}

class _PendingEditSummary {
  final int lineDelta;
  final int characterDelta;

  const _PendingEditSummary({
    required this.lineDelta,
    required this.characterDelta,
  });

  factory _PendingEditSummary.fromTexts({
    required String currentContent,
    required String pendingContent,
  }) {
    final currentLines =
        currentContent.isEmpty ? 0 : '\n'.allMatches(currentContent).length + 1;
    final pendingLines =
        pendingContent.isEmpty ? 0 : '\n'.allMatches(pendingContent).length + 1;

    return _PendingEditSummary(
      lineDelta: pendingLines - currentLines,
      characterDelta: pendingContent.length - currentContent.length,
    );
  }

  String get lineDeltaLabel => _formatDelta(lineDelta, 'lines');
  String get characterDeltaLabel => _formatDelta(characterDelta, 'chars');

  static String _formatDelta(int delta, String unit) {
    if (delta == 0) {
      return '0 $unit';
    }
    return '${delta > 0 ? '+' : ''}$delta $unit';
  }
}

class _ModelOptionTile extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _ModelOptionTile({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: onTap,
      leading: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color:
            selected ? Theme.of(context).colorScheme.primary : Colors.grey[500],
      ),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}

class ChatMessage {
  final bool isUser;
  final String text;

  const ChatMessage({required this.isUser, required this.text});
}

class _ChatOverlay extends StatelessWidget {
  final List<ChatMessage> messages;
  final bool loading;
  final TextEditingController controller;
  final String? fileLabel;
  final VoidCallback onSend;
  final VoidCallback onClose;
  final ValueChanged<String> onSeedPrompt;
  final VoidCallback? onApplyEdit;
  final VoidCallback? onDismissEdit;

  const _ChatOverlay({
    required this.messages,
    required this.loading,
    required this.controller,
    required this.fileLabel,
    required this.onSend,
    required this.onClose,
    required this.onSeedPrompt,
    this.onApplyEdit,
    this.onDismissEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = <String>[
      'Explain this file',
      'Review for bugs',
      'Refactor safely',
      'Suggest tests',
    ];

    return Material(
      elevation: 16,
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 32,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(context),
            _buildMessagesList(context),
            if (onApplyEdit != null || onDismissEdit != null)
              _buildDraftActions(context),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                return Column(
                  children: [
                    if (value.text.trim().isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              suggestions.map((suggestion) {
                                return ActionChip(
                                  label: Text(suggestion),
                                  onPressed:
                                      () => onSeedPrompt(
                                        _suggestionToPrompt(
                                          suggestion,
                                          fileLabel ?? 'this file',
                                        ),
                                      ),
                                );
                              }).toList(),
                        ),
                      ),
                    _buildInputArea(context),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.smart_toy_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SlashText('Code Assistant', fontWeight: FontWeight.w700),
                SlashText(
                  fileLabel ?? 'No file selected',
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close assistant',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        itemCount: messages.length + (loading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length && loading) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final message = messages[index];
          return Align(
            alignment:
                message.isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(maxWidth: 320),
              decoration: BoxDecoration(
                color:
                    message.isUser
                        ? theme.colorScheme.primary.withValues(alpha: 0.10)
                        : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: SlashText(
                message.text,
                fontSize: 13,
                color:
                    message.isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDraftActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          if (onDismissEdit != null)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDismissEdit,
                icon: const Icon(Icons.close_rounded),
                label: const SlashText('Dismiss Draft'),
              ),
            ),
          if (onDismissEdit != null && onApplyEdit != null)
            const SizedBox(width: 8),
          if (onApplyEdit != null)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onApplyEdit,
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const SlashText('Apply Draft'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Ask for an edit, explanation, or review',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            height: 48,
            child: ElevatedButton(
              onPressed: loading ? null : onSend,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Icon(Icons.send_rounded),
            ),
          ),
        ],
      ),
    );
  }

  String _suggestionToPrompt(String suggestion, String filePath) {
    switch (suggestion) {
      case 'Explain this file':
        return 'Explain how $filePath works and call out the important moving parts.';
      case 'Review for bugs':
        return 'Review $filePath for likely bugs, regressions, and missing edge cases.';
      case 'Refactor safely':
        return 'Refactor $filePath to improve clarity without changing behavior.';
      case 'Suggest tests':
        return 'Suggest the highest-value tests for $filePath and explain why.';
      default:
        return suggestion;
    }
  }
}

const Map<String, TextStyle> _darkCodeTheme = {
  'root': TextStyle(color: Color(0xFFE5E7EB)),
  'keyword': TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.w700),
  'string': TextStyle(color: Color(0xFFF9A8D4)),
  'comment': TextStyle(color: Color(0xFF64748B), fontStyle: FontStyle.italic),
  'number': TextStyle(color: Color(0xFFFCA5A5)),
  'class': TextStyle(color: Color(0xFFFDE68A)),
  'title': TextStyle(color: Color(0xFF67E8F9)),
  'function': TextStyle(color: Color(0xFF67E8F9)),
  'params': TextStyle(color: Color(0xFFE2E8F0)),
  'variable': TextStyle(color: Color(0xFFA7F3D0)),
  'literal': TextStyle(color: Color(0xFFC4B5FD)),
  'built_in': TextStyle(color: Color(0xFFC4B5FD)),
};

const Map<String, TextStyle> _lightCodeTheme = {
  'root': TextStyle(color: Color(0xFF0F172A)),
  'keyword': TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.w700),
  'string': TextStyle(color: Color(0xFFBE185D)),
  'comment': TextStyle(color: Color(0xFF64748B), fontStyle: FontStyle.italic),
  'number': TextStyle(color: Color(0xFFB45309)),
  'class': TextStyle(color: Color(0xFF0F766E)),
  'title': TextStyle(color: Color(0xFF0F766E)),
  'function': TextStyle(color: Color(0xFF0369A1)),
  'params': TextStyle(color: Color(0xFF0F172A)),
  'variable': TextStyle(color: Color(0xFF047857)),
  'literal': TextStyle(color: Color(0xFF7C3AED)),
  'built_in': TextStyle(color: Color(0xFF7C3AED)),
};

const Map<String, String> _extensionLanguageMap = {
  '.dart': 'dart',
  '.yaml': 'yaml',
  '.yml': 'yaml',
  '.json': 'json',
  '.md': 'markdown',
  '.js': 'javascript',
  '.jsx': 'javascript',
  '.ts': 'typescript',
  '.tsx': 'typescript',
  '.java': 'java',
  '.kt': 'kotlin',
  '.swift': 'swift',
  '.py': 'python',
  '.rb': 'ruby',
  '.go': 'go',
  '.rs': 'rust',
  '.sh': 'bash',
  '.bash': 'bash',
  '.zsh': 'bash',
  '.c': 'cpp',
  '.cc': 'cpp',
  '.cpp': 'cpp',
  '.h': 'cpp',
  '.hpp': 'cpp',
  '.cs': 'cs',
  '.css': 'css',
  '.scss': 'scss',
  '.html': 'xml',
  '.xml': 'xml',
  '.svg': 'xml',
  '.sql': 'sql',
  '.toml': 'ini',
  '.ini': 'ini',
  '.gradle': 'gradle',
  '.plist': 'xml',
};

const Map<String, String> _namedLanguageMap = {
  'dockerfile': 'dockerfile',
  'makefile': 'makefile',
  'podfile': 'ruby',
  'gemfile': 'ruby',
};

const Map<String, String> _languageLabels = {
  'plaintext': 'Plain Text',
  'dart': 'Dart',
  'yaml': 'YAML',
  'json': 'JSON',
  'markdown': 'Markdown',
  'javascript': 'JavaScript',
  'typescript': 'TypeScript',
  'java': 'Java',
  'kotlin': 'Kotlin',
  'swift': 'Swift',
  'python': 'Python',
  'ruby': 'Ruby',
  'go': 'Go',
  'rust': 'Rust',
  'bash': 'Shell',
  'cpp': 'C/C++',
  'cs': 'C#',
  'css': 'CSS',
  'scss': 'SCSS',
  'xml': 'XML/HTML',
  'sql': 'SQL',
  'ini': 'INI/TOML',
  'gradle': 'Gradle',
  'dockerfile': 'Dockerfile',
  'makefile': 'Makefile',
};
