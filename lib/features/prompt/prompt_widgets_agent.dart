import 'package:flutter/material.dart';

import '../agent/orchestrator/agent_orchestrator.dart';

class AgentTraceView extends StatelessWidget {
  final List<Map<String, dynamic>> trace;
  const AgentTraceView({super.key, required this.trace});

  @override
  Widget build(BuildContext context) {
    if (trace.isEmpty) {
      return const Text('No tool calls yet.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: trace.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final t = trace[i];
        final tool = t['tool'];
        final args = t['args'];
        final result = t['result'];
        final ok = result?['success'] == true;
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: ok ? Colors.green.withOpacity(0.07) : Colors.red.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ok ? Colors.green.shade200 : Colors.red.shade200),
          ),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodySmall!,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tool: $tool', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Args: ${_shorten(args)}'),
                if (result != null) ...[
                  const SizedBox(height: 4),
                  Text('Result: ${_shorten(result)}'),
                ]
              ],
            ),
          ),
        );
      },
    );
  }

  String _shorten(Object? o) {
    final s = o.toString();
    if (s.length <= 300) return s;
    return '${s.substring(0, 300)}…';
    }
}

class AgentDiffList extends StatelessWidget {
  final List<ProposedFileDiff> diffs;
  final void Function(String path, String preview)? onApplyOne;
  const AgentDiffList({super.key, required this.diffs, this.onApplyOne});

  @override
  Widget build(BuildContext context) {
    if (diffs.isEmpty) {
      return const Text('No diffs proposed.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: diffs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final d = diffs[i];
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blueGrey.withOpacity(0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blueGrey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.path, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    d.patchPreview,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (onApplyOne != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => onApplyOne!(d.path, d.patchPreview),
                    icon: const Icon(Icons.check),
                    label: const Text('Apply preview content'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
