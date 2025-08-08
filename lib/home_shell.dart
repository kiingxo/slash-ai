import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/features/prompt/prompt_widgets.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'features/prompt/prompt_page.dart';
import 'features/prompt/code_page.dart';
import 'features/auth/auth_page.dart';
import 'features/review/pr_page.dart';
import 'features/auth/auth_controller.dart';
import 'ui/screens/settings_screen.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static final List<Widget> _pages = <Widget>[
    PromptPage(),
    CodeScreen(),
    PRsPage(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Route guard: if no credentials after logout/login, force auth screen as a clean start.
    final auth = ref.watch(authControllerProvider);

    // Consider "logged in" if at least the provider model is chosen (persisted)
    // AND we have at least one of the AI keys or the GitHub PAT.
    final hasProvider = (auth.model.isNotEmpty);
    final hasAnyKey = (auth.geminiApiKey?.isNotEmpty == true) ||
        (auth.openAIApiKey?.isNotEmpty == true) ||
        (auth.githubPat?.isNotEmpty == true);

    // Only force AuthPage when NOTHING is configured (fresh state).
    if (!hasProvider && !hasAnyKey) {
      return const AuthPage();
    }

    final theme = Theme.of(context);
    final selectedIndex = ref.watch(tabIndexProvider);
    return Scaffold(
      body: _pages[selectedIndex],
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
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
                  _NavBarItem(
                    assetIcon: 'assets/slash2.png',
                    label: 'Prompt',
                    selected: selectedIndex == 0,
                    onTap: () => ref.read(tabIndexProvider.notifier).state = 0,
                    theme: theme,
                  ),
                  _NavBarItem(
                    icon: Icons.code,
                    label: 'Code',
                    selected: selectedIndex == 1,
                    onTap: () => ref.read(tabIndexProvider.notifier).state = 1,
                    theme: theme,
                  ),
                  _NavBarItem(
                    icon: Icons.merge_type,
                    label: 'PRs',
                    selected: selectedIndex == 2,
                    onTap: () => ref.read(tabIndexProvider.notifier).state = 2,
                    theme: theme,
                  ),
                  _NavBarItem(
                    icon: Icons.settings,
                    label: 'Settings',
                    selected: selectedIndex == 3,
                    onTap: () => ref.read(tabIndexProvider.notifier).state = 3,
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
  final IconData? icon;
  final String? assetIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;
  const _NavBarItem({
    this.icon,
    this.assetIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
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
                width: assetIcon != null ? 50 : 40,
                height: assetIcon != null ? 50 : 36,
                decoration: BoxDecoration(
                  color:
                      selected
                          ? theme.colorScheme.primary.withOpacity(0.12)
                          : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child:
                    assetIcon != null
                        ? Center(
                          child: Image.asset(
                            assetIcon!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.contain,
                            color:
                                selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface.withOpacity(
                                      0.7,
                                    ),
                          ),
                        )
                        : Icon(
                          icon,
                          size: 24,
                          color:
                              selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withOpacity(
                                    0.7,
                                  ),
                        ),
              ),
              const SizedBox(height: 2),
              if (selected && assetIcon == null)
                SlashText(
                  label,
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
