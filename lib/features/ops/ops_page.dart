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
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate(
                          [
                            if (state.error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _ErrorBanner(
                                  message: state.error!,
                                  onDismiss: controller.clearError,
                                ),
                              ),
                            // Connection Status Hero Card
                            _HeroStatusCard(
                              state: state,
                              snapshot: snapshot,
                              onOpenConnection:
                                  () => _openFeature(
                                    context,
                                    const OpsConnectionPage(),
                                  ),
                              onRefresh:
                                  state.profile.canConnect
                                      ? () => _refresh(ref, state)
                                      : null,
                              onDisconnect:
                                  state.isConnected
                                      ? controller.disconnect
                                      : null,
                            ),
                            const SizedBox(height: 20),
                            // Quick Stats Row
                            if (snapshot != null)
                              _QuickStatsRow(snapshot: snapshot),
                            if (snapshot != null)
                              const SizedBox(height: 20),
                            // Feature Grid
                            _FeatureGrid(
                              state: state,
                              snapshot: snapshot,
                              onFeatureTap: _openFeature,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}

class _HeroStatusCard extends StatelessWidget {
  const _HeroStatusCard({
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
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.08),
            accent.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.cloud_done_rounded,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected ? 'System Online' : 'System Offline',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                      Text(
                        snapshot?.endpointLabel ??
                            state.profile.endpointLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        connected ? 'LIVE' : 'IDLE',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StatChip(
                    label: 'Host',
                    value:
                        snapshot?.hostname ??
                        state.profile.host.ifBlank('Not set'),
                    icon: Icons.dns_rounded,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Last Sync',
                    value:
                        snapshot == null
                            ? 'Never'
                            : formatOpsClock(snapshot!.collectedAt),
                    icon: Icons.schedule_rounded,
                  ),
                  if (snapshot != null) ...[const SizedBox(width: 8),
                    _StatChip(
                      label: 'Uptime',
                      value: snapshot!.uptime,
                      icon: Icons.timer_rounded,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onOpenConnection,
                    icon: const Icon(Icons.dns_rounded, size: 14),
                    label: const Text('Connection'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (onRefresh != null)
                  FilledButton.tonalIcon(
                    onPressed: onRefresh!,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: Text(
                      connected ? 'Refresh' : 'Connect',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                const SizedBox(width: 6),
                if (onDisconnect != null)
                  IconButton(
                    onPressed: onDisconnect!,
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    style: IconButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.25,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 7,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow({required this.snapshot});

  final VpsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.memory_rounded,
            label: 'Memory',
            value: '${snapshot.memoryUsagePercent.toStringAsFixed(1)}%',
            progress: snapshot.memoryUsagePercent / 100,
            color: const Color(0xFF3B82F6),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.settings_outlined,
            label: 'CPU',
            value: '${snapshot.cpuLoadPercent.toStringAsFixed(1)}%',
            progress: snapshot.cpuLoadPercent / 100,
            color: const Color(0xFFEC4899),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.storage_rounded,
            label: 'Disk',
            value: '${snapshot.diskUsagePercent.toStringAsFixed(1)}%',
            progress: snapshot.diskUsagePercent / 100,
            color: const Color(0xFFF59E0B),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clampedProgress = progress.clamp(0.0, 1.0);
    final isWarning = clampedProgress > 0.7;
    final isCritical = clampedProgress > 0.85;

    Color getProgressColor() {
      if (isCritical) return const Color(0xFFDC2626);
      if (isWarning) return const Color(0xFFF59E0B);
      return color;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clampedProgress,
              minHeight: 4,
              backgroundColor:
                  theme.colorScheme.outline.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(getProgressColor()),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({
    required this.state,
    required this.snapshot,
    required this.onFeatureTap,
  });

  final OpsDashboardState state;
  final VpsSnapshot? snapshot;
  final void Function(BuildContext context, Widget page) onFeatureTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Dashboard',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface.withValues(
                alpha: 0.6,
              ),
              letterSpacing: 0.3,
            ),
          ),
        ),
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _DashboardFeatureCard(
                    icon: Icons.monitor_heart_outlined,
                    title: 'Overview',
                    description:
                        snapshot == null
                            ? 'System metrics'
                            : '${snapshot!.cpuLoadPercent.toStringAsFixed(0)}% CPU',
                    onTap:
                        () => onFeatureTap(
                          context,
                          const OpsOverviewPage(),
                        ),
                    accentColor: const Color(0xFF8B5CF6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DashboardFeatureCard(
                    icon: Icons.terminal_rounded,
                    title: 'Terminal',
                    description:
                        state.terminalHistory.isEmpty
                            ? 'Run commands'
                            : state.terminalHistory.first.command
                                .length > 30
                            ? '${state.terminalHistory.first.command.substring(0, 30)}...'
                            : state.terminalHistory.first.command,
                    onTap:
                        () => onFeatureTap(
                          context,
                          const OpsTerminalPage(),
                        ),
                    accentColor: const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DashboardFeatureCard(
                    icon: Icons.inventory_2_rounded,
                    title: 'Runtime',
                    description:
                        snapshot == null
                            ? 'Containers'
                            : '${snapshot!.runningContainers} active',
                    onTap:
                        () => onFeatureTap(
                          context,
                          const OpsRuntimePage(),
                        ),
                    accentColor: const Color(0xFF06B6D4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DashboardFeatureCard(
                    icon: Icons.engineering_rounded,
                    title: 'AI Oncall Engineer',
                    description:
                        '24/7 AI assistance for your VPS operations',
                    onTap:
                        () => onFeatureTap(
                          context,
                          const OpsOverviewPage(),
                        ),
                    accentColor: const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _DashboardFeatureCard extends StatefulWidget {
  const _DashboardFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final Color accentColor;

  @override
  State<_DashboardFeatureCard> createState() => _DashboardFeatureCardState();
}

class _DashboardFeatureCardState extends State<_DashboardFeatureCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  _isHovered
                      ? widget.accentColor.withValues(alpha: 0.3)
                      : theme.colorScheme.outline.withValues(alpha: 0.1),
            ),
            boxShadow: [
              if (_isHovered)
                BoxShadow(
                  color: widget.accentColor.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.icon,
                  color: widget.accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Open',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: widget.accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: widget.accentColor.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ],
          ),
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
