import 'package:flutter/foundation.dart';

import '../agent/orchestrator/agent_orchestrator.dart';

class AgentRunResult {
  final AgentPlanResult plan;
  AgentRunResult(this.plan);
}

class AgentRunner with ChangeNotifier {
  final AgentOrchestrator _orchestrator = AgentOrchestrator(allowedRoots: const ['lib', 'assets']);
  bool _running = false;
  AgentPlanResult? _lastResult;

  bool get running => _running;
  AgentPlanResult? get lastResult => _lastResult;

  Future<AgentRunResult> runSimpleSearchReplace({
    required String goal,
    required String dir,
    required String regex,
    required String replaceWith,
    List<String>? extensions = const ['dart'],
  }) async {
    _running = true;
    notifyListeners();
    try {
      final res = await _orchestrator.runSimpleSearchReplace(
        goal: goal,
        dir: dir,
        regex: regex,
        replaceWith: replaceWith,
        extensions: extensions,
        dryRun: true,
      );
      _lastResult = res;
      notifyListeners();
      return AgentRunResult(res);
    } finally {
      _running = false;
      notifyListeners();
    }
  }
}
