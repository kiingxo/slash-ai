import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/components/slash_text.dart';
import 'ops_controller.dart';
import 'ops_models.dart';

const List<OpsCommandPreset> opsCommandPresets = <OpsCommandPreset>[
  OpsCommandPreset(
    label: 'Docker ps',
    command: 'docker ps --format "table {{.Names}}\\t{{.Image}}\\t{{.Status}}"',
  ),
  OpsCommandPreset(
    label: 'Failed units',
    command: 'systemctl --failed --no-pager',
  ),
  OpsCommandPreset(
    label: 'CPU hot list',
    command: 'ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 12',
  ),
  OpsCommandPreset(label: 'Disk usage', command: 'df -h'),
  OpsCommandPreset(
    label: 'Recent auth logs',
    command:
        'journalctl -u sshd -n 60 --no-pager || journalctl -u ssh -n 60 --no-pager',
  ),
];

class OpsCommandPreset {
  final String label;
  final String command;

  const OpsCommandPreset({required this.label, required this.command});
}

enum OpsLogTargetType { container, service }

class OpsConnectionPage extends ConsumerStatefulWidget {
  const OpsConnectionPage({super.key});

  @override
  ConsumerState<OpsConnectionPage> createState() => _OpsConnectionPageState();
}

class _OpsConnectionPageState extends ConsumerState<OpsConnectionPage> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();

  bool _seededProfile = false;
  VpsAuthMode _authMode = VpsAuthMode.password;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
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

  void _clearLocalDraft() {
    _hostController.clear();
    _portController.text = '22';
    _usernameController.clear();
    _passwordController.clear();
    _privateKeyController.clear();
    _passphraseController.clear();
    setState(() {
      _authMode = VpsAuthMode.password;
    });
  }

  Future<void> _saveProfile() async {
    await ref.read(opsControllerProvider.notifier).saveProfile(_draftProfile());
    if (!mounted) {
      return;
    }
    if (ref.read(opsControllerProvider).error == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('VPS profile saved')));
    }
  }

  Future<void> _connect() async {
    await ref.read(opsControllerProvider.notifier).connect(_draftProfile());
  }

  Future<void> _clearSaved() async {
    _clearLocalDraft();
    await ref.read(opsControllerProvider.notifier).clearSavedProfile();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(opsControllerProvider);
    _seedFromState(state);

    final snapshot = state.snapshot;
    final controller = ref.read(opsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Connection', fontWeight: FontWeight.w700),
        actions: [
          IconButton(
            tooltip:
                state.isConnected ? 'Refresh from saved profile' : 'Connect',
            onPressed:
                state.isHydrating || state.isConnecting || state.isRefreshing
                    ? null
                    : _connect,
            icon:
                state.isConnecting || state.isRefreshing
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                    : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body:
          state.isHydrating
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _FeatureHeroCard(
                    icon: Icons.dns_rounded,
                    eyebrow: 'Connection',
                    title:
                        snapshot?.endpointLabel ?? state.profile.endpointLabel,
                    description:
                        snapshot == null
                            ? 'Saved SSH profile'
                            : '${snapshot.osSummary} • ${snapshot.uptime}',
                    accent:
                        state.isConnected
                            ? const Color(0xFF34D399)
                            : const Color(0xFFF97316),
                    chips: [
                      _HeroChip(
                        label: 'Status',
                        value: state.isConnected ? 'Live' : 'Offline',
                      ),
                      _HeroChip(
                        label: 'Host',
                        value:
                            snapshot?.hostname ??
                            state.profile.host.ifBlank('Not set'),
                      ),
                      _HeroChip(
                        label: 'Last sync',
                        value:
                            snapshot == null
                                ? 'Waiting'
                                : formatOpsClock(snapshot.collectedAt),
                      ),
                    ],
                    primaryActionLabel:
                        state.isConnected ? 'Reconnect' : 'Connect',
                    onPrimaryAction:
                        state.isConnecting || state.isRefreshing
                            ? null
                            : _connect,
                    secondaryActionLabel:
                        state.isConnected ? 'Disconnect' : null,
                    onSecondaryAction:
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
                        const _SectionHeading(
                          icon: Icons.admin_panel_settings_outlined,
                          title: 'Connection Details',
                          subtitle: 'Host and auth',
                        ),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final fullWidth = constraints.maxWidth;
                            final pairWidth =
                                fullWidth >= 900
                                    ? (fullWidth - 12) / 2
                                    : fullWidth;

                            return Column(
                              children: [
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    SizedBox(
                                      width: pairWidth,
                                      child: _Field(
                                        label: 'Host',
                                        hint: '203.0.113.10 or box.example.com',
                                        controller: _hostController,
                                        prefixIcon: Icons.public,
                                      ),
                                    ),
                                    SizedBox(
                                      width: pairWidth,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: _Field(
                                              label: 'Port',
                                              hint: '22',
                                              controller: _portController,
                                              keyboardType:
                                                  TextInputType.number,
                                              prefixIcon:
                                                  Icons.settings_ethernet,
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
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: VpsAuthMode.values
                              .map((mode) {
                                return ChoiceChip(
                                  selected: _authMode == mode,
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
                        const SizedBox(height: 10),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Auto refresh dashboard'),
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
                                      : _connect,
                              icon: Icon(
                                state.isConnected
                                    ? Icons.sync_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              label: Text(
                                state.isConnected ? 'Reconnect' : 'Connect',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  state.isSavingProfile ? null : _saveProfile,
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
                              onPressed: _clearSaved,
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('Clear saved'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }
}

class OpsOverviewPage extends ConsumerWidget {
  const OpsOverviewPage({super.key});

  Future<void> _refresh(WidgetRef ref, OpsDashboardState state) async {
    final controller = ref.read(opsControllerProvider.notifier);
    if (state.isConnected) {
      await controller.refreshDashboard();
      return;
    }
    await controller.connect(state.profile);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(opsControllerProvider);
    final snapshot = state.snapshot;
    final controller = ref.read(opsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Overview', fontWeight: FontWeight.w700),
        actions: [
          IconButton(
            tooltip:
                state.isConnected
                    ? 'Refresh overview'
                    : 'Connect from saved profile',
            onPressed:
                state.isHydrating || state.isRefreshing || state.isConnecting
                    ? null
                    : () => _refresh(ref, state),
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
                onRefresh: () => _refresh(ref, state),
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
                        _FeatureHeroCard(
                          icon: Icons.monitor_heart_outlined,
                          eyebrow: 'Overview',
                          title:
                              snapshot?.hostname ??
                              state.profile.host.ifBlank('Connect a VPS'),
                          description:
                              snapshot == null
                                  ? 'CPU, memory, disk'
                                  : '${snapshot.osSummary} • ${snapshot.uptime}',
                          accent:
                              snapshot == null
                                  ? const Color(0xFFF97316)
                                  : const Color(0xFF22C55E),
                          chips: [
                            _HeroChip(
                              label: 'CPU',
                              value:
                                  snapshot == null
                                      ? '--'
                                      : '${snapshot.cpuLoadPercent.toStringAsFixed(0)}%',
                            ),
                            _HeroChip(
                              label: 'Memory',
                              value:
                                  snapshot == null
                                      ? '--'
                                      : '${snapshot.memoryUsagePercent.toStringAsFixed(0)}%',
                            ),
                            _HeroChip(
                              label: 'Disk',
                              value:
                                  snapshot == null
                                      ? '--'
                                      : '${snapshot.diskUsagePercent.toStringAsFixed(0)}%',
                            ),
                          ],
                          primaryActionLabel:
                              state.isConnected ? 'Refresh' : 'Connect',
                          onPrimaryAction:
                              state.isRefreshing || state.isConnecting
                                  ? null
                                  : () => _refresh(ref, state),
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
                        if (snapshot == null)
                          _MissingDataPanel(
                            icon: Icons.monitor_heart_outlined,
                            title: 'No data yet',
                            description: 'Connect',
                            actionLabel: 'Connection',
                            onAction:
                                () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const OpsConnectionPage(),
                                  ),
                                ),
                          )
                        else ...[
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
                          _ProcessPanel(snapshot: snapshot),
                        ],
                      ],
                    );
                  },
                ),
              ),
    );
  }
}

class OpsRuntimePage extends ConsumerWidget {
  const OpsRuntimePage({super.key});

  Future<void> _refresh(WidgetRef ref, OpsDashboardState state) async {
    final controller = ref.read(opsControllerProvider.notifier);
    if (state.isConnected) {
      await controller.refreshDashboard();
      return;
    }
    await controller.connect(state.profile);
  }

  void _openContainerLogs(BuildContext context, VpsContainerInfo container) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => OpsRuntimeLogsPage(
              targetType: OpsLogTargetType.container,
              targetName: container.name,
              subtitle: container.image,
            ),
      ),
    );
  }

  void _openServiceLogs(BuildContext context, VpsServiceInfo service) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => OpsRuntimeLogsPage(
              targetType: OpsLogTargetType.service,
              targetName: service.name,
              subtitle: service.description,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(opsControllerProvider);
    final snapshot = state.snapshot;
    final controller = ref.read(opsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Runtime', fontWeight: FontWeight.w700),
        actions: [
          IconButton(
            tooltip:
                state.isConnected
                    ? 'Refresh runtime inventory'
                    : 'Connect from saved profile',
            onPressed:
                state.isHydrating || state.isRefreshing || state.isConnecting
                    ? null
                    : () => _refresh(ref, state),
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
                onRefresh: () => _refresh(ref, state),
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
                        _FeatureHeroCard(
                          icon: Icons.inventory_2_rounded,
                          eyebrow: 'Runtime',
                          title:
                              snapshot?.endpointLabel ??
                              state.profile.endpointLabel,
                          description:
                              snapshot == null
                                  ? 'Containers and services'
                                  : 'Docker and systemd inventory',
                          accent: const Color(0xFF60A5FA),
                          chips: [
                            _HeroChip(
                              label: 'Containers',
                              value:
                                  snapshot == null
                                      ? '--'
                                      : '${snapshot.runningContainers}',
                            ),
                            _HeroChip(
                              label: 'Services',
                              value:
                                  snapshot == null
                                      ? '--'
                                      : '${snapshot.runningServices}',
                            ),
                            _HeroChip(
                              label: 'Docker',
                              value:
                                  snapshot == null
                                      ? 'Unknown'
                                      : snapshot.dockerAvailable
                                      ? 'Yes'
                                      : 'No',
                            ),
                          ],
                          primaryActionLabel:
                              state.isConnected ? 'Refresh' : 'Connect',
                          onPrimaryAction:
                              state.isRefreshing || state.isConnecting
                                  ? null
                                  : () => _refresh(ref, state),
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
                        if (snapshot == null)
                          _MissingDataPanel(
                            icon: Icons.inventory_2_outlined,
                            title: 'No data yet',
                            description: 'Connect',
                            actionLabel: 'Connection',
                            onAction:
                                () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const OpsConnectionPage(),
                                  ),
                                ),
                          )
                        else
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              SizedBox(
                                width: pairWidth,
                                child: _DockerPanel(
                                  snapshot: snapshot,
                                  onOpenLogs:
                                      (container) => _openContainerLogs(
                                        context,
                                        container,
                                      ),
                                ),
                              ),
                              SizedBox(
                                width: pairWidth,
                                child: _ServicePanel(
                                  snapshot: snapshot,
                                  onOpenLogs:
                                      (service) =>
                                          _openServiceLogs(context, service),
                                ),
                              ),
                            ],
                          ),
                      ],
                    );
                  },
                ),
              ),
    );
  }
}

class OpsRuntimeLogsPage extends ConsumerStatefulWidget {
  const OpsRuntimeLogsPage({
    required this.targetType,
    required this.targetName,
    required this.subtitle,
    super.key,
  });

  final OpsLogTargetType targetType;
  final String targetName;
  final String subtitle;

  @override
  ConsumerState<OpsRuntimeLogsPage> createState() => _OpsRuntimeLogsPageState();
}

class _OpsRuntimeLogsPageState extends ConsumerState<OpsRuntimeLogsPage> {
  OpsCommandLogEntry? _entry;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final controller = ref.read(opsControllerProvider.notifier);
      final entry =
          widget.targetType == OpsLogTargetType.container
              ? await controller.fetchContainerLogs(widget.targetName)
              : await controller.fetchServiceLogs(widget.targetName);

      if (!mounted) {
        return;
      }

      setState(() {
        _entry = entry;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '').trim();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isContainer = widget.targetType == OpsLogTargetType.container;
    final accent =
        isContainer ? const Color(0xFF60A5FA) : const Color(0xFFA78BFA);

    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Logs', fontWeight: FontWeight.w700),
        actions: [
          IconButton(
            tooltip: 'Refresh logs',
            onPressed: _isLoading ? null : _load,
            icon:
                _isLoading
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                    : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _FeatureHeroCard(
            icon: isContainer ? Icons.inventory_2_rounded : Icons.hub_rounded,
            eyebrow: 'Logs',
            title: widget.targetName,
            description:
                widget.subtitle.trim().isEmpty
                    ? isContainer
                        ? 'Container logs'
                        : 'Service logs'
                    : widget.subtitle,
            accent: accent,
            chips: [
              _HeroChip(
                label: 'Source',
                value: isContainer ? 'Container' : 'Service',
              ),
              _HeroChip(
                label: 'Last fetch',
                value:
                    _entry == null ? 'Waiting' : formatOpsClock(_entry!.ranAt),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ErrorBanner(
                message: _error!,
                onDismiss: () {
                  setState(() {
                    _error = null;
                  });
                },
              ),
            ),
          if (_entry != null)
            _TerminalOutput(entry: _entry!)
          else
            _Panel(
              child:
                  _isLoading
                      ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Center(child: CircularProgressIndicator()),
                      )
                      : const _EmptyStateCopy(
                        message: 'No logs were returned for this target.',
                      ),
            ),
        ],
      ),
    );
  }
}

class OpsTerminalPage extends ConsumerStatefulWidget {
  const OpsTerminalPage({super.key});

  @override
  ConsumerState<OpsTerminalPage> createState() => _OpsTerminalPageState();
}

class _OpsTerminalPageState extends ConsumerState<OpsTerminalPage> {
  final _commandController = TextEditingController();

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    await ref
        .read(opsControllerProvider.notifier)
        .runCommand(_commandController.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(opsControllerProvider);
    final controller = ref.read(opsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Terminal', fontWeight: FontWeight.w700),
      ),
      body:
          state.isHydrating
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _FeatureHeroCard(
                    icon: Icons.terminal_rounded,
                    eyebrow: 'Terminal',
                    title:
                        state.snapshot?.endpointLabel ??
                        state.profile.endpointLabel,
                    description:
                        state.isConnected ? 'Session live' : 'Saved profile',
                    accent: const Color(0xFF22C55E),
                    chips: [
                      _HeroChip(
                        label: 'Session',
                        value: state.isConnected ? 'Live' : 'Offline',
                      ),
                      _HeroChip(
                        label: 'Last run',
                        value:
                            state.terminalHistory.isEmpty
                                ? 'None'
                                : formatOpsClock(
                                  state.terminalHistory.first.ranAt,
                                ),
                      ),
                    ],
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
                  _TerminalPanel(
                    state: state,
                    commandController: _commandController,
                    onRun: _run,
                    onPresetSelected: (command) {
                      _commandController.text = command;
                      controller.runCommand(command);
                    },
                  ),
                ],
              ),
    );
  }
}

class _FeatureHeroCard extends StatelessWidget {
  const _FeatureHeroCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.accent,
    this.chips = const <_HeroChip>[],
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final Color accent;
  final List<_HeroChip> chips;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F172A),
            const Color(0xFF111827),
            accent.withValues(alpha: 0.22),
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
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.32)),
                  ),
                  child: Icon(icon, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.54),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SlashText(
                        title,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      if (description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.70),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 12, runSpacing: 12, children: chips),
            ],
            if (primaryActionLabel != null || secondaryActionLabel != null) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (primaryActionLabel != null)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F172A),
                      ),
                      onPressed: onPrimaryAction,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(primaryActionLabel!),
                    ),
                  if (secondaryActionLabel != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      onPressed: onSecondaryAction,
                      icon: const Icon(Icons.link_off_rounded),
                      label: Text(secondaryActionLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
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
              color: Colors.white.withValues(alpha: 0.54),
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

class _MissingDataPanel extends StatelessWidget {
  const _MissingDataPanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(icon: icon, title: title, subtitle: description),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(actionLabel),
          ),
        ],
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
          const _SectionHeading(
            icon: Icons.speed_rounded,
            title: 'Operational Snapshot',
            subtitle: 'Latest poll',
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
  const _DockerPanel({required this.snapshot, required this.onOpenLogs});

  final VpsSnapshot snapshot;
  final ValueChanged<VpsContainerInfo> onOpenLogs;

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
                snapshot.dockerAvailable ? 'docker ps' : 'Docker not found',
          ),
          const SizedBox(height: 16),
          if (!snapshot.dockerAvailable)
            const _EmptyStateCopy(
              message: 'Docker is not available on this host.',
            )
          else if (snapshot.containers.isEmpty)
            const _EmptyStateCopy(message: 'No running containers.')
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
                      onTap: () => onOpenLogs(container),
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
  const _ServicePanel({required this.snapshot, required this.onOpenLogs});

  final VpsSnapshot snapshot;
  final ValueChanged<VpsServiceInfo> onOpenLogs;

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
                    ? 'systemctl active units'
                    : 'systemd not found',
          ),
          const SizedBox(height: 16),
          if (!snapshot.systemdAvailable)
            const _EmptyStateCopy(
              message: 'systemd is not available on this host.',
            )
          else if (visibleServices.isEmpty)
            const _EmptyStateCopy(message: 'No running services.')
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
                      onTap: () => onOpenLogs(service),
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
          const _SectionHeading(
            icon: Icons.memory_rounded,
            title: 'Top Processes',
            subtitle: 'Latest CPU sample',
          ),
          const SizedBox(height: 16),
          if (snapshot.topProcesses.isEmpty)
            const _EmptyStateCopy(message: 'No process data.')
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
              children: opsCommandPresets
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
                hintText: 'Run SSH command',
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
                Expanded(
                  child: Text(
                    state.isConnected ? 'Live session' : 'Connects on run',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.64),
                    ),
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
                  'Output appears here.',
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
                                  '${formatOpsClock(entry.ranAt)} • exit ${entry.exitCode ?? 'unknown'}',
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
        const _TrafficDot(color: Color(0xFFFB7185)),
        const SizedBox(width: 6),
        const _TrafficDot(color: Color(0xFFF59E0B)),
        const SizedBox(width: 6),
        const _TrafficDot(color: Color(0xFF34D399)),
        const SizedBox(width: 12),
        Text(
          'ops terminal',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
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
    this.onTap,
  });

  final Color color;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Row(
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
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
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
        if (onTap != null) ...[
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.46),
          ),
        ],
      ],
    );

    final content = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.28,
        ),
      ),
      child: row,
    );

    if (onTap == null) {
      return content;
    }

    return GestureDetector(onTap: onTap, child: content);
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

double _containerChartCeiling(List<OpsMetricPoint> trend) {
  if (trend.isEmpty) {
    return 5;
  }
  final peak = trend.map((point) => point.value).reduce(math.max);
  return math.max(5, peak + 1);
}

String formatOpsClock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  final second = time.second.toString().padLeft(2, '0');

  return '$hour:$minute:$second';
}

extension OpsStringX on String {
  String ifBlank(String fallback) {
    return trim().isEmpty ? fallback : this;
  }
}
