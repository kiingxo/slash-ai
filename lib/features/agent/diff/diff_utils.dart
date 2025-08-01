import 'dart:convert';

/// A simple, line-oriented diff generator (Myers-like) and a robust
/// multi-hunk unified diff applier. This is intended for medium-sized files.
/// Notes:
/// - Diff granularity is per-line (not character-level).
/// - Generator produces unified diff with context lines around changes.
/// - Applier supports multiple hunks, context checking, and offset matching.
///
/// API:
///   final unified = UnifiedDiff.generate(oldContent, newContent, path: 'lib/a.dart');
///   final applyResult = UnifiedDiff.apply(originalContent, unified);
///   if (applyResult.success) final updated = applyResult.content;

/// Represents a single unified diff hunk.
class UnifiedHunk {
  final int oldStart; // 1-based
  final int oldCount;
  final int newStart; // 1-based
  final int newCount;
  final List<String> lines; // includes ' ', '+', '-' prefixes

  UnifiedHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });

  @override
  String toString() => '@@ -$oldStart,$oldCount +$newStart,$newCount @@';
}

class UnifiedPatch {
  final String? path; // optional metadata
  final List<UnifiedHunk> hunks;

  UnifiedPatch({this.path, required this.hunks});

  String toUnifiedString() {
    final buf = StringBuffer();
    if (path != null) {
      // Optional headers (kept minimal)
      buf.writeln('--- a/$path');
      buf.writeln('+++ b/$path');
    }
    for (final h in hunks) {
      buf.writeln('@@ -${h.oldStart},${h.oldCount} +${h.newStart},${h.newCount} @@');
      for (final l in h.lines) {
        buf.writeln(l);
      }
    }
    return buf.toString();
  }

  static UnifiedPatch parse(String patch) {
    final lines = const LineSplitter().convert(patch);
    String? path;
    int idx = 0;

    // Optional headers
    if (idx < lines.length && lines[idx].startsWith('--- ')) {
      idx++;
      if (idx < lines.length && lines[idx].startsWith('+++ ')) {
        // attempt to derive path
        final plus = lines[idx];
        // format: +++ b/path
        final space = plus.indexOf(' ');
        if (space != -1) {
          final part = plus.substring(space + 1).trim();
          if (part.startsWith('b/')) {
            path = part.substring(2);
          } else {
            path = part;
          }
        }
        idx++;
      }
    }

    final hunks = <UnifiedHunk>[];
    while (idx < lines.length) {
      final l = lines[idx];
      if (!l.startsWith('@@')) {
        idx++;
        continue;
      }
      // @@ -oldStart,oldCount +newStart,newCount @@
      final match = RegExp(r'^@@\s+-(\d+),(\d+)\s+\+(\d+),(\d+)\s+@@').firstMatch(l);
      if (match == null) {
        idx++;
        continue;
      }
      final oldStart = int.parse(match.group(1)!);
      final oldCount = int.parse(match.group(2)!);
      final newStart = int.parse(match.group(3)!);
      final newCount = int.parse(match.group(4)!);
      idx++;

      final hunkLines = <String>[];
      while (idx < lines.length) {
        final hl = lines[idx];
        if (hl.startsWith('@@')) break;
        if (hl.isEmpty) {
          // empty lines are allowed as context with explicit space prefix not guaranteed in some patches
          // normalize to context where missing a sign
          hunkLines.add(' $hl');
        } else if (hl.startsWith(' ') || hl.startsWith('+') || hl.startsWith('-')) {
          hunkLines.add(hl);
        } else {
          // normalize to context if no sign
          hunkLines.add(' $hl');
        }
        idx++;
      }
      hunks.add(UnifiedHunk(
        oldStart: oldStart,
        oldCount: oldCount,
        newStart: newStart,
        newCount: newCount,
        lines: hunkLines,
      ));
    }
    return UnifiedPatch(path: path, hunks: hunks);
  }
}

class ApplyResult {
  final bool success;
  final String? content;
  final String? error;

  ApplyResult._(this.success, this.content, this.error);

  static ApplyResult ok(String content) => ApplyResult._(true, content, null);
  static ApplyResult fail(String error) => ApplyResult._(false, null, error);
}

class UnifiedDiff {
  /// Generate unified diff between old and updated content.
  static String generate(String oldContent, String newContent, {String? path, int context = 3}) {
    final oldLines = const LineSplitter().convert(oldContent);
    final newLines = const LineSplitter().convert(newContent);

    final ops = _diff(oldLines, newLines);
    final hunks = _opsToHunks(oldLines, newLines, ops, context: context);
    final patch = UnifiedPatch(path: path, hunks: hunks);
    return patch.toUnifiedString();
  }

  /// Apply unified diff to original content, supporting multiple hunks with context matching and offsets.
  static ApplyResult apply(String original, String unifiedPatch) {
    final patch = UnifiedPatch.parse(unifiedPatch);
    final lines = const LineSplitter().convert(original);

    // We'll apply hunks sequentially with cumulative offset tracking.
    var current = List<String>.from(lines);
    int offset = 0;

    for (final h in patch.hunks) {
      final res = _applyOneHunk(current, h, offset);
      if (res == null) {
        return ApplyResult.fail('Failed to apply hunk starting at -${h.oldStart},+${h.newStart}');
      }
      current = res.lines;
      offset = res.offset;
    }
    return ApplyResult.ok(current.join('\n'));
  }

  // Internal: apply a single hunk with best-effort context search window.
  static _HunkApplyState? _applyOneHunk(List<String> base, UnifiedHunk hunk, int baseOffset) {
    // Convert 1-based to 0-based index with current offset.
    final expectedIndex = hunk.oldStart - 1 + baseOffset;

    // Try exact position, then small search window around.
    final candidates = <int>[
      expectedIndex,
      expectedIndex - 1,
      expectedIndex + 1,
      expectedIndex - 2,
      expectedIndex + 2,
    ].where((i) => i >= 0 && i <= base.length).toList();

    for (final startIdx in candidates) {
      final res = _tryApplyAt(base, hunk, startIdx);
      if (res != null) return res;
    }
    return null;
  }

  static _HunkApplyState? _tryApplyAt(List<String> base, UnifiedHunk hunk, int startIdx) {
    final out = <String>[];
    out.addAll(base.take(startIdx));

    int readCursor = startIdx;
    int removed = 0;
    int added = 0;

    for (final l in hunk.lines) {
      if (l.isEmpty) continue;
      final sign = l[0];
      final body = l.length > 1 ? l.substring(1) : '';

      if (sign == ' ') {
        // context: must match base at readCursor; if not, abort
        if (readCursor >= base.length) return null;
        final baseLine = base[readCursor];
        if (baseLine != body) return null;
        out.add(baseLine);
        readCursor++;
      } else if (sign == '-') {
        // removal: base at readCursor must equal body, then skip it
        if (readCursor >= base.length) return null;
        final baseLine = base[readCursor];
        if (baseLine != body) return null;
        readCursor++;
        removed++;
      } else if (sign == '+') {
        // addition: add body to out
        out.add(body);
        added++;
      } else {
        // unknown sign
        return null;
      }
    }

    // Append remaining base
    out.addAll(base.skip(readCursor));

    final offsetDelta = added - removed;
    return _HunkApplyState(lines: out, offset: offsetDelta);
  }

  // Myers diff (simplified) returning operations between two line arrays.
  static List<_Op> _diff(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    final max = n + m;
    final v = <int, int>{1: 0};
    final trace = <Map<int, int>>[];

    for (int d = 0; d <= max; d++) {
      final vd = <int, int>{};
      for (int k = -d; k <= d; k += 2) {
        int x;
        if (k == -d || (k != d && (v[k - 1] ?? -1) < (v[k + 1] ?? -1))) {
          x = v[k + 1] ?? 0;
        } else {
          x = (v[k - 1] ?? 0) + 1;
        }
        int y = x - k;
        while (x < n && y < m && a[x] == b[y]) {
          x++;
          y++;
        }
        vd[k] = x;
        if (x >= n && y >= m) {
          trace.add(vd);
          return _buildOp(a, b, trace);
        }
      }
      trace.add(vd);
      v
        ..clear()
        ..addAll(vd);
    }
    return _buildOp(a, b, trace);
  }

  static List<_Op> _buildOp(List<String> a, List<String> b, List<Map<int, int>> trace) {
    int x = a.length;
    int y = b.length;
    final ops = <_Op>[];

    for (int d = trace.length - 1; d >= 0; d--) {
      final v = trace[d];
      final k = x - y;
      int prevK;
      int prevX;
      if (k == -d || (k != d && (v[k - 1] ?? -1) < (v[k + 1] ?? -1))) {
        prevK = k + 1;
        prevX = v[prevK] ?? 0;
      } else {
        prevK = k - 1;
        prevX = (v[prevK] ?? 0) + 1;
      }
      final prevY = prevX - prevK;

      while (x > prevX && y > prevY) {
        ops.add(_Op.equal(a[x - 1]));
        x--;
        y--;
      }
      if (d == 0) break;
      if (x == prevX) {
        ops.add(_Op.insert(b[y - 1]));
        y--;
      } else {
        ops.add(_Op.delete(a[x - 1]));
        x--;
      }
    }
    return ops.reversed.toList();
  }

  static List<UnifiedHunk> _opsToHunks(List<String> oldLines, List<String> newLines, List<_Op> ops, {int context = 3}) {
    final hunks = <UnifiedHunk>[];

    int oldLine = 1;
    int newLine = 1;

    List<String> hunkLines = [];
    int? hunkOldStart;
    int? hunkNewStart;
    int hunkOldCount = 0;
    int hunkNewCount = 0;
    int trailingContext = 0;

    void flushHunk() {
      if (hunkOldStart == null) return;
      hunks.add(UnifiedHunk(
        oldStart: hunkOldStart!,
        oldCount: hunkOldCount,
        newStart: hunkNewStart!,
        newCount: hunkNewCount,
        lines: List<String>.from(hunkLines),
      ));
      hunkLines = [];
      hunkOldStart = null;
      hunkNewStart = null;
      hunkOldCount = 0;
      hunkNewCount = 0;
      trailingContext = 0;
    }

    void ensureOpen() {
      hunkOldStart ??= oldLine;
      hunkNewStart ??= newLine;
    }

    for (final op in ops) {
      if (op.type == _OpType.equal) {
        if (hunkOldStart != null) {
          if (trailingContext < context) {
            hunkLines.add(' ${op.text}');
            hunkOldCount++;
            hunkNewCount++;
            trailingContext++;
          } else {
            // too much context; close current hunk
            flushHunk();
            // start fresh after this equal line is outside hunks
            trailingContext = 0;
          }
        }
        oldLine++;
        newLine++;
      } else if (op.type == _OpType.delete) {
        ensureOpen();
        hunkLines.add('-${op.text}');
        hunkOldCount++;
        oldLine++;
        trailingContext = 0;
      } else if (op.type == _OpType.insert) {
        ensureOpen();
        hunkLines.add('+${op.text}');
        hunkNewCount++;
        newLine++;
        trailingContext = 0;
      }
    }
    flushHunk();
    return hunks;
  }
}

enum _OpType { equal, insert, delete }

class _Op {
  final _OpType type;
  final String text;

  _Op._(this.type, this.text);

  factory _Op.equal(String s) => _Op._(_OpType.equal, s);
  factory _Op.insert(String s) => _Op._(_OpType.insert, s);
  factory _Op.delete(String s) => _Op._(_OpType.delete, s);
}

class _HunkApplyState {
  final List<String> lines;
  final int offset; // offset delta contributed by this hunk

  _HunkApplyState({required this.lines, required this.offset});
}
