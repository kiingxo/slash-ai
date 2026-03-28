import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/components/slash_text.dart';
import 'ops_controller.dart';
import 'ops_feature_pages.dart';
import 'ops_models.dart';

class OpsPage extends ConsumerWidget {
  const OpsPage({super.key});

  Future<void> _refresh(WidgetRef ref, OpsDashboardState state) async {
    final controller = ref.read(opsControllerProvider.notifier);
    if (state.isConnected) {
      await controller.refreshDashboard();
      return;
    }
    await controller.connect(state.profile);
  }

  void _openFeature(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(opsControllerProvider);
    final snapshot = state.snapshot;
    final controller = ref.read(opsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const SlashText('Ops', fontWeight: FontWeight.w700),
        actions: [
          IconButton(
            tooltip:
                state.isConnected
                    ? 'Refresh'
                    : state.profile.canConnect
                    ? 'Connect'
                    : 'Open connection',
            onPressed:
                state.isHydrating || state.isConnecting || state.isRefreshing
                    ? null
                    : state.profile.canConnect
                    ? () => _refresh(ref, state)
                    : () => _openFeature(context, const OpsConnectionPage()),
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
                onRefresh:
                    state.profile.canConnect
                        ? () => _refresh(ref, state)
                        : () async {},
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  children: [
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _ErrorBanner(
                          message: state.error!,
                          onDismiss: controller.clearError,
                        ),
                      ),
                    _MenuPanel(
                      children: [
                        _MenuTile(
                          icon: Icons.dns_rounded,
                          title: 'Connection',
                          subtitle:
                              snapshot?.hostname ??
                              state.profile.host.ifBlank('No VPS saved'),
                          trailing:
                              state.isConnected
                                  ? 'Live'
                                  : state.profile.canConnect
                                  ? 'Saved'
                                  : 'Setup',
                          onTap:
                              () => _openFeature(
                                context,
                                const OpsConnectionPage(),
                              ),
                        ),
                        _MenuTile(
                          icon: Icons.monitor_heart_outlined,
                          title: 'Overview',
                          subtitle:
                              snapshot == null
                                  ? 'CPU, memory, disk'
                                  : '${snapshot.cpuLoadPercent.toStringAsFixed(0)}% CPU • ${snapshot.memoryUsagePercent.toStringAsFixed(0)}% RAM',
                          trailing: snapshot == null ? 'Stats' : 'Live',
                          onTap:
                              () => _openFeature(
                                context,
                                const OpsOverviewPage(),
                              ),
                        ),
                        _MenuTile(
                          icon: Icons.inventory_2_rounded,
                          title: 'Runtime',
                          subtitle:
                              snapshot == null
                                  ? 'Containers and services'
                                  : '${snapshot.runningContainers} containers • ${snapshot.runningServices} services',
                          trailing:
                              snapshot == null
                                  ? 'Runtime'
                                  : snapshot.dockerAvailable
                                  ? 'Docker'
                                  : 'Services',
                          onTap:
                              () =>
                                  _openFeature(context, const OpsRuntimePage()),
                        ),
                        _MenuTile(
                          icon: Icons.terminal_rounded,
                          title: 'Terminal',
                          subtitle:
                              state.terminalHistory.isEmpty
                                  ? 'Run commands'
                                  : state.terminalHistory.first.command,
                          trailing: state.isConnected ? 'SSH' : 'Shell',
                          onTap:
                              () => _openFeature(
                                context,
                                const OpsTerminalPage(),
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _StatusCard(
                      state: state,
                      snapshot: snapshot,
                      onOpenConnection:
                          () =>
                              _openFeature(context, const OpsConnectionPage()),
                      onRefresh:
                          state.profile.canConnect
                              ? () => _refresh(ref, state)
                              : null,
                      onDisconnect:
                          state.isConnected ? controller.disconnect : null,
                    ),
                  ],
                ),
              ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
    required this.snapshot,
    required this.onOpenConnection,
    required this.onRefresh,
    required this.onDisconnect,
  });

  final OpsDashboardState state;
  final VpsSnapshot? snapshot;
  final VoidCallback onOpenConnection;
  final VoidCallback? onRefresh;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = state.isConnected;
    final accent =
        connected ? const Color(0xFF22C55E) : const Color(0xFFF97316);

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
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.cloud_outlined, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected ? 'Connected' : 'Not connected',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snapshot?.endpointLabel ?? state.profile.endpointLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.68,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(label: connected ? 'LIVE' : 'IDLE', color: accent),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InlineStat(
                  label: 'Host',
                  value:
                      snapshot?.hostname ??
                      state.profile.host.ifBlank('Not set'),
                ),
                _InlineStat(
                  label: 'Last sync',
                  value:
                      snapshot == null
                          ? 'Waiting'
                          : formatOpsClock(snapshot!.collectedAt),
                ),
                if (snapshot != null)
                  _InlineStat(
                    label: 'CPU',
                    value: '${snapshot!.cpuLoadPercent.toStringAsFixed(0)}%',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onOpenConnection,
                  icon: const Icon(Icons.dns_rounded),
                  label: const Text('Connection'),
                ),
                if (onRefresh != null)
                  OutlinedButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(connected ? 'Refresh' : 'Connect'),
                  ),
                if (onDisconnect != null)
                  TextButton.icon(
                    onPressed: onDisconnect,
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Disconnect'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({required this.children});

  final List<Widget> children;

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
      child: Column(children: children),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.66,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                trailing,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.56),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.26,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.56),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.8,
        ),
      ),
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
