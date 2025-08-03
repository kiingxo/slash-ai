import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/auth_page.dart';
import '../../services/secure_storage_service.dart';
import '../../features/repo/repo_controller.dart';
import '../../services/github_oauth_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _geminiCtrl = TextEditingController();
  final _openRouterCtrl = TextEditingController();
  final _openRouterModelCtrl = TextEditingController();
  final _githubPatCtrl = TextEditingController();
  String _provider = 'gemini';
  bool _oauthInProgress = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    _provider = (auth.model.isNotEmpty ? auth.model : 'gemini');
    _geminiCtrl.text = auth.geminiApiKey ?? '';
    // OpenRouter is not exposed via legacy AuthController; fetch from storage to populate fields.
    _initOpenRouterFromStorage();
    _githubPatCtrl.text = auth.githubPat ?? '';
  }

  Future<void> _initOpenRouterFromStorage() async {
    final storage = SecureStorageService();
    _openRouterCtrl.text = (await storage.getApiKey('openrouter_api_key')) ?? '';
    _openRouterModelCtrl.text = (await storage.getApiKey('openrouter_model')) ?? '';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _geminiCtrl.dispose();
    _openRouterCtrl.dispose();
    _openRouterModelCtrl.dispose();
    _githubPatCtrl.dispose();
    super.dispose();
  }

  Future<void> _startGitHubOAuth() async {
    if (_oauthInProgress) return;
    setState(() => _oauthInProgress = true);
    try {
      final dc = await GitHubOAuthService.startDeviceFlow();
      final uriToOpen = dc.verificationUriComplete.isNotEmpty
          ? dc.verificationUriComplete
          : dc.verificationUri;
      final uri = Uri.parse(uriToOpen);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      final token = await GitHubOAuthService.pollForToken(
        deviceCode: dc.deviceCode,
        intervalSeconds: dc.interval,
      );
      final storage = SecureStorageService();
      await storage.saveApiKey('github_token', token);
      await storage.deleteApiKey('github_pat');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: SlashText('GitHub connected via OAuth')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: SlashText('GitHub OAuth failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _oauthInProgress = false);
    }
  }

  Future<void> _save() async {
    final auth = ref.read(authControllerProvider.notifier);
    final storage = SecureStorageService();

    // Persist provider
    await auth.saveModel(_provider);

    // Persist keys
    if (_provider == 'gemini') {
      await auth.saveGeminiApiKey(_geminiCtrl.text.trim());
    }
    // Store OpenRouter keys directly (legacy AuthController lacks fields)
    await storage.saveApiKey('openrouter_api_key', _openRouterCtrl.text.trim());
    if (_openRouterModelCtrl.text.trim().isNotEmpty) {
      await storage.saveApiKey('openrouter_model', _openRouterModelCtrl.text.trim());
    }

    // GitHub PAT
    await auth.saveGitHubPat(_githubPatCtrl.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: SlashText('Settings saved')),
      );
      setState(() {});
    }
  }

  Future<void> _logout() async {
    // Full app reset: clear secure storage and invalidate providers; then navigate to AuthPage
    final storage = SecureStorageService();
    await storage.deleteAll();

    // Invalidate all stateful providers that hold credentials or repo state
    ref.invalidate(authControllerProvider);
    ref.invalidate(repoControllerProvider);

    if (!mounted) return;

    // Pop any dialogs/sheets first to avoid leaving Settings in the stack
    Navigator.of(context)
      ..popUntil((route) => route.isFirst);

    // Replace the entire stack with AuthPage (not SettingsScreen)
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC),
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
            title: 'Provider',
            child: Row(
              children: [
                ChoiceChip(
                  label: const SlashText('Gemini'),
                  selected: _provider == 'gemini',
                  onSelected: (_) => setState(() => _provider = 'gemini'),
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const SlashText('OpenRouter'),
                  selected: _provider == 'openrouter',
                  onSelected: (_) => setState(() => _provider = 'openrouter'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_provider == 'gemini') _card(
            context: context,
            titleIcon: Icons.vpn_key,
            title: 'Gemini API Key',
            child: TextField(
              controller: _geminiCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Paste your Gemini API key',
              ),
            ),
          ),
          if (_provider == 'openrouter') _card(
            context: context,
            titleIcon: Icons.router,
            title: 'OpenRouter',
            child: Column(
              children: [
                TextField(
                  controller: _openRouterCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Paste your OpenRouter API key',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _openRouterModelCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Model (e.g., openrouter/anthropic/claude-3.5-sonnet)',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            context: context,
            titleIcon: Icons.lock,
            title: 'GitHub',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: _oauthInProgress ? null : _startGitHubOAuth,
                  icon: const Icon(Icons.login),
                  label: SlashText(_oauthInProgress ? 'Signing in…' : 'Sign in with GitHub'),
                ),
                const SizedBox(height: 10),
                ExpansionTile(
                  title: const SlashText('Use a Personal Access Token instead (legacy)'),
                  children: [
                    TextField(
                      controller: _githubPatCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        hintText: 'GitHub Personal Access Token',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
