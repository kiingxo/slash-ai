import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/nav_preferences.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/auth_page.dart';
import '../../features/repo/repo_controller.dart';
import '../../services/app_config.dart';
import '../../services/github_auth_service.dart';
import '../../ui/components/slash_text.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _openAIKeyController = TextEditingController();
  final _openAIModelController = TextEditingController(
    text: AppConfig.defaultOpenAIModel,
  );
  final _openRouterKeyController = TextEditingController();
  final _openRouterModelController = TextEditingController(
    text: AppConfig.defaultOpenRouterModel,
  );
  final _githubClientIdController = TextEditingController();

  bool _seeded = false;
  String _provider = 'openai';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) {
      return;
    }

    final auth = ref.read(authControllerProvider);
    if (auth.isLoading) {
      return;
    }

    _provider = auth.model.isNotEmpty ? auth.model : 'openai';
    _openAIKeyController.text = auth.openAIApiKey ?? '';
    _openAIModelController.text =
        auth.openAIModel ?? AppConfig.defaultOpenAIModel;
    _openRouterKeyController.text = auth.openRouterApiKey ?? '';
    _openRouterModelController.text =
        auth.openRouterModel ?? AppConfig.defaultOpenRouterModel;
    if (!AppConfig.hasBundledGitHubClientId) {
      _githubClientIdController.text = auth.githubOAuthClientId ?? '';
    }
    _seeded = true;
  }

  @override
  void dispose() {
    _openAIKeyController.dispose();
    _openAIModelController.dispose();
    _openRouterKeyController.dispose();
    _openRouterModelController.dispose();
    _githubClientIdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = ref.read(authControllerProvider.notifier);

    await auth.saveModel(_provider);
    if (_provider == 'openrouter') {
      await auth.saveOpenRouterKey(_openRouterKeyController.text.trim());
      await auth.saveOpenRouterModel(_openRouterModelController.text.trim());
    } else {
      await auth.saveOpenAIApiKey(_openAIKeyController.text.trim());
      await auth.saveOpenAIModel(_openAIModelController.text.trim());
    }
    if (!AppConfig.hasBundledGitHubClientId) {
      await auth.saveGitHubOAuthClientId(
        _githubClientIdController.text.trim(),
      );
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: SlashText('Settings saved')));
  }

  Future<void> _connectGitHub() async {
    try {
      final authController = ref.read(authControllerProvider.notifier);
      final session = await authController.beginGitHubDeviceFlow();
      final launchTarget =
          session.verificationUriComplete ?? session.verificationUri;
      final signInFuture = ref
          .read(authControllerProvider.notifier)
          .completeGitHubDeviceFlow(session: session);
      await launchUrl(launchTarget, mode: LaunchMode.externalApplication);

      if (!mounted) {
        return;
      }

      final user = await showDialog<GitHubUser>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return _GitHubSettingsDialog(
            session: session,
            signInFuture: signInFuture,
            onOpenBrowser: () async {
              await launchUrl(
                launchTarget,
                mode: LaunchMode.externalApplication,
              );
            },
          );
        },
      );

      if (!mounted || user == null) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SlashText('GitHub connected as @${user.login}')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: SlashText('GitHub sign-in failed: $e')));
    }
  }

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).resetAll();
    ref.invalidate(authControllerProvider);
    ref.invalidate(repoControllerProvider);

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF23232A) : Colors.white,
        elevation: 1,
        title: Row(
          children: [
            Image.asset('assets/slash2.png', height: 36),
            const SizedBox(width: 12),
            const SlashText('Settings', fontWeight: FontWeight.bold),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton(
              onPressed: _save,
              child: const SlashText('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            context: context,
            titleIcon: Icons.tune,
            title: 'AI Provider',
            child: Wrap(
              spacing: 10,
              children: [
                ChoiceChip(
                  label: const SlashText('OpenAI'),
                  selected: _provider == 'openai',
                  onSelected: (_) => setState(() => _provider = 'openai'),
                ),
                ChoiceChip(
                  label: const SlashText('OpenRouter'),
                  selected: _provider == 'openrouter',
                  onSelected: (_) => setState(() => _provider = 'openrouter'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_provider == 'openrouter')
            _card(
              context: context,
              titleIcon: Icons.route_outlined,
              title: 'OpenRouter',
              child: Column(
                children: [
                  TextField(
                    controller: _openRouterKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText: 'OpenRouter API key',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _openRouterModelController,
                    decoration: const InputDecoration(
                      hintText: 'OpenRouter model',
                    ),
                  ),
                ],
              ),
            )
          else
            _card(
              context: context,
              titleIcon: Icons.auto_awesome_outlined,
              title: 'OpenAI',
              child: Column(
                children: [
                  TextField(
                    controller: _openAIKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText: 'OpenAI API key',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _openAIModelController,
                    decoration: const InputDecoration(hintText: 'OpenAI model'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _card(
            context: context,
            titleIcon: Icons.account_circle_outlined,
            title: 'GitHub',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SlashText(
                  'GitHub sign-in uses the OAuth device flow. Tap Sign in and approve the request in your browser.',
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.72),
                ),
                if (!AppConfig.hasBundledGitHubClientId) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _githubClientIdController,
                    decoration: const InputDecoration(
                      hintText: 'GitHub OAuth App Client ID',
                      helperText:
                          'Create an OAuth App at github.com/settings/developers',
                    ),
                  ),
                ],
                if (auth.githubUser != null)
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundImage:
                            auth.githubUser?.avatarUrl != null
                                ? NetworkImage(auth.githubUser!.avatarUrl!)
                                : null,
                        child:
                            auth.githubUser?.avatarUrl == null
                                ? Text(auth.githubUser!.login[0].toUpperCase())
                                : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SlashText(
                              auth.githubUser?.name ?? auth.githubUser!.login,
                              fontWeight: FontWeight.w600,
                            ),
                            SlashText(
                              '@${auth.githubUser!.login}',
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  const SlashText(
                    'No GitHub session is connected yet.',
                    fontSize: 12,
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: Text(
                          auth.hasGitHubAuth ? 'Reconnect' : 'Sign in',
                        ),
                        onPressed:
                            auth.isSigningInWithGitHub ||
                                    !auth.canSignInWithGitHub
                                ? null
                                : _connectGitHub,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
                        onPressed:
                            auth.hasGitHubAuth
                                ? () =>
                                    ref
                                        .read(authControllerProvider.notifier)
                                        .disconnectGitHub()
                                : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _NavFeaturesCard(),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              label: const SlashText('Logout & Reset'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _logout,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required BuildContext context,
    required IconData titleIcon,
    required String title,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      color: isDark ? const Color(0xFF23232A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(titleIcon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                SlashText(title, fontWeight: FontWeight.w600),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _GitHubSettingsDialog extends StatefulWidget {
  final GitHubDeviceCodeSession session;
  final Future<GitHubUser> signInFuture;
  final Future<void> Function() onOpenBrowser;

  const _GitHubSettingsDialog({
    required this.session,
    required this.signInFuture,
    required this.onOpenBrowser,
  });

  @override
  State<_GitHubSettingsDialog> createState() => _GitHubSettingsDialogState();
}

class _GitHubSettingsDialogState extends State<_GitHubSettingsDialog> {
  bool _didAutoClose = false;

  void _complete(GitHubUser user) {
    if (_didAutoClose || !mounted) {
      return;
    }
    _didAutoClose = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(user);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const SlashText('Finish GitHub sign-in'),
      content: FutureBuilder<GitHubUser>(
        future: widget.signInFuture,
        builder: (context, snapshot) {
          final user = snapshot.data;
          final waiting = snapshot.connectionState != ConnectionState.done;
          final error = snapshot.hasError ? snapshot.error.toString() : null;

          if (user != null) {
            _complete(user);
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SlashText(
                'Approve the request in your browser using this code. You do not need to paste a GitHub token back into /slash.',
                fontSize: 13,
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        widget.session.userCode,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy code',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: widget.session.userCode),
                        );
                      },
                      icon: const Icon(Icons.copy_all_outlined),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: waiting ? widget.onOpenBrowser : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open browser again'),
              ),
              const SizedBox(height: 12),
              if (waiting)
                const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: SlashText(
                        'Waiting for GitHub approval...',
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              else if (error != null)
                SlashText(error, color: Colors.red, fontSize: 13)
              else if (user != null)
                SlashText(
                  'Connected as @${user.login}. Returning to /slash...',
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
            ],
          );
        },
      ),
      actions: [
        FutureBuilder<GitHubUser>(
          future: widget.signInFuture,
          builder: (context, snapshot) {
            final waiting = snapshot.connectionState != ConnectionState.done;
            if (waiting) {
              return TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              );
            }

            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}

// ── Navigation features card ───────────────────────────────────────────────

class _NavFeaturesCard extends ConsumerWidget {
  const _NavFeaturesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prefs = ref.watch(navPreferencesProvider);
    final pickable = SlashFeature.values
        .where((f) => kFeatureMeta[f]?.showInPicker == true)
        .toList();

    return Card(
      color: isDark ? const Color(0xFF23232A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const SlashText('Navigation', fontWeight: FontWeight.w600),
              ],
            ),
            const SizedBox(height: 4),
            SlashText(
              'Choose which features appear on your bottom nav bar.',
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            for (final feature in pickable)
              _FeatureToggleRow(
                feature: feature,
                enabled: prefs.contains(feature),
                onToggle:
                    () =>
                        ref.read(navPreferencesProvider.notifier).toggle(
                          feature,
                        ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeatureToggleRow extends StatelessWidget {
  final SlashFeature feature;
  final bool enabled;
  final VoidCallback onToggle;

  const _FeatureToggleRow({
    required this.feature,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final meta = kFeatureMeta[feature]!;
    final isRequired = meta.required;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (meta.assetIcon != null)
            Image.asset(
              meta.assetIcon!,
              width: 20,
              height: 20,
              color: Theme.of(context).colorScheme.onSurface.withValues(
                alpha: 0.72,
              ),
            )
          else
            Icon(
              meta.icon,
              size: 20,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: SlashText(
              meta.label,
              fontSize: 14,
              color:
                  isRequired
                      ? Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.45)
                      : null,
            ),
          ),
          if (isRequired)
            SlashText(
              'Always on',
              fontSize: 11,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            )
          else
            Switch(
              value: enabled,
              onChanged: (_) => onToggle(),
            ),
        ],
      ),
    );
  }
}
