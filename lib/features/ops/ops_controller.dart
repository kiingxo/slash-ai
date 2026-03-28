import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/secure_storage_service.dart';
import 'ops_models.dart';
import 'ops_service.dart';

class OpsController extends StateNotifier<OpsDashboardState> {
  OpsController(this._storage, this._service)
    : super(const OpsDashboardState()) {
    _loadProfile();
  }

  final SecureStorageService _storage;
  final VpsOpsService _service;
  Timer? _refreshTimer;

  static const _historyLimit = 24;
  static const _commandHistoryLimit = 12;

  Future<void> _loadProfile() async {
    state = state.copyWith(isHydrating: true, error: null);

    final portValue = await _storage.readString(StoredKeys.vpsPort);
    final profile =
        VpsConnectionProfile(
          host: await _storage.readString(StoredKeys.vpsHost) ?? '',
          port: int.tryParse(portValue ?? '') ?? 22,
          username: await _storage.readString(StoredKeys.vpsUsername) ?? '',
          authMode: VpsAuthModeX.fromStorage(
            await _storage.readString(StoredKeys.vpsAuthMode),
          ),
          password: await _storage.readString(StoredKeys.vpsPassword) ?? '',
          privateKey: await _storage.readString(StoredKeys.vpsPrivateKey) ?? '',
          passphrase: await _storage.readString(StoredKeys.vpsPassphrase) ?? '',
        ).normalized();

    final autoRefresh =
        (await _storage.readString(StoredKeys.vpsAutoRefresh)) != 'false';

    state = state.copyWith(
      isHydrating: false,
      autoRefresh: autoRefresh,
      profile: profile,
    );
  }

  Future<void> saveProfile(VpsConnectionProfile profile) async {
    final normalized = profile.normalized();
    state = state.copyWith(
      isSavingProfile: true,
      error: null,
      profile: normalized,
    );

    try {
      await _persistProfile(normalized);
      state = state.copyWith(isSavingProfile: false, profile: normalized);
    } catch (error) {
      state = state.copyWith(
        isSavingProfile: false,
        error: _friendlyError(error),
      );
    }
  }

  Future<void> clearSavedProfile() async {
    await disconnect();
    await _storage.deleteApiKey(StoredKeys.vpsHost);
    await _storage.deleteApiKey(StoredKeys.vpsPort);
    await _storage.deleteApiKey(StoredKeys.vpsUsername);
    await _storage.deleteApiKey(StoredKeys.vpsAuthMode);
    await _storage.deleteApiKey(StoredKeys.vpsPassword);
    await _storage.deleteApiKey(StoredKeys.vpsPrivateKey);
    await _storage.deleteApiKey(StoredKeys.vpsPassphrase);
    await _storage.deleteApiKey(StoredKeys.vpsAutoRefresh);

    state = state.copyWith(
      autoRefresh: true,
      profile: const VpsConnectionProfile(),
      snapshot: null,
      cpuHistory: const [],
      memoryHistory: const [],
      diskHistory: const [],
      containerHistory: const [],
      terminalHistory: const [],
      error: null,
    );
  }

  Future<void> connect([VpsConnectionProfile? draftProfile]) async {
    final profile = (draftProfile ?? state.profile).normalized();
    if (!profile.canConnect) {
      state = state.copyWith(
        error:
            'Add a host, username, and an SSH password or private key first.',
      );
      return;
    }

    state = state.copyWith(isConnecting: true, error: null, profile: profile);

    try {
      await _service.connect(profile);
      await _persistProfile(profile);
      state = state.copyWith(
        isConnecting: false,
        isConnected: true,
        profile: profile,
      );
      _syncRefreshTimer();
      await refreshDashboard(silent: false);
    } catch (error) {
      state = state.copyWith(
        isConnecting: false,
        isConnected: false,
        error: _friendlyError(error),
      );
    }
  }

  Future<void> disconnect() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _service.disconnect();
    state = state.copyWith(isConnected: false, isRefreshing: false);
  }

  Future<void> refreshDashboard({bool silent = false}) async {
    if (state.isConnecting || state.isRunningCommand) {
      return;
    }

    final profile = state.profile.normalized();
    if (!profile.canConnect) {
      state = state.copyWith(
        error: 'Set up your SSH connection details to load VPS telemetry.',
      );
      return;
    }

    state = state.copyWith(
      isRefreshing: !silent,
      error: null,
      profile: profile,
    );

    try {
      final snapshot = await _service.fetchSnapshot(profile);
      final timestamp = snapshot.collectedAt;

      state = state.copyWith(
        isRefreshing: false,
        isConnected: true,
        snapshot: snapshot,
        cpuHistory: _appendMetric(
          state.cpuHistory,
          OpsMetricPoint(timestamp: timestamp, value: snapshot.cpuLoadPercent),
        ),
        memoryHistory: _appendMetric(
          state.memoryHistory,
          OpsMetricPoint(
            timestamp: timestamp,
            value: snapshot.memoryUsagePercent,
          ),
        ),
        diskHistory: _appendMetric(
          state.diskHistory,
          OpsMetricPoint(
            timestamp: timestamp,
            value: snapshot.diskUsagePercent,
          ),
        ),
        containerHistory: _appendMetric(
          state.containerHistory,
          OpsMetricPoint(
            timestamp: timestamp,
            value: snapshot.runningContainers.toDouble(),
          ),
        ),
      );
      _syncRefreshTimer();
    } catch (error) {
      await _service.disconnect();
      state = state.copyWith(
        isRefreshing: false,
        isConnected: false,
        error: _friendlyError(error),
      );
    }
  }

  Future<void> runCommand(
    String command, {
    VpsConnectionProfile? draftProfile,
  }) async {
    final trimmedCommand = command.trim();
    if (trimmedCommand.isEmpty ||
        state.isConnecting ||
        state.isRunningCommand) {
      return;
    }

    final profile = (draftProfile ?? state.profile).normalized();
    if (!profile.canConnect) {
      state = state.copyWith(
        error:
            'Set up your SSH connection details before opening the terminal.',
      );
      return;
    }

    state = state.copyWith(
      isRunningCommand: true,
      error: null,
      profile: profile,
    );

    try {
      final entry = await _service.runCommand(
        profile: profile,
        command: trimmedCommand,
      );

      state = state.copyWith(
        isRunningCommand: false,
        isConnected: true,
        terminalHistory: <OpsCommandLogEntry>[
          entry,
          ...state.terminalHistory,
        ].take(_commandHistoryLimit).toList(growable: false),
      );
      _syncRefreshTimer();
    } catch (error) {
      final message = _friendlyError(error);
      state = state.copyWith(
        isRunningCommand: false,
        isConnected: false,
        error: message,
        terminalHistory: <OpsCommandLogEntry>[
          OpsCommandLogEntry(
            command: trimmedCommand,
            output: message,
            exitCode: null,
            isError: true,
            ranAt: DateTime.now(),
          ),
          ...state.terminalHistory,
        ].take(_commandHistoryLimit).toList(growable: false),
      );
    }
  }

  Future<OpsCommandLogEntry> fetchContainerLogs(
    String containerName, {
    int tailLines = 200,
  }) {
    return _runTransientCommand(
      invalidProfileMessage:
          'Set up your SSH connection details before loading container logs.',
      operation:
          (profile) => _service.fetchContainerLogs(
            profile: profile,
            containerName: containerName,
            tailLines: tailLines,
          ),
    );
  }

  Future<OpsCommandLogEntry> fetchServiceLogs(
    String serviceName, {
    int tailLines = 200,
  }) {
    return _runTransientCommand(
      invalidProfileMessage:
          'Set up your SSH connection details before loading service logs.',
      operation:
          (profile) => _service.fetchServiceLogs(
            profile: profile,
            serviceName: serviceName,
            tailLines: tailLines,
          ),
    );
  }

  Future<void> setAutoRefresh(bool enabled) async {
    state = state.copyWith(autoRefresh: enabled);
    await _storage.saveString(StoredKeys.vpsAutoRefresh, enabled.toString());
    _syncRefreshTimer();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<void> _persistProfile(VpsConnectionProfile profile) async {
    await _storage.saveString(StoredKeys.vpsHost, profile.host);
    await _storage.saveString(StoredKeys.vpsPort, profile.port.toString());
    await _storage.saveString(StoredKeys.vpsUsername, profile.username);
    await _storage.saveString(
      StoredKeys.vpsAuthMode,
      profile.authMode.storageValue,
    );
    await _storage.saveString(StoredKeys.vpsPassword, profile.password);
    await _storage.saveString(StoredKeys.vpsPrivateKey, profile.privateKey);
    await _storage.saveString(StoredKeys.vpsPassphrase, profile.passphrase);
  }

  void _syncRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    if (!state.autoRefresh || !state.isConnected) {
      return;
    }

    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (state.isConnecting || state.isRefreshing || state.isRunningCommand) {
        return;
      }
      unawaited(refreshDashboard(silent: true));
    });
  }

  List<OpsMetricPoint> _appendMetric(
    List<OpsMetricPoint> history,
    OpsMetricPoint point,
  ) {
    return <OpsMetricPoint>[...history, point]
        .skip(math.max(0, history.length + 1 - _historyLimit))
        .toList(growable: false);
  }

  Future<OpsCommandLogEntry> _runTransientCommand({
    required String invalidProfileMessage,
    required Future<OpsCommandLogEntry> Function(VpsConnectionProfile profile)
    operation,
  }) async {
    if (state.isConnecting || state.isRefreshing || state.isRunningCommand) {
      throw Exception('Wait for the current Ops action to finish first.');
    }

    final profile = state.profile.normalized();
    if (!profile.canConnect) {
      state = state.copyWith(error: invalidProfileMessage);
      throw Exception(invalidProfileMessage);
    }

    state = state.copyWith(
      isRunningCommand: true,
      error: null,
      profile: profile,
    );

    try {
      final entry = await operation(profile);
      state = state.copyWith(
        isRunningCommand: false,
        isConnected: true,
        profile: profile,
      );
      _syncRefreshTimer();
      return entry;
    } catch (error) {
      final message = _friendlyError(error);
      state = state.copyWith(
        isRunningCommand: false,
        isConnected: false,
        error: message,
      );
      throw Exception(message);
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final lower = raw.toLowerCase();

    if (lower.contains('socketexception') ||
        lower.contains('sshsocketerror') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable')) {
      return 'Unable to reach that VPS. Check the host, port, and network path.';
    }

    if (lower.contains('auth fail') ||
        lower.contains('permission denied') ||
        lower.contains('authentication failed')) {
      return 'SSH authentication failed. Double-check the username and secret.';
    }

    if (lower.contains('private key is encrypted') ||
        lower.contains('invalid passphrase')) {
      return 'That SSH key needs a valid passphrase before it can connect.';
    }

    if (lower.contains('unsupported key type')) {
      return 'That SSH private key format is not supported by this app yet.';
    }

    return raw.isEmpty ? 'Something went wrong while talking to the VPS.' : raw;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    unawaited(_service.disconnect());
    super.dispose();
  }
}

final opsControllerProvider =
    StateNotifierProvider<OpsController, OpsDashboardState>((ref) {
      return OpsController(SecureStorageService(), VpsOpsService());
    });
