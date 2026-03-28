import 'package:flutter/foundation.dart';

enum VpsAuthMode { password, privateKey }

extension VpsAuthModeX on VpsAuthMode {
  String get storageValue =>
      this == VpsAuthMode.privateKey ? 'key' : 'password';

  String get label => this == VpsAuthMode.privateKey ? 'SSH Key' : 'Password';

  static VpsAuthMode fromStorage(String? raw) {
    return raw == 'key' ? VpsAuthMode.privateKey : VpsAuthMode.password;
  }
}

@immutable
class VpsConnectionProfile {
  final String host;
  final int port;
  final String username;
  final VpsAuthMode authMode;
  final String password;
  final String privateKey;
  final String passphrase;

  const VpsConnectionProfile({
    this.host = '',
    this.port = 22,
    this.username = '',
    this.authMode = VpsAuthMode.password,
    this.password = '',
    this.privateKey = '',
    this.passphrase = '',
  });

  bool get hasPassword => password.trim().isNotEmpty;

  bool get hasPrivateKey => privateKey.trim().isNotEmpty;

  bool get canConnect {
    if (host.trim().isEmpty || username.trim().isEmpty) {
      return false;
    }
    return authMode == VpsAuthMode.password ? hasPassword : hasPrivateKey;
  }

  String get endpointLabel {
    final safeUser = username.trim().isEmpty ? 'ssh' : username.trim();
    final safeHost = host.trim().isEmpty ? 'your-server' : host.trim();
    return '$safeUser@$safeHost:$port';
  }

  VpsConnectionProfile normalized() {
    return copyWith(
      host: host.trim(),
      username: username.trim(),
      password: password.trim(),
      privateKey: privateKey.trim(),
      passphrase: passphrase.trim(),
      port: port <= 0 ? 22 : port,
    );
  }

  VpsConnectionProfile copyWith({
    String? host,
    int? port,
    String? username,
    VpsAuthMode? authMode,
    String? password,
    String? privateKey,
    String? passphrase,
  }) {
    return VpsConnectionProfile(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMode: authMode ?? this.authMode,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      passphrase: passphrase ?? this.passphrase,
    );
  }
}

@immutable
class OpsMetricPoint {
  final DateTime timestamp;
  final double value;

  const OpsMetricPoint({required this.timestamp, required this.value});
}

@immutable
class VpsContainerInfo {
  final String name;
  final String image;
  final String status;
  final String ports;

  const VpsContainerInfo({
    required this.name,
    required this.image,
    required this.status,
    required this.ports,
  });

  bool get isHealthy {
    final lower = status.toLowerCase();
    return lower.startsWith('up') && !lower.contains('unhealthy');
  }
}

@immutable
class VpsServiceInfo {
  final String name;
  final String loadState;
  final String activeState;
  final String subState;
  final String description;

  const VpsServiceInfo({
    required this.name,
    required this.loadState,
    required this.activeState,
    required this.subState,
    required this.description,
  });

  bool get isHealthy => activeState == 'active' && subState == 'running';
}

@immutable
class VpsProcessInfo {
  final int pid;
  final String command;
  final double cpuPercent;
  final double memoryPercent;

  const VpsProcessInfo({
    required this.pid,
    required this.command,
    required this.cpuPercent,
    required this.memoryPercent,
  });
}

@immutable
class VpsSnapshot {
  final DateTime collectedAt;
  final String host;
  final String username;
  final String hostname;
  final String osSummary;
  final String uptime;
  final double cpuLoadPercent;
  final double memoryUsagePercent;
  final double diskUsagePercent;
  final double loadAverage1;
  final double loadAverage5;
  final double loadAverage15;
  final int cpuCores;
  final int memoryUsedMb;
  final int memoryTotalMb;
  final int diskUsedGb;
  final int diskTotalGb;
  final bool dockerAvailable;
  final bool systemdAvailable;
  final List<VpsContainerInfo> containers;
  final List<VpsServiceInfo> services;
  final List<VpsProcessInfo> topProcesses;

  const VpsSnapshot({
    required this.collectedAt,
    required this.host,
    required this.username,
    required this.hostname,
    required this.osSummary,
    required this.uptime,
    required this.cpuLoadPercent,
    required this.memoryUsagePercent,
    required this.diskUsagePercent,
    required this.loadAverage1,
    required this.loadAverage5,
    required this.loadAverage15,
    required this.cpuCores,
    required this.memoryUsedMb,
    required this.memoryTotalMb,
    required this.diskUsedGb,
    required this.diskTotalGb,
    required this.dockerAvailable,
    required this.systemdAvailable,
    required this.containers,
    required this.services,
    required this.topProcesses,
  });

  int get runningContainers => containers.length;

  int get runningServices => services.length;

  String get endpointLabel => '$username@$host';
}

@immutable
class OpsCommandLogEntry {
  final String command;
  final String output;
  final int? exitCode;
  final bool isError;
  final DateTime ranAt;

  const OpsCommandLogEntry({
    required this.command,
    required this.output,
    required this.exitCode,
    required this.isError,
    required this.ranAt,
  });
}

const Object _opsUnset = Object();

@immutable
class OpsDashboardState {
  final bool isHydrating;
  final bool isConnecting;
  final bool isRefreshing;
  final bool isSavingProfile;
  final bool isRunningCommand;
  final bool isConnected;
  final bool autoRefresh;
  final String? error;
  final VpsConnectionProfile profile;
  final VpsSnapshot? snapshot;
  final List<OpsMetricPoint> cpuHistory;
  final List<OpsMetricPoint> memoryHistory;
  final List<OpsMetricPoint> diskHistory;
  final List<OpsMetricPoint> containerHistory;
  final List<OpsCommandLogEntry> terminalHistory;

  const OpsDashboardState({
    this.isHydrating = true,
    this.isConnecting = false,
    this.isRefreshing = false,
    this.isSavingProfile = false,
    this.isRunningCommand = false,
    this.isConnected = false,
    this.autoRefresh = true,
    this.error,
    this.profile = const VpsConnectionProfile(),
    this.snapshot,
    this.cpuHistory = const [],
    this.memoryHistory = const [],
    this.diskHistory = const [],
    this.containerHistory = const [],
    this.terminalHistory = const [],
  });

  bool get hasMetrics => snapshot != null;

  OpsDashboardState copyWith({
    bool? isHydrating,
    bool? isConnecting,
    bool? isRefreshing,
    bool? isSavingProfile,
    bool? isRunningCommand,
    bool? isConnected,
    bool? autoRefresh,
    Object? error = _opsUnset,
    VpsConnectionProfile? profile,
    Object? snapshot = _opsUnset,
    List<OpsMetricPoint>? cpuHistory,
    List<OpsMetricPoint>? memoryHistory,
    List<OpsMetricPoint>? diskHistory,
    List<OpsMetricPoint>? containerHistory,
    List<OpsCommandLogEntry>? terminalHistory,
  }) {
    return OpsDashboardState(
      isHydrating: isHydrating ?? this.isHydrating,
      isConnecting: isConnecting ?? this.isConnecting,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isSavingProfile: isSavingProfile ?? this.isSavingProfile,
      isRunningCommand: isRunningCommand ?? this.isRunningCommand,
      isConnected: isConnected ?? this.isConnected,
      autoRefresh: autoRefresh ?? this.autoRefresh,
      error: identical(error, _opsUnset) ? this.error : error as String?,
      profile: profile ?? this.profile,
      snapshot:
          identical(snapshot, _opsUnset)
              ? this.snapshot
              : snapshot as VpsSnapshot?,
      cpuHistory: cpuHistory ?? this.cpuHistory,
      memoryHistory: memoryHistory ?? this.memoryHistory,
      diskHistory: diskHistory ?? this.diskHistory,
      containerHistory: containerHistory ?? this.containerHistory,
      terminalHistory: terminalHistory ?? this.terminalHistory,
    );
  }
}
