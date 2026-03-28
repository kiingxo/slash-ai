import 'dart:convert';
import 'dart:math' as math;

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'ops_models.dart';

class VpsOpsService {
  SSHClient? _client;
  VpsConnectionProfile? _activeProfile;

  bool get isConnected => _client != null && !(_client?.isClosed ?? true);

  Future<void> connect(VpsConnectionProfile profile) async {
    if (kIsWeb) {
      throw Exception('SSH sockets are not available on Flutter Web.');
    }

    final normalized = profile.normalized();
    await disconnect();

    try {
      final identities =
          normalized.authMode == VpsAuthMode.privateKey
              ? SSHKeyPair.fromPem(
                normalized.privateKey,
                normalized.passphrase.isEmpty ? null : normalized.passphrase,
              )
              : null;

      final socket = await SSHSocket.connect(
        normalized.host,
        normalized.port,
        timeout: const Duration(seconds: 8),
      );

      final client = SSHClient(
        socket,
        username: normalized.username,
        identities: identities,
        onPasswordRequest:
            normalized.authMode == VpsAuthMode.password
                ? () => normalized.password
                : null,
        keepAliveInterval: const Duration(seconds: 15),
      );

      final authProbe = await client.runWithResult(
        'printf slash-ready',
        stderr: false,
      );

      if (authProbe.exitCode != 0) {
        client.close();
        throw Exception('SSH authentication failed.');
      }

      _client = client;
      _activeProfile = normalized;
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final current = _client;
    _client = null;
    _activeProfile = null;
    if (current == null) {
      return;
    }

    try {
      current.close();
      await current.done;
    } catch (_) {
      // Swallow shutdown errors because they are not actionable for the UI.
    }
  }

  Future<VpsSnapshot> fetchSnapshot(VpsConnectionProfile profile) async {
    await _ensureConnected(profile);
    final output = await _runSectionedScript(_snapshotScript);
    final sections = _parseSections(output);
    final now = DateTime.now();

    final cpuInfo = _parseCpu(sections['CPU']);
    final memoryInfo = _parseMemory(sections['MEMORY']);
    final diskInfo = _parseDisk(sections['DISK']);
    final dockerAvailable = sections['DOCKER_CHECK']?.trim() == 'yes';
    final systemdAvailable = sections['SYSTEMD_CHECK']?.trim() == 'yes';

    return VpsSnapshot(
      collectedAt: now,
      host: profile.host.trim(),
      username: profile.username.trim(),
      hostname: _firstLine(sections['HOSTNAME']) ?? profile.host.trim(),
      osSummary: _firstLine(sections['OS']) ?? 'Linux server',
      uptime: _firstLine(sections['UPTIME']) ?? 'Unavailable',
      cpuLoadPercent: cpuInfo.loadPercent,
      memoryUsagePercent: memoryInfo.usagePercent,
      diskUsagePercent: diskInfo.usagePercent,
      loadAverage1: cpuInfo.load1,
      loadAverage5: cpuInfo.load5,
      loadAverage15: cpuInfo.load15,
      cpuCores: cpuInfo.cores,
      memoryUsedMb: memoryInfo.usedMb,
      memoryTotalMb: memoryInfo.totalMb,
      diskUsedGb: diskInfo.usedGb,
      diskTotalGb: diskInfo.totalGb,
      dockerAvailable: dockerAvailable,
      systemdAvailable: systemdAvailable,
      containers:
          dockerAvailable ? _parseContainers(sections['DOCKER']) : const [],
      services:
          systemdAvailable ? _parseServices(sections['SERVICES']) : const [],
      topProcesses: _parseProcesses(sections['PROCESSES']),
    );
  }

  Future<OpsCommandLogEntry> runCommand({
    required VpsConnectionProfile profile,
    required String command,
  }) async {
    await _ensureConnected(profile);
    final trimmedCommand = command.trim();
    final result = await _runCommand('sh -lc ${_shellQuote(trimmedCommand)}');
    final output = _composeCommandOutput(result);

    return OpsCommandLogEntry(
      command: trimmedCommand,
      output: output,
      exitCode: result.exitCode,
      isError: (result.exitCode ?? 0) != 0,
      ranAt: DateTime.now(),
    );
  }

  Future<void> _ensureConnected(VpsConnectionProfile profile) async {
    final normalized = profile.normalized();
    if (!isConnected ||
        _activeProfile?.endpointLabel != normalized.endpointLabel) {
      await connect(normalized);
    }
  }

  Future<String> _runSectionedScript(String script) async {
    final result = await _runCommand('sh -lc ${_shellQuote(script)}');
    return utf8.decode(result.stdout);
  }

  Future<SSHRunResult> _runCommand(String command) async {
    final client = _client;
    if (client == null) {
      throw Exception('No SSH session is active.');
    }
    return client.runWithResult(command, stderr: true);
  }

  Map<String, String> _parseSections(String output) {
    final lines = const LineSplitter().convert(output);
    final sections = <String, StringBuffer>{};
    String? current;

    for (final line in lines) {
      if (line.startsWith(_sectionPrefix)) {
        current = line.substring(_sectionPrefix.length).trim();
        sections[current] = StringBuffer();
        continue;
      }
      if (current == null) {
        continue;
      }
      sections[current]!.writeln(line);
    }

    return sections.map((key, value) => MapEntry(key, value.toString().trim()));
  }

  String? _firstLine(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return raw.split('\n').first.trim();
  }

  _CpuInfo _parseCpu(String? raw) {
    final lines =
        raw == null || raw.trim().isEmpty
            ? const <String>[]
            : raw
                .split('\n')
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty)
                .toList();

    int cores = 1;
    double load1 = 0;
    double load5 = 0;
    double load15 = 0;

    if (lines.isNotEmpty) {
      final parsedCores = int.tryParse(lines.first);
      if (parsedCores != null && parsedCores > 0) {
        cores = parsedCores;
      }
    }

    if (lines.length >= 2) {
      final parts = lines[1].split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        load1 = double.tryParse(parts[0]) ?? 0;
        load5 = double.tryParse(parts[1]) ?? 0;
        load15 = double.tryParse(parts[2]) ?? 0;
      }
    }

    final loadPercent = math.min(
      100.0,
      math.max(0.0, (load1 / math.max(1, cores)) * 100),
    );
    return _CpuInfo(
      cores: cores,
      load1: load1,
      load5: load5,
      load15: load15,
      loadPercent: loadPercent,
    );
  }

  _MemoryInfo _parseMemory(String? raw) {
    int totalMb = 0;
    int usedMb = 0;

    if (raw != null && raw.trim().isNotEmpty) {
      for (final line in raw.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('Mem:')) {
          continue;
        }
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          totalMb = int.tryParse(parts[1]) ?? 0;
          usedMb = int.tryParse(parts[2]) ?? 0;
        }
      }
    }

    final usagePercent =
        totalMb == 0
            ? 0.0
            : math.min(100.0, math.max(0.0, (usedMb / totalMb) * 100));
    return _MemoryInfo(
      totalMb: totalMb,
      usedMb: usedMb,
      usagePercent: usagePercent,
    );
  }

  _DiskInfo _parseDisk(String? raw) {
    int totalKb = 0;
    int usedKb = 0;
    double usagePercent = 0;

    if (raw != null && raw.trim().isNotEmpty) {
      final lines =
          raw
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();

      if (lines.length >= 2) {
        final parts = lines[1].split(RegExp(r'\s+'));
        if (parts.length >= 5) {
          totalKb = int.tryParse(parts[1]) ?? 0;
          usedKb = int.tryParse(parts[2]) ?? 0;
          usagePercent =
              double.tryParse(parts[4].replaceAll('%', '')) ??
              (totalKb == 0 ? 0 : (usedKb / totalKb) * 100);
        }
      }
    }

    return _DiskInfo(
      totalGb: (totalKb / 1024 / 1024).round(),
      usedGb: (usedKb / 1024 / 1024).round(),
      usagePercent: math.min(100, math.max(0, usagePercent)),
    );
  }

  List<VpsContainerInfo> _parseContainers(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) {
          final parts = line.split('|');
          return VpsContainerInfo(
            name: parts.isNotEmpty ? parts[0] : 'container',
            image: parts.length > 1 ? parts[1] : 'unknown',
            status: parts.length > 2 ? parts[2] : 'unknown',
            ports: parts.length > 3 ? parts[3] : '',
          );
        })
        .toList(growable: false);
  }

  List<VpsServiceInfo> _parseServices(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    final services = <VpsServiceInfo>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 5) {
        continue;
      }
      services.add(
        VpsServiceInfo(
          name: parts[0],
          loadState: parts[1],
          activeState: parts[2],
          subState: parts[3],
          description: parts.sublist(4).join(' '),
        ),
      );
    }
    return services;
  }

  List<VpsProcessInfo> _parseProcesses(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    final processes = <VpsProcessInfo>[];
    final lines =
        raw
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();

    for (final line in lines.skip(1)) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 4) {
        continue;
      }
      processes.add(
        VpsProcessInfo(
          pid: int.tryParse(parts[0]) ?? 0,
          command: parts[1],
          cpuPercent: double.tryParse(parts[2]) ?? 0,
          memoryPercent: double.tryParse(parts[3]) ?? 0,
        ),
      );
    }

    return processes;
  }

  String _composeCommandOutput(SSHRunResult result) {
    final stdout = utf8.decode(result.stdout).trimRight();
    final stderr = utf8.decode(result.stderr).trimRight();
    final buffer = StringBuffer();

    if (stdout.isNotEmpty) {
      buffer.writeln(stdout);
    }
    if (stderr.isNotEmpty) {
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.writeln(stderr);
    }
    if (buffer.isEmpty) {
      buffer.write('(no output)');
    }
    buffer.write('\n\nexit code: ${result.exitCode ?? 'unknown'}');

    final text = buffer.toString().trim();
    if (text.length <= 12000) {
      return text;
    }
    return '${text.substring(0, 12000)}\n\n... output truncated ...';
  }
}

class _CpuInfo {
  final int cores;
  final double load1;
  final double load5;
  final double load15;
  final double loadPercent;

  const _CpuInfo({
    required this.cores,
    required this.load1,
    required this.load5,
    required this.load15,
    required this.loadPercent,
  });
}

class _MemoryInfo {
  final int totalMb;
  final int usedMb;
  final double usagePercent;

  const _MemoryInfo({
    required this.totalMb,
    required this.usedMb,
    required this.usagePercent,
  });
}

class _DiskInfo {
  final int totalGb;
  final int usedGb;
  final double usagePercent;

  const _DiskInfo({
    required this.totalGb,
    required this.usedGb,
    required this.usagePercent,
  });
}

const String _sectionPrefix = '__slash_section__ ';

const String _snapshotScript = '''
set +e
printf '__slash_section__ HOSTNAME\n'
(hostname 2>/dev/null || uname -n 2>/dev/null || printf unknown)
printf '\n__slash_section__ OS\n'
(uname -srmo 2>/dev/null || uname -a 2>/dev/null || printf Linux)
printf '\n__slash_section__ UPTIME\n'
(uptime 2>/dev/null || cat /proc/uptime 2>/dev/null || printf unavailable)
printf '\n__slash_section__ CPU\n'
(nproc 2>/dev/null || printf 1)
(printf '\n')
(cat /proc/loadavg 2>/dev/null || printf '0.00 0.00 0.00')
printf '\n__slash_section__ MEMORY\n'
(free -m 2>/dev/null || printf 'Mem: 0 0 0 0 0 0')
printf '\n__slash_section__ DISK\n'
(df -Pk / 2>/dev/null || df -Pk . 2>/dev/null || printf 'filesystem 0 0 0 0%% /')
printf '\n__slash_section__ DOCKER_CHECK\n'
(command -v docker >/dev/null 2>&1 && printf yes || printf no)
printf '\n__slash_section__ DOCKER\n'
(docker ps --format "{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}" 2>/dev/null || true)
printf '\n__slash_section__ SYSTEMD_CHECK\n'
(command -v systemctl >/dev/null 2>&1 && printf yes || printf no)
printf '\n__slash_section__ SERVICES\n'
(systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null || true)
printf '\n__slash_section__ PROCESSES\n'
(ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n 9 || true)
''';

String _shellQuote(String value) {
  return "'${value.replaceAll("'", r"'\''")}'";
}
