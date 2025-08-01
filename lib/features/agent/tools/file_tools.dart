import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'tool.dart';
import '../diff/diff_utils.dart';

/// Utility to normalize paths for guards
String _normalize(String path) => path.replaceAll('\\', '/');

/// Lists files under a directory with optional glob-like filtering (very small subset).
class FileListTool implements Tool {
  @override
  String get name => 'file_list';

  @override
  String get description => 'List files under a directory. Args: { "dir": "lib/", "recursive": true, "extensions": ["dart"] }';

  @override
  Future<ToolResult> call(Map<String, dynamic> args) async {
    final sw = Stopwatch()..start();
    try {
      final dirPath = (args['dir'] as String?) ?? 'lib';
      final recursive = (args['recursive'] as bool?) ?? true;
      final extensions = (args['extensions'] as List?)?.cast<String>();

      if (!ToolRegistry.instance.isPathAllowed(dirPath)) {
        return ToolResult.fail(stderr: 'Path not allowed: $dirPath', duration: sw.elapsed);
      }

      final root = Directory(dirPath);
      if (!await root.exists()) {
        return ToolResult.ok(data: {'files': []}, duration: sw.elapsed);
      }

      final files = <String>[];
      final lister = root.list(recursive: recursive, followLinks: false);
      await for (final entity in lister) {
        if (entity is File) {
          final p = _normalize(entity.path);
          if (!ToolRegistry.instance.isPathAllowed(p)) continue;
          if (extensions != null && extensions.isNotEmpty) {
            final ext = p.split('.').last;
            if (!extensions.contains(ext)) continue;
          }
          files.add(p);
        }
      }
      return ToolResult.ok(data: {'files': files}, duration: sw.elapsed);
    } catch (e) {
      return ToolResult.fail(stderr: e.toString(), duration: sw.elapsed);
    }
  }
}

/// Reads a text file.
class FileReadTool implements Tool {
  @override
  String get name => 'file_read';

  @override
  String get description => 'Read a text file. Args: { "path": "lib/main.dart", "maxBytes": 1024*1024 }';

  @override
  Future<ToolResult> call(Map<String, dynamic> args) async {
    final sw = Stopwatch()..start();
    try {
      final path = (args['path'] as String?) ?? '';
      if (!ToolRegistry.instance.isPathAllowed(path)) {
        return ToolResult.fail(stderr: 'Path not allowed: $path', duration: sw.elapsed);
      }
      final file = File(path);
      if (!await file.exists()) {
        return ToolResult.fail(stderr: 'File not found: $path', duration: sw.elapsed);
      }
      final maxBytes = (args['maxBytes'] as int?) ?? (2 * 1024 * 1024);
      final raf = await file.open();
      final len = await raf.length();
      final toRead = len > maxBytes ? maxBytes : len;
      final bytes = await raf.read(toRead);
      await raf.close();
      final content = utf8.decode(bytes);
      return ToolResult.ok(data: {'path': path, 'content': content}, duration: sw.elapsed);
    } catch (e) {
      return ToolResult.fail(stderr: e.toString(), duration: sw.elapsed);
    }
  }
}

/// Writes full content to a file (creates if missing).
class FileWriteTool implements Tool {
  @override
  String get name => 'file_write';

  @override
  String get description => 'Write full content to file. Args: { "path": "lib/a.dart", "content": "..." }';

  @override
  Future<ToolResult> call(Map<String, dynamic> args) async {
    final sw = Stopwatch()..start();
    try {
      final path = (args['path'] as String?) ?? '';
      final content = (args['content'] as String?) ?? '';
      if (!ToolRegistry.instance.isPathAllowed(path)) {
        return ToolResult.fail(stderr: 'Path not allowed: $path', duration: sw.elapsed);
      }
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      return ToolResult.ok(data: {'path': path, 'bytes': content.length}, duration: sw.elapsed);
    } catch (e) {
      return ToolResult.fail(stderr: e.toString(), duration: sw.elapsed);
    }
  }
}

/// Naive regex search in files (small projects). Args: { "dir": "lib", "regex": "class\\s+Home", "extensions": ["dart"], "maxResults": 200 }
class FileSearchTool implements Tool {
  @override
  String get name => 'file_search';

  @override
  String get description => 'Search files by regex. Args: { "dir": "lib", "regex": "...", "extensions": ["dart"], "maxResults": 200 }';

  @override
  Future<ToolResult> call(Map<String, dynamic> args) async {
    final sw = Stopwatch()..start();
    try {
      final dirPath = (args['dir'] as String?) ?? 'lib';
      final pattern = (args['regex'] as String?) ?? '';
      final extensions = (args['extensions'] as List?)?.cast<String>();
      final maxResults = (args['maxResults'] as int?) ?? 200;

      if (pattern.isEmpty) {
        return ToolResult.fail(stderr: 'regex is required', duration: sw.elapsed);
      }
      if (!ToolRegistry.instance.isPathAllowed(dirPath)) {
        return ToolResult.fail(stderr: 'Path not allowed: $dirPath', duration: sw.elapsed);
      }

      final re = RegExp(pattern, multiLine: true);
      final results = <Map<String, dynamic>>[];

      final root = Directory(dirPath);
      if (!await root.exists()) {
        return ToolResult.ok(data: {'matches': results}, duration: sw.elapsed);
      }

      final lister = root.list(recursive: true, followLinks: false);
      await for (final entity in lister) {
        if (results.length >= maxResults) break;
        if (entity is! File) continue;
        final p = _normalize(entity.path);
        if (!ToolRegistry.instance.isPathAllowed(p)) continue;
        if (extensions != null && extensions.isNotEmpty) {
          final ext = p.split('.').last;
          if (!extensions.contains(ext)) continue;
        }
        final content = await entity.readAsString();
        final matches = re.allMatches(content);
        if (matches.isEmpty) continue;
        final firstN = matches.take(10).map((m) {
          final start = m.start;
          final end = m.end;
          // capture surrounding context
          final lineStart = content.lastIndexOf('\n', start - 1) + 1;
          final lineEnd = content.indexOf('\n', end);
          final context = content.substring(
            lineStart < 0 ? 0 : lineStart,
            lineEnd == -1 ? content.length : lineEnd,
          );
          return {
            'start': start,
            'end': end,
            'match': m.group(0),
            'context': context,
          };
        }).toList();

        results.add({'path': p, 'count': matches.length, 'samples': firstN});
        if (results.length >= maxResults) break;
      }

      return ToolResult.ok(data: {'matches': results}, duration: sw.elapsed);
    } catch (e) {
      return ToolResult.fail(stderr: e.toString(), duration: sw.elapsed);
    }
  }
}

/// Apply a minimal unified diff patch (very small subset).
/// Args: { "path": "lib/a.dart", "patch": "@@ -1,3 +1,3 @@\n-old\n+new\n", "dryRun": true }
class FilePatchTool implements Tool {
  String _extractPathFromHeaders(String patch) {
    // Try to parse +++ b/path from header
    final lines = const LineSplitter().convert(patch);
    for (final l in lines) {
      if (l.startsWith('+++ ')) {
        final space = l.indexOf(' ');
        if (space != -1) {
          var part = l.substring(space + 1).trim();
          if (part.startsWith('b/')) part = part.substring(2);
          if (part.startsWith('a/')) part = part.substring(2);
          return part;
        }
      }
      // stop if we hit the first hunk
      if (l.startsWith('@@')) break;
    }
    return '';
  }
  @override
  String get name => 'file_patch';

  @override
  String get description => 'Apply unified diff to a single file. Args: { "path": "...", "patch": "unified diff", "dryRun": true|false }';

  @override
  Future<ToolResult> call(Map<String, dynamic> args) async {
    final sw = Stopwatch()..start();
    try {
      String path = (args['path'] as String?) ?? '';
      final patch = (args['patch'] as String?) ?? '';
      final dryRun = (args['dryRun'] as bool?) ?? true;

      if (patch.isEmpty) {
        return ToolResult.fail(stderr: 'patch is required', duration: sw.elapsed);
      }

      // If path not provided, try read from unified headers
      if (path.isEmpty) {
        path = _extractPathFromHeaders(patch);
      }
      if (path.isEmpty) {
        return ToolResult.fail(stderr: 'path is required (not provided and not found in patch headers)', duration: sw.elapsed);
      }

      if (!ToolRegistry.instance.isPathAllowed(path)) {
        return ToolResult.fail(stderr: 'Path not allowed: $path', duration: sw.elapsed);
      }

      final file = File(path);
      if (!await file.exists()) {
        return ToolResult.fail(stderr: 'File not found: $path', duration: sw.elapsed);
      }
      final original = await file.readAsString();

      // Use robust unified diff applier
      final applied = UnifiedDiff.apply(original, patch);
      if (!applied.success) {
        return ToolResult.fail(stderr: applied.error ?? 'Failed to apply patch', duration: sw.elapsed);
      }

      if (!dryRun) {
        await file.writeAsString(applied.content!);
      }

      return ToolResult.ok(
        data: {'path': path, 'dryRun': dryRun, 'preview': applied.content},
        duration: sw.elapsed,
      );
    } catch (e) {
      return ToolResult.fail(stderr: e.toString(), duration: sw.elapsed);
    }
  }

  // removed naive single-hunk applier in favor of robust UnifiedDiff.apply
}

/// Helper to register default tools.
void registerDefaultFileTools() {
  final reg = ToolRegistry.instance;
  if (!reg.isRegistered('file_list')) reg.register(FileListTool());
  if (!reg.isRegistered('file_read')) reg.register(FileReadTool());
  if (!reg.isRegistered('file_write')) reg.register(FileWriteTool());
  if (!reg.isRegistered('file_search')) reg.register(FileSearchTool());
  if (!reg.isRegistered('file_patch')) reg.register(FilePatchTool());
}
