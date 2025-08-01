import 'dart:async';

class ToolResult {
  final bool success;
  final String? stdout;
  final String? stderr;
  final Map<String, dynamic>? data;
  final Duration? duration;

  const ToolResult({
    required this.success,
    this.stdout,
    this.stderr,
    this.data,
    this.duration,
  });

  static ToolResult ok({
    String? stdout,
    Map<String, dynamic>? data,
    Duration? duration,
  }) =>
      ToolResult(success: true, stdout: stdout, data: data, duration: duration);

  static ToolResult fail({
    String? stderr,
    Duration? duration,
  }) =>
      ToolResult(success: false, stderr: stderr, duration: duration);
}

abstract class Tool {
  String get name;
  String get description;

  /// Allowed top-level directories guard (enforced by registry / orchestrator)
  Future<ToolResult> call(Map<String, dynamic> args);
}

class ToolRegistry {
  ToolRegistry._();
  static final ToolRegistry instance = ToolRegistry._();

  final Map<String, Tool> _tools = {};
  final Set<String> _allowedRoots = {'lib', 'assets'}; // default guard
  int maxFilesTouched = 50;

  void register(Tool tool) {
    _tools[tool.name] = tool;
  }

  bool isRegistered(String name) => _tools.containsKey(name);

  Tool? get(String name) => _tools[name];

  Iterable<Tool> get all => _tools.values;

  void setAllowedRoots(Iterable<String> roots) {
    _allowedRoots
      ..clear()
      ..addAll(roots);
  }

  bool isPathAllowed(String path) {
    if (path.isEmpty) return false;
    final norm = path.replaceAll('\\', '/');
    final top = norm.split('/').first;
    return _allowedRoots.contains(top);
  }

  Future<ToolResult> invoke(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null) {
      return ToolResult.fail(stderr: 'Tool not found: $name');
    }
    return await tool.call(args);
  }
}
