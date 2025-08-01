import 'dart:async';

import '../tools/tool.dart';
import '../tools/file_tools.dart';

class AgentPlanStep {
  final String step;
  final List<Map<String, dynamic>> toolCalls; // [{tool, args}]
  final String? rationale;

  AgentPlanStep({required this.step, required this.toolCalls, this.rationale});
}

class AgentPlanResult {
  final List<AgentPlanStep> steps;
  final List<Map<String, dynamic>> trace; // [{tool, args, result}]
  final List<ProposedFileDiff> diffs;
  final bool success;
  final String? error;

  AgentPlanResult({
    required this.steps,
    required this.trace,
    required this.diffs,
    required this.success,
    this.error,
  });
}

class ProposedFileDiff {
  final String path;
  final String patchPreview; // full new content or unified diff preview

  ProposedFileDiff({required this.path, required this.patchPreview});
}

/// Minimal MVP orchestrator:
/// - registers default file tools
/// - executes a simple scripted plan for a "search and propose replace" flow
/// - does not call external LLM yet; this is the skeleton to wire UI and tool trace.
class AgentOrchestrator {
  AgentOrchestrator({
    List<String>? allowedRoots,
    this.maxFiles = 30,
  }) {
    // Register default tools
    registerDefaultFileTools();
    if (allowedRoots != null && allowedRoots.isNotEmpty) {
      ToolRegistry.instance.setAllowedRoots(allowedRoots);
    }
  }

  final int maxFiles;

  /// Very small proof: search for regex and propose replacement diffs for matches.
  /// Args:
  ///   goal: natural text, e.g., "Replace all SlashText with Text in lib/features/prompt"
  ///   dir: scope directory (e.g., 'lib/features/prompt')
  ///   regex: search regex (e.g., r'\bSlashText\b')
  ///   replaceWith: replacement text (e.g., 'Text')
  /// Returns: plan result with tool trace and proposed diffs (previewed new content).
  Future<AgentPlanResult> runSimpleSearchReplace({
    required String goal,
    required String dir,
    required String regex,
    required String replaceWith,
    List<String>? extensions = const ['dart'],
    bool dryRun = true,
  }) async {
    final trace = <Map<String, dynamic>>[];
    final steps = <AgentPlanStep>[];
    final diffs = <ProposedFileDiff>[];

    try {
      // Step 1: list/search
      steps.add(AgentPlanStep(
        step: 'Search for matches',
        rationale: 'Identify files impacted by the requested change.',
        toolCalls: [
          {
            'tool': 'file_search',
            'args': {
              'dir': dir,
              'regex': regex,
              'extensions': extensions,
              'maxResults': maxFiles
            }
          }
        ],
      ));

      final searchRes =
          await ToolRegistry.instance.invoke('file_search', {'dir': dir, 'regex': regex, 'extensions': extensions, 'maxResults': maxFiles});
      trace.add({
        'tool': 'file_search',
        'args': {'dir': dir, 'regex': regex, 'extensions': extensions, 'maxResults': maxFiles},
        'result': {
          'success': searchRes.success,
          'stderr': searchRes.stderr,
          'data': searchRes.data,
        }
      });
      if (!searchRes.success) {
        return AgentPlanResult(
          steps: steps,
          trace: trace,
          diffs: diffs,
          success: false,
          error: searchRes.stderr ?? 'Search failed',
        );
      }

      final matches = (searchRes.data?['matches'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final paths = matches.map((m) => m['path'] as String).toSet().toList();
      if (paths.isEmpty) {
        return AgentPlanResult(
          steps: steps,
          trace: trace,
          diffs: diffs,
          success: true,
          error: null,
        );
      }

      // Step 2: read each file and propose new content (preview only)
      for (final p in paths.take(maxFiles)) {
        steps.add(AgentPlanStep(
          step: 'Read and propose edit for $p',
          rationale: 'Prepare a diff preview before applying changes.',
          toolCalls: [
            {
              'tool': 'file_read',
              'args': {'path': p}
            }
          ],
        ));

        final readRes = await ToolRegistry.instance.invoke('file_read', {'path': p});
        trace.add({
          'tool': 'file_read',
          'args': {'path': p},
          'result': {'success': readRes.success, 'stderr': readRes.stderr}
        });
        if (!readRes.success) {
          continue;
        }
        final content = (readRes.data?['content'] as String?) ?? '';
        final newContent = content.replaceAll(RegExp(regex), replaceWith);

        if (newContent != content) {
          // Preview via file_patch dry-run by crafting a minimal unified-like patch
          final previewPatch = _makeUnifiedLikePreview(old: content, updated: newContent);

          steps.add(AgentPlanStep(
            step: 'Propose patch for $p',
            rationale: 'Offer a preview patch (dryRun).',
            toolCalls: [
              {
                'tool': 'file_patch',
                'args': {'path': p, 'patch': previewPatch, 'dryRun': true}
              }
            ],
          ));

          final patchRes = await ToolRegistry.instance.invoke('file_patch', {
            'path': p,
            'patch': previewPatch,
            'dryRun': true,
          });

          trace.add({
            'tool': 'file_patch',
            'args': {'path': p, 'dryRun': true},
            'result': {
              'success': patchRes.success,
              'stderr': patchRes.stderr,
              'data': {'previewBytes': newContent.length}
            }
          });

          // Even if naive applier fails, keep preview from our computation
          final preview = patchRes.success
              ? (patchRes.data?['preview'] as String? ?? newContent)
              : newContent;

          diffs.add(ProposedFileDiff(path: p, patchPreview: preview));
        }
      }

      return AgentPlanResult(
        steps: steps,
        trace: trace,
        diffs: diffs,
        success: true,
      );
    } catch (e) {
      return AgentPlanResult(
        steps: steps,
        trace: trace,
        diffs: diffs,
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Build a simple "unified-like" patch from full old/new content.
  /// For MVP we just mark a single big replacement hunk.
  String _makeUnifiedLikePreview({
    required String old,
    required String updated,
  }) {
    final oldLines = old.split('\n');
    final newLines = updated.split('\n');
    final oldLen = oldLines.length;
    final newLen = newLines.length;
    final header = '@@ -1,$oldLen +1,$newLen @@';
    final buf = StringBuffer()..writeln(header);

    // naive: produce full removal and addition
    for (final l in oldLines) {
      buf.writeln('-$l');
    }
    for (final l in newLines) {
      buf.writeln('+$l');
    }
    return buf.toString();
  }
}
