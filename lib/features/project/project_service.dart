import 'dart:convert';

import '../../services/github_service.dart';
import '../prompt/prompt_service.dart' as prompt_service;

enum ProjectWindow { oneDay, sevenDays }

extension ProjectWindowX on ProjectWindow {
  int get days => this == ProjectWindow.oneDay ? 1 : 7;

  String get label => this == ProjectWindow.oneDay ? '24h' : '7d';

  String get longLabel =>
      this == ProjectWindow.oneDay ? 'Last 24 Hours' : 'Last 7 Days';
}

class ProjectStats {
  final int commitCount;
  final int mergedPrCount;
  final int openPrCount;
  final int draftPrCount;
  final int stalePrCount;
  final int openedIssueCount;
  final int closedIssueCount;
  final int openIssueCount;
  final int failedRunCount;
  final int successfulRunCount;
  final int releaseCount;

  const ProjectStats({
    required this.commitCount,
    required this.mergedPrCount,
    required this.openPrCount,
    required this.draftPrCount,
    required this.stalePrCount,
    required this.openedIssueCount,
    required this.closedIssueCount,
    required this.openIssueCount,
    required this.failedRunCount,
    required this.successfulRunCount,
    required this.releaseCount,
  });
}

class ProjectReportItem {
  final int? number;
  final String title;
  final String subtitle;
  final String? actor;
  final String? url;
  final DateTime? timestamp;
  final String? status;
  final bool isDraft;

  const ProjectReportItem({
    required this.title,
    required this.subtitle,
    this.number,
    this.actor,
    this.url,
    this.timestamp,
    this.status,
    this.isDraft = false,
  });
}

class ProjectContributor {
  final String name;
  final int commitCount;

  const ProjectContributor({required this.name, required this.commitCount});
}

class ProjectTimelineEntry {
  final String kind;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final String? url;

  const ProjectTimelineEntry({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.url,
  });
}

class ProjectOverview {
  final String repoFullName;
  final String branch;
  final ProjectWindow window;
  final DateTime since;
  final DateTime generatedAt;
  final String healthLabel;
  final String momentumLabel;
  final String executiveSummary;
  final String engineeringSummary;
  final List<String> highlights;
  final List<String> risks;
  final List<String> nextActions;
  final List<ProjectReportItem> mergedPullRequests;
  final List<ProjectReportItem> openPullRequests;
  final List<ProjectReportItem> openedIssues;
  final List<ProjectReportItem> closedIssues;
  final List<ProjectReportItem> releases;
  final List<ProjectReportItem> workflowFailures;
  final List<ProjectContributor> contributors;
  final List<ProjectTimelineEntry> timeline;
  final ProjectStats stats;
  final bool summaryUsedAI;

  const ProjectOverview({
    required this.repoFullName,
    required this.branch,
    required this.window,
    required this.since,
    required this.generatedAt,
    required this.healthLabel,
    required this.momentumLabel,
    required this.executiveSummary,
    required this.engineeringSummary,
    required this.highlights,
    required this.risks,
    required this.nextActions,
    required this.mergedPullRequests,
    required this.openPullRequests,
    required this.openedIssues,
    required this.closedIssues,
    required this.releases,
    required this.workflowFailures,
    required this.contributors,
    required this.timeline,
    required this.stats,
    required this.summaryUsedAI,
  });
}

class ProjectInsightsService {
  static Future<ProjectOverview> load({
    required dynamic repo,
    required ProjectWindow window,
    required String githubAccessToken,
    required String model,
    String? openAIApiKey,
    String? openAIModel,
    String? openRouterApiKey,
    String? openRouterModel,
  }) async {
    final owner = (repo['owner']?['login'] ?? '').toString();
    final repoName = (repo['name'] ?? '').toString();
    final repoFullName =
        (repo['full_name'] ?? '$owner/$repoName').toString().trim();
    final branch = (repo['default_branch'] ?? 'main').toString();
    if (owner.isEmpty || repoName.isEmpty) {
      throw Exception('Repository metadata is missing.');
    }

    final github = GitHubService(githubAccessToken);
    final now = DateTime.now().toUtc();
    final since = now.subtract(Duration(days: window.days));
    final staleThreshold = now.subtract(
      Duration(days: window == ProjectWindow.oneDay ? 2 : 5),
    );
    final sinceLabel = _dateOnly(since);

    final commitsFuture = github.fetchCommits(
      owner: owner,
      repo: repoName,
      branch: branch,
      since: since,
      perPage: 100,
    );
    final mergedPrsFuture = github.searchIssuesAndPullRequests(
      query: 'repo:$repoFullName is:pr is:merged merged:>=$sinceLabel',
      sort: 'updated',
      order: 'desc',
      perPage: 10,
    );
    final openPrSearchFuture = github.searchIssuesAndPullRequests(
      query: 'repo:$repoFullName is:pr is:open',
      sort: 'updated',
      order: 'desc',
      perPage: 10,
    );
    final openPrsFuture = github.fetchPullRequests(
      owner: owner,
      repo: repoName,
      state: 'open',
      sort: 'updated',
      direction: 'desc',
      base: branch,
      perPage: 30,
    );
    final openedIssuesFuture = github.searchIssuesAndPullRequests(
      query: 'repo:$repoFullName is:issue created:>=$sinceLabel',
      sort: 'created',
      order: 'desc',
      perPage: 10,
    );
    final closedIssuesFuture = github.searchIssuesAndPullRequests(
      query: 'repo:$repoFullName is:issue closed:>=$sinceLabel',
      sort: 'updated',
      order: 'desc',
      perPage: 10,
    );
    final workflowRunsFuture = github.fetchWorkflowRuns(
      owner: owner,
      repo: repoName,
      branch: branch,
      perPage: 30,
    );
    final releasesFuture = github.fetchReleases(
      owner: owner,
      repo: repoName,
      perPage: 10,
    );

    final commits = await commitsFuture;
    final mergedPrSearch = await mergedPrsFuture;
    final openPrSearch = await openPrSearchFuture;
    final openPrs = await openPrsFuture;
    final openedIssuesSearch = await openedIssuesFuture;
    final closedIssuesSearch = await closedIssuesFuture;
    final workflowRuns = await workflowRunsFuture;
    final releases = await releasesFuture;

    final contributors = _buildContributorList(commits);
    final mergedPullRequests =
        mergedPrSearch.items.map(_mapIssueLikeItem).take(5).toList();
    final openPullRequests =
        openPrs
            .map(_mapPullRequestItem)
            .whereType<ProjectReportItem>()
            .take(5)
            .toList();
    final openedIssues =
        openedIssuesSearch.items.map(_mapIssueLikeItem).take(5).toList();
    final closedIssues =
        closedIssuesSearch.items.map(_mapIssueLikeItem).take(5).toList();
    final releaseItems =
        releases
            .where((item) {
              final publishedAt = _parseDate(item['published_at']);
              return publishedAt != null && !publishedAt.isBefore(since);
            })
            .map(_mapReleaseItem)
            .take(5)
            .toList();

    final filteredWorkflowRuns =
        workflowRuns.where((item) {
          final createdAt =
              _parseDate(item['created_at']) ?? _parseDate(item['updated_at']);
          return createdAt != null && !createdAt.isBefore(since);
        }).toList();

    final workflowFailures =
        filteredWorkflowRuns
            .where((item) => _isWorkflowFailure(item['conclusion']))
            .map(_mapWorkflowRunItem)
            .take(5)
            .toList();

    final failedRunCount =
        filteredWorkflowRuns
            .where((item) => _isWorkflowFailure(item['conclusion']))
            .length;
    final successfulRunCount =
        filteredWorkflowRuns
            .where((item) => (item['conclusion'] ?? '').toString() == 'success')
            .length;
    final stalePrCount =
        openPrs.where((item) {
          final updatedAt = _parseDate(item['updated_at']);
          return updatedAt != null && updatedAt.isBefore(staleThreshold);
        }).length;
    final draftPrCount = openPrs.where((item) => item['draft'] == true).length;
    final openPrCount = openPrSearch.totalCount;
    final openIssueCountEstimate = _estimateOpenIssueCount(repo, openPrCount);

    final stats = ProjectStats(
      commitCount: commits.length,
      mergedPrCount: mergedPrSearch.totalCount,
      openPrCount: openPrCount,
      draftPrCount: draftPrCount,
      stalePrCount: stalePrCount,
      openedIssueCount: openedIssuesSearch.totalCount,
      closedIssueCount: closedIssuesSearch.totalCount,
      openIssueCount: openIssueCountEstimate,
      failedRunCount: failedRunCount,
      successfulRunCount: successfulRunCount,
      releaseCount: releaseItems.length,
    );

    final highlights = _buildHighlights(
      branch: branch,
      stats: stats,
      contributors: contributors,
      mergedPullRequests: mergedPullRequests,
      releases: releaseItems,
    );
    final risks = _buildRisks(stats);
    final nextActions = _buildNextActions(stats);
    final healthLabel = _healthLabel(stats);
    final momentumLabel = _momentumLabel(stats);
    final engineeringSummary = _engineeringSummary(
      branch: branch,
      window: window,
      stats: stats,
      contributors: contributors,
    );
    final narrative = await _generateNarrative(
      repoFullName: repoFullName,
      branch: branch,
      window: window,
      stats: stats,
      contributors: contributors,
      mergedPullRequests: mergedPullRequests,
      openPullRequests: openPullRequests,
      openedIssues: openedIssues,
      closedIssues: closedIssues,
      workflowFailures: workflowFailures,
      releases: releaseItems,
      model: model,
      openAIApiKey: openAIApiKey,
      openAIModel: openAIModel,
      openRouterApiKey: openRouterApiKey,
      openRouterModel: openRouterModel,
      fallbackExecutiveSummary: _heuristicExecutiveSummary(
        repoFullName: repoFullName,
        window: window,
        stats: stats,
        healthLabel: healthLabel,
        momentumLabel: momentumLabel,
      ),
      fallbackHighlights: highlights,
      fallbackRisks: risks,
      fallbackNextActions: nextActions,
      fallbackEngineeringSummary: engineeringSummary,
    );

    return ProjectOverview(
      repoFullName: repoFullName,
      branch: branch,
      window: window,
      since: since,
      generatedAt: now,
      healthLabel: healthLabel,
      momentumLabel: momentumLabel,
      executiveSummary: narrative.executiveSummary,
      engineeringSummary: narrative.engineeringSummary,
      highlights: narrative.highlights,
      risks: narrative.risks,
      nextActions: narrative.nextActions,
      mergedPullRequests: mergedPullRequests,
      openPullRequests: openPullRequests,
      openedIssues: openedIssues,
      closedIssues: closedIssues,
      releases: releaseItems,
      workflowFailures: workflowFailures,
      contributors: contributors,
      timeline: _buildTimeline(
        commits: commits,
        mergedPullRequests: mergedPullRequests,
        openedIssues: openedIssues,
        closedIssues: closedIssues,
        workflowFailures: workflowFailures,
        releases: releaseItems,
      ),
      stats: stats,
      summaryUsedAI: narrative.usedAI,
    );
  }

  static Future<_ProjectNarrative> _generateNarrative({
    required String repoFullName,
    required String branch,
    required ProjectWindow window,
    required ProjectStats stats,
    required List<ProjectContributor> contributors,
    required List<ProjectReportItem> mergedPullRequests,
    required List<ProjectReportItem> openPullRequests,
    required List<ProjectReportItem> openedIssues,
    required List<ProjectReportItem> closedIssues,
    required List<ProjectReportItem> workflowFailures,
    required List<ProjectReportItem> releases,
    required String model,
    required String? openAIApiKey,
    required String? openAIModel,
    required String? openRouterApiKey,
    required String? openRouterModel,
    required String fallbackExecutiveSummary,
    required String fallbackEngineeringSummary,
    required List<String> fallbackHighlights,
    required List<String> fallbackRisks,
    required List<String> fallbackNextActions,
  }) async {
    try {
      final aiService = prompt_service.PromptService.createAIService(
        model: model,
        openAIApiKey: openAIApiKey,
        openAIModel: openAIModel,
        openRouterApiKey: openRouterApiKey,
        openRouterModel: openRouterModel,
      );

      final facts = {
        'repository': repoFullName,
        'branch': branch,
        'window': window.longLabel,
        'stats': {
          'commits': stats.commitCount,
          'merged_prs': stats.mergedPrCount,
          'open_prs': stats.openPrCount,
          'draft_prs': stats.draftPrCount,
          'stale_prs': stats.stalePrCount,
          'opened_issues': stats.openedIssueCount,
          'closed_issues': stats.closedIssueCount,
          'open_issues': stats.openIssueCount,
          'failed_runs': stats.failedRunCount,
          'successful_runs': stats.successfulRunCount,
          'releases': stats.releaseCount,
        },
        'contributors':
            contributors
                .take(5)
                .map((item) => {'name': item.name, 'commits': item.commitCount})
                .toList(),
        'merged_prs':
            mergedPullRequests
                .take(4)
                .map((item) => _compactItem(item))
                .toList(),
        'open_prs':
            openPullRequests.take(4).map((item) => _compactItem(item)).toList(),
        'opened_issues':
            openedIssues.take(4).map((item) => _compactItem(item)).toList(),
        'closed_issues':
            closedIssues.take(4).map((item) => _compactItem(item)).toList(),
        'workflow_failures':
            workflowFailures.take(4).map((item) => _compactItem(item)).toList(),
        'releases': releases.take(3).map((item) => _compactItem(item)).toList(),
      };

      final raw = await aiService.chat(
        messages: [
          {
            'role': 'system',
            'content':
                'You are /slash project monitor. Summarize repository activity '
                'for an engineering lead or founder. Use only the provided facts. '
                'Do not invent metrics, events, or confidence. Return valid JSON only '
                'with keys executive_summary, engineering_summary, highlights, risks, next_actions. '
                'Each array must contain 2 to 5 concise strings.',
          },
          {'role': 'user', 'content': jsonEncode(facts)},
        ],
        maxTokens: 900,
        temperature: 0.2,
      );

      final cleaned = prompt_service.stripCodeFences(raw);
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected summary format.');
      }

      final executiveSummary =
          (decoded['executive_summary'] ?? '').toString().trim();
      final engineeringSummary =
          (decoded['engineering_summary'] ?? '').toString().trim();
      final highlights = _stringList(decoded['highlights']);
      final risks = _stringList(decoded['risks']);
      final nextActions = _stringList(decoded['next_actions']);

      if (executiveSummary.isEmpty ||
          engineeringSummary.isEmpty ||
          highlights.isEmpty ||
          risks.isEmpty ||
          nextActions.isEmpty) {
        throw const FormatException('Summary JSON missing required fields.');
      }

      return _ProjectNarrative(
        executiveSummary: executiveSummary,
        engineeringSummary: engineeringSummary,
        highlights: highlights,
        risks: risks,
        nextActions: nextActions,
        usedAI: true,
      );
    } catch (_) {
      return _ProjectNarrative(
        executiveSummary: fallbackExecutiveSummary,
        engineeringSummary: fallbackEngineeringSummary,
        highlights: fallbackHighlights,
        risks: fallbackRisks,
        nextActions: fallbackNextActions,
        usedAI: false,
      );
    }
  }

  static List<ProjectContributor> _buildContributorList(
    List<Map<String, dynamic>> commits,
  ) {
    final counts = <String, int>{};
    for (final commit in commits) {
      final author =
          (commit['author']?['login'] ??
                  commit['commit']?['author']?['name'] ??
                  'unknown')
              .toString();
      counts.update(author, (value) => value + 1, ifAbsent: () => 1);
    }

    final entries =
        counts.entries.toList()..sort((left, right) {
          final countDelta = right.value.compareTo(left.value);
          if (countDelta != 0) {
            return countDelta;
          }
          return left.key.compareTo(right.key);
        });

    return entries
        .take(5)
        .map(
          (entry) =>
              ProjectContributor(name: entry.key, commitCount: entry.value),
        )
        .toList();
  }

  static List<ProjectTimelineEntry> _buildTimeline({
    required List<Map<String, dynamic>> commits,
    required List<ProjectReportItem> mergedPullRequests,
    required List<ProjectReportItem> openedIssues,
    required List<ProjectReportItem> closedIssues,
    required List<ProjectReportItem> workflowFailures,
    required List<ProjectReportItem> releases,
  }) {
    final entries = <ProjectTimelineEntry>[
      for (final release in releases)
        if (release.timestamp != null)
          ProjectTimelineEntry(
            kind: 'Release',
            title: release.title,
            subtitle: release.subtitle,
            timestamp: release.timestamp!,
            url: release.url,
          ),
      for (final pr in mergedPullRequests)
        if (pr.timestamp != null)
          ProjectTimelineEntry(
            kind: 'PR merged',
            title: pr.title,
            subtitle: pr.subtitle,
            timestamp: pr.timestamp!,
            url: pr.url,
          ),
      for (final issue in openedIssues)
        if (issue.timestamp != null)
          ProjectTimelineEntry(
            kind: 'Issue opened',
            title: issue.title,
            subtitle: issue.subtitle,
            timestamp: issue.timestamp!,
            url: issue.url,
          ),
      for (final issue in closedIssues)
        if (issue.timestamp != null)
          ProjectTimelineEntry(
            kind: 'Issue closed',
            title: issue.title,
            subtitle: issue.subtitle,
            timestamp: issue.timestamp!,
            url: issue.url,
          ),
      for (final run in workflowFailures)
        if (run.timestamp != null)
          ProjectTimelineEntry(
            kind: 'CI failure',
            title: run.title,
            subtitle: run.subtitle,
            timestamp: run.timestamp!,
            url: run.url,
          ),
      for (final commit in commits.take(8))
        if (_parseDate(commit['commit']?['author']?['date']) != null)
          ProjectTimelineEntry(
            kind: 'Commit',
            title:
                ((commit['commit']?['message'] ?? '')
                        .toString()
                        .split('\n')
                        .first)
                    .trim(),
            subtitle:
                '${(commit['author']?['login'] ?? commit['commit']?['author']?['name'] ?? 'unknown').toString()} • ${_shortSha((commit['sha'] ?? '').toString())}',
            timestamp: _parseDate(commit['commit']?['author']?['date'])!,
            url: (commit['html_url'] ?? '').toString(),
          ),
    ];

    entries.sort((left, right) => right.timestamp.compareTo(left.timestamp));
    return entries.take(16).toList();
  }

  static ProjectReportItem _mapIssueLikeItem(Map<String, dynamic> item) {
    final number = (item['number'] as num?)?.toInt();
    final actor = (item['user']?['login'] ?? '').toString().trim();
    final timestamp =
        _parseDate(item['closed_at']) ??
        _parseDate(item['created_at']) ??
        _parseDate(item['updated_at']);

    return ProjectReportItem(
      number: number,
      title: (item['title'] ?? 'Untitled').toString(),
      subtitle:
          '${actor.isEmpty ? 'unknown' : actor} • ${_formatDateTime(timestamp)}',
      actor: actor.isEmpty ? null : actor,
      url: (item['html_url'] ?? '').toString(),
      timestamp: timestamp,
      status: (item['state'] ?? '').toString(),
    );
  }

  static ProjectReportItem? _mapPullRequestItem(Map<String, dynamic> item) {
    final timestamp =
        _parseDate(item['updated_at']) ??
        _parseDate(item['created_at']) ??
        _parseDate(item['closed_at']);
    if (timestamp == null) {
      return null;
    }

    final actor = (item['user']?['login'] ?? '').toString().trim();
    final branch = (item['head']?['ref'] ?? '').toString().trim();
    final draft = item['draft'] == true;
    final subtitleParts = <String>[
      if (actor.isNotEmpty) actor,
      if (branch.isNotEmpty) branch,
      _formatDateTime(timestamp),
    ];

    return ProjectReportItem(
      number: (item['number'] as num?)?.toInt(),
      title: (item['title'] ?? 'Untitled').toString(),
      subtitle: subtitleParts.join(' • '),
      actor: actor.isEmpty ? null : actor,
      url: (item['html_url'] ?? '').toString(),
      timestamp: timestamp,
      status: draft ? 'draft' : 'open',
      isDraft: draft,
    );
  }

  static ProjectReportItem _mapReleaseItem(Map<String, dynamic> item) {
    final timestamp =
        _parseDate(item['published_at']) ?? _parseDate(item['created_at']);
    final tag = (item['tag_name'] ?? '').toString().trim();
    final prerelease = item['prerelease'] == true;
    return ProjectReportItem(
      title: (item['name'] ?? tag.ifEmpty('Untitled release')).toString(),
      subtitle:
          '${tag.ifEmpty('release')} • ${_formatDateTime(timestamp)}${prerelease ? ' • prerelease' : ''}',
      actor: (item['author']?['login'] ?? '').toString(),
      url: (item['html_url'] ?? '').toString(),
      timestamp: timestamp,
      status: prerelease ? 'prerelease' : 'release',
    );
  }

  static ProjectReportItem _mapWorkflowRunItem(Map<String, dynamic> item) {
    final timestamp =
        _parseDate(item['updated_at']) ?? _parseDate(item['created_at']);
    final branch = (item['head_branch'] ?? '').toString().trim();
    final conclusion = (item['conclusion'] ?? 'failed').toString().trim();
    return ProjectReportItem(
      title: (item['name'] ?? 'Workflow run').toString(),
      subtitle:
          '${branch.ifEmpty('branch unknown')} • ${conclusion.ifEmpty('failed')} • ${_formatDateTime(timestamp)}',
      actor: (item['actor']?['login'] ?? '').toString(),
      url: (item['html_url'] ?? '').toString(),
      timestamp: timestamp,
      status: conclusion,
    );
  }

  static int _estimateOpenIssueCount(dynamic repo, int openPrCount) {
    final raw = (repo['open_issues_count'] as num?)?.toInt() ?? 0;
    final estimate = raw - openPrCount;
    return estimate < 0 ? 0 : estimate;
  }

  static List<String> _buildHighlights({
    required String branch,
    required ProjectStats stats,
    required List<ProjectContributor> contributors,
    required List<ProjectReportItem> mergedPullRequests,
    required List<ProjectReportItem> releases,
  }) {
    final items = <String>[];
    if (stats.mergedPrCount > 0) {
      final titles = mergedPullRequests
          .take(2)
          .map((item) => item.title)
          .join(' and ');
      items.add(
        stats.mergedPrCount == 1
            ? '1 pull request merged${titles.isEmpty ? '.' : ': $titles.'}'
            : '${stats.mergedPrCount} pull requests merged${titles.isEmpty ? '.' : ', including $titles.'}',
      );
    }
    if (stats.commitCount > 0) {
      final contributorCount = contributors.length;
      items.add(
        '${stats.commitCount} commits landed on $branch from ${contributorCount == 0 ? 'the team' : '$contributorCount contributor${contributorCount == 1 ? '' : 's'}'}.',
      );
    }
    if (stats.closedIssueCount > 0) {
      items.add(
        'Closed ${stats.closedIssueCount} issue${stats.closedIssueCount == 1 ? '' : 's'} in this window.',
      );
    }
    if (releases.isNotEmpty) {
      items.add(
        '${releases.length} release${releases.length == 1 ? '' : 's'} published, latest being ${releases.first.title}.',
      );
    }
    if (stats.failedRunCount == 0 && stats.successfulRunCount > 0) {
      items.add(
        'CI stayed green across ${stats.successfulRunCount} completed workflow run${stats.successfulRunCount == 1 ? '' : 's'}.',
      );
    }
    return items.take(5).toList();
  }

  static List<String> _buildRisks(ProjectStats stats) {
    final items = <String>[];
    if (stats.failedRunCount > 0) {
      items.add(
        '${stats.failedRunCount} workflow run${stats.failedRunCount == 1 ? '' : 's'} failed in this window.',
      );
    }
    if (stats.stalePrCount > 0) {
      items.add(
        '${stats.stalePrCount} open PR${stats.stalePrCount == 1 ? '' : 's'} look stale based on recent updates.',
      );
    }
    if (stats.draftPrCount > 0) {
      items.add(
        '${stats.draftPrCount} open PR${stats.draftPrCount == 1 ? '' : 's'} are still sitting in draft.',
      );
    }
    if (stats.openedIssueCount > stats.closedIssueCount) {
      items.add(
        'Issue intake exceeded closures by ${stats.openedIssueCount - stats.closedIssueCount}.',
      );
    }
    if (stats.commitCount == 0 &&
        stats.mergedPrCount == 0 &&
        stats.releaseCount == 0) {
      items.add('Very little visible delivery activity landed in this window.');
    }
    if (items.isEmpty) {
      items.add('No major delivery risks stood out in the current window.');
    }
    return items.take(5).toList();
  }

  static List<String> _buildNextActions(ProjectStats stats) {
    final items = <String>[];
    if (stats.failedRunCount > 0) {
      items.add('Investigate the latest failing workflow runs and restore CI.');
    }
    if (stats.stalePrCount > 0) {
      items.add(
        'Review stale pull requests and either unblock them or close them.',
      );
    }
    if (stats.openPrCount > 0 && stats.mergedPrCount == 0) {
      items.add(
        'Move at least one open PR toward review or merge to keep flow moving.',
      );
    }
    if (stats.openedIssueCount > stats.closedIssueCount) {
      items.add('Spend the next triage pass reducing net issue growth.');
    }
    if (stats.draftPrCount > 0) {
      items.add(
        'Convert draft PRs into review-ready work or cut scope where needed.',
      );
    }
    if (items.isEmpty) {
      items.add(
        'Delivery looks steady. Keep the branch stable and maintain review cadence.',
      );
    }
    return items.take(5).toList();
  }

  static String _heuristicExecutiveSummary({
    required String repoFullName,
    required ProjectWindow window,
    required ProjectStats stats,
    required String healthLabel,
    required String momentumLabel,
  }) {
    return '$repoFullName showed $momentumLabel momentum over the ${window.longLabel.toLowerCase()}. '
        'The repo recorded ${stats.commitCount} commits, ${stats.mergedPrCount} merged pull requests, '
        '${stats.openedIssueCount} newly opened issues, and ${stats.failedRunCount} failed workflow runs. '
        'Overall health is $healthLabel.';
  }

  static String _engineeringSummary({
    required String branch,
    required ProjectWindow window,
    required ProjectStats stats,
    required List<ProjectContributor> contributors,
  }) {
    final contributorSummary =
        contributors.isEmpty
            ? 'No clear contributor pattern stood out.'
            : 'Top contributors were ${contributors.map((item) => '${item.name} (${item.commitCount})').join(', ')}.';
    return 'Branch $branch in the ${window.longLabel.toLowerCase()} saw '
        '${stats.commitCount} commits, ${stats.mergedPrCount} merged PRs, ${stats.openPrCount} open PRs, '
        '${stats.closedIssueCount} issue closures, and ${stats.failedRunCount == 0 ? 'no failing CI runs' : '${stats.failedRunCount} failing CI runs'}. '
        '$contributorSummary';
  }

  static String _healthLabel(ProjectStats stats) {
    var riskScore = 0;
    if (stats.failedRunCount > 0) {
      riskScore += 2;
    }
    if (stats.stalePrCount > 0) {
      riskScore += 1;
    }
    if (stats.openedIssueCount > stats.closedIssueCount) {
      riskScore += 1;
    }
    if (stats.draftPrCount >= 3) {
      riskScore += 1;
    }

    if (riskScore >= 3) {
      return 'Needs attention';
    }
    if (riskScore >= 1) {
      return 'Watch';
    }
    return 'Healthy';
  }

  static String _momentumLabel(ProjectStats stats) {
    final score =
        stats.commitCount +
        (stats.mergedPrCount * 3) +
        (stats.closedIssueCount * 2) +
        (stats.releaseCount * 4);

    if (score >= 20) {
      return 'high';
    }
    if (score >= 8) {
      return 'steady';
    }
    if (score >= 1) {
      return 'light';
    }
    return 'quiet';
  }

  static List<String> _stringList(dynamic raw) {
    return (raw as List<dynamic>? ?? const <dynamic>[])
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  static Map<String, dynamic> _compactItem(ProjectReportItem item) {
    return {
      if (item.number != null) 'number': item.number,
      'title': item.title,
      'subtitle': item.subtitle,
      if (item.status != null) 'status': item.status,
    };
  }

  static bool _isWorkflowFailure(dynamic conclusion) {
    final value = (conclusion ?? '').toString().trim().toLowerCase();
    if (value.isEmpty) {
      return false;
    }
    return value != 'success' && value != 'neutral' && value != 'skipped';
  }

  static DateTime? _parseDate(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  static String _formatDateTime(DateTime? timestamp) {
    if (timestamp == null) {
      return 'unknown time';
    }
    final local = timestamp.toLocal();
    final month = _monthLabel(local.month);
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month ${local.day}, ${local.hour}:$minute';
  }

  static String _dateOnly(DateTime timestamp) {
    final utc = timestamp.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }

  static String _shortSha(String sha) {
    final trimmed = sha.trim();
    if (trimmed.length <= 7) {
      return trimmed;
    }
    return trimmed.substring(0, 7);
  }

  static String _monthLabel(int month) {
    const labels = <String>[
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
    if (month < 1 || month > 12) {
      return 'Mon';
    }
    return labels[month - 1];
  }
}

class _ProjectNarrative {
  final String executiveSummary;
  final String engineeringSummary;
  final List<String> highlights;
  final List<String> risks;
  final List<String> nextActions;
  final bool usedAI;

  const _ProjectNarrative({
    required this.executiveSummary,
    required this.engineeringSummary,
    required this.highlights,
    required this.risks,
    required this.nextActions,
    required this.usedAI,
  });
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
