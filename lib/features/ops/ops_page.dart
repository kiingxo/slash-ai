import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/components/slash_text.dart';
import 'ops_controller.dart';
import 'ops_models.dart';

class OpsPage extends ConsumerStatefulWidget {
  const OpsPage({super.key});

  @override
  ConsumerState<OpsPage> createState() => _OpsPageState();
}

class _OpsPageState extends ConsumerState<OpsPage> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _commandController = TextEditingController();

  bool _seededProfile = false;
  VpsAuthMode _authMode = VpsAuthMode.password;

  static const _presets = <_CommandPreset>[
    _CommandPreset(
      label: 'Docker ps',
      command:
          'docker ps --format "table {{.Names}}\\t{{.Image}}\\t{{.Status}}"',
    ),
    _CommandPreset(
      label: 'Failed units',
      command: 'systemctl --failed --no-pager',
    ),
    _CommandPreset(
      label: 'CPU hot list',
      command: 'ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 12',
    ),
    _CommandPreset(label: 'Disk usage', command: 'df -h'),
    _CommandPreset(
      label: 'Recent auth logs',
      command:
          'journalctl -u sshd -n 60 --no-pager || journalctl -u ssh -n 60 --no-pager',
    ),
  ];

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  void _seedFromState(OpsDashboardState state) {
    if (_seededProfile || state.isHydrating) {
      return;
    }
    final profile = state.profile;
    _hostController.text = profile.host;
    _portController.text = profile.port.toString();
    _usernameController.text = profile.username;
    _passwordController.text = profile.password;
    _privateKeyController.text = profile.privateKey;
    _passphraseController.text = profile.passphrase;
    _authMode = profile.authMode;
    _seededProfile = true;
  }

  VpsConnectionProfile _draftProfile() {
    return VpsConnectionProfile(
      host: _hostController.text,
      port: int.tryParse(_portController.text.trim()) ?? 22,
      username: _usernameController.text,
      authMode: _authMode,
      password: _passwordController.text,
      privateKey: _privateKeyController.text,
      passphrase: _passphraseController.text,
    ).normalized();
  }

  Future<void> _refresh(OpsDashboardState state) async {
    final controller = ref.read(opsControllerProvider.notifier);
    if (state.isConnected) {
      await controller.refreshDashboard();
      return;
    }
    await controller.connect(_draftProfile());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(opsControllerProvider);
    _seedFromState(state);

    final theme = Theme.of(context);
    final snapshot = state.snapshot;
    final controller = ref.read(opsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SlashText('Ops', fontWeight: FontWeight.w700),
            SlashText(
              'SSH dashboard, containers, services, and terminal',
              fontSize: 12,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: state.isConnected ? 'Refresh VPS telemetry' : 'Connect',
            onPressed:
                state.isHydrating || state.isConnecting || state.isRefreshing
                    ? null
                    : () => _refresh(state),
            icon:
                state.isRefreshing || state.isConnecting
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                    : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body:
          state.isHydrating
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: () => _refresh(state),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pairWidth =
                        constraints.maxWidth >= 980
                            ? (constraints.maxWidth - 14) / 2
                            : constraints.maxWidth;

                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                      children: [
                        _HeroPanel(
                          state: state,
                          snapshot: snapshot,
                          onConnect: () => controller.connect(_draftProfile()),
                          onDisconnect:
                              state.isConnected ? controller.disconnect : null,
                        ),
                        const SizedBox(height: 16),
                        if (state.error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _ErrorBanner(
                              message: state.error!,
                              onDismiss: controller.clearError,
                            ),
                          ),
                        _Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionHeading(
                                icon: Icons.dns_rounded,
                                title: 'SSH Connection',
                                subtitle:
                                    'Securely store your VPS details on this device, then connect or reconnect whenever you need the war-room.',
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  SizedBox(
                                    width:
                                        pairWidth == constraints.maxWidth
                                            ? pairWidth
                                            : pairWidth - 6,
                                    child: _Field(
                                      label: 'Host',
                                      hint: '203.0.113.10 or box.example.com',
                                      controller: _hostController,
                                      prefixIcon: Icons.public,
                                    ),
                                  ),
                                  SizedBox(
                                    width:
                                        pairWidth == constraints.maxWidth
                                            ? pairWidth
                                            : pairWidth - 6,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: _Field(
                                            label: 'Port',
                                            hint: '22',
                                            controller: _portController,
                                            keyboardType: TextInputType.number,
                                            prefixIcon: Icons.settings_ethernet,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 5,
                                          child: _Field(
                                            label: 'Username',
                                            hint: 'root or deploy',
                                            controller: _usernameController,
                                            prefixIcon: Icons.person_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: VpsAuthMode.values
                                    .map((mode) {
                                      final selected = _authMode == mode;
                                      return ChoiceChip(
                                        selected: selected,
                                        label: Text(mode.label),
                                        onSelected: (_) {
                                          setState(() {
                                            _authMode = mode;
                                          });
                                        },
                                      );
                                    })
                                    .toList(growable: false),
                              ),
                              const SizedBox(height: 16),
                              if (_authMode == VpsAuthMode.password)
                                _Field(
                                  label: 'Password',
                                  hint: 'SSH password',
                                  controller: _passwordController,
                                  obscureText: true,
                                  prefixIcon: Icons.password_rounded,
                                )
                              else
                                Column(
                                  children: [
                                    _Field(
                                      label: 'Private Key',
                                      hint:
                                          'Paste your OpenSSH or PEM private key here',
                                      controller: _privateKeyController,
                                      minLines: 7,
                                      maxLines: 10,
                                      prefixIcon: Icons.vpn_key_outlined,
                                    ),
                                    const SizedBox(height: 12),
                                    _Field(
                                      label: 'Passphrase',
                                      hint: 'Only if the key is encrypted',
                                      controller: _passphraseController,
                                      obscureText: true,
                                      prefixIcon: Icons.lock_outline,
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.42),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: theme.colorScheme.outline.withValues(
                                      alpha: 0.16,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.shield_outlined,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SlashText(
                                            'Stored in secure storage',
                                            fontWeight: FontWeight.w700,
                                          ),
                                          const SizedBox(height: 4),
                                          SlashText(
                                            'Secrets stay on this device. Auto-refresh polls every 20 seconds while the tunnel is connected.',
                                            fontSize: 12,
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.72),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Auto refresh dashboard'),
                                subtitle: const Text(
                                  'Builds CPU, memory, disk, and container trend graphs while connected.',
                                ),
                                value: state.autoRefresh,
                                onChanged: controller.setAutoRefresh,
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    onPressed:
                                        state.isConnecting || state.isRefreshing
                                            ? null
                                            : () => controller.connect(
                                              _draftProfile(),
                                            ),
                                    icon: Icon(
                                      state.isConnected
                                          ? Icons.sync_rounded
                                          : Icons.play_arrow_rounded,
                                    ),
                                    label: Text(
                                      state.isConnected
                                          ? 'Reconnect'
                                          : 'Connect',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed:
                                        state.isSavingProfile
                                            ? null
                                            : () => controller.saveProfile(
                                              _draftProfile(),
                                            ),
                                    icon:
                                        state.isSavingProfile
                                            ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                            : const Icon(Icons.save_outlined),
                                    label: const Text('Save profile'),
                                  ),
                                  if (state.isConnected)
                                    OutlinedButton.icon(
                                      onPressed: controller.disconnect,
                                      icon: const Icon(Icons.link_off_rounded),
                                      label: const Text('Disconnect'),
                                    ),
                                  TextButton.icon(
                                    onPressed: controller.clearSavedProfile,
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                    label: const Text('Clear saved'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (snapshot != null) ...[
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              SizedBox(
                                width: pairWidth,
                                child: _TrendCard(
                                  title: 'CPU Pressure',
                                  subtitle:
                                      'Load ${snapshot.loadAverage1.toStringAsFixed(2)} / ${snapshot.loadAverage5.toStringAsFixed(2)} / ${snapshot.loadAverage15.toStringAsFixed(2)}',
                                  valueLabel:
                                      '${snapshot.cpuLoadPercent.toStringAsFixed(0)}%',
                                  trend: state.cpuHistory,
                                  color: const Color(0xFFFB7185),
                                  maxY: 100,
                                  footer:
                                      '${snapshot.cpuCores} cores online on ${snapshot.hostname}',
                                ),
                              ),
                              SizedBox(
                                width: pairWidth,
                                child: _TrendCard(
                                  title: 'Memory Burn',
                                  subtitle:
                                      '${snapshot.memoryUsedMb} / ${snapshot.memoryTotalMb} MB',
                                  valueLabel:
                                      '${snapshot.memoryUsagePercent.toStringAsFixed(0)}%',
                                  trend: state.memoryHistory,
                                  color: const Color(0xFF22C55E),
                                  maxY: 100,
                                  footer:
                                      'Live RAM pressure over the last polls',
                                ),
                              ),
                              SizedBox(
                                width: pairWidth,
                                child: _TrendCard(
                                  title: 'Disk Headroom',
                                  subtitle:
                                      '${snapshot.diskUsedGb} / ${snapshot.diskTotalGb} GB',
                                  valueLabel:
                                      '${snapshot.diskUsagePercent.toStringAsFixed(0)}%',
                                  trend: state.diskHistory,
                                  color: const Color(0xFFF59E0B),
                                  maxY: 100,
                                  footer: 'Root volume saturation',
                                ),
                              ),
                              SizedBox(
                                width: pairWidth,
                                child: _TrendCard(
                                  title: 'Container Count',
                                  subtitle:
                                      snapshot.dockerAvailable
                                          ? 'Docker is live on this host'
                                          : 'Docker not detected on this host',
                                  valueLabel: '${snapshot.runningContainers}',
                                  trend: state.containerHistory,
                                  color: const Color(0xFF60A5FA),
                                  maxY: _containerChartCeiling(
                                    state.containerHistory,
                                  ),
                                  footer:
                                      '${snapshot.runningServices} running services observed',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _MetricsGrid(snapshot: snapshot),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              SizedBox(
                                width: pairWidth,
                                child: _DockerPanel(snapshot: snapshot),
                              ),
                              SizedBox(
                                width: pairWidth,
                                child: _ServicePanel(snapshot: snapshot),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _ProcessPanel(snapshot: snapshot),
                          const SizedBox(height: 16),
                        ] else
                          _Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionHeading(
                                  icon: Icons.monitor_heart_outlined,
                                  title: 'No Live Snapshot Yet',
                                  subtitle:
                                      'Connect to a VPS to start collecting telemetry, trend history, containers, and running services.',
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    gradient: LinearGradient(
                                      colors: [
                                        theme.colorScheme.primary.withValues(
                                          alpha: 0.10,
                                        ),
                                        const Color(
                                          0xFFF97316,
                                        ).withValues(alpha: 0.08),
                                      ],
                                    ),
                                  ),
                                  child: const SlashText(
                                    'Once the SSH session lands, this page turns into a live ops wall with health cards, trend graphs, running containers, systemd services, and an inspect-anything terminal.',
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        _TerminalPanel(
                          state: state,
                          commandController: _commandController,
                          onRun: () {
                            controller.runCommand(
                              _commandController.text,
                              draftProfile: _draftProfile(),
                            );
                          },
                          onPresetSelected: (command) {
                            _commandController.text = command;
                            controller.runCommand(
                              command,
                              draftProfile: _draftProfile(),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
    );
  }

  double _containerChartCeiling(List<OpsMetricPoint> trend) {
    if (trend.isEmpty) {
      return 5;
    }
    final peak = trend.map((point) => point.value).reduce(math.max);
    return math.max(5, peak + 1);
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.state,
    required this.snapshot,
    required this.onConnect,
    required this.onDisconnect,
  });

  final OpsDashboardState state;
  final VpsSnapshot? snapshot;
  final VoidCallback onConnect;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final accent =
        state.isConnected ? const Color(0xFF34D399) : const Color(0xFFF97316);
    final target = snapshot?.endpointLabel ?? state.profile.endpointLabel;
    final secondary =
        snapshot == null
            ? 'Ready to dial into your VPS'
            : '${snapshot!.osSummary} • ${snapshot!.uptime}';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F172A),
            const Color(0xFF111827),
            accent.withValues(alpha: 0.24),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.terminal_rounded, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SlashText(
                        'VPS War Room',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 6),
                      SlashText(
                        target,
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                      const SizedBox(height: 4),
                      SlashText(
                        secondary,
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.64),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(
                  label: state.isConnected ? 'LIVE' : 'OFFLINE',
                  color: accent,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _HeroStat(
                  label: 'Host',
                  value:
                      snapshot?.hostname ??
                      state.profile.host.ifBlank('Not set'),
                ),
                _HeroStat(
                  label: 'Containers',
                  value:
                      snapshot == null
                          ? '--'
                          : '${snapshot!.runningContainers}',
                ),
                _HeroStat(
                  label: 'Services',
                  value:
                      snapshot == null ? '--' : '${snapshot!.runningServices}',
                ),
                _HeroStat(
                  label: 'Last sync',
                  value:
                      snapshot == null
                          ? 'Waiting'
                          : _formatClock(snapshot!.collectedAt),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F172A),
                  ),
                  onPressed: state.isConnecting ? null : onConnect,
                  icon: Icon(
                    state.isConnected
                        ? Icons.sync_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    state.isConnected ? 'Reconnect now' : 'Connect now',
                  ),
                ),
                if (onDisconnect != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.24),
                      ),
                    ),
                    onPressed: onDisconnect,
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Drop session'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.snapshot});

  final VpsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            icon: Icons.speed_rounded,
            title: 'Operational Snapshot',
            subtitle:
                'Current server pressure, storage burn, and service posture from the latest poll.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(
                title: 'CPU',
                value: '${snapshot.cpuLoadPercent.toStringAsFixed(0)}%',
                subtitle:
                    '${snapshot.cpuCores} cores • load1 ${snapshot.loadAverage1.toStringAsFixed(2)}',
                color: const Color(0xFFFB7185),
              ),
              _MetricTile(
                title: 'Memory',
                value: '${snapshot.memoryUsedMb} MB',
                subtitle: '${snapshot.memoryTotalMb} MB total',
                color: const Color(0xFF22C55E),
              ),
              _MetricTile(
                title: 'Disk',
                value: '${snapshot.diskUsedGb} GB',
                subtitle: '${snapshot.diskTotalGb} GB total',
                color: const Color(0xFFF59E0B),
              ),
              _MetricTile(
                title: 'Docker',
                value:
                    snapshot.dockerAvailable
                        ? '${snapshot.runningContainers} running'
                        : 'Not installed',
                subtitle: 'Containers visible from docker ps',
                color: const Color(0xFF60A5FA),
              ),
              _MetricTile(
                title: 'systemd',
                value:
                    snapshot.systemdAvailable
                        ? '${snapshot.runningServices} active'
                        : 'Unavailable',
                subtitle: 'Services from systemctl',
                color: const Color(0xFFA78BFA),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DockerPanel extends StatelessWidget {
  const _DockerPanel({required this.snapshot});

  final VpsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            icon: Icons.inventory_2_rounded,
            title: 'Running Containers',
            subtitle:
                snapshot.dockerAvailable
                    ? 'Live output from docker ps.'
                    : 'Docker was not detected on this host.',
          ),
          const SizedBox(height: 16),
          if (!snapshot.dockerAvailable)
            const _EmptyStateCopy(
              message:
                  'Install Docker or connect to a containerized host to populate this panel.',
            )
          else if (snapshot.containers.isEmpty)
            const _EmptyStateCopy(
              message:
                  'Docker is available, but there are no running containers right now.',
            )
          else
            Column(
              children: snapshot.containers
                  .map(
                    (container) => _InfoRow(
                      color:
                          container.isHealthy
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFF97316),
                      title: container.name,
                      subtitle: '${container.image} • ${container.status}',
                      trailing: container.ports.ifBlank('No exposed ports'),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _ServicePanel extends StatelessWidget {
  const _ServicePanel({required this.snapshot});

  final VpsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final visibleServices = snapshot.services.take(12).toList(growable: false);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            icon: Icons.hub_rounded,
            title: 'Running Services',
            subtitle:
                snapshot.systemdAvailable
                    ? 'systemctl units currently reporting active + running.'
                    : 'systemd was not detected on this host.',
          ),
          const SizedBox(height: 16),
          if (!snapshot.systemdAvailable)
            const _EmptyStateCopy(
              message:
                  'Use a systemd-managed distro to see live service status here.',
            )
          else if (visibleServices.isEmpty)
            const _EmptyStateCopy(
              message: 'No running services were returned from systemctl.',
            )
          else
            Column(
              children: visibleServices
                  .map(
                    (service) => _InfoRow(
                      color:
                          service.isHealthy
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFF97316),
                      title: service.name,
                      subtitle:
                          '${service.description} • ${service.loadState}/${service.activeState}/${service.subState}',
                      trailing: service.activeState.toUpperCase(),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _ProcessPanel extends StatelessWidget {
  const _ProcessPanel({required this.snapshot});

  final VpsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            icon: Icons.memory_rounded,
            title: 'Top Processes',
            subtitle: 'Sorted by CPU usage from the latest process sample.',
          ),
          const SizedBox(height: 16),
          if (snapshot.topProcesses.isEmpty)
            const _EmptyStateCopy(
              message: 'No process telemetry was returned by ps.',
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text('PID', style: theme.textTheme.labelMedium),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        'Command',
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'CPU',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'MEM',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...snapshot.topProcesses.map(
                  (process) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.32),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text('${process.pid}')),
                        Expanded(
                          flex: 4,
                          child: Text(
                            process.command,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${process.cpuPercent.toStringAsFixed(1)}%',
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${process.memoryPercent.toStringAsFixed(1)}%',
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TerminalPanel extends StatelessWidget {
  const _TerminalPanel({
    required this.state,
    required this.commandController,
    required this.onRun,
    required this.onPresetSelected,
  });

  final OpsDashboardState state;
  final TextEditingController commandController;
  final VoidCallback onRun;
  final ValueChanged<String> onPresetSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest =
        state.terminalHistory.isNotEmpty ? state.terminalHistory.first : null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF09090B),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TerminalHeader(),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _OpsPageState._presets
                  .map(
                    (preset) => ActionChip(
                      avatar: const Icon(Icons.flash_on_rounded, size: 16),
                      label: Text(preset.label),
                      onPressed: () => onPresetSelected(preset.command),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: commandController,
              minLines: 2,
              maxLines: 5,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText:
                    'Type any safe SSH command, like docker logs app -n 100',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.36),
                  fontFamily: 'monospace',
                ),
                filled: true,
                fillColor: const Color(0xFF18181B),
                prefixIcon: const Icon(Icons.keyboard_command_key_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFF27272A)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFF27272A)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: state.isRunningCommand ? null : onRun,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.black,
                  ),
                  icon:
                      state.isRunningCommand
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    state.isConnected ? 'Run command' : 'Connect & run',
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  state.isConnected
                      ? 'Session is live'
                      : 'A command run will connect first if the profile is valid',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.64),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (latest == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Command output will appear here once you run something.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontFamily: 'monospace',
                  ),
                ),
              )
            else
              _TerminalOutput(entry: latest),
            if (state.terminalHistory.length > 1) ...[
              const SizedBox(height: 14),
              Text(
                'Recent runs',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              ...state.terminalHistory
                  .skip(1)
                  .take(3)
                  .map(
                    (entry) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            entry.isError
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            color:
                                entry.isError
                                    ? const Color(0xFFFB7185)
                                    : const Color(0xFF34D399),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.command,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_formatClock(entry.ranAt)} • exit ${entry.exitCode ?? 'unknown'}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.54),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TerminalHeader extends StatelessWidget {
  const _TerminalHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TrafficDot(color: const Color(0xFFFB7185)),
        const SizedBox(width: 6),
        _TrafficDot(color: const Color(0xFFF59E0B)),
        const SizedBox(width: 6),
        _TrafficDot(color: const Color(0xFF34D399)),
        const SizedBox(width: 12),
        const Text(
          'ops terminal',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TerminalOutput extends StatelessWidget {
  const _TerminalOutput({required this.entry});

  final OpsCommandLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              entry.isError ? const Color(0xFF7F1D1D) : const Color(0xFF1F2937),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\$ ${entry.command}',
            style: TextStyle(
              color:
                  entry.isError
                      ? const Color(0xFFFDA4AF)
                      : const Color(0xFF86EFAC),
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            entry.output,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    required this.trend,
    required this.color,
    required this.maxY,
    required this.footer,
  });

  final String title;
  final String subtitle;
  final String valueLabel;
  final List<OpsMetricPoint> trend;
  final Color color;
  final double maxY;
  final String footer;

  @override
  Widget build(BuildContext context) {
    final values = trend.map((point) => point.value).toList(growable: false);
    final theme = Theme.of(context);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                valueLabel,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                '${values.length} samples',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 92,
            child: CustomPaint(
              painter: _SparklinePainter(
                values: values,
                color: color,
                maxY: maxY,
              ),
              child: Container(),
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value:
                values.isEmpty
                    ? 0
                    : (values.last / math.max(1, maxY)).clamp(0.0, 1.0),
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          const SizedBox(height: 10),
          Text(
            footer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.surface,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final Color color;
  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.28,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              trailing,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateCopy extends StatelessWidget {
  const _EmptyStateCopy({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.24,
        ),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.prefixIcon,
    this.obscureText = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData prefixIcon;
  final bool obscureText;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(prefixIcon),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF7F1D1D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded),
              color: const Color(0xFF7F1D1D),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficDot extends StatelessWidget {
  const _TrafficDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.maxY,
  });

  final List<double> values;
  final Color color;
  final double maxY;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint =
        Paint()
          ..color = color.withValues(alpha: 0.08)
          ..strokeWidth = 1;

    for (var i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.isEmpty) {
      return;
    }

    final safeMax = math.max(1, maxY);
    final path = Path();
    final fill = Path();

    for (var i = 0; i < values.length; i++) {
      final dx =
          values.length == 1 ? 0.0 : (size.width * i) / (values.length - 1);
      final normalized = (values[i] / safeMax).clamp(0.0, 1.0);
      final dy = size.height - (normalized * size.height);

      if (i == 0) {
        path.moveTo(dx, dy);
        fill.moveTo(dx, size.height);
        fill.lineTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
        fill.lineTo(dx, dy);
      }
    }

    final lastDx = values.length == 1 ? 0.0 : size.width;
    fill.lineTo(lastDx, size.height);
    fill.close();

    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final lastNormalized = (values.last / safeMax).clamp(0.0, 1.0);
    final lastPoint = Offset(
      lastDx,
      size.height - (lastNormalized * size.height),
    );
    canvas.drawCircle(lastPoint, 4.5, Paint()..color = color);
    canvas.drawCircle(
      lastPoint,
      8.5,
      Paint()..color = color.withValues(alpha: 0.14),
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.maxY != maxY;
  }
}

class _CommandPreset {
  const _CommandPreset({required this.label, required this.command});

  final String label;
  final String command;
}

String _formatClock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  final second = time.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

extension on String {
  String ifBlank(String fallback) {
    return trim().isEmpty ? fallback : this;
  }
}
