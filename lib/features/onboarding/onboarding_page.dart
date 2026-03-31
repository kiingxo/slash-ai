import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../home_shell.dart';
import '../../services/cache_storage_service.dart';
import '../../ui/components/cool_background.dart';
import '../auth/auth_page.dart';

class OnboardingPage extends StatefulWidget {
  static const String seenKey = 'intro_onboarding_seen_v1';

  final bool canAccessWorkspace;

  const OnboardingPage({super.key, required this.canAccessWorkspace});

  static bool get hasSeen => CacheStorage.fetchBool(seenKey) == true;

  static Future<void> markSeen() => CacheStorage.save(seenKey, true);

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  final _controller = PageController();
  int _page = 0;

  static const _slides = <_SlideData>[
    _SlideData(
      kind: _SlideKind.welcome,
      eyebrow: 'slash',
      title: 'Built by engineers,\nfor engineers.',
      body:
          'Your mobile command center for the entire dev lifecycle  AI coding, repo intelligence, and production ops.',
      accent: Color(0xFF8B5CF6),
      secondary: Color(0xFF3B82F6),
      chips: [],
    ),
    _SlideData(
      kind: _SlideKind.build,
      eyebrow: 'Build',
      title: 'Code and ship\nfrom anywhere.',
      body:
          'Full repo-aware AI chat, syntax-highlighted editing, and PR momentum. No laptop needed.',
      accent: Color(0xFF38BDF8),
      secondary: Color(0xFF2563EB),
      chips: ['Prompt', 'Code editor', 'Pull requests'],
    ),
    _SlideData(
      kind: _SlideKind.project,
      eyebrow: 'Observe',
      title: 'Repo intelligence\non every commit.',
      body:
          'Delivery velocity, risk radar, contributor breakdown, and AI-generated executive summaries.',
      accent: Color(0xFFF59E0B),
      secondary: Color(0xFFEA580C),
      chips: ['Velocity', 'Risk radar', 'Exec reports'],
    ),
    _SlideData(
      kind: _SlideKind.ops,
      eyebrow: 'Operate',
      title: 'Your VPS,\nalways in your pocket.',
      body:
          'SSH into any server, monitor containers, stream logs, and get AI-powered incident analysis.',
      accent: Color(0xFF22C55E),
      secondary: Color(0xFF0F766E),
      chips: ['SSH', 'Docker', 'Logs & incidents'],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await OnboardingPage.markSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) =>
                widget.canAccessWorkspace ? const HomeShell() : const AuthPage(),
      ),
    );
  }

  Future<void> _next() async {
    if (_page >= _slides.length - 1) {
      await _finish();
      return;
    }
    await _controller.nextPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_page];
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SlashBackground(
        overlayOpacity: 0.44,
        showGrid: false,
        showSlashes: false,
        animate: false,
        child: SafeArea(
          child: Column(
            children: [
              // ── Top bar ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                child: Row(
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/slash2.png',
                          width: 24,
                          height: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '/slash',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _finish,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Pages ────────────────────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (v) => setState(() => _page = v),
                  itemBuilder: (context, index) {
                    return _SlidePage(data: _slides[index]);
                  },
                ),
              ),

              // ── Bottom nav ───────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  4,
                  22,
                  MediaQuery.of(context).padding.bottom + 20,
                ),
                child: Row(
                  children: [
                    // Progress bars
                    Expanded(
                      child: Row(
                        children: [
                          for (int i = 0; i < _slides.length; i++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: i < _slides.length - 1 ? 5 : 0,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color:
                                        i <= _page
                                            ? slide.accent
                                            : Colors.white.withValues(
                                              alpha: 0.14,
                                            ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    // CTA
                    GestureDetector(
                      onTap: _next,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: slide.accent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: slide.accent.withValues(alpha: 0.38),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isLast ? 'Get started' : 'Next',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.1,
                              ),
                            ),
                            if (!isLast) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 15,
                                color: Colors.black,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Slide data ────────────────────────────────────────────────────────────────

enum _SlideKind { welcome, build, project, ops }

class _SlideData {
  final _SlideKind kind;
  final String eyebrow;
  final String title;
  final String body;
  final Color accent;
  final Color secondary;
  final List<String> chips;

  const _SlideData({
    required this.kind,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.accent,
    required this.secondary,
    required this.chips,
  });
}

// ── Slide page ────────────────────────────────────────────────────────────────

class _SlidePage extends StatelessWidget {
  final _SlideData data;

  const _SlidePage({required this.data});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SlideVisual(data: data),
          const SizedBox(height: 28),

          // Eyebrow
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: data.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                data.eyebrow.toUpperCase(),
                style: TextStyle(
                  color: data.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Title
          Text(
            data.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 29,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 12),

          // Body
          Text(
            data.body,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.60),
              fontSize: 14.5,
              height: 1.65,
            ),
          ),

          if (data.chips.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in data.chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: data.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: data.accent.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      chip,
                      style: TextStyle(
                        color: data.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Visual dispatcher ─────────────────────────────────────────────────────────

class _SlideVisual extends StatelessWidget {
  final _SlideData data;

  const _SlideVisual({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 310,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF080C14),
            Color.lerp(const Color(0xFF0D1424), data.secondary, 0.35)!,
            Color.lerp(const Color(0xFF0A0F1E), data.accent, 0.22)!,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: data.accent.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Subtle grid overlay
          Positioned.fill(child: _GridOverlay(color: data.accent)),

          // Glow orb
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    data.accent.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Slide number watermark
          Positioned(
            bottom: -8,
            right: 14,
            child: Text(
              '0${data.kind.index + 1}',
              style: TextStyle(
                fontSize: 96,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.04),
                height: 1,
              ),
            ),
          ),

          // Content
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: switch (data.kind) {
                _SlideKind.welcome => _WelcomeVisual(data: data),
                _SlideKind.build => _BuildVisual(data: data),
                _SlideKind.project => _ProjectVisual(data: data),
                _SlideKind.ops => _OpsVisual(data: data),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Welcome visual ────────────────────────────────────────────────────────────

class _WelcomeVisual extends StatelessWidget {
  final _SlideData data;

  const _WelcomeVisual({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Logo
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Image.asset('assets/slash2.png'),
          ),
        ),
        const SizedBox(height: 20),

        // Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: data.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: data.accent.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.terminal_rounded, size: 13, color: data.accent),
              const SizedBox(width: 6),
              Text(
                'Built by engineers, for engineers',
                style: TextStyle(
                  color: data.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Feature icon row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FeatureIcon(
              icon: Icons.auto_awesome_rounded,
              label: 'Prompt',
              color: const Color(0xFF38BDF8),
            ),
            const SizedBox(width: 12),
            _FeatureIcon(
              icon: Icons.code_rounded,
              label: 'Code',
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 12),
            _FeatureIcon(
              icon: Icons.insights_rounded,
              label: 'Project',
              color: const Color(0xFFF59E0B),
            ),
            const SizedBox(width: 12),
            _FeatureIcon(
              icon: Icons.terminal_rounded,
              label: 'Ops',
              color: const Color(0xFF22C55E),
            ),
            const SizedBox(width: 12),
            _FeatureIcon(
              icon: Icons.merge_type_rounded,
              label: 'PRs',
              color: const Color(0xFFA78BFA),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeatureIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _FeatureIcon({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.50),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Build visual ──────────────────────────────────────────────────────────────

class _BuildVisual extends StatelessWidget {
  final _SlideData data;

  const _BuildVisual({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // File tabs
        _FileTabs(
          tabs: const ['prompt.dart', 'auth.dart', 'ops.dart'],
          activeIndex: 0,
          accent: data.accent,
        ),
        const SizedBox(height: 10),

        // Code block
        Expanded(
          child: _GlassPanel(
            accent: data.accent,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CodeLine(
                  lineNum: 1,
                  tokens: [
                    _Token('final', const Color(0xFF38BDF8)),
                    _Token(' response = ', Colors.white70),
                    _Token('await ', const Color(0xFF38BDF8)),
                    _Token('ai.chat(', Colors.white70),
                  ],
                ),
                _CodeLine(
                  lineNum: 2,
                  tokens: [
                    _Token('  context: ', Colors.white70),
                    _Token('repo', const Color(0xFFF59E0B)),
                    _Token('.currentFile,', Colors.white54),
                  ],
                ),
                _CodeLine(
                  lineNum: 3,
                  tokens: [
                    _Token('  prompt: ', Colors.white70),
                    _Token('"refactor this"', const Color(0xFF86EFAC)),
                    _Token(',', Colors.white54),
                  ],
                ),
                _CodeLine(
                  lineNum: 4,
                  tokens: [_Token(');', Colors.white70)],
                ),
                const SizedBox(height: 8),
                const _SectionDivider(),
                const SizedBox(height: 8),
                _CodeLine(
                  lineNum: 6,
                  tokens: [
                    _Token('// ✦ AI response', const Color(0xFF6B7280)),
                  ],
                ),
                _CodeLine(
                  lineNum: 7,
                  tokens: [
                    _Token('+ ', const Color(0xFF22C55E)),
                    _Token(
                      'final changes = response.apply();',
                      Colors.white70,
                    ),
                  ],
                  highlight: true,
                  highlightColor: const Color(0xFF22C55E),
                ),
                _CodeLine(
                  lineNum: 8,
                  tokens: [
                    _Token('+ ', const Color(0xFF22C55E)),
                    _Token('await push(branch, message);', Colors.white70),
                  ],
                  highlight: true,
                  highlightColor: const Color(0xFF22C55E),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // PR chip
        _StatusRow(accent: data.accent),
      ],
    );
  }
}

// ── Project visual ────────────────────────────────────────────────────────────

class _ProjectVisual extends StatelessWidget {
  final _SlideData data;

  const _ProjectVisual({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Metric row
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Velocity',
                value: '94%',
                delta: '+12%',
                accent: data.accent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: 'Open PRs',
                value: '14',
                delta: '3 stale',
                accent: data.secondary,
                deltaWarning: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: 'Risks',
                value: '2',
                delta: 'flagged',
                accent: const Color(0xFFFB7185),
                deltaWarning: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Summary card
        Expanded(
          child: _GlassPanel(
            accent: data.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: data.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.insights_rounded,
                        color: data.accent,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Executive summary',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: data.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'AI',
                        style: TextStyle(
                          color: data.accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SkeletonLine(width: double.infinity, opacity: 0.15),
                const SizedBox(height: 6),
                _SkeletonLine(width: double.infinity, opacity: 0.12),
                const SizedBox(height: 6),
                _SkeletonLine(width: 160, opacity: 0.10),
                const Spacer(),
                Row(
                  children: [
                    _MiniTag(
                      label: 'Risk radar',
                      color: const Color(0xFFFB7185),
                    ),
                    const SizedBox(width: 6),
                    _MiniTag(label: 'Next actions', color: data.accent),
                    const SizedBox(width: 6),
                    _MiniTag(label: 'PDF export', color: Colors.white38),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Ops visual ────────────────────────────────────────────────────────────────

class _OpsVisual extends StatelessWidget {
  final _SlideData data;

  const _OpsVisual({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Stats row
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'CPU',
                value: '48%',
                delta: '4 cores',
                accent: data.accent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: 'Memory',
                value: '63%',
                delta: '10.2 GB',
                accent: data.secondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: 'Uptime',
                value: '99.9%',
                delta: '12d 4h',
                accent: Colors.white38,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Terminal card
        Expanded(
          child: _GlassPanel(
            accent: data.accent,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Window chrome
                Row(
                  children: [
                    _DotButton(color: const Color(0xFFFF5F57)),
                    const SizedBox(width: 5),
                    _DotButton(color: const Color(0xFFFFBD2E)),
                    const SizedBox(width: 5),
                    _DotButton(color: const Color(0xFF28C840)),
                    const SizedBox(width: 10),
                    Text(
                      'root@prod-01 ~',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: data.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'LIVE',
                        style: TextStyle(
                          color: data.accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _TermLine(
                  prompt: '\$',
                  text: 'docker ps --format "{{.Names}}"',
                  accent: data.accent,
                ),
                const SizedBox(height: 4),
                _TermLine(prompt: '›', text: 'api-gateway', isOutput: true),
                const SizedBox(height: 4),
                _TermLine(prompt: '›', text: 'worker-prod', isOutput: true),
                const SizedBox(height: 4),
                _TermLine(prompt: '›', text: 'nginx-lb', isOutput: true),
                const SizedBox(height: 4),
                _TermLine(
                  prompt: '\$',
                  text: 'tail -f /var/log/api.log',
                  accent: data.accent,
                ),
                const Spacer(),
                Row(
                  children: [
                    _MiniTag(label: 'SSH', color: data.accent),
                    const SizedBox(width: 6),
                    _MiniTag(label: 'Docker', color: data.secondary),
                    const SizedBox(width: 6),
                    _MiniTag(
                      label: 'AI analysis',
                      color: const Color(0xFFA78BFA),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _GridOverlay extends StatelessWidget {
  final Color color;

  const _GridOverlay({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter(color: color));
  }
}

class _GridPainter extends CustomPainter {
  final Color color;

  const _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final Color accent;
  final EdgeInsets? padding;

  const _GlassPanel({required this.child, required this.accent, this.padding});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: double.infinity,
          padding: padding ?? const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FileTabs extends StatelessWidget {
  final List<String> tabs;
  final int activeIndex;
  final Color accent;

  const _FileTabs({
    required this.tabs,
    required this.activeIndex,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < tabs.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color:
                    i == activeIndex
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      i == activeIndex
                          ? accent.withValues(alpha: 0.25)
                          : Colors.transparent,
                ),
              ),
              child: Text(
                tabs[i],
                style: TextStyle(
                  color:
                      i == activeIndex
                          ? Colors.white.withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.30),
                  fontSize: 10.5,
                  fontWeight:
                      i == activeIndex ? FontWeight.w600 : FontWeight.w400,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Token {
  final String text;
  final Color color;

  const _Token(this.text, this.color);
}

class _CodeLine extends StatelessWidget {
  final int lineNum;
  final List<_Token> tokens;
  final bool highlight;
  final Color? highlightColor;

  const _CodeLine({
    required this.lineNum,
    required this.tokens,
    this.highlight = false,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration:
          highlight
              ? BoxDecoration(
                color: highlightColor?.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(3),
              )
              : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$lineNum',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.20),
                fontSize: 9.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  for (final t in tokens)
                    TextSpan(
                      text: t.text,
                      style: TextStyle(
                        color: t.color,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.5,
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
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: Colors.white.withValues(alpha: 0.07),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final Color accent;

  const _StatusRow({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Icon(Icons.merge_type_rounded, size: 14, color: accent),
          const SizedBox(width: 8),
          Text(
            'feat/ai-context-refactor',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Ready to merge',
              style: TextStyle(
                color: Color(0xFF22C55E),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String delta;
  final Color accent;
  final bool deltaWarning;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.delta,
    required this.accent,
    this.deltaWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.40),
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            delta,
            style: TextStyle(
              color:
                  deltaWarning
                      ? const Color(0xFFFB7185).withValues(alpha: 0.80)
                      : Colors.white.withValues(alpha: 0.35),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TermLine extends StatelessWidget {
  final String prompt;
  final String text;
  final Color? accent;
  final bool isOutput;

  const _TermLine({
    required this.prompt,
    required this.text,
    this.accent,
    this.isOutput = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          prompt,
          style: TextStyle(
            color:
                isOutput
                    ? Colors.white.withValues(alpha: 0.25)
                    : accent ?? const Color(0xFF22C55E),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  isOutput
                      ? Colors.white.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.75),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

class _DotButton extends StatelessWidget {
  final Color color;

  const _DotButton({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final double width;
  final double opacity;

  const _SkeletonLine({required this.width, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width.isFinite ? width : null,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
