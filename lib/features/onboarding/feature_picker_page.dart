import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/nav_preferences.dart';
import '../../home_shell.dart';
import '../../ui/components/cool_background.dart';
import '../../ui/components/slash_text.dart';
import '../../ui/theme/app_theme_builder.dart';

class FeaturePickerPage extends ConsumerStatefulWidget {
  const FeaturePickerPage({super.key});

  @override
  ConsumerState<FeaturePickerPage> createState() => _FeaturePickerPageState();
}

class _FeaturePickerPageState extends ConsumerState<FeaturePickerPage> {
  late Set<SlashFeature> _selected;

  @override
  void initState() {
    super.initState();
    final pickable =
        SlashFeature.values.where((f) => kFeatureMeta[f]?.showInPicker == true);
    if (NavPreferencesNotifier.isSetupDone) {
      // Returning user — pre-populate with their saved choices.
      final saved = ref.read(navPreferencesProvider);
      _selected = pickable.where((f) => saved.contains(f)).toSet();
      if (_selected.isEmpty) {
        _selected = pickable.toSet();
      }
    } else {
      // New user — default to everything enabled.
      _selected = pickable.toSet();
    }
  }

  void _toggle(SlashFeature feature) {
    final meta = kFeatureMeta[feature];
    if (meta == null || meta.required) return;
    setState(() {
      if (_selected.contains(feature)) {
        _selected = Set.from(_selected)..remove(feature);
      } else {
        _selected = {..._selected, feature};
      }
    });
  }

  void _confirm() {
    ref.read(navPreferencesProvider.notifier).saveAll(_selected);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pickable = SlashFeature.values
        .where((f) => kFeatureMeta[f]?.showInPicker == true)
        .toList();
    final enabledCount = _selected.length;

    return ThemeBuilder(
      builder: (context, colors, ref) {
        return SlashBackground(
          showGrid: false,
          showSlashes: false,
          overlayOpacity: 0.52,
          animate: false,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header
                          Center(
                            child: Image.asset(
                              'assets/slash2.png',
                              width: 72,
                              height: 72,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const SlashText(
                            'Personalize your workspace',
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          SlashText(
                            'Pick the features you want on your bottom nav bar. You can change this anytime in Settings.',
                            fontSize: 13,
                            color: colors.always909090,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),

                          // Feature cards
                          _buildGlassCard(
                            context,
                            child: Column(
                              children: [
                                for (int i = 0; i < pickable.length; i++) ...[
                                  if (i > 0) const Divider(height: 1),
                                  _FeatureCard(
                                    feature: pickable[i],
                                    selected: _selected.contains(pickable[i]),
                                    onTap: () => _toggle(pickable[i]),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: SlashText(
                              '$enabledCount feature${enabledCount == 1 ? '' : 's'} selected',
                              fontSize: 12,
                              color: colors.always909090,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // CTA
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    MediaQuery.of(context).padding.bottom + 16,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Get Started',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassCard(BuildContext context, {required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final SlashFeature feature;
  final bool selected;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.feature,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final meta = kFeatureMeta[feature]!;
    final isRequired = meta.required;

    return InkWell(
      onTap: isRequired ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    selected
                        ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  meta.assetIcon != null
                      ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: Image.asset(
                          meta.assetIcon!,
                          color:
                              selected
                                  ? const Color(0xFF8B5CF6)
                                  : Colors.white.withValues(alpha: 0.6),
                        ),
                      )
                      : Icon(
                        meta.icon,
                        size: 22,
                        color:
                            selected
                                ? const Color(0xFF8B5CF6)
                                : Colors.white.withValues(alpha: 0.6),
                      ),
            ),
            const SizedBox(width: 14),

            // Label + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        meta.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color:
                              selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                      if (isRequired) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(
                              alpha: 0.18,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Required',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFBB8EFF),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.48),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Toggle indicator
            if (isRequired)
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.3),
              )
            else
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      selected
                          ? const Color(0xFF8B5CF6)
                          : Colors.white.withValues(alpha: 0.08),
                  border: Border.all(
                    color:
                        selected
                            ? const Color(0xFF8B5CF6)
                            : Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child:
                    selected
                        ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                        : null,
              ),
          ],
        ),
      ),
    );
  }
}
