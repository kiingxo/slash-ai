import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/theme/app_theme.dart';
import 'features/auth/auth_page.dart';
import 'home_shell.dart';
import 'services/secure_storage_service.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/repo/repo_controller.dart';

void main() {
  runApp(const ProviderScope(child: SlashApp()));
}

class SplashScreen extends StatelessWidget {
  final bool showLoader;
  const SplashScreen({super.key, this.showLoader = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF000000),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/slash2.png', width: 200, height: 200),
            const SizedBox(height: 50),
            if (showLoader)
              const CircularProgressIndicator(),
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
    final hasAIKey = (gemini != null && gemini.isNotEmpty) || (openai != null && openai.isNotEmpty);
    return hasAIKey && github != null && github.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '/slash',
      
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: SplashGate(_hasTokens),
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
    return _hasTokens!
        ? const HomeShell()
        : const AuthPage();
  }
}