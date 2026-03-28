import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/components/slash_text.dart';
import '../prompt/prompt_service.dart';
import '../repo/repo_controller.dart';
import 'project_controller.dart';
import 'project_service.dart';

class ProjectPage extends ConsumerWidget {
  const ProjectPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(projectOverviewProvider);
    await ref.read(projectOverviewProvider.future);
  }

  Future<void> _openExternal(BuildContext context, String? rawUrl) async {
    final value = (rawUrl ?? '').trim();
    if (value.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(value);
    if (uri == null) {
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open that GitHub link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repoState = ref.watch(repoControllerProvider);
    final report = ref.watch(projectOverviewProvider);
    final selectedRepo =
        repoState.selectedRepo ??
        (repoState.repos.isNotEmpty ? repoState.repos.first : null);
    final selectedWindow = ref.watch(projectWindowProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SlashText('Project', fontWeight: FontWeight.w700),
            SlashText(
              'Repo summary, risk radar, and action queue',
              fontSize: 12,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh report',
            onPressed: () => _refresh(ref),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body:
          repoState.isLoading && repoState.repos.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : selectedRepo == null
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Select a repository to generate a project report.',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
              : RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  children: [
                    _ProjectHeaderCard(
                      repos: repoState.repos,
                      selectedRepo: selectedRepo,
                      selectedWindow: selectedWindow,
                      onSelectRepo: (fullName) {
                        for (final repo in repoState.repos) {
                          final candidate =
                              (repo['full_name'] ?? repo['name']).toString();
                          if (candidate == fullName) {
                            ref
                                .read(repoControllerProvider.notifier)
                                .selectRepo(repo);
                            ref.invalidate(projectOverviewProvider);
                            break;
                          }
                        }
                      },
                      onSelectWindow: (window) {
                        ref.read(projectWindowProvider.notifier).state = window;
                      },
                      onRefresh: () => _refresh(ref),
                    ),
                    const SizedBox(height: 16),
                    report.when(
                      loading:
                          () => const Padding(
                            padding: EdgeInsets.only(top: 48),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      error:
                          (error, _) => _ErrorCard(
                            message: friendlyErrorMessage(error.toString()),
                            onRetry: () => _refresh(ref),
                          ),
                      data: (overview) {
                        return _ProjectOverviewContent(
                          overview: overview,
                          repo: selectedRepo,
                          onOpenLink: (url) => _openExternal(context, url),
                        );
                      },
                    ),
                  ],
                ),
              ),
    );
  }
}

class _ProjectHeaderCard extends StatelessWidget {
  final List<dynamic> repos;
  final dynamic selectedRepo;
  final ProjectWindow selectedWindow;
  final ValueChanged<String> onSelectRepo;
  final ValueChanged<ProjectWindow> onSelectWindow;
  final Future<void> Function() onRefresh;

  const _ProjectHeaderCard({
    required this.repos,
    required this.selectedRepo,
    required this.selectedWindow,
    required this.onSelectRepo,
    required this.onSelectWindow,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedRepoValue =
        (selectedRepo['full_name'] ?? selectedRepo['name']).toString();
    final description = (selectedRepo['description'] ?? '').toString().trim();
    final language = (selectedRepo['language'] ?? '').toString().trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.dashboard_customize_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SlashText(
                      'Project Command Center',
                      fontWeight: FontWeight.w700,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Leadership summary and delivery radar for the selected repository.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: selectedRepoValue,
              borderRadius: BorderRadius.circular(16),
              items:
                  repos.map((repo) {
                    final value =
                        (repo['full_name'] ?? repo['name']).toString();
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    );
                  }).toList(),
              onChanged: (value) {
                if (value != null) {
                  onSelectRepo(value);
                }
              },
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(description, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(
                label:
                    'Default branch • ${(selectedRepo['default_branch'] ?? 'main').toString()}',
              ),
              _InfoPill(
                label:
                    'Stars • ${((selectedRepo['stargazers_count'] as num?)?.toInt() ?? 0)}',
              ),
              _InfoPill(
                label:
                    'Forks • ${((selectedRepo['forks_count'] as num?)?.toInt() ?? 0)}',
              ),
              if (language.isNotEmpty) _InfoPill(label: 'Language • $language'),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children:
                ProjectWindow.values.map((window) {
                  final selected = selectedWindow == window;
                  return ChoiceChip(
                    label: Text(window.longLabel),
                    selected: selected,
                    onSelected: (_) => onSelectWindow(window),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ProjectOverviewContent extends StatelessWidget {
  final ProjectOverview overview;
  final dynamic repo;
  final Future<void> Function(String? url) onOpenLink;

  const _ProjectOverviewContent({
    required this.overview,
    required this.repo,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StartHereCard(overview: overview),
        const SizedBox(height: 16),
        _StatusStrip(overview: overview),
        const SizedBox(height: 16),
        _MetricGrid(overview: overview),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Executive Brief',
          trailing: _InfoPill(
            label: overview.summaryUsedAI ? 'AI summary' : 'Rules summary',
          ),
          child: Text(
            overview.executiveSummary,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Engineering Lens',
          child: Text(
            overview.engineeringSummary,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Highlights',
          child: _BulletList(
            items: overview.highlights,
            icon: Icons.north_east_rounded,
            color: const Color(0xFF0F766E),
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Risk Radar',
          child: _BulletList(
            items: overview.risks,
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFB45309),
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Next Actions',
          child: _BulletList(
            items: overview.nextActions,
            icon: Icons.task_alt_rounded,
            color: theme.colorScheme.primary,
          ),
        ),
        if (overview.contributors.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Team Activity',
            child: Column(
              children:
                  overview.contributors
                      .map(
                        (item) =>
                            _ContributorRow(item: item, overview: overview),
                      )
                      .toList(),
            ),
          ),
        ],
        if (overview.releases.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Recent Releases',
            child: _ReportList(
              items: overview.releases,
              emptyLabel: 'No recent releases.',
              onOpenLink: onOpenLink,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Pull Request Queue',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _MiniSectionTitle('Open PRs'),
              const SizedBox(height: 8),
              _ReportList(
                items: overview.openPullRequests,
                emptyLabel: 'No open pull requests.',
                onOpenLink: onOpenLink,
              ),
              const SizedBox(height: 16),
              const _MiniSectionTitle('Recent Merges'),
              const SizedBox(height: 8),
              _ReportList(
                items: overview.mergedPullRequests,
                emptyLabel: 'No merged PRs in this window.',
                onOpenLink: onOpenLink,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Issue Flow',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _MiniSectionTitle('Opened'),
              const SizedBox(height: 8),
              _ReportList(
                items: overview.openedIssues,
                emptyLabel: 'No new issues in this window.',
                onOpenLink: onOpenLink,
              ),
              const SizedBox(height: 16),
              const _MiniSectionTitle('Closed'),
              const SizedBox(height: 8),
              _ReportList(
                items: overview.closedIssues,
                emptyLabel: 'No closed issues in this window.',
                onOpenLink: onOpenLink,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Workflow Failures',
          child: _ReportList(
            items: overview.workflowFailures,
            emptyLabel: 'No failed workflow runs in this window.',
            onOpenLink: onOpenLink,
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Timeline',
          child: _TimelineList(
            items: overview.timeline,
            onOpenLink: onOpenLink,
          ),
        ),
      ],
    );
  }
}

class _StartHereCard extends StatelessWidget {
  final ProjectOverview overview;

  const _StartHereCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets = <_PriorityBucketData>[
      _PriorityBucketData(
        title: 'What Changed',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF0F766E),
        items:
            overview.highlights.isNotEmpty
                ? overview.highlights.take(2).toList()
                : [overview.executiveSummary],
      ),
      _PriorityBucketData(
        title: 'Watch Closely',
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFB45309),
        items:
            overview.risks.isNotEmpty
                ? overview.risks.take(2).toList()
                : ['No major risks were flagged in this window.'],
      ),
      _PriorityBucketData(
        title: 'Do Next',
        icon: Icons.task_alt_rounded,
        color: theme.colorScheme.primary,
        items:
            overview.nextActions.isNotEmpty
                ? overview.nextActions.take(2).toList()
                : ['No immediate follow-up actions are suggested right now.'],
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SlashText('Start Here', fontWeight: FontWeight.w700),
          const SizedBox(height: 6),
          Text(
            'The most important updates are surfaced first so you do not have to hunt for them.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns =
                  width >= 960
                      ? 3
                      : width >= 620
                      ? 2
                      : 1;
              final totalSpacing = 12.0 * (columns - 1);
              final cardWidth = (width - totalSpacing) / columns;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    buckets.map((bucket) {
                      return SizedBox(
                        width: cardWidth.clamp(0.0, width),
                        child: _PriorityBucket(data: bucket),
                      );
                    }).toList(),
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.7,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.south_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Scroll for metrics, PR queue, issues, workflow failures, releases, and the activity timeline.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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

class _StatusStrip extends StatelessWidget {
  final ProjectOverview overview;

  const _StatusStrip({required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final generated = _formatRelative(overview.generatedAt.toLocal());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _InfoPill(label: 'Health • ${overview.healthLabel}'),
          _InfoPill(label: 'Momentum • ${overview.momentumLabel}'),
          _InfoPill(label: 'Branch • ${overview.branch}'),
          _InfoPill(label: 'Window • ${overview.window.longLabel}'),
          _InfoPill(label: 'Updated • $generated'),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final ProjectOverview overview;

  const _MetricGrid({required this.overview});

  @override
  Widget build(BuildContext context) {
    final items = <_MetricCardData>[
      _MetricCardData(
        label: 'Commits',
        value: overview.stats.commitCount.toString(),
        icon: Icons.commit_rounded,
      ),
      _MetricCardData(
        label: 'Merged PRs',
        value: overview.stats.mergedPrCount.toString(),
        icon: Icons.merge_type_rounded,
      ),
      _MetricCardData(
        label: 'Open PRs',
        value: overview.stats.openPrCount.toString(),
        icon: Icons.call_split_rounded,
      ),
      _MetricCardData(
        label: 'Issues Opened',
        value: overview.stats.openedIssueCount.toString(),
        icon: Icons.bug_report_outlined,
      ),
      _MetricCardData(
        label: 'Issues Closed',
        value: overview.stats.closedIssueCount.toString(),
        icon: Icons.check_circle_outline_rounded,
      ),
      _MetricCardData(
        label: 'Failed Runs',
        value: overview.stats.failedRunCount.toString(),
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFB91C1C),
      ),
      _MetricCardData(
        label: 'Draft PRs',
        value: overview.stats.draftPrCount.toString(),
        icon: Icons.edit_note_rounded,
      ),
      _MetricCardData(
        label: 'Releases',
        value: overview.stats.releaseCount.toString(),
        icon: Icons.rocket_launch_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns =
            width >= 900
                ? 4
                : width >= 640
                ? 3
                : width >= 420
                ? 2
                : 1;
        final totalSpacing = 12.0 * (columns - 1);
        final cardWidth = (width - totalSpacing) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              items.map((item) {
                return SizedBox(
                  width: cardWidth.clamp(0.0, width),
                  child: _MetricCard(data: item),
                );
              }).toList(),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stackHeader =
                  trailing != null && constraints.maxWidth < 420;

              if (stackHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SlashText(title, fontWeight: FontWeight.w700),
                    const SizedBox(height: 10),
                    trailing!,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: SlashText(title, fontWeight: FontWeight.w700),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing!,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  final List<ProjectReportItem> items;
  final String emptyLabel;
  final Future<void> Function(String? url) onOpenLink;

  const _ReportList({
    required this.items,
    required this.emptyLabel,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Text(emptyLabel, style: theme.textTheme.bodyMedium);
    }

    return Column(
      children:
          items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: theme.colorScheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: item.url == null ? null : () => onOpenLink(item.url),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final status = (item.status ?? '').trim();
                      final stackStatus =
                          status.isNotEmpty && constraints.maxWidth < 430;

                      return Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.10,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      item.number == null
                                          ? '•'
                                          : '#${item.number}',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.subtitle,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                if (!stackStatus && status.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _InfoPill(label: status),
                                  ),
                              ],
                            ),
                            if (stackStatus) ...[
                              const SizedBox(height: 10),
                              _InfoPill(label: status),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }
}

class _TimelineList extends StatelessWidget {
  final List<ProjectTimelineEntry> items;
  final Future<void> Function(String? url) onOpenLink;

  const _TimelineList({required this.items, required this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Text(
        'No notable activity captured yet.',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      children:
          items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: item.url == null ? null : () => onOpenLink(item.url),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.kind,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.subtitle} • ${_formatAbsolute(item.timestamp)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  final IconData icon;
  final Color color;

  const _BulletList({
    required this.items,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }
}

class _ContributorRow extends StatelessWidget {
  final ProjectContributor item;
  final ProjectOverview overview;

  const _ContributorRow({required this.item, required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxCommits =
        overview.contributors.isEmpty
            ? 1
            : overview.contributors.first.commitCount;
    final ratio =
        maxCommits == 0 ? 0.0 : (item.commitCount / maxCommits).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${item.commitCount} commit${item.commitCount == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final _MetricCardData data;

  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = data.accent ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(data.icon, color: accent),
          ),
          const SizedBox(height: 14),
          Text(
            data.value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.label,
            style: theme.textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _PriorityBucket extends StatelessWidget {
  final _PriorityBucketData data;

  const _PriorityBucket({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: data.color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(data.icon, size: 18, color: data.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: data.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...data.items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: BoxDecoration(
                      color: data.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SlashText(
            'Unable To Load Project Report',
            fontWeight: FontWeight.w700,
          ),
          const SizedBox(height: 10),
          Text(message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;

  const _InfoPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MiniSectionTitle extends StatelessWidget {
  final String label;

  const _MiniSectionTitle(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _MetricCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  const _MetricCardData({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });
}

class _PriorityBucketData {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  const _PriorityBucketData({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });
}

String _formatRelative(DateTime time) {
  final delta = DateTime.now().difference(time);
  if (delta.inSeconds < 10) {
    return 'just now';
  }
  if (delta.inMinutes < 1) {
    return '${delta.inSeconds}s ago';
  }
  if (delta.inHours < 1) {
    return '${delta.inMinutes}m ago';
  }
  if (delta.inDays < 1) {
    return '${delta.inHours}h ago';
  }
  return '${delta.inDays}d ago';
}

String _formatAbsolute(DateTime time) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = time.toLocal();
  final month = months[local.month - 1];
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month ${local.day}, ${local.hour}:$minute';
}
