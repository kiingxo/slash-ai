import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'project_service.dart';

enum ProjectPdfExportMode { preview, share }

class ProjectPdfService {
  static const String _logoAssetPath = 'assets/slash2.png';
  static const String _fontRegularPath = 'assets/fonts/DMSans-Regular.ttf';
  static const String _fontMediumPath = 'assets/fonts/DMSans-Medium.ttf';
  static const String _fontSemiBoldPath = 'assets/fonts/DMSans-SemiBold.ttf';
  static const String _fontBoldPath = 'assets/fonts/DMSans-Bold.ttf';

  static const PdfColor _accent = PdfColor(0.19, 0.38, 0.82);
  static const PdfColor _teal = PdfColor(0.06, 0.46, 0.43);
  static const PdfColor _amber = PdfColor(0.73, 0.47, 0.08);
  static const PdfColor _rose = PdfColor(0.76, 0.17, 0.22);
  static const PdfColor _pageBg = PdfColor(0.05, 0.07, 0.11);
  static const PdfColor _panelBg = PdfColor(0.10, 0.13, 0.19);
  static const PdfColor _panelStrong = PdfColor(0.13, 0.17, 0.25);
  static const PdfColor _panelBorder = PdfColor(0.18, 0.23, 0.33);
  static const PdfColor _textPrimary = PdfColor(0.96, 0.97, 0.99);
  static const PdfColor _textSecondary = PdfColor(0.73, 0.77, 0.85);

  static Future<_ProjectPdfAssets>? _cachedAssets;

  static Future<void> exportExecutiveSummary({
    required ProjectOverview overview,
    required dynamic repo,
    required ProjectPdfExportMode mode,
  }) async {
    final fileName = _buildFileName(overview);
    if (mode == ProjectPdfExportMode.preview) {
      await Printing.layoutPdf(
        name: fileName,
        onLayout:
            (format) => buildExecutiveSummaryPdf(
              overview: overview,
              repo: repo,
              pageFormat: format,
            ),
      );
      return;
    }

    final bytes = await buildExecutiveSummaryPdf(
      overview: overview,
      repo: repo,
    );
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  static Future<Uint8List> buildExecutiveSummaryPdf({
    required ProjectOverview overview,
    required dynamic repo,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final assets = await _loadAssets();
    final repoDescription = (repo['description'] ?? '').toString().trim();
    final repoLanguage = (repo['language'] ?? '').toString().trim();
    final repoUrl = (repo['html_url'] ?? '').toString().trim();
    final repoStars = _asInt(repo['stargazers_count']);
    final repoForks = _asInt(repo['forks_count']);
    final repoWatchers = _asInt(repo['watchers_count']);
    final repoOpenIssues = _asInt(repo['open_issues_count']);
    final reportStamp = _formatDateTime(overview.generatedAt.toUtc());
    final windowLabel =
        '${_formatDate(overview.since.toUtc())} to ${_formatDate(overview.generatedAt.toUtc())}';

    final theme = pw.ThemeData.withFont(
      base: assets.regular,
      bold: assets.bold,
      italic: assets.medium,
      boldItalic: assets.semiBold,
    );

    final document = pw.Document(
      title: '${overview.repoFullName} Executive Summary',
      author: '/slash',
      creator: '/slash',
      subject: 'Project executive summary for ${overview.repoFullName}',
      keywords: 'slash, project report, executive summary, github, engineering',
    );

    document.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: pageFormat,
          theme: theme,
          margin: pw.EdgeInsets.zero,
        ),
        build:
            (_) => _buildOverviewPage(
              assets: assets,
              overview: overview,
              repoDescription:
                  repoDescription.isEmpty
                      ? 'Executive view of repository activity, delivery velocity, and current risk surface.'
                      : repoDescription,
              repoLanguage: repoLanguage,
              repoUrl: repoUrl,
              repoStars: repoStars,
              repoForks: repoForks,
              repoWatchers: repoWatchers,
              repoOpenIssues: repoOpenIssues,
              windowLabel: windowLabel,
              reportStamp: reportStamp,
            ),
      ),
    );

    document.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: pageFormat,
          theme: theme,
          margin: pw.EdgeInsets.zero,
        ),
        build:
            (_) => _buildExecutionPage(
              assets: assets,
              overview: overview,
              reportStamp: reportStamp,
            ),
      ),
    );

    return document.save();
  }

  static Future<_ProjectPdfAssets> _loadAssets() {
    final cached = _cachedAssets;
    if (cached != null) {
      return cached;
    }

    final future = _createAssets();
    _cachedAssets = future;
    return future.catchError((error) {
      _cachedAssets = null;
      throw error;
    });
  }

  static Future<_ProjectPdfAssets> _createAssets() async {
    final regularData = await rootBundle.load(_fontRegularPath);
    final mediumData = await rootBundle.load(_fontMediumPath);
    final semiBoldData = await rootBundle.load(_fontSemiBoldPath);
    final boldData = await rootBundle.load(_fontBoldPath);
    final logoData = await rootBundle.load(_logoAssetPath);

    return _ProjectPdfAssets(
      regular: pw.Font.ttf(regularData),
      medium: pw.Font.ttf(mediumData),
      semiBold: pw.Font.ttf(semiBoldData),
      bold: pw.Font.ttf(boldData),
      logo: pw.MemoryImage(_toBytes(logoData)),
    );
  }

  static pw.Widget _buildOverviewPage({
    required _ProjectPdfAssets assets,
    required ProjectOverview overview,
    required String repoDescription,
    required String repoLanguage,
    required String repoUrl,
    required int repoStars,
    required int repoForks,
    required int repoWatchers,
    required int repoOpenIssues,
    required String windowLabel,
    required String reportStamp,
  }) {
    return _buildPageShell(
      assets: assets,
      repoFullName: overview.repoFullName,
      pageLabel: '01 / 02',
      reportStamp: reportStamp,
      body: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildHeroBoard(
            assets: assets,
            overview: overview,
            repoDescription: repoDescription,
            windowLabel: windowLabel,
            reportStamp: reportStamp,
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 12,
                child: _buildDarkCard(
                  title: 'Executive Signal',
                  badge:
                      overview.summaryUsedAI
                          ? 'AI narrative'
                          : 'Rules narrative',
                  subtitle:
                      'Fast read for a founder, manager, or lead reviewing this repo.',
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _truncateText(overview.executiveSummary, maxChars: 470),
                        style: _darkBodyStyle(
                          size: 12.6,
                          height: 1.55,
                          color: _textPrimary,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 12),
                      pw.Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildTonePill('Health ${overview.healthLabel}'),
                          _buildTonePill('Momentum ${overview.momentumLabel}'),
                          _buildTonePill('Branch ${overview.branch}'),
                          _buildTonePill(overview.window.longLabel),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 8,
                child: _buildDarkCard(
                  title: 'Snapshot',
                  subtitle: 'Project context and repo posture at export time.',
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _buildKickerLine('Window', windowLabel),
                      _buildKickerLine('Generated', reportStamp),
                      if (repoLanguage.isNotEmpty)
                        _buildKickerLine('Language', repoLanguage),
                      _buildKickerLine('Stars', '$repoStars'),
                      _buildKickerLine('Forks', '$repoForks'),
                      _buildKickerLine('Watchers', '$repoWatchers'),
                      _buildKickerLine('Open Issues', '$repoOpenIssues'),
                      if (repoUrl.isNotEmpty)
                        _buildKickerLine(
                          'Repo',
                          _truncateText(repoUrl, maxChars: 36),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          _buildDarkCard(
            title: 'Delivery Dashboard',
            subtitle:
                'The most important repo metrics for this reporting window.',
            child: pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildDarkMetricCard(
                  label: 'Commits',
                  value: overview.stats.commitCount.toString(),
                  accent: _accent,
                ),
                _buildDarkMetricCard(
                  label: 'Merged PRs',
                  value: overview.stats.mergedPrCount.toString(),
                  accent: _teal,
                ),
                _buildDarkMetricCard(
                  label: 'Open PRs',
                  value: overview.stats.openPrCount.toString(),
                  accent: _accent,
                ),
                _buildDarkMetricCard(
                  label: 'Issues Opened',
                  value: overview.stats.openedIssueCount.toString(),
                  accent: _amber,
                ),
                _buildDarkMetricCard(
                  label: 'Issues Closed',
                  value: overview.stats.closedIssueCount.toString(),
                  accent: _teal,
                ),
                _buildDarkMetricCard(
                  label: 'Failed Runs',
                  value: overview.stats.failedRunCount.toString(),
                  accent: _rose,
                ),
                _buildDarkMetricCard(
                  label: 'Draft PRs',
                  value: overview.stats.draftPrCount.toString(),
                  accent: _amber,
                ),
                _buildDarkMetricCard(
                  label: 'Releases',
                  value: overview.stats.releaseCount.toString(),
                  accent: _teal,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _buildPriorityPanel(
                  title: 'What Changed',
                  accent: _teal,
                  items:
                      overview.highlights.isNotEmpty
                          ? overview.highlights.take(2).toList()
                          : [overview.executiveSummary],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildPriorityPanel(
                  title: 'Watch Closely',
                  accent: _amber,
                  items:
                      overview.risks.isNotEmpty
                          ? overview.risks.take(2).toList()
                          : ['No major risks were flagged in this window.'],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildPriorityPanel(
                  title: 'Do Next',
                  accent: _accent,
                  items:
                      overview.nextActions.isNotEmpty
                          ? overview.nextActions.take(2).toList()
                          : ['No immediate follow-up actions are recommended.'],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildExecutionPage({
    required _ProjectPdfAssets assets,
    required ProjectOverview overview,
    required String reportStamp,
  }) {
    return _buildPageShell(
      assets: assets,
      repoFullName: overview.repoFullName,
      pageLabel: '02 / 02',
      reportStamp: reportStamp,
      body: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 11,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildDarkCard(
                  title: 'Detailed Executive Summary',
                  badge:
                      overview.summaryUsedAI
                          ? 'AI narrative'
                          : 'Executive snapshot',
                  subtitle:
                      'Longer leadership readout covering momentum, risk, and what matters next.',
                  child: pw.Text(
                    _truncateText(overview.executiveSummary, maxChars: 1400),
                    style: _darkBodyStyle(
                      size: 11.1,
                      height: 1.55,
                      color: _textPrimary,
                    ),
                  ),
                ),
                if (overview.codeSummary.isNotEmpty) ...[
                  pw.SizedBox(height: 12),
                  _buildDarkCard(
                    title: 'What Changed in the Codebase',
                    badge: 'AI code analysis',
                    subtitle:
                        'Technical breakdown of what was built, fixed, and refactored during this window.',
                    child: pw.Text(
                      _truncateText(overview.codeSummary, maxChars: 900),
                      style: _darkBodyStyle(
                        size: 11.1,
                        height: 1.55,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                ],
                pw.SizedBox(height: 12),
                _buildDarkCard(
                  title: 'Engineering Lens',
                  subtitle:
                      'Technical read on execution, quality, and delivery posture.',
                  child: pw.Text(
                    _truncateText(overview.engineeringSummary, maxChars: 720),
                    style: _darkBodyStyle(
                      size: 11.1,
                      height: 1.55,
                      color: _textPrimary,
                    ),
                  ),
                ),
                pw.SizedBox(height: 12),
                _buildDarkCard(
                  title: 'Contributor Activity',
                  subtitle: 'Top code movement by author during this window.',
                  child:
                      overview.contributors.isEmpty
                          ? _buildEmptyState(
                            'No contributor activity was captured in this window.',
                          )
                          : pw.Column(
                            children:
                                overview.contributors
                                    .take(4)
                                    .map(
                                      (item) => _buildDarkContributorRow(
                                        item: item,
                                        maxCommits:
                                            overview
                                                        .contributors
                                                        .first
                                                        .commitCount ==
                                                    0
                                                ? 1
                                                : overview
                                                    .contributors
                                                    .first
                                                    .commitCount,
                                      ),
                                    )
                                    .toList(),
                          ),
                ),
                pw.SizedBox(height: 12),
                _buildDarkCard(
                  title: 'Shipments',
                  subtitle: 'Fresh releases and merges worth surfacing.',
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _buildCompactGroup(
                        'Recent Releases',
                        overview.releases,
                        emptyLabel: 'No releases landed in this window.',
                        limit: 2,
                      ),
                      pw.SizedBox(height: 10),
                      _buildCompactGroup(
                        'Recent Merges',
                        overview.mergedPullRequests,
                        emptyLabel: 'No merged PRs in this window.',
                        limit: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            flex: 10,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildDarkCard(
                  title: 'Delivery Radar',
                  subtitle:
                      'Current queue, new issue load, and operational blockers.',
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _buildCompactGroup(
                        'Open Pull Requests',
                        overview.openPullRequests,
                        emptyLabel: 'No open pull requests.',
                        limit: 2,
                      ),
                      pw.SizedBox(height: 10),
                      _buildCompactGroup(
                        'Opened Issues',
                        overview.openedIssues,
                        emptyLabel: 'No new issues opened.',
                        limit: 2,
                      ),
                      pw.SizedBox(height: 10),
                      _buildCompactGroup(
                        'Workflow Failures',
                        overview.workflowFailures,
                        emptyLabel: 'No failed workflow runs.',
                        limit: 2,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
                _buildDarkCard(
                  title: 'Activity Timeline',
                  subtitle: 'The most notable events from the selected window.',
                  child:
                      overview.timeline.isEmpty
                          ? _buildEmptyState('No notable timeline events yet.')
                          : pw.Column(
                            children:
                                overview.timeline
                                    .take(5)
                                    .map(_buildDarkTimelineRow)
                                    .toList(),
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPageShell({
    required _ProjectPdfAssets assets,
    required String repoFullName,
    required String pageLabel,
    required String reportStamp,
    required pw.Widget body,
  }) {
    return pw.Container(
      color: _pageBg,
      child: pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(28, 22, 28, 22),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 34,
                  height: 34,
                  padding: const pw.EdgeInsets.all(7),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  child: pw.Image(assets.logo, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '/slash executive export',
                      style: _darkBodyStyle(
                        size: 12.4,
                        color: _textPrimary,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      _truncateText(repoFullName, maxChars: 42),
                      style: _darkBodyStyle(size: 9.8, color: _textSecondary),
                    ),
                  ],
                ),
                pw.Spacer(),
                _buildTonePill(pageLabel),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Expanded(child: body),
            pw.SizedBox(height: 12),
            pw.Row(
              children: [
                pw.Text(
                  'Generated by /slash',
                  style: _darkBodyStyle(size: 9.4, color: _textSecondary),
                ),
                pw.Spacer(),
                pw.Text(
                  reportStamp,
                  style: _darkBodyStyle(size: 9.4, color: _textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildHeroBoard({
    required _ProjectPdfAssets assets,
    required ProjectOverview overview,
    required String repoDescription,
    required String windowLabel,
    required String reportStamp,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(22),
      decoration: pw.BoxDecoration(
        color: _panelStrong,
        borderRadius: pw.BorderRadius.circular(24),
        border: pw.Border.all(color: _panelBorder, width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildTonePill('Dark Executive Brief'),
                pw.SizedBox(height: 14),
                pw.Text(
                  overview.repoFullName,
                  style: _darkBodyStyle(
                    size: 24,
                    color: _textPrimary,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  _truncateText(repoDescription, maxChars: 180),
                  style: _darkBodyStyle(
                    size: 11.3,
                    height: 1.45,
                    color: _textSecondary,
                  ),
                ),
                pw.SizedBox(height: 14),
                pw.Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildTonePill(overview.window.longLabel),
                    _buildTonePill('Branch ${overview.branch}'),
                    _buildTonePill(windowLabel),
                    _buildTonePill('Generated $reportStamp'),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Container(
            width: 108,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: _panelBg,
              borderRadius: pw.BorderRadius.circular(20),
              border: pw.Border.all(color: _panelBorder, width: 1),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 54,
                  height: 54,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(16),
                  ),
                  child: pw.Image(assets.logo, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Generated by /slash',
                  textAlign: pw.TextAlign.center,
                  style: _darkBodyStyle(
                    size: 9.8,
                    color: _textPrimary,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDarkCard({
    required String title,
    String? subtitle,
    String? badge,
    required pw.Widget child,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _panelBg,
        borderRadius: pw.BorderRadius.circular(20),
        border: pw.Border.all(color: _panelBorder, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      title,
                      style: _darkBodyStyle(
                        size: 14.4,
                        color: _textPrimary,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        subtitle,
                        style: _darkBodyStyle(
                          size: 9.6,
                          color: _textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null && badge.trim().isNotEmpty) ...[
                pw.SizedBox(width: 8),
                _buildTonePill(badge),
              ],
            ],
          ),
          pw.SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  static pw.Widget _buildPriorityPanel({
    required String title,
    required PdfColor accent,
    required List<String> items,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _panelBg,
        borderRadius: pw.BorderRadius.circular(18),
        border: pw.Border.all(color: _panelBorder, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(999),
            ),
            child: pw.Text(
              title,
              style: _darkBodyStyle(
                size: 9.8,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          ...items
              .take(2)
              .map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 10),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 6,
                        height: 6,
                        margin: const pw.EdgeInsets.only(top: 5),
                        decoration: pw.BoxDecoration(
                          color: accent,
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Text(
                          _truncateText(item, maxChars: 120),
                          style: _darkBodyStyle(
                            size: 10.2,
                            color: _textPrimary,
                            height: 1.42,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  static pw.Widget _buildDarkMetricCard({
    required String label,
    required String value,
    required PdfColor accent,
  }) {
    return pw.Container(
      width: 118,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _panelStrong,
        borderRadius: pw.BorderRadius.circular(16),
        border: pw.Border.all(color: _panelBorder, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 12,
            height: 12,
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(999),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            value,
            style: _darkBodyStyle(
              size: 19,
              color: _textPrimary,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            label,
            style: _darkBodyStyle(
              size: 9.6,
              color: _textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildKickerLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: _darkBodyStyle(
              size: 8.8,
              color: _textSecondary,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: _darkBodyStyle(size: 10.3, color: _textPrimary),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDarkContributorRow({
    required ProjectContributor item,
    required int maxCommits,
  }) {
    final ratio =
        maxCommits == 0 ? 0.0 : (item.commitCount / maxCommits).clamp(0.0, 1.0);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  item.name,
                  style: _darkBodyStyle(
                    size: 10.8,
                    color: _textPrimary,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                '${item.commitCount} commit${item.commitCount == 1 ? '' : 's'}',
                style: _darkBodyStyle(size: 9.4, color: _textSecondary),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            height: 7,
            decoration: pw.BoxDecoration(
              color: _panelStrong,
              borderRadius: pw.BorderRadius.circular(999),
            ),
            child: pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Container(
                width: 180 * ratio,
                decoration: pw.BoxDecoration(
                  color: _accent,
                  borderRadius: pw.BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCompactGroup(
    String label,
    List<ProjectReportItem> items, {
    required String emptyLabel,
    int limit = 2,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: _darkBodyStyle(
            size: 10,
            color: _textSecondary,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 6),
        if (items.isEmpty)
          _buildEmptyState(emptyLabel)
        else
          ...items.take(limit).map(_buildCompactItem),
      ],
    );
  }

  static pw.Widget _buildCompactItem(ProjectReportItem item) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _truncateText(item.title, maxChars: 70),
            style: _darkBodyStyle(
              size: 10.4,
              color: _textPrimary,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            _truncateText(item.subtitle, maxChars: 88),
            style: _darkBodyStyle(size: 9.2, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDarkTimelineRow(ProjectTimelineEntry item) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 7,
            height: 7,
            margin: const pw.EdgeInsets.only(top: 5),
            decoration: pw.BoxDecoration(
              color: _accent,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  item.kind,
                  style: _darkBodyStyle(
                    size: 8.8,
                    color: _textSecondary,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  _truncateText(item.title, maxChars: 66),
                  style: _darkBodyStyle(
                    size: 10.4,
                    color: _textPrimary,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  _truncateText(
                    '${item.subtitle} | ${_formatDateTime(item.timestamp.toUtc())}',
                    maxChars: 96,
                  ),
                  style: _darkBodyStyle(size: 9.1, color: _textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildEmptyState(String value) {
    return pw.Text(
      value,
      style: _darkBodyStyle(size: 9.6, color: _textSecondary, height: 1.4),
    );
  }

  static pw.Widget _buildTonePill(String label) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: pw.BoxDecoration(
        color: _panelBg,
        borderRadius: pw.BorderRadius.circular(999),
        border: pw.Border.all(color: _panelBorder, width: 1),
      ),
      child: pw.Text(
        _truncateText(label, maxChars: 34),
        style: _darkBodyStyle(
          size: 9.2,
          color: _textPrimary,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.TextStyle _darkBodyStyle({
    double size = 10.5,
    double height = 1.4,
    PdfColor color = _textPrimary,
    pw.FontWeight? fontWeight,
  }) {
    return pw.TextStyle(
      color: color,
      fontSize: size,
      height: height,
      fontWeight: fontWeight,
    );
  }

  static String _truncateText(String value, {required int maxChars}) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= maxChars) {
      return normalized;
    }
    final clipped = normalized.substring(0, maxChars);
    final boundary = clipped.lastIndexOf(' ');
    final safe =
        boundary > (maxChars * 0.6).round()
            ? clipped.substring(0, boundary)
            : clipped;
    return '${safe.trim()}...';
  }

  static String _buildFileName(ProjectOverview overview) {
    final slug = overview.repoFullName.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '-',
    );
    final timestamp = _compactTimestamp(overview.generatedAt.toUtc());
    return 'slash-$slug-${overview.window.label.toLowerCase()}-$timestamp.pdf';
  }

  static Uint8List _toBytes(ByteData data) {
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  static String _compactTimestamp(DateTime value) {
    return '${value.year}${_twoDigits(value.month)}${_twoDigits(value.day)}-${_twoDigits(value.hour)}${_twoDigits(value.minute)}';
  }

  static String _formatDate(DateTime value) {
    return '${_monthLabel(value.month)} ${value.day}, ${value.year}';
  }

  static String _formatDateTime(DateTime value) {
    final hour =
        value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${_monthLabel(value.month)} ${value.day}, ${value.year} ${_twoDigits(hour)}:${_twoDigits(value.minute)} $suffix UTC';
  }

  static String _monthLabel(int month) {
    const months = [
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
    return months[(month - 1).clamp(0, 11)];
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _ProjectPdfAssets {
  final pw.Font regular;
  final pw.Font medium;
  final pw.Font semiBold;
  final pw.Font bold;
  final pw.MemoryImage logo;

  const _ProjectPdfAssets({
    required this.regular,
    required this.medium,
    required this.semiBold,
    required this.bold,
    required this.logo,
  });
}
