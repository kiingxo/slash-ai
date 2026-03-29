import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common/nav_preferences.dart';
import 'features/auth/auth_page.dart';
import 'features/auth/auth_controller.dart';
import 'features/ops/ops_page.dart';
import 'features/project/project_page.dart';
import 'features/prompt/prompt_page.dart';
import 'features/prompt/code_page.dart';
import 'features/review/pr_page.dart';
import 'ui/components/slash_text.dart';
import 'ui/screens/settings_screen.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

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
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (!auth.isLoading && !auth.isReady) {
      return const AuthPage();
    }

    final theme = Theme.of(context);
    final activeFeatures = ref.watch(activeNavFeaturesProvider);
    final selectedFeature = ref.watch(selectedFeatureProvider);

    // Clamp selection to a valid feature if the active set changed.
    final safeFeature =
        activeFeatures.contains(selectedFeature)
            ? selectedFeature
            : activeFeatures.first;

    final selectedIndex = activeFeatures.indexOf(safeFeature);

    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: [for (final f in activeFeatures) _pageForFeature(f)],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final feature in activeFeatures)
                    _NavBarItem(
                      feature: feature,
                      selected: safeFeature == feature,
                      onTap:
                          () =>
                              ref
                                  .read(selectedFeatureProvider.notifier)
                                  .state = feature,
                      theme: theme,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final SlashFeature feature;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _NavBarItem({
    required this.feature,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final meta = kFeatureMeta[feature]!;
    final hasAsset = meta.assetIcon != null;

    return Flexible(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: hasAsset ? 50 : 40,
                height: hasAsset ? 50 : 36,
                decoration: BoxDecoration(
                  color:
                      selected
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child:
                    hasAsset
                        ? Center(
                          child: Image.asset(
                            meta.assetIcon!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.contain,
                            color:
                                selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                          ),
                        )
                        : Icon(
                          meta.icon,
                          size: 24,
                          color:
                              selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.7,
                                  ),
                        ),
              ),
              const SizedBox(height: 2),
              if (selected && !hasAsset)
                SlashText(
                  meta.label,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
