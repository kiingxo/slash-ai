import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common/nav_preferences.dart';
import 'features/auth/auth_page.dart';
import 'features/auth/auth_controller.dart';
import 'features/ops/ops_page.dart';
import 'features/project/project_page.dart';
import 'features/prompt/prompt_page.dart';
import 'features/prompt/code_page.dart';
import 'features/review/pr_page.dart';
import 'ui/screens/settings_screen.dart';

// ── Sidebar open signal ───────────────────────────────────────────────────────

/// Increment this from any page to request the sidebar to open.
final sidebarOpenSignalProvider = StateProvider<int>((ref) => 0);

// ── Shared menu button ────────────────────────────────────────────────────────

/// Drop this into any AppBar's `leading:` to wire up sidebar open.
class SidebarMenuButton extends ConsumerWidget {
  const SidebarMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.menu_rounded),
      tooltip: 'Menu',
      onPressed: () {
        ref.read(sidebarOpenSignalProvider.notifier).update((s) => s + 1);
        HapticFeedback.lightImpact();
      },
    );
  }
}

// ── Shell ─────────────────────────────────────────────────────────────────────

const _kSidebarWidth = 280.0;

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _scrimAnim;
  bool _isOpen = false;

  static Widget _pageForFeature(SlashFeature feature) {
    switch (feature) {
      case SlashFeature.prompt:
        return const PromptPage();
      case SlashFeature.code:
        return const CodeScreen();
      case SlashFeature.project:
        return const ProjectPage();
      case SlashFeature.ops:
        return const OpsPage();
      case SlashFeature.reviews:
        return const PRsPage();
      case SlashFeature.settings:
        return const SizedBox.shrink(); // Settings shown as bottom sheet
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _scrimAnim = Tween<double>(begin: 0, end: 0.55).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _open() {
    if (_isOpen) return;
    setState(() => _isOpen = true);
    _ctrl.forward();
  }

  void _close() {
    if (!_isOpen) return;
    _ctrl.reverse().then((_) {
      if (mounted) setState(() => _isOpen = false);
    });
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const SettingsBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen for sidebar open requests from any page's menu button.
    ref.listen(sidebarOpenSignalProvider, (prev, next) {
      if (next > (prev ?? 0)) _open();
    });

    final auth = ref.watch(authControllerProvider);
    if (!auth.isLoading && !auth.canAccessWorkspace) {
      return const AuthPage();
    }

    final activeFeatures = ref.watch(activeNavFeaturesProvider);
    final selectedFeature = ref.watch(selectedFeatureProvider);

    final safeFeature =
        activeFeatures.contains(selectedFeature)
            ? selectedFeature
            : activeFeatures.first;

    final selectedIndex = activeFeatures.indexOf(safeFeature);

    return GestureDetector(
      // Swipe right to open, swipe left to close.
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v > 180 && !_isOpen) _open();
        if (v < -180 && _isOpen) _close();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Stack(
          children: [
            // ── Pages ────────────────────────────────────────────────────
            IndexedStack(
              index: selectedIndex,
              children: [for (final f in activeFeatures) _pageForFeature(f)],
            ),

            // ── Scrim ─────────────────────────────────────────────────────
            if (_isOpen)
              AnimatedBuilder(
                animation: _scrimAnim,
                builder: (_, __) => GestureDetector(
                  onTap: _close,
                  child: Container(
                    color: Colors.black.withValues(alpha: _scrimAnim.value),
                  ),
                ),
              ),

            // ── Sidebar ───────────────────────────────────────────────────
            SlideTransition(
              position: _slideAnim,
              child: _Sidebar(
                activeFeatures: activeFeatures,
                selectedFeature: safeFeature,
                onSelect: (f) {
                  if (f == SlashFeature.settings) {
                    _close();
                    _showSettingsBottomSheet();
                  } else {
                    ref.read(selectedFeatureProvider.notifier).state = f;
                    _close();
                  }
                },
                onClose: _close,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sidebar panel ─────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final List<SlashFeature> activeFeatures;
  final SlashFeature selectedFeature;
  final void Function(SlashFeature) onSelect;
  final VoidCallback onClose;

  const _Sidebar({
    required this.activeFeatures,
    required this.selectedFeature,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B0B0F) : const Color(0xFFF9FAFB);
    final borderColor =
        isDark
            ? const Color(0xFF1E1E28)
            : const Color(0xFFE5E7EB);

    final navFeatures =
        activeFeatures.where((f) => f != SlashFeature.settings).toList();
    final hasSettings = activeFeatures.contains(SlashFeature.settings);

    return Container(
      width: _kSidebarWidth,
      height: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        border: Border(right: BorderSide(color: borderColor, width: 1)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Image.asset('assets/slash2.png', width: 28, height: 28),
                  const SizedBox(width: 10),
                  Text(
                    '/slash',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: isDark ? Colors.white : const Color(0xFF111111),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onClose,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 19,
                        color:
                            isDark
                                ? Colors.white.withValues(alpha: 0.35)
                                : Colors.black.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Thin separator
            Divider(
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.07),
              height: 1,
              indent: 20,
              endIndent: 20,
            ),
            const SizedBox(height: 10),

            // ── Nav items ──────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final feature in navFeatures)
                    _SidebarItem(
                      feature: feature,
                      selected: selectedFeature == feature,
                      onTap: () => onSelect(feature),
                      isDark: isDark,
                    ),
                ],
              ),
            ),

            // ── Settings pinned at bottom ──────────────────────────────
            if (hasSettings) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(
                  color:
                      isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.07),
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _SidebarItem(
                  feature: SlashFeature.settings,
                  selected: selectedFeature == SlashFeature.settings,
                  onTap: () => onSelect(SlashFeature.settings),
                  isDark: isDark,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Sidebar item ──────────────────────────────────────────────────────────────

class _SidebarItem extends StatelessWidget {
  final SlashFeature feature;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  const _SidebarItem({
    required this.feature,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final meta = kFeatureMeta[feature]!;
    final primary = const Color(0xFF8B5CF6);

    final activeBg =
        isDark
            ? const Color(0xFF1A1826)
            : const Color(0xFFEDE9FE);

    final textColor =
        selected
            ? primary
            : (isDark
                ? Colors.white.withValues(alpha: 0.72)
                : const Color(0xFF374151));

    final iconColor =
        selected
            ? primary
            : (isDark
                ? Colors.white.withValues(alpha: 0.45)
                : const Color(0xFF6B7280));

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: primary.withValues(alpha: 0.08),
          highlightColor: primary.withValues(alpha: 0.04),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                // Purple accent bar on the left when selected
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 3,
                  height: 17,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: selected ? primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Icon
                SizedBox(
                  width: 20,
                  height: 20,
                  child:
                      meta.assetIcon != null
                          ? Image.asset(
                            meta.assetIcon!,
                            width: 20,
                            height: 20,
                            color: iconColor,
                          )
                          : Icon(meta.icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 12),
                // Label
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        meta.label,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: textColor,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (meta.isBeta) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'BETA',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
