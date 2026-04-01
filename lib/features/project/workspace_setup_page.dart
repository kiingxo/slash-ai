import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/github_service.dart';
import '../../services/secure_storage_service.dart';
import '../../ui/components/slash_text.dart';
import '../repo/repo_controller.dart';

// ── Page ──────────────────────────────────────────────────────────────────────

class WorkspaceSetupPage extends ConsumerStatefulWidget {
  const WorkspaceSetupPage({super.key});

  @override
  ConsumerState<WorkspaceSetupPage> createState() => _WorkspaceSetupPageState();
}

class _WorkspaceSetupPageState extends ConsumerState<WorkspaceSetupPage> {
  final _identityCtrl = TextEditingController();
  final _rulesCtrl = TextEditingController();
  final _contextCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  String? _saving; // which file key is saving
  final _saved = <String>{};

  // tracks whether a file already exists (has a sha)
  final _shas = <String, String>{};

  static const _files = <_WsFile>[
    _WsFile(
      key: 'identity',
      path: '.slash/identity.md',
      title: 'Project Identity',
      icon: Icons.badge_rounded,
      accentColor: Color(0xFF8B5CF6),
      description:
          'Describe this project for Slash — what it does, the tech stack, '
          'the primary language/framework, and what areas Slash should focus on.',
      placeholder: '''# Project Identity

## What this project does
Briefly describe what this repo builds and who it's for.

## Tech stack
- Language: ...
- Framework: ...
- Database: ...

## Focus areas for Slash
- Primary source directory: src/ (or wherever your code lives)
- Key areas: authentication, API, data models, UI

## What Slash should avoid
- Do not modify auto-generated files
- Do not change lock files (package-lock.json, pubspec.lock, etc.)
''',
    ),
    _WsFile(
      key: 'rules',
      path: '.slash/rules.md',
      title: 'Coding Rules',
      icon: Icons.rule_rounded,
      accentColor: Color(0xFF06B6D4),
      description:
          'Define coding conventions Slash must follow — naming, formatting, '
          'patterns to use or avoid, and anything that would fail a code review.',
      placeholder: '''# Coding Rules

## Naming
- Classes/components: PascalCase
- Variables/functions: camelCase (or snake_case — whatever your team uses)
- Constants: UPPER_SNAKE or kConstantName

## Style
- Max line length: 100 chars
- Always use trailing commas
- Prefer explicit types over var/any

## Patterns
- How state is managed: ...
- How API calls are structured: ...
- Folder/module structure: ...

## Forbidden
- No console.log / print() in production code
- No hardcoded secrets or API keys
- No direct database calls outside of service/repository layer
''',
    ),
    _WsFile(
      key: 'context',
      path: '.slash/context.md',
      title: 'Architecture Context',
      icon: Icons.account_tree_rounded,
      accentColor: Color(0xFF10B981),
      description:
          'Explain architecture decisions, known technical debt, and any '
          'non-obvious design choices that would confuse an outside engineer.',
      placeholder: '''# Architecture Context

## Folder structure
- src/features/ — describe your structure here
- src/services/ — shared services
- src/utils/ — helpers and utilities

## Key decisions
- Why certain libraries or patterns were chosen
- Any non-obvious architectural choices
- How authentication works in this project

## Known debt
- Areas of the codebase that need refactoring
- Known performance issues
- Missing test coverage

## Do not touch
- List any fragile or critical files Slash should leave alone
- Third-party integrations that are known to be brittle
''',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _identityCtrl.dispose();
    _rulesCtrl.dispose();
    _contextCtrl.dispose();
    super.dispose();
  }

  TextEditingController _ctrl(String key) {
    return switch (key) {
      'identity' => _identityCtrl,
      'rules' => _rulesCtrl,
      _ => _contextCtrl,
    };
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repoState = ref.read(repoControllerProvider);
      final repo =
          repoState.selectedRepo ??
          (repoState.repos.isNotEmpty ? repoState.repos.first : null);
      if (repo == null) throw Exception('No repository selected.');

      final token = await SecureStorageService().getGitHubAccessToken();
      if (token == null || token.isEmpty) {
        throw Exception('GitHub authentication required.');
      }

      final owner = (repo['owner']?['login'] ?? '').toString();
      final repoName = (repo['name'] ?? '').toString();
      final branch = (repo['default_branch'] ?? 'main').toString();
      final github = GitHubService(token);

      for (final file in _files) {
        try {
          final fetched = await github.fetchFileContent(
            owner: owner,
            repo: repoName,
            path: file.path,
            branch: branch,
          );
          _ctrl(file.key).text = fetched.content;
          if (fetched.sha.isNotEmpty) _shas[file.key] = fetched.sha;
        } catch (_) {
          // File doesn't exist yet — leave controller empty
        }
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveFile(_WsFile file) async {
    final content = _ctrl(file.key).text.trim();
    if (content.isEmpty) return;

    setState(() {
      _saving = file.key;
      _error = null;
    });

    try {
      final repoState = ref.read(repoControllerProvider);
      final repo =
          repoState.selectedRepo ??
          (repoState.repos.isNotEmpty ? repoState.repos.first : null);
      if (repo == null) throw Exception('No repository selected.');

      final token = await SecureStorageService().getGitHubAccessToken();
      if (token == null || token.isEmpty) {
        throw Exception('GitHub authentication required.');
      }

      final owner = (repo['owner']?['login'] ?? '').toString();
      final repoName = (repo['name'] ?? '').toString();
      final branch = (repo['default_branch'] ?? 'main').toString();
      final github = GitHubService(token);

      await github.commitFile(
        owner: owner,
        repo: repoName,
        branch: branch,
        path: file.path,
        content: content,
        message: 'chore: update ${file.path}',
      );

      // Refresh sha after commit
      try {
        final fetched = await github.fetchFileContent(
          owner: owner,
          repo: repoName,
          path: file.path,
          branch: branch,
        );
        _shas[file.key] = fetched.sha;
      } catch (_) {}

      if (mounted) {
        setState(() => _saved.add(file.key));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${file.path} saved to $branch'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _saved.remove(file.key));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Workspace', fontWeight: FontWeight.w700),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                // Explainer banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: 0.08),
                        theme.colorScheme.primary.withValues(alpha: 0.02),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.15,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.psychology_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Workspace Identity Files',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'These Markdown files live in your repo\'s .slash/ folder. '
                              'Slash reads them automatically on every prompt — '
                              'they define the project\'s identity, rules, and architecture '
                              'so Slash always follows your conventions.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBanner(
                    message: _error!,
                    onDismiss: () => setState(() => _error = null),
                  ),
                ],
                const SizedBox(height: 20),
                for (final file in _files) ...[
                  _FileEditor(
                    file: file,
                    controller: _ctrl(file.key),
                    isSaving: _saving == file.key,
                    isSaved: _saved.contains(file.key),
                    exists: _shas.containsKey(file.key),
                    onSave: () => _saveFile(file),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
    );
  }
}

// ── File editor card ──────────────────────────────────────────────────────────

class _FileEditor extends StatefulWidget {
  const _FileEditor({
    required this.file,
    required this.controller,
    required this.isSaving,
    required this.isSaved,
    required this.exists,
    required this.onSave,
  });

  final _WsFile file;
  final TextEditingController controller;
  final bool isSaving;
  final bool isSaved;
  final bool exists;
  final VoidCallback onSave;

  @override
  State<_FileEditor> createState() => _FileEditorState();
}

class _FileEditorState extends State<_FileEditor> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // auto-expand if file already has content
    _expanded = widget.controller.text.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.file.accentColor;
    final hasContent = widget.controller.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _expanded
              ? accent.withValues(alpha: 0.25)
              : theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.file.icon, color: accent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.file.title,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (widget.exists || hasContent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.exists
                                      ? const Color(
                                          0xFF22C55E,
                                        ).withValues(alpha: 0.12)
                                      : accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.exists ? 'SAVED' : 'DRAFT',
                                  style: TextStyle(
                                    color: widget.exists
                                        ? const Color(0xFF22C55E)
                                        : accent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 9,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.file.path,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.45,
                            ),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
          // Expanded body
          if (_expanded) ...[
            Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.08),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.file.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: widget.controller,
                    maxLines: null,
                    minLines: 10,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.6,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.file.placeholder,
                      hintStyle: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.25,
                        ),
                        fontFamily: 'monospace',
                        height: 1.6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.12,
                          ),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: accent.withValues(alpha: 0.4),
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.isSaved)
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: const Color(0xFF22C55E),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Committed to GitHub',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF22C55E),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      else
                        FilledButton.icon(
                          onPressed:
                              (widget.isSaving || !hasContent)
                                  ? null
                                  : widget.onSave,
                          icon: widget.isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload_rounded, size: 16),
                          label: Text(
                            widget.isSaving
                                ? 'Saving…'
                                : widget.exists
                                ? 'Update'
                                : 'Commit to Repo',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF7F1D1D),
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 16),
            color: const Color(0xFF7F1D1D),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _WsFile {
  const _WsFile({
    required this.key,
    required this.path,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.description,
    required this.placeholder,
  });

  final String key;
  final String path;
  final String title;
  final IconData icon;
  final Color accentColor;
  final String description;
  final String placeholder;
}
