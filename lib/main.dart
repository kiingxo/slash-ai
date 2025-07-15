import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/theme/app_theme.dart';
import 'features/auth/auth_page.dart';
import 'home_shell.dart';
import 'services/secure_storage_service.dart';

void main() {
  runApp(const ProviderScope(child: SlashApp()));
}

class SlashApp extends StatelessWidget {
  const SlashApp({super.key});

  Future<bool> _hasTokens() async {
    final storage = SecureStorageService();
    final gemini = await storage.getApiKey('gemini_api_key');
    final github = await storage.getApiKey('github_pat');
    return gemini != null && gemini.isNotEmpty && github != null && github.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '/slash',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: FutureBuilder<bool>(
        future: _hasTokens(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data! ? const HomeShell() : const AuthPage();
        },
      ),
    );
  }
}
