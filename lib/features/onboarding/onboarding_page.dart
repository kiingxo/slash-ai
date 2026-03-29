import 'package:flutter/material.dart';

import '../../home_shell.dart';
import '../../services/cache_storage_service.dart';
import '../../ui/components/cool_background.dart';
import '../../ui/components/slash_text.dart';
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

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = <_OnboardingSlideData>[
    _OnboardingSlideData(
      eyebrow: 'Build',
      title: 'Plan, edit, and ship without bouncing between tools.',
      body:
          '/slash blends repo-aware AI chat, manual editing, and pull request momentum into one mobile workflow.',
      accent: Color(0xFF38BDF8),
      secondary: Color(0xFF2563EB),
      chips: ['Prompt', 'Code', 'PRs'],
      kind: _OnboardingKind.build,
    ),
    _OnboardingSlideData(
      eyebrow: 'See',
      title: 'Turn repo movement into a clean leadership readout.',
      body:
          'Watch delivery velocity, risks, contributors, workflows, and executive summaries without digging through GitHub tabs.',
      accent: Color(0xFFF59E0B),
      secondary: Color(0xFFEA580C),
      chips: ['Project', 'Reports', 'Executive PDF'],
      kind: _OnboardingKind.project,
    ),
    _OnboardingSlideData(
      eyebrow: 'Operate',
      title: 'Open the VPS command center straight from your phone.',
      body:
          'Connect over SSH, inspect Docker and services, read logs, run terminal commands, and review incidents with AI.',
      accent: Color(0xFF22C55E),
      secondary: Color(0xFF0F766E),
      chips: ['SSH', 'Logs', 'Docker + Services'],
      kind: _OnboardingKind.ops,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await OnboardingPage.markSeen();
    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) =>
                widget.canAccessWorkspace
                    ? const HomeShell()
                    : const AuthPage(),
      ),
    );
  }

  Future<void> _next() async {
    if (_page >= _slides.length - 1) {
      await _finish();
      return;
    }
    await _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _back() async {
    if (_page == 0) {
      return;
    }
    await _controller.previousPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_page];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SlashBackground(
        overlayOpacity: 0.34,
        showGrid: false,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: const SlashText(
                        '/slash',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton(onPressed: _finish, child: const Text('Skip')),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (value) {
                    setState(() {
                      _page = value;
                    });
                  },
                  itemBuilder: (context, index) {
                    final item = _slides[index];
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _OnboardingVisual(data: item),
                              const SizedBox(height: 24),
                              SlashText(
                                item.eyebrow.toUpperCase(),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: item.accent,
                              ),
                              const SizedBox(height: 12),
                              SlashText(
                                item.title,
                                fontSize: 31,
                                fontWeight: FontWeight.w800,
                              ),
                              const SizedBox(height: 14),
                              SlashText(
                                item.body,
                                fontSize: 15,
                                color: Colors.white.withValues(alpha: 0.74),
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final chip in item.chips)
                                    _OnboardingChip(
                                      label: chip,
                                      accent: item.accent,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  MediaQuery.of(context).padding.bottom + 16,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child:
                            _page == 0
                                ? const SizedBox.shrink()
                                : TextButton(
                                  onPressed: _back,
                                  child: const Text('Back'),
                                ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (int i = 0; i < _slides.length; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                width: i == _page ? 28 : 8,
                                height: 8,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      i == _page
                                          ? slide.accent
                                          : Colors.white.withValues(
                                            alpha: 0.18,
                                          ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 92,
                        child: FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: slide.accent,
                            foregroundColor: Colors.black,
                          ),
                          child: Text(
                            _page == _slides.length - 1 ? 'Start' : 'Next',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _OnboardingKind { build, project, ops }

class _OnboardingSlideData {
  final String eyebrow;
  final String title;
  final String body;
  final Color accent;
  final Color secondary;
  final List<String> chips;
  final _OnboardingKind kind;

  const _OnboardingSlideData({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.accent,
    required this.secondary,
    required this.chips,
    required this.kind,
  });
}

class _OnboardingVisual extends StatelessWidget {
  final _OnboardingSlideData data;

  const _OnboardingVisual({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 338,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0B1220),
            Color.lerp(const Color(0xFF111827), data.secondary, 0.45)!,
            Color.lerp(const Color(0xFF0F172A), data.accent, 0.32)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: data.accent.withValues(alpha: 0.18),
            blurRadius: 34,
            offset: const Offset(0, 16),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -12,
            right: 10,
            child: Text(
              '0${data.kind.index + 1}',
              style: TextStyle(
                fontSize: 112,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.05),
                height: 1,
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: switch (data.kind) {
                _OnboardingKind.build => _BuildVisual(data: data),
                _OnboardingKind.project => _ProjectVisual(data: data),
                _OnboardingKind.ops => _OpsVisual(data: data),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildVisual extends StatelessWidget {
  final _OnboardingSlideData data;

  const _BuildVisual({required this.data});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: _GlassPanel(
            width: 208,
            accent: data.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MiniHeader(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Prompt',
                  accent: data.accent,
                ),
                const SizedBox(height: 14),
                const _Line(width: 124),
                const SizedBox(height: 8),
                const _Line(width: 156),
                const SizedBox(height: 8),
                const _Line(width: 112),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: data.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const SlashText(
                      'Draft ready',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Transform.rotate(
            angle: -0.04,
            child: _GlassPanel(
              width: 226,
              accent: data.secondary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MiniHeader(
                    icon: Icons.code_rounded,
                    label: 'Code',
                    accent: data.secondary,
                  ),
                  const SizedBox(height: 16),
                  const _CodeRow(prefix: '+', text: 'final changes = apply();'),
                  const SizedBox(height: 8),
                  const _CodeRow(prefix: '+', text: 'await push(branch);'),
                  const SizedBox(height: 8),
                  const _CodeRow(prefix: '-', text: 'manual copy / paste'),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 28,
          right: 56,
          bottom: 64,
          child: Transform.rotate(
            angle: 0.06,
            child: _GlassPanel(
              accent: Colors.white,
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: data.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.merge_type_rounded, color: data.accent),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SlashText(
                          'Pull request momentum',
                          fontWeight: FontWeight.w700,
                        ),
                        SizedBox(height: 4),
                        SlashText(
                          'Review, approve, and move code forward.',
                          fontSize: 12,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProjectVisual extends StatelessWidget {
  final _OnboardingSlideData data;

  const _ProjectVisual({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Velocity',
                value: '24h',
                accent: data.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                label: 'Risks',
                value: '3',
                accent: data.secondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                label: 'PRs',
                value: '12',
                accent: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _GlassPanel(
            accent: data.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MiniHeader(
                  icon: Icons.insights_rounded,
                  label: 'Executive summary',
                  accent: data.accent,
                ),
                const SizedBox(height: 16),
                const _Line(width: double.infinity),
                const SizedBox(height: 8),
                const _Line(width: double.infinity),
                const SizedBox(height: 8),
                const _Line(width: 220),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: _StackNote(
                        title: 'Risk radar',
                        text: 'What is slipping or piling up',
                        accent: data.secondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StackNote(
                        title: 'Next actions',
                        text: 'What leadership should do next',
                        accent: data.accent,
                      ),
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

class _OpsVisual extends StatelessWidget {
  final _OnboardingSlideData data;

  const _OpsVisual({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'CPU',
                value: '48%',
                accent: data.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                label: 'Memory',
                value: '63%',
                accent: data.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _GlassPanel(
            accent: data.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MiniHeader(
                  icon: Icons.terminal_rounded,
                  label: 'Live terminal',
                  accent: data.accent,
                ),
                const SizedBox(height: 16),
                const _TerminalLine(
                  prompt: '\$',
                  text: 'docker ps --format "{{.Names}}"',
                ),
                const SizedBox(height: 8),
                const _TerminalLine(prompt: '>', text: 'api'),
                const SizedBox(height: 8),
                const _TerminalLine(prompt: '>', text: 'worker'),
                const SizedBox(height: 8),
                const _TerminalLine(prompt: '>', text: 'nginx'),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: _StackNote(
                        title: 'Logs',
                        text: 'Open services and inspect application logs',
                        accent: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StackNote(
                        title: 'AI review',
                        text: 'Get a quick read on what is going wrong',
                        accent: data.secondary,
                      ),
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

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final Color accent;
  final double? width;

  const _GlassPanel({required this.child, required this.accent, this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: child,
    );
  }
}

class _MiniHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _MiniHeader({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
        const SizedBox(width: 10),
        SlashText(label, fontWeight: FontWeight.w700),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SlashText(
            label,
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.66),
          ),
          const SizedBox(height: 8),
          SlashText(value, fontSize: 26, fontWeight: FontWeight.w800),
        ],
      ),
    );
  }
}

class _StackNote extends StatelessWidget {
  final String title;
  final String text;
  final Color accent;

  const _StackNote({
    required this.title,
    required this.text,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SlashText(title, fontSize: 12, fontWeight: FontWeight.w700),
          const SizedBox(height: 6),
          SlashText(
            text,
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.72),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final double width;

  const _Line({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width.isFinite ? width : null,
      height: 10,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  final String prefix;
  final String text;

  const _CodeRow({required this.prefix, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SlashText(
          prefix,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color:
              prefix == '+' ? const Color(0xFF22C55E) : const Color(0xFFFB7185),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SlashText(
            text,
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.76),
          ),
        ),
      ],
    );
  }
}

class _TerminalLine extends StatelessWidget {
  final String prompt;
  final String text;

  const _TerminalLine({required this.prompt, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SlashText(
          prompt,
          color: const Color(0xFF22C55E),
          fontWeight: FontWeight.w700,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SlashText(
            text,
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.78),
          ),
        ),
      ],
    );
  }
}

class _OnboardingChip extends StatelessWidget {
  final String label;
  final Color accent;

  const _OnboardingChip({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: SlashText(label, fontSize: 12, fontWeight: FontWeight.w700),
    );
  }
}
