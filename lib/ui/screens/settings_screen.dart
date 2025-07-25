import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import '../../features/auth/auth_controller.dart';
import '../../services/secure_storage_service.dart';
import '../../features/auth/auth_page.dart';
import '../../features/repo/repo_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final storage = SecureStorageService();
    await storage.deleteAll();
    ref.invalidate(authControllerProvider);
    ref.invalidate(repoControllerProvider);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    String mask(String? value) {
      if (value == null || value.isEmpty) return 'Not set';
      if (value.length <= 6) return '*' * value.length;
      return '${value.substring(0, 3)}***${value.substring(value.length - 3)}';
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (authState.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const SlashText('Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
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
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          // Friendly header
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SlashText(
              'Configure your AI provider, API keys, and GitHub access. Your credentials are stored securely on your device.',
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          // AI Model Card
          Card(
            color: isDark ? const Color(0xFF23232A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.memory,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      SlashText('AI Provider'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Radio<String>(
                        value: 'gemini',
                        groupValue: authState.model,
                        onChanged: (val) {
                          if (val != null)
                            ref
                                .read(authControllerProvider.notifier)
                                .saveModel(val);
                        },
                      ),
                      Image.asset('assets/slash.png', height: 24),
                      const SizedBox(width: 6),
                      const SlashText('Gemini'),
                      const SizedBox(width: 24),
                      Radio<String>(
                        value: 'openai',
                        groupValue: authState.model,
                        onChanged: (val) {
                          if (val != null)
                            ref
                                .read(authControllerProvider.notifier)
                                .saveModel(val);
                        },
                      ),
                      Icon(Icons.bolt, color: Colors.amber[700]),
                      const SizedBox(width: 6),
                      const SlashText('OpenAI'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // API Key Card
          Card(
            color: isDark ? const Color(0xFF23232A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.vpn_key,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      SlashText('API Keys'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (authState.model == 'gemini') ...[
                    Row(
                      children: [
                        Image.asset('assets/slash.png', height: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            obscureText: true,
                            controller: TextEditingController(
                              text: authState.geminiApiKey ?? '',
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Enter Gemini API Key',
                            ),
                            onSubmitted: (val) {
                              ref
                                  .read(authControllerProvider.notifier)
                                  .saveGeminiApiKey(val.trim());
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {},
                          child: const SlashText('Save'),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Icon(Icons.bolt, color: Colors.amber[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            obscureText: true,
                            controller: TextEditingController(
                              text: authState.openAIApiKey ?? '',
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Enter OpenAI API Key',
                            ),
                            onSubmitted: (val) {
                              ref
                                  .read(authControllerProvider.notifier)
                                  .saveOpenAIApiKey(val.trim());
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {},
                          child: const SlashText('Save'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.lock, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          obscureText: true,
                          controller: TextEditingController(
                            text: authState.githubPat ?? '',
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Enter GitHub PAT',
                          ),
                          onSubmitted: (val) {
                            ref
                                .read(authControllerProvider.notifier)
                                .saveGitHubPat(val.trim());
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {},
                        child: const SlashText('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Status Card
          Card(
            color: isDark ? const Color(0xFF23232A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      SlashText('Key Status'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Image.asset('assets/slash.png', height: 18),
                      const SizedBox(width: 8),
                      const SlashText('Gemini Key:'),
                      const SizedBox(width: 8),
                      SlashText(
                        mask(authState.geminiApiKey),
                        fontFamily: 'monospace',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.bolt, color: Colors.amber[700], size: 18),
                      const SizedBox(width: 8),
                      const SlashText('OpenAI Key:'),
                      const SizedBox(width: 8),
                      SlashText(
                        mask(authState.openAIApiKey),
                        fontFamily: 'monospace',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.lock, color: Colors.grey, size: 18),
                      const SizedBox(width: 8),
                      const SlashText('GitHub PAT:'),
                      const SizedBox(width: 8),
                      SlashText(
                        mask(authState.githubPat),
                        fontFamily: 'monospace',
                      ),
                    ],
                  ),
                  if ((authState.geminiApiKey == null ||
                          authState.geminiApiKey!.isEmpty) &&
                      (authState.openAIApiKey == null ||
                          authState.openAIApiKey!.isEmpty) &&
                      (authState.githubPat == null ||
                          authState.githubPat!.isEmpty))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SlashText(
                        'No API keys found. Please log in again.',
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Logout
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              label: const SlashText('Clear Tokens / Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                elevation: 0,
              ),
              onPressed: () => _logout(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}
