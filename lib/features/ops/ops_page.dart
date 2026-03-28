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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SlashText('Ops', fontWeight: FontWeight.w700),
            SlashText(
              'Choose the exact surface you want instead of one giant wall',
              fontSize: 12,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip:
                state.isConnected
                    ? 'Refresh saved profile data'
                    : 'Connect from saved profile',
            onPressed:
                state.isHydrating || state.isConnecting || state.isRefreshing
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
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  children: [
                    _OpsHubHero(
                      state: state,
                      snapshot: snapshot,
                      onPrimaryAction:
                          state.profile.canConnect
                              ? () => _refresh(ref, state)
                              : () => _openFeature(
                                context,
                                const OpsConnectionPage(),
                              ),
                      onSecondaryAction:
                          state.isConnected ? controller.disconnect : null,
                    ),
                    const SizedBox(height: 16),
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _HubErrorBanner(
                          message: state.error!,
                          onDismiss: controller.clearError,
                        ),
                      ),
                    _HubSection(
                      title: 'Feature Routes',
                      subtitle:
                          'Each card opens a dedicated screen, so you can stay inside one ops task at a time.',
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 900;
                          final cardWidth =
                              wide
                                  ? (constraints.maxWidth - 14) / 2
                                  : constraints.maxWidth;

                          return Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              SizedBox(
                                width: cardWidth,
                                child: _HubFeatureCard(
                                  icon: Icons.dns_rounded,
                                  title: 'Connection',
                                  subtitle:
                                      'Host, auth mode, saved profile, and reconnect controls live here now.',
                                  accent: const Color(0xFFF97316),
                                  meta: state.profile.host.ifBlank(
                                    'No host saved yet',
                                  ),
                                  statLabel: 'Session',
                                  statValue:
                                      state.isConnected ? 'Live' : 'Offline',
                                  onTap:
                                      () => _openFeature(
                                        context,
                                        const OpsConnectionPage(),
                                      ),
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: _HubFeatureCard(
                                  icon: Icons.monitor_heart_outlined,
                                  title: 'Overview',
                                  subtitle:
                                      'CPU, memory, disk trends and hot processes without the rest of the clutter.',
                                  accent: const Color(0xFF22C55E),
                                  meta:
                                      snapshot == null
                                          ? 'No live health snapshot'
                                          : '${snapshot.cpuLoadPercent.toStringAsFixed(0)}% CPU • ${snapshot.memoryUsagePercent.toStringAsFixed(0)}% RAM',
                                  statLabel: 'Processes',
                                  statValue:
                                      snapshot == null
                                          ? '--'
                                          : '${snapshot.topProcesses.length}',
                                  onTap:
                                      () => _openFeature(
                                        context,
                                        const OpsOverviewPage(),
                                      ),
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: _HubFeatureCard(
                                  icon: Icons.inventory_2_rounded,
                                  title: 'Runtime',
                                  subtitle:
                                      'A focused screen for Docker containers and running system services.',
                                  accent: const Color(0xFF60A5FA),
                                  meta:
                                      snapshot == null
                                          ? 'No runtime inventory yet'
                                          : '${snapshot.runningContainers} containers • ${snapshot.runningServices} services',
                                  statLabel: 'Docker',
                                  statValue:
                                      snapshot == null
                                          ? '--'
                                          : snapshot.dockerAvailable
                                          ? 'Yes'
                                          : 'No',
                                  onTap:
                                      () => _openFeature(
                                        context,
                                        const OpsRuntimePage(),
                                      ),
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: _HubFeatureCard(
                                  icon: Icons.terminal_rounded,
                                  title: 'Terminal',
                                  subtitle:
                                      'Preset commands, ad-hoc inspection, and recent output live on their own screen.',
                                  accent: const Color(0xFFA78BFA),
                                  meta:
                                      state.terminalHistory.isEmpty
                                          ? 'No commands run yet'
                                          : state.terminalHistory.first.command,
                                  statLabel: 'History',
                                  statValue: '${state.terminalHistory.length}',
                                  onTap:
                                      () => _openFeature(
                                        context,
                                        const OpsTerminalPage(),
                                      ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    _HubSection(
                      title: 'Quick Snapshot',
                      subtitle:
                          'A tiny status strip stays here so the hub still tells you what is alive at a glance.',
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _MiniMetric(
                            title: 'Host',
                            value:
                                snapshot?.hostname ??
                                state.profile.host.ifBlank('Not connected'),
                            color: const Color(0xFF0F172A),
                          ),
                          _MiniMetric(
                            title: 'CPU',
                            value:
                                snapshot == null
                                    ? '--'
                                    : '${snapshot.cpuLoadPercent.toStringAsFixed(0)}%',
                            color: const Color(0xFFFB7185),
                          ),
                          _MiniMetric(
                            title: 'Containers',
                            value:
                                snapshot == null
                                    ? '--'
                                    : '${snapshot.runningContainers}',
                            color: const Color(0xFF60A5FA),
                          ),
                          _MiniMetric(
                            title: 'Last sync',
                            value:
                                snapshot == null
                                    ? 'Waiting'
                                    : formatOpsClock(snapshot.collectedAt),
                            color: const Color(0xFF22C55E),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Container(
                    //   padding: const EdgeInsets.all(18),
                    //   decoration: BoxDecoration(
                    //     borderRadius: BorderRadius.circular(24),
                    //     gradient: LinearGradient(
                    //       colors: [
                    //         theme.colorScheme.primary.withValues(alpha: 0.10),
                    //         const Color(0xFFF97316).withValues(alpha: 0.08),
                    //       ],
                    //     ),
                    //   ),
                 
                    // ),
                  ],
                ),
              ),
    );
  }
}

class _OpsHubHero extends StatelessWidget {
  const _OpsHubHero({
    required this.state,
    required this.snapshot,
    required this.onPrimaryAction,
    required this.onSecondaryAction,
  });

  final OpsDashboardState state;
  final VpsSnapshot? snapshot;
  final VoidCallback onPrimaryAction;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final accent =
        state.isConnected ? const Color(0xFF34D399) : const Color(0xFFF97316);
    final target = snapshot?.endpointLabel ?? state.profile.endpointLabel;
    final description =
        snapshot == null
            ? 'Pick a feature lane below and only open the surface you actually need.'
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
                    border: Border.all(color: accent.withValues(alpha: 0.32)),
                  ),
                  child: Icon(Icons.route_rounded, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OPS HUB',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.54),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // const SlashText(
                      //   'Choose Your Lane',
                      //   fontSize: 24,
                      //   fontWeight: FontWeight.w700,
                      //   color: Colors.white,
                      // ),
                      const SizedBox(height: 6),
                      SlashText(
                        target,
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                _HubStatusPill(
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
                _HeroMetric(
                  label: 'Host',
                  value:
                      snapshot?.hostname ??
                      state.profile.host.ifBlank('Not set'),
                ),
                _HeroMetric(
                  label: 'Containers',
                  value:
                      snapshot == null
                          ? '--'
                          : '${snapshot!.runningContainers}',
                ),
                _HeroMetric(
                  label: 'Services',
                  value:
                      snapshot == null ? '--' : '${snapshot!.runningServices}',
                ),
                _HeroMetric(
                  label: 'Commands',
                  value: '${state.terminalHistory.length}',
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
                  onPressed: onPrimaryAction,
                  icon: Icon(
                    state.profile.canConnect
                        ? Icons.sync_rounded
                        : Icons.dns_rounded,
                  ),
                  label: Text(
                    state.profile.canConnect
                        ? 'Refresh / Connect'
                        : 'Set up connection',
                  ),
                ),
                if (onSecondaryAction != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.24),
                      ),
                    ),
                    onPressed: onSecondaryAction,
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

class _HubSection extends StatelessWidget {
  const _HubSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
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
      child: Padding(
        padding: const EdgeInsets.all(18),
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
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _HubFeatureCard extends StatelessWidget {
  const _HubFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.meta,
    required this.statLabel,
    required this.statValue,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String meta;
  final String statLabel;
  final String statValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.12),
              accent.withValues(alpha: 0.03),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_rounded),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.74),
                height: 1.42,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              meta,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.46),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Text(
                    statLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.64,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    statValue,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

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

class _HubStatusPill extends StatelessWidget {
  const _HubStatusPill({required this.label, required this.color});

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

class _HubErrorBanner extends StatelessWidget {
  const _HubErrorBanner({required this.message, required this.onDismiss});

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
