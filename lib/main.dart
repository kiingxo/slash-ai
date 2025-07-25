import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/ui/components/slash_loading.dart';
import 'package:slash_flutter/ui/theme/app_theme.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';
import 'package:toastification/toastification.dart';
import 'features/auth/auth_page.dart';
import 'home_shell.dart';
import 'services/secure_storage_service.dart';
import 'dart:async';
import 'features/repo/repo_controller.dart';

void main() {
  runApp(const ProviderScope(child: SlashApp()));
}

class SplashScreen extends StatelessWidget {
  final bool showLoader;
  const SplashScreen({super.key, this.showLoader = false});

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      builder:
          (context, colors, ref) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/slash2.png', width: 200, height: 200),
                const SizedBox(height: 50),
                if (showLoader) const SlashLoading(),
              ],
            ),
          ),
    );
  }
}

class SlashApp extends StatelessWidget {
  const SlashApp({super.key});

  Future<bool> _hasTokens() async {
    final storage = SecureStorageService();
    final gemini = await storage.getApiKey('gemini_api_key');
    final openai = await storage.getApiKey('openai_api_key');
    final github = await storage.getApiKey('github_pat');
    final hasAIKey =
        (gemini != null && gemini.isNotEmpty) ||
        (openai != null && openai.isNotEmpty);
    return hasAIKey && github != null && github.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: MaterialApp(
        title: '/slash',
        theme: AppTheme.buildAppTheme(Brightness.light),
        darkTheme: AppTheme.buildAppTheme(Brightness.dark),
        themeMode: AppTheme.dark().mode,
        debugShowCheckedModeBanner: false,
        builder: (_, child) {
          return _UnFocus(child: child!);
        },
        home: SplashGate(_hasTokens),
      ),
    );
  }
}

class SplashGate extends StatefulWidget {
  final Future<bool> Function() hasTokens;
  const SplashGate(this.hasTokens, {super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool? _hasTokens;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(seconds: 1));
    final tokens = await widget.hasTokens();
    if (tokens) {
      // Wait for repos to load
      final container = ProviderScope.containerOf(context, listen: false);
      final repoController = container.read(repoControllerProvider.notifier);
      await repoController.whenLoaded;
    }
    if (mounted) {
      setState(() {
        _hasTokens = tokens;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SplashScreen(showLoader: true);
    }
    return _hasTokens! ? const HomeShell() : const AuthPage();
  }
}

class _UnFocus extends StatelessWidget {
  final Widget child;
  const _UnFocus({required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

// com.example.slashFlutter
