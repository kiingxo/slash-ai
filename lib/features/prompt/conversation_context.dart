import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../agent/tools/file_tools.dart';
import '../agent/tools/tool.dart';

/// Lightweight conversational context manager + repo index.
/// - Maintains rolling chat history within a token budget.
/// - Builds a scoped index (by folder) of files for auto-retrieval.
/// - Selects relevant files for each prompt using regex/fuzzy search.
/// - Avoids requiring the user to reselect files every turn.
///
/// Usage:
///   final ctx = ConversationContext(scopeRoot: 'lib', maxFilesPerTurn: 12);
///   await ctx.buildIndex(); // once per repo/scope or when invalidated
///   final selection = await ctx.selectContextFor("How is PromptController wiring messages?");
///   // use selection.files (List<{path, content}>) for the LLM call.
///   ctx.addUserTurn(prompt); ctx.addAssistantTurn(reply);
class ConversationContext {
  ConversationContext({
    required this.scopeRoot,
    this.maxFilesPerTurn = 12,
    this.maxMessageChars = 8 * 1024,
  }) {
    ToolRegistry.instance.setAllowedRoots([scopeRoot.split('/').first, 'assets']);
    registerDefaultFileTools();
  }

  final String scopeRoot;
  final int maxFilesPerTurn;
  final int maxMessageChars;

  final ListQueue<Map<String, String>> _chat = ListQueue();
  final Map<String, _IndexedFile> _index = {}; // path -> indexed file

  // Public snapshot accessors
  List<Map<String, String>> get chatTurns => _chat.toList(growable: false);

  void clearChat() => _chat.clear();

  void addUserTurn(String text) {
    _appendTrimmed({'role': 'user', 'text': text});
  }

  void addAssistantTurn(String text) {
    _appendTrimmed({'role': 'assistant', 'text': text});
  }

  void _appendTrimmed(Map<String, String> turn) {
    _chat.add(turn);
    _trimChat();
  }

  void _trimChat() {
    // Keep total serialized length under maxMessageChars by dropping oldest.
    while (_serializedChatLength() > maxMessageChars && _chat.isNotEmpty) {
      _chat.removeFirst();
    }
  }

  int _serializedChatLength() {
    final sb = StringBuffer();
    for (final t in _chat) {
      sb.write(t['role']);
      sb.write(':');
      sb.write(t['text']);
      sb.write('\n');
    }
    return sb.length;
  }

  /// Build or rebuild scoped index (paths + small content previews + stats).
  Future<void> buildIndex() async {
    _index.clear();
    final listRes = await ToolRegistry.instance.invoke('file_list', {
      'dir': scopeRoot,
      'recursive': true,
      'extensions': ['dart', 'yaml', 'md']
    });
    if (!listRes.success) return;

    final files = (listRes.data?['files'] as List?)?.cast<String>() ?? const [];
    for (final p in files) {
      final read = await ToolRegistry.instance.invoke('file_read', {'path': p, 'maxBytes': 100 * 1024});
      if (!read.success) continue;
      final content = (read.data?['content'] as String?) ?? '';
      _index[p] = _IndexedFile(
        path: p,
        content: content,
        lower: content.toLowerCase(),
        size: content.length,
        mtime: await _mtime(p),
      );
    }
  }

  /// Returns selected files with full content for a given prompt + prior conversation.
  Future<ContextSelection> selectContextFor(String prompt, {List<String>? forceIncludePaths}) async {
    if (_index.isEmpty) {
      await buildIndex();
    }
    final query = _buildQuery(prompt);
    final ranked = _rankFiles(query, forceIncludePaths: forceIncludePaths);
    final top = ranked.take(maxFilesPerTurn).toList();

    // fetch full content (already present in index; re-read if needed)
    final files = <Map<String, String>>[];
    for (final f in top) {
      files.add({'name': f.path, 'content': f.content});
    }

    return ContextSelection(
      files: files,
      debugInfo: {
        'query': query,
        'selectedCount': files.length,
        'scopeRoot': scopeRoot,
      },
    );
  }

  /// Allow changing scope quickly, invalidating the index.
  void updateScopeRoot(String newRoot) {
    if (newRoot == scopeRoot) return;
    _index.clear();
    ToolRegistry.instance.setAllowedRoots([newRoot.split('/').first, 'assets']);
  }

  // Build a query string using user prompt + latest assistant turns for cohesion.
  String _buildQuery(String prompt) {
    final sb = StringBuffer();
    sb.writeln(prompt.toLowerCase());
    // include last 2 assistant turns for follow-up continuity
    int taken = 0;
    for (final t in _chat.toList().reversed) {
      if (t['role'] == 'assistant') {
        sb.writeln(t['text']?.toLowerCase() ?? '');
        taken++;
        if (taken >= 2) break;
      }
    }
    return sb.toString();
  }

  List<_IndexedFile> _rankFiles(String query, {List<String>? forceIncludePaths}) {
    final q = query.toLowerCase().trim();
    final words = q.split(RegExp(r'[^a-z0-9_]+')).where((w) => w.isNotEmpty).toList();
    final forced = Set<String>.from(forceIncludePaths ?? const []);

    double scoreFile(_IndexedFile f) {
      double s = 0;
      // filename exact/partial match boosts
      final base = f.path.split('/').last.toLowerCase();
      if (q.contains(base)) s += 5;
      for (final w in words) {
        if (base.contains(w)) s += 2;
        // content occurrences
        final occ = _countOccurrences(f.lower, w);
        s += occ * 1.0;
      }
      // small bias against very large files
      s -= (f.size / (200 * 1024)).clamp(0, 5);
      // recency bias
      s += f.mtimeBias;
      // forced include goes to top
      if (forced.contains(f.path)) s += 1000;
      return s;
    }

    final files = _index.values.toList();
    files.sort((a, b) => scoreFile(b).compareTo(scoreFile(a)));
    return files;
  }

  int _countOccurrences(String text, String term) {
    if (term.isEmpty) return 0;
    int count = 0;
    int start = 0;
    while (true) {
      final idx = text.indexOf(term, start);
      if (idx == -1) break;
      count++;
      start = idx + term.length;
    }
    return count;
  }

  Future<DateTime> _mtime(String path) async {
    try {
      final stat = await File(path).stat();
      return stat.modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}

class ContextSelection {
  final List<Map<String, String>> files;
  final Map<String, dynamic> debugInfo;

  ContextSelection({required this.files, required this.debugInfo});
}

class _IndexedFile {
  final String path;
  final String content;
  final String lower;
  final int size;
  final DateTime mtime;

  _IndexedFile({
    required this.path,
    required this.content,
    required this.lower,
    required this.size,
    required this.mtime,
  });

  double get mtimeBias {
    final ageHours = DateTime.now().difference(mtime).inHours;
    if (ageHours <= 1) return 3;
    if (ageHours <= 24) return 2;
    if (ageHours <= 72) return 1;
    return 0;
  }
}
