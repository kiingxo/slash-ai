import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/components/slash_text.dart';
import '../../home_shell.dart';
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
        leading: const SidebarMenuButton(),
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
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surface,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.cloud_outlined, color: accent, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected ? 'Connected' : 'Not connected',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        snapshot?.endpointLabel ?? state.profile.endpointLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(label: connected ? 'LIVE' : 'IDLE', color: accent),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InlineStat(
                  label: 'Host',
                  value:
                      snapshot?.hostname ??
                      state.profile.host.ifBlank('Not set'),
                ),
                _InlineStat(
                  label: 'Sync',
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CompactButton(
                  onPressed: onOpenConnection,
                  icon: Icons.dns_rounded,
                  label: 'Connection',
                  filled: true,
                ),
                if (onRefresh != null)
                  _CompactButton(
                    onPressed: onRefresh!,
                    icon: Icons.refresh_rounded,
                    label: connected ? 'Refresh' : 'Connect',
                  ),
                if (onDisconnect != null)
                  _CompactButton(
                    onPressed: onDisconnect!,
                    icon: Icons.link_off_rounded,
                    label: 'Disconnect',
                    destructive: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactButton extends StatelessWidget {
  const _CompactButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.filled = false,
    this.destructive = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool filled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        destructive
            ? theme.colorScheme.error
            : theme.colorScheme.primary;

    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(color: color)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: color.withValues(alpha: 0.35)),
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
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surface,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 4),
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
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              fontSize: 9,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 10,
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
