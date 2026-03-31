import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/components/slash_text.dart';
import '../../home_shell.dart';
import '../auth/auth_controller.dart';
import '../prompt/prompt_service.dart';
import '../repo/repo_controller.dart';
import 'project_controller.dart';
import 'project_pdf_service.dart';
import 'project_service.dart';

final _projectPdfExportingProvider = StateProvider<bool>((_) => false);

enum _ProjectExportAction { previewPdf, sharePdf }

class ProjectPage extends ConsumerStatefulWidget {
  const ProjectPage({super.key});

  @override
  ConsumerState<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends ConsumerState<ProjectPage> {
  String? _summaryKey;
  ProjectOverview? _generatedSummaryOverview;
  String? _executiveSummaryError;
  bool _isGeneratingExecutiveSummary = false;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(projectOverviewProvider);
    await ref.read(projectOverviewProvider.future);
  }

  Future<void> _openExternal(BuildContext context, String? rawUrl) async {
    final value = (rawUrl ?? '').trim();
    if (value.isEmpty) return;
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open that GitHub link.')),
      );
    }
  }

  String _overviewKey(ProjectOverview overview) {
    return '${overview.repoFullName}::${overview.branch}::${overview.window.name}::${overview.generatedAt.toUtc().millisecondsSinceEpoch}';
  }

  bool _isCurrentSummaryState(ProjectOverview overview) =>
      _summaryKey == _overviewKey(overview);

  ProjectOverview _effectiveOverview(ProjectOverview overview) {
    if (_isCurrentSummaryState(overview) && _generatedSummaryOverview != null) {
      return _generatedSummaryOverview!;
    }
    return overview;
  }

  Future<ProjectOverview> _requestExecutiveSummary(
    ProjectOverview overview,
  ) async {
    final key = _overviewKey(overview);
    setState(() {
      _summaryKey = key;
      _executiveSummaryError = null;
      _isGeneratingExecutiveSummary = true;
    });
    try {
      final authState = ref.read(authControllerProvider);
      final generated = await ProjectInsightsService.generateExecutiveSummary(
        overview: overview,
        model: authState.model,
        openAIApiKey: authState.openAIApiKey,
        openAIModel: authState.openAIModel,
        openRouterApiKey: authState.openRouterApiKey,
        openRouterModel: authState.openRouterModel,
      );
      if (!mounted) return generated;
      setState(() {
        _summaryKey = key;
        _generatedSummaryOverview = generated;
        _executiveSummaryError = null;
        _isGeneratingExecutiveSummary = false;
      });
      return generated;
    } catch (error) {
      final friendly = friendlyErrorMessage(error.toString());
      if (mounted) {
        setState(() {
          _summaryKey = key;
          _executiveSummaryError = friendly;
          _isGeneratingExecutiveSummary = false;
        });
      }
      rethrow;
    }
  }

  Future<void> _generateExecutiveSummary(ProjectOverview overview) async {
    try {
      await _requestExecutiveSummary(_effectiveOverview(overview));
    } catch (_) {}
  }

  Future<ProjectOverview> _ensureDetailedOverview(
    ProjectOverview overview,
  ) async {
    final effective = _effectiveOverview(overview);
    if (effective.summaryUsedAI) return effective;
    return _requestExecutiveSummary(effective);
  }

  Future<void> _exportReport({
    required BuildContext context,
    required ProjectOverview overview,
    required dynamic repo,
    required _ProjectExportAction action,
  }) async {
    if (ref.read(_projectPdfExportingProvider) || _isGeneratingExecutiveSummary) {
      return;
    }
    ref.read(_projectPdfExportingProvider.notifier).state = true;
    try {
      final exportOverview = await _ensureDetailedOverview(overview);
      await ProjectPdfService.exportExecutiveSummary(
        overview: exportOverview,
        repo: repo,
        mode: action == _ProjectExportAction.previewPdf
            ? ProjectPdfExportMode.preview
            : ProjectPdfExportMode.share,
      );
    } catch (error) {
      if (context.mounted) {
        final details = error.toString().trim();
        final friendly = friendlyErrorMessage(details);
        final showDetails = details.isNotEmpty &&
            details != friendly &&
            friendly == 'Something went wrong. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              showDetails
                  ? 'Unable to export the executive summary PDF. $details'
                  : 'Unable to export the executive summary PDF. $friendly',
            ),
          ),
        );
      }
    } finally {
      ref.read(_projectPdfExportingProvider.notifier).state = false;
    }
  }

  bool _canExport(ProjectOverview? overview, dynamic repo) {
    if (overview == null || repo == null) return false;
    final repoFullName = (repo['full_name'] ?? repo['name']).toString().trim();
    return repoFullName.isNotEmpty && repoFullName == overview.repoFullName;
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final repoState = ref.watch(repoControllerProvider);
    final report = ref.watch(projectOverviewProvider);
    final rawOverview = report.valueOrNull;
    final overview = rawOverview == null ? null : _effectiveOverview(rawOverview);
    final isExporting = ref.watch(_projectPdfExportingProvider);
    final selectedRepo =
        repoState.selectedRepo ??
        (repoState.repos.isNotEmpty ? repoState.repos.first : null);
    final selectedWindow = ref.watch(projectWindowProvider);
    final canExport = _canExport(overview, selectedRepo);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        leading: const SidebarMenuButton(),
        title: const SlashText('Project', fontWeight: FontWeight.w700),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: report.isLoading ? null : () => _refresh(ref),
            icon: report.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: repoState.isLoading && repoState.repos.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : selectedRepo == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Select a repository to load the project report.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _ProjectHeroCard(
                          repos: repoState.repos,
                          selectedRepo: selectedRepo,
                          selectedWindow: selectedWindow,
                          isLoading: report.isLoading,
                          overview: overview,
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
                            ref.read(projectWindowProvider.notifier).state =
                                window;
                          },
                          onRefresh: () => _refresh(ref),
                        ),
                        const SizedBox(height: 20),
                        if (report.hasError)
                          _ErrorCard(
                            message: friendlyErrorMessage(
                              report.error.toString(),
                            ),
                            details: report.error.toString(),
                            onRetry: () => _refresh(ref),
                          ),
                        if (overview != null) ...[
                          _ProjectQuickStats(overview: overview),
                          const SizedBox(height: 20),
                          _ProjectFeatureGrid(
                            overview: overview,
                            isGeneratingBrief:
                                _isCurrentSummaryState(overview) &&
                                _isGeneratingExecutiveSummary,
                            briefError: _isCurrentSummaryState(overview)
                                ? _executiveSummaryError
                                : null,
                            onBriefTap: () => _openPage(
                              context,
                              _ProjectBriefPage(
                                overview: overview,
                                isGenerating:
                                    _isCurrentSummaryState(overview) &&
                                    _isGeneratingExecutiveSummary,
                                error: _isCurrentSummaryState(overview)
                                    ? _executiveSummaryError
                                    : null,
                                onGenerate: () =>
                                    _generateExecutiveSummary(overview),
                              ),
                            ),
                            onStartHereTap: () => _openPage(
                              context,
                              _ProjectStartHerePage(overview: overview),
                            ),
                            onPRsTap: () => _openPage(
                              context,
                              _ProjectPRPage(
                                overview: overview,
                                onOpenLink: (url) =>
                                    _openExternal(context, url),
                              ),
                            ),
                            onIssuesTap: () => _openPage(
                              context,
                              _ProjectIssuePage(
                                overview: overview,
                                onOpenLink: (url) =>
                                    _openExternal(context, url),
                              ),
                            ),
                            onTeamTap: () => _openPage(
                              context,
                              _ProjectTeamPage(
                                overview: overview,
                                onOpenLink: (url) =>
                                    _openExternal(context, url),
                              ),
                            ),
                            onReleasesTap: () => _openPage(
                              context,
                              _ProjectReleasesPage(
                                overview: overview,
                                onOpenLink: (url) =>
                                    _openExternal(context, url),
                                onPreviewPdf: canExport
                                    ? () => _exportReport(
                                        context: context,
                                        overview: overview,
                                        repo: selectedRepo,
                                        action: _ProjectExportAction.previewPdf,
                                      )
                                    : null,
                                onSharePdf: canExport
                                    ? () => _exportReport(
                                        context: context,
                                        overview: overview,
                                        repo: selectedRepo,
                                        action: _ProjectExportAction.sharePdf,
                                      )
                                    : null,
                                isExporting: isExporting,
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ── Hero Card ─────────────────────────────────────────────────────────────────

Color _healthAccent(String? health, Color fallback) {
  if (health == null) return fallback;
  final h = health.toLowerCase();
  if (h.contains('healthy') || h.contains('active') || h.contains('strong')) {
    return const Color(0xFF22C55E);
  }
  if (h.contains('risk') || h.contains('stall') || h.contains('slow')) {
    return const Color(0xFFF97316);
  }
  if (h.contains('inactive') || h.contains('critical')) {
    return const Color(0xFFDC2626);
  }
  return fallback;
}

class _ProjectHeroCard extends StatelessWidget {
  const _ProjectHeroCard({
    required this.repos,
    required this.selectedRepo,
    required this.selectedWindow,
    required this.isLoading,
    required this.overview,
    required this.onSelectRepo,
    required this.onSelectWindow,
    required this.onRefresh,
  });

  final List<dynamic> repos;
  final dynamic selectedRepo;
  final ProjectWindow selectedWindow;
  final bool isLoading;
  final ProjectOverview? overview;
  final ValueChanged<String> onSelectRepo;
  final ValueChanged<ProjectWindow> onSelectWindow;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _healthAccent(overview?.healthLabel, theme.colorScheme.primary);
    final repoName =
        (selectedRepo['full_name'] ?? selectedRepo['name']).toString();
    final description = (selectedRepo['description'] ?? '').toString().trim();
    final isPrivate = selectedRepo['private'] == true;

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
        border: Border.all(color: accent.withValues(alpha: 0.2)),
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
                    Icons.folder_special_rounded,
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
                        overview?.healthLabel ?? 'Loading…',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                      Text(
                        repoName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
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
                        isPrivate ? 'PRIVATE' : 'PUBLIC',
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
            if (overview != null)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _StatChip(
                      label: 'Branch',
                      value: overview!.branch,
                      icon: Icons.call_split_rounded,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: 'Momentum',
                      value: overview!.momentumLabel,
                      icon: Icons.trending_up_rounded,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: 'Window',
                      value: overview!.window.longLabel,
                      icon: Icons.date_range_rounded,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: 'Updated',
                      value: _formatRelative(overview!.generatedAt.toLocal()),
                      icon: Icons.schedule_rounded,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: repoName,
                      borderRadius: BorderRadius.circular(12),
                      items: repos.map((repo) {
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
                        if (value != null) onSelectRepo(value);
                      },
                    ),
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ProjectWindow.values.map((window) {
                  final selected = selectedWindow == window;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(window.longLabel),
                      selected: selected,
                      onSelected: (_) => onSelectWindow(window),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick Stats Row ────────────────────────────────────────────────────────────

class _ProjectQuickStats extends StatelessWidget {
  const _ProjectQuickStats({required this.overview});

  final ProjectOverview overview;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.commit_rounded,
            label: 'Commits',
            value: overview.stats.commitCount.toString(),
            color: const Color(0xFF3B82F6),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.call_split_rounded,
            label: 'Open PRs',
            value: overview.stats.openPrCount.toString(),
            color: const Color(0xFFEC4899),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.merge_type_rounded,
            label: 'Merged',
            value: overview.stats.mergedPrCount.toString(),
            color: const Color(0xFF22C55E),
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
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        ],
      ),
    );
  }
}

// ── Feature Grid ──────────────────────────────────────────────────────────────

class _ProjectFeatureGrid extends StatelessWidget {
  const _ProjectFeatureGrid({
    required this.overview,
    required this.isGeneratingBrief,
    required this.briefError,
    required this.onBriefTap,
    required this.onStartHereTap,
    required this.onPRsTap,
    required this.onIssuesTap,
    required this.onTeamTap,
    required this.onReleasesTap,
  });

  final ProjectOverview overview;
  final bool isGeneratingBrief;
  final String? briefError;
  final VoidCallback onBriefTap;
  final VoidCallback onStartHereTap;
  final VoidCallback onPRsTap;
  final VoidCallback onIssuesTap;
  final VoidCallback onTeamTap;
  final VoidCallback onReleasesTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Dashboard',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              letterSpacing: 0.3,
            ),
          ),
        ),
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _ProjectFeatureCard(
                    icon: Icons.auto_awesome_rounded,
                    title: 'AI Brief',
                    description: overview.summaryUsedAI
                        ? 'AI summary ready'
                        : isGeneratingBrief
                        ? 'Generating…'
                        : 'On demand',
                    accentColor: const Color(0xFF8B5CF6),
                    onTap: onBriefTap,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProjectFeatureCard(
                    icon: Icons.flag_rounded,
                    title: 'Start Here',
                    description:
                        '${overview.highlights.length + overview.risks.length + overview.nextActions.length} signals',
                    accentColor: const Color(0xFF0F766E),
                    onTap: onStartHereTap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ProjectFeatureCard(
                    icon: Icons.call_merge_rounded,
                    title: 'PR Queue',
                    description:
                        '${overview.openPullRequests.length} open · ${overview.mergedPullRequests.length} merged',
                    accentColor: const Color(0xFF3B82F6),
                    onTap: onPRsTap,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProjectFeatureCard(
                    icon: Icons.bug_report_rounded,
                    title: 'Issues',
                    description:
                        '${overview.openedIssues.length} opened · ${overview.closedIssues.length} closed',
                    accentColor: const Color(0xFFB45309),
                    onTap: onIssuesTap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ProjectFeatureCard(
                    icon: Icons.people_rounded,
                    title: 'Team',
                    description:
                        '${overview.contributors.length} contributor${overview.contributors.length == 1 ? '' : 's'}',
                    accentColor: const Color(0xFF06B6D4),
                    onTap: onTeamTap,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProjectFeatureCard(
                    icon: Icons.rocket_launch_rounded,
                    title: 'Releases',
                    description: overview.releases.isNotEmpty
                        ? '${overview.releases.length} recent'
                        : 'Failures & exports',
                    accentColor: const Color(0xFF6366F1),
                    onTap: onReleasesTap,
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

class _ProjectFeatureCard extends StatefulWidget {
  const _ProjectFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  State<_ProjectFeatureCard> createState() => _ProjectFeatureCardState();
}

class _ProjectFeatureCardState extends State<_ProjectFeatureCard> {
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
              color: _isHovered
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

// ── Sub-pages ─────────────────────────────────────────────────────────────────

class _ProjectBriefPage extends StatelessWidget {
  const _ProjectBriefPage({
    required this.overview,
    required this.isGenerating,
    required this.error,
    required this.onGenerate,
  });

  final ProjectOverview overview;
  final bool isGenerating;
  final String? error;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const SlashText('AI Brief', fontWeight: FontWeight.w700),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _SectionCard(
            title: 'Executive Brief',
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(
                  label: overview.summaryUsedAI ? 'AI summary' : 'On demand',
                ),
                FilledButton.tonalIcon(
                  onPressed: isGenerating ? null : onGenerate,
                  label: Text(overview.summaryUsedAI ? 'Regenerate' : 'Generate'),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overview.summaryUsedAI)
                  Text(
                    overview.executiveSummary,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  )
                else if (isGenerating)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Expanded(child: Text('Generating summary…')),
                      ],
                    ),
                  )
                else
                  Text(
                    'Tap Generate for an AI-powered summary of delivery, risks, and next steps.',
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                if (overview.summaryUsedAI && overview.codeSummary.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Divider(color: theme.dividerColor.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.code_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'What Changed in the Codebase',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    overview.codeSummary,
                    style:
                        theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                ],
                if ((error ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
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
        ],
      ),
    );
  }
}

class _ProjectStartHerePage extends StatelessWidget {
  const _ProjectStartHerePage({required this.overview});

  final ProjectOverview overview;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Start Here', fontWeight: FontWeight.w700),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _StartHereCard(overview: overview),
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
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectPRPage extends StatelessWidget {
  const _ProjectPRPage({
    required this.overview,
    required this.onOpenLink,
  });

  final ProjectOverview overview;
  final Future<void> Function(String? url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SlashText('PR Queue', fontWeight: FontWeight.w700),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
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
        ],
      ),
    );
  }
}

class _ProjectIssuePage extends StatelessWidget {
  const _ProjectIssuePage({
    required this.overview,
    required this.onOpenLink,
  });

  final ProjectOverview overview;
  final Future<void> Function(String? url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Issues', fontWeight: FontWeight.w700),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
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
        ],
      ),
    );
  }
}

class _ProjectTeamPage extends StatelessWidget {
  const _ProjectTeamPage({
    required this.overview,
    required this.onOpenLink,
  });

  final ProjectOverview overview;
  final Future<void> Function(String? url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Team', fontWeight: FontWeight.w700),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          if (overview.contributors.isNotEmpty) ...[
            _SectionCard(
              title: 'Team Activity',
              child: Column(
                children: overview.contributors
                    .map((item) =>
                        _ContributorRow(item: item, overview: overview))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _SectionCard(
            title: 'Timeline',
            child: _TimelineList(
              items: overview.timeline,
              onOpenLink: onOpenLink,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectReleasesPage extends StatelessWidget {
  const _ProjectReleasesPage({
    required this.overview,
    required this.onOpenLink,
    required this.isExporting,
    required this.onPreviewPdf,
    required this.onSharePdf,
  });

  final ProjectOverview overview;
  final Future<void> Function(String? url) onOpenLink;
  final bool isExporting;
  final VoidCallback? onPreviewPdf;
  final VoidCallback? onSharePdf;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Releases', fontWeight: FontWeight.w700),
        actions: [
          if (onPreviewPdf != null || onSharePdf != null)
            PopupMenuButton<String>(
              enabled: !isExporting,
              onSelected: (v) {
                if (v == 'preview') onPreviewPdf?.call();
                if (v == 'share') onSharePdf?.call();
              },
              itemBuilder: (_) => [
                if (onPreviewPdf != null)
                  const PopupMenuItem(
                    value: 'preview',
                    child: Text('Preview PDF'),
                  ),
                if (onSharePdf != null)
                  const PopupMenuItem(
                    value: 'share',
                    child: Text('Share PDF'),
                  ),
              ],
              child: isExporting
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  : const Icon(Icons.more_vert_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          if (overview.releases.isNotEmpty) ...[
            _SectionCard(
              title: 'Recent Releases',
              child: _ReportList(
                items: overview.releases,
                emptyLabel: 'No recent releases.',
                onOpenLink: onOpenLink,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _SectionCard(
            title: 'Workflow Failures',
            child: _ReportList(
              items: overview.workflowFailures,
              emptyLabel: 'No failed workflow runs in this window.',
              onOpenLink: onOpenLink,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _StartHereCard extends StatelessWidget {
  const _StartHereCard({required this.overview});

  final ProjectOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets = <_PriorityBucketData>[
      _PriorityBucketData(
        title: 'What Changed',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF0F766E),
        items: overview.highlights.isNotEmpty
            ? overview.highlights.take(2).toList()
            : ['Recent delivery signals will surface here.'],
      ),
      _PriorityBucketData(
        title: 'Watch Closely',
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFB45309),
        items: overview.risks.isNotEmpty
            ? overview.risks.take(2).toList()
            : ['No major risks were flagged in this window.'],
      ),
      _PriorityBucketData(
        title: 'Do Next',
        icon: Icons.task_alt_rounded,
        color: theme.colorScheme.primary,
        items: overview.nextActions.isNotEmpty
            ? overview.nextActions.take(2).toList()
            : ['No immediate follow-up actions are suggested right now.'],
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 960
                  ? 3
                  : width >= 620
                  ? 2
                  : 1;
              final totalSpacing = 12.0 * (columns - 1);
              final cardWidth = (width - totalSpacing) / columns;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: buckets.map((bucket) {
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
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.7),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final stackHeader = trailing != null && constraints.maxWidth < 420;
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
  const _ReportList({
    required this.items,
    required this.emptyLabel,
    required this.onOpenLink,
  });

  final List<ProjectReportItem> items;
  final String emptyLabel;
  final Future<void> Function(String? url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Text(emptyLabel, style: theme.textTheme.bodyMedium);
    }
    return Column(
      children: items.map((item) {
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
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  item.number == null
                                      ? '•'
                                      : '#${item.number}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: theme.textTheme.bodyLarge?.copyWith(
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
  const _TimelineList({required this.items, required this.onOpenLink});

  final List<ProjectTimelineEntry> items;
  final Future<void> Function(String? url) onOpenLink;

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
      children: items.map((item) {
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
  const _BulletList({
    required this.items,
    required this.icon,
    required this.color,
  });

  final List<String> items;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) {
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
                  style:
                      theme.textTheme.bodyMedium?.copyWith(height: 1.45),
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
  const _ContributorRow({
    required this.item,
    required this.overview,
  });

  final ProjectContributor item;
  final ProjectOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxCommits =
        overview.contributors.isEmpty ? 1 : overview.contributors.first.commitCount;
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    this.details,
    required this.onRetry,
  });

  final String message;
  final String? details;
  final Future<void> Function() onRetry;

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
          if ((details ?? '').trim().isNotEmpty &&
              details!.trim() != message.trim()) ...[
            const SizedBox(height: 10),
            SelectableText(
              details!.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.78),
              ),
            ),
          ],
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
  const _InfoPill({required this.label});

  final String label;

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
        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MiniSectionTitle extends StatelessWidget {
  const _MiniSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 7,
                  letterSpacing: 0.2,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
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

class _PriorityBucket extends StatelessWidget {
  const _PriorityBucket({required this.data});

  final _PriorityBucketData data;

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
                      style:
                          theme.textTheme.bodyMedium?.copyWith(height: 1.4),
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

class _PriorityBucketData {
  const _PriorityBucketData({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatRelative(DateTime time) {
  final delta = DateTime.now().difference(time);
  if (delta.inSeconds < 10) return 'just now';
  if (delta.inMinutes < 1) return '${delta.inSeconds}s ago';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

String _formatAbsolute(DateTime time) {
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = time.toLocal();
  final month = months[local.month - 1];
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month ${local.day}, ${local.hour}:$minute';
}
