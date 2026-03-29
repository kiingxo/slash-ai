import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../common/nav_preferences.dart';
import '../../features/onboarding/feature_picker_page.dart';
import '../../home_shell.dart';
import '../../services/app_config.dart';
import '../../services/github_auth_service.dart';
import '../../ui/components/cool_background.dart';
import '../../ui/components/slash_button.dart';
import '../../ui/components/slash_text.dart';
import '../../ui/components/slash_text_field.dart';
import '../../ui/theme/app_theme_builder.dart';
import 'auth_controller.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _openAIKeyController = TextEditingController();
  final _openAIModelController = TextEditingController(
    text: AppConfig.defaultOpenAIModel,
  );
  final _openRouterKeyController = TextEditingController();
  final _openRouterModelController = TextEditingController(
    text: AppConfig.defaultOpenRouterModel,
  );

  bool _seeded = false;
  String _provider = 'openai';
  String? _errorMessage;
  String? _successMessage;
  bool _loadingModels = false;
  List<String> _openRouterModels = const [];

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
    _seeded = true;
  }

  @override
  void dispose() {
    _openAIKeyController.dispose();
    _openAIModelController.dispose();
    _openRouterKeyController.dispose();
    _openRouterModelController.dispose();
    super.dispose();
  }

  bool get _hasAiConfig {
    if (_provider == 'openrouter') {
      return _openRouterKeyController.text.trim().isNotEmpty;
    }
    return _openAIKeyController.text.trim().isNotEmpty;
  }

  Future<void> _persistAiConfig(AuthController authController) async {
    await authController.saveModel(_provider);
    if (_provider == 'openrouter') {
      await authController.saveOpenRouterKey(_openRouterKeyController.text);
      await authController.saveOpenRouterModel(_openRouterModelController.text);
    } else {
      await authController.saveOpenAIApiKey(_openAIKeyController.text);
      await authController.saveOpenAIModel(_openAIModelController.text);
    }
  }

  Future<void> _saveAndContinue() async {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });

    if (!_hasAiConfig) {
      setState(() {
        _errorMessage =
            'Add your ${_provider == 'openrouter' ? 'OpenRouter' : 'OpenAI'} key before continuing.';
      });
      return;
    }

    final authController = ref.read(authControllerProvider.notifier);
    final authState = ref.read(authControllerProvider);

    if (!authState.hasGitHubAuth) {
      setState(() {
        _errorMessage = 'Sign in with GitHub before continuing.';
      });
      return;
    }

    await _persistAiConfig(authController);

    setState(() {
      _successMessage = 'Workspace connected.';
    });

    if (!mounted) {
      return;
    }

    final destination =
        NavPreferencesNotifier.isSetupDone
            ? const HomeShell()
            : const FeaturePickerPage();

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  Future<void> _continueOpsFirst() async {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });

    final authController = ref.read(authControllerProvider.notifier);
    await _persistAiConfig(authController);
    await authController.enableGuestMode();
    ref.read(navPreferencesProvider.notifier).saveAll({SlashFeature.ops});
    ref.read(selectedFeatureProvider.notifier).state = SlashFeature.ops;

    if (!mounted) {
      return;
    }

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  Future<void> _startGitHubSignIn() async {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });

    final authController = ref.read(authControllerProvider.notifier);

    try {
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
          return _GitHubDeviceFlowDialog(
            session: session,
            onOpenBrowser: () async {
              await launchUrl(
                launchTarget,
                mode: LaunchMode.externalApplication,
              );
            },
            signInFuture: signInFuture,
          );
        },
      );

      if (!mounted) {
        return;
      }

      if (user != null) {
        if (_hasAiConfig) {
          await _saveAndContinue();
          return;
        }

        setState(() {
          _successMessage =
              'GitHub connected as @${user.login}. Add your ${_provider == 'openrouter' ? 'OpenRouter' : 'OpenAI'} key to continue.';
        });
        return;
      }

      final updatedAuth = ref.read(authControllerProvider);
      if (updatedAuth.hasGitHubAuth && mounted) {
        if (_hasAiConfig) {
          await _saveAndContinue();
          return;
        }

        setState(() {
          _successMessage =
              'GitHub connected as @${updatedAuth.githubUser?.login ?? 'user'}. Add your ${_provider == 'openrouter' ? 'OpenRouter' : 'OpenAI'} key to continue.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _showOpenRouterModelSelector() async {
    final key = _openRouterKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _errorMessage =
            'Add your OpenRouter key first so models can be loaded.';
      });
      return;
    }

    if (_openRouterModels.isEmpty && !_loadingModels) {
      await _loadOpenRouterModels(key);
      if (!mounted) {
        return;
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0.98),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered =
                _openRouterModels
                    .where(
                      (model) =>
                          model.toLowerCase().contains(query.toLowerCase()),
                    )
                    .toList();
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Select OpenRouter model',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          autofocus: true,
                          onChanged:
                              (value) => setSheetState(() => query = value),
                          decoration: InputDecoration(
                            hintText: 'Search models',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_loadingModels)
                        const Expanded(
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 1.6),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            itemCount: filtered.length,
                            separatorBuilder:
                                (_, __) => const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final model = filtered[index];
                              final selected =
                                  model ==
                                  _openRouterModelController.text.trim();
                              return ListTile(
                                dense: true,
                                title: Text(
                                  model,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                trailing:
                                    selected
                                        ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 18,
                                        )
                                        : null,
                                onTap: () {
                                  setState(() {
                                    _openRouterModelController.text = model;
                                  });
                                  Navigator.of(context).pop();
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadOpenRouterModels(String apiKey) async {
    if (_loadingModels) {
      return;
    }

    setState(() {
      _loadingModels = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('https://openrouter.ai/api/v1/models'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('OpenRouter returned ${response.statusCode}.');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final data = decoded['data'];
      if (data is! List) {
        throw const FormatException('Invalid models response.');
      }

      final models =
          data
              .whereType<Map<String, dynamic>>()
              .map((entry) => (entry['id'] ?? '').toString())
              .where((id) => id.isNotEmpty)
              .toList()
            ..sort();

      setState(() {
        _openRouterModels = models;
        if (!_openRouterModels.contains(
          _openRouterModelController.text.trim(),
        )) {
          _openRouterModelController.text =
              models.isNotEmpty
                  ? models.first
                  : AppConfig.defaultOpenRouterModel;
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load OpenRouter models: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingModels = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final visibleError = _errorMessage ?? auth.error;

    return ThemeBuilder(
      builder: (context, colors, ref) {
        return SlashBackground(
          showGrid: false,
          showSlashes: false,
          overlayOpacity: 0.52,
          animate: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  children: [
                    Image.asset('assets/slash2.png', width: 104, height: 104),
                    const SizedBox(height: 14),
                    SlashText(
                      'by Blueprintlabs',
                      fontSize: 12,
                      color: colors.always909090,
                      textAlign: TextAlign.center,
                    ),
                  
                    const SizedBox(height: 18),
                    _buildGlassCard(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (visibleError != null) ...[
                            SlashText(
                              visibleError,
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_successMessage != null) ...[
                            SlashText(
                              _successMessage!,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                          ],
                          _ProviderSegmentedControl(
                            value: _provider,
                            onChanged: (value) {
                              setState(() {
                                _provider = value;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          if (_provider == 'openrouter') ...[
                            SlashTextField(
                              controller: _openRouterKeyController,
                              hint: 'OpenRouter API key',
                              obscure: true,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: SlashTextField(
                                    controller: _openRouterModelController,
                                    hint: 'OpenRouter model',
                                    readOnly: true,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  height: 44,
                                  child: OutlinedButton(
                                    onPressed:
                                        _loadingModels
                                            ? null
                                            : _showOpenRouterModelSelector,
                                    child: Text(
                                      _loadingModels ? 'Loading' : 'Browse',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            SlashTextField(
                              controller: _openAIKeyController,
                              hint: 'OpenAI API key',
                              obscure: true,
                            ),
                            const SizedBox(height: 10),
                            SlashTextField(
                              controller: _openAIModelController,
                              hint: 'OpenAI model',
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (auth.githubUser != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundImage:
                                        auth.githubUser?.avatarUrl != null
                                            ? NetworkImage(
                                              auth.githubUser!.avatarUrl!,
                                            )
                                            : null,
                                    child:
                                        auth.githubUser?.avatarUrl == null
                                            ? Text(
                                              auth.githubUser!.login[0]
                                                  .toUpperCase(),
                                            )
                                            : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SlashText(
                                          auth.githubUser?.name ??
                                              auth.githubUser!.login,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        SlashText(
                                          '@${auth.githubUser!.login}',
                                          fontSize: 12,
                                          color: colors.always909090,
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed:
                                        auth.isSigningInWithGitHub
                                            ? null
                                            : () =>
                                                ref
                                                    .read(
                                                      authControllerProvider
                                                          .notifier,
                                                    )
                                                    .disconnectGitHub(),
                                    child: const Text('Disconnect'),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (!auth.hasGitHubAuth) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: SlashButton(
                                    text:
                                        auth.isSigningInWithGitHub
                                            ? 'Connecting GitHub...'
                                            : 'Connect GitHub',
                                    onPressed:
                                        auth.isSigningInWithGitHub
                                            ? () {}
                                            : _startGitHubSignIn,
                                    validator:
                                        () =>
                                            auth.canSignInWithGitHub &&
                                            !auth.isSigningInWithGitHub,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _QuickActionButton(
                                  icon: Icons.terminal_rounded,
                                  tooltip: 'Explore Ops',
                                  onTap:
                                      auth.isSigningInWithGitHub
                                          ? null
                                          : _continueOpsFirst,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SlashText(
                              'Use Ops without GitHub.',
                              fontSize: 12,
                              color: colors.always909090,
                              textAlign: TextAlign.center,
                            ),
                          ] else ...[
                            SlashButton(
                              text: 'Continue',
                              onPressed:
                                  auth.isSigningInWithGitHub
                                      ? () {}
                                      : _saveAndContinue,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed:
                                        auth.isSigningInWithGitHub
                                            ? null
                                            : _startGitHubSignIn,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(48),
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.14,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.login_rounded),
                                    label: const Text('Reconnect GitHub'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _QuickActionButton(
                                  icon: Icons.terminal_rounded,
                                  tooltip: 'Open Ops Layout',
                                  onTap:
                                      auth.isSigningInWithGitHub
                                          ? null
                                          : _continueOpsFirst,
                                ),
                              ],
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
      },
    );
  }

  Widget _buildGlassCard(BuildContext context, {required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _QuickActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color:
                enabled
                    ? theme.colorScheme.surface.withValues(alpha: 0.72)
                    : theme.colorScheme.surface.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(
                alpha: enabled ? 0.18 : 0.08,
              ),
            ),
          ),
          child: Icon(
            icon,
            color:
                enabled
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

class _ProviderSegmentedControl extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _ProviderSegmentedControl({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isOpenRouter = value == 'openrouter';
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _ProviderSegment(
              label: 'OpenAI',
              icon: Icons.auto_awesome_outlined,
              selected: !isOpenRouter,
              onTap: () => onChanged('openai'),
            ),
          ),
          Expanded(
            child: _ProviderSegment(
              label: 'OpenRouter',
              icon: Icons.route_outlined,
              selected: isOpenRouter,
              onTap: () => onChanged('openrouter'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderSegment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color:
            selected
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color:
                    selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GitHubDeviceFlowDialog extends StatefulWidget {
  final GitHubDeviceCodeSession session;
  final Future<GitHubUser> signInFuture;
  final Future<void> Function() onOpenBrowser;

  const _GitHubDeviceFlowDialog({
    required this.session,
    required this.signInFuture,
    required this.onOpenBrowser,
  });

  @override
  State<_GitHubDeviceFlowDialog> createState() =>
      _GitHubDeviceFlowDialogState();
}

class _GitHubDeviceFlowDialogState extends State<_GitHubDeviceFlowDialog> {
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
          final code = widget.session.userCode;
          final waiting = snapshot.connectionState != ConnectionState.done;
          final error = snapshot.hasError ? snapshot.error.toString() : null;
          final user = snapshot.data;

          if (user != null) {
            _complete(user);
          }

          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // const SlashText(
                //   'Approve the request in your browser using this code. You do not need to paste a GitHub token back into /slash.',
                //   fontSize: 13,
                // ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          code,
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
                          await Clipboard.setData(ClipboardData(text: code));
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
                if (waiting) ...[
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
                  ),
                ] else if (error != null) ...[
                  SlashText(error, color: Colors.red, fontSize: 13),
                ] else if (user != null) ...[
                  SlashText(
                    'Connected as @${user.login}. Returning to /slash...',
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ],
              ],
            ),
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
