import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    // ignore: use_build_context_synchronously
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
      return value.substring(0, 3) + '***' + value.substring(value.length - 3);
    }
    if (authState.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('API Key Status', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Gemini/OpenAI Key: '),
                Text(mask(authState.geminiApiKey), style: const TextStyle(fontFamily: 'monospace')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('GitHub PAT: '),
                Text(mask(authState.githubPat), style: const TextStyle(fontFamily: 'monospace')),
              ],
            ),
            const SizedBox(height: 24),
            if ((authState.geminiApiKey == null || authState.geminiApiKey!.isEmpty) &&
                (authState.githubPat == null || authState.githubPat!.isEmpty))
              Text('No API keys found. Please log in again.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Expanded(child: Container()),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Clear Tokens / Logout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => _logout(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 