import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/theme/app_theme.dart';
import 'features/auth/auth_page.dart';
import 'home_shell.dart';
import 'services/secure_storage_service.dart';
import 'dart:async';
import 'package:dio/dio.dart';

void main() {
  runApp(const ProviderScope(child: SlashApp()));
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:  Color(0xFF000000),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/slash2.png', width: 120, height: 120),
            const SizedBox(height: 32),
            // Text(
            //   '/slash',
            //   style: TextStyle(
            //     color: Colors.white,
            //     fontSize: 32,
            //     fontWeight: FontWeight.bold,
            //     letterSpacing: 2,
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}

class SlashApp extends StatelessWidget {
  const SlashApp({super.key});

  Future<bool> _hasValidTokens() async {
    final storage = SecureStorageService();
    final gemini = await storage.getApiKey('gemini_api_key');
    final github = await storage.getApiKey('github_pat');
    
    // Check if both tokens exist and are not empty
    if (gemini == null || gemini.isEmpty || github == null || github.isEmpty) {
      return false;
    }
    
    // Test if GitHub token is valid by making a simple API call
    try {
      final dio = Dio(BaseOptions(
        baseUrl: 'https://api.github.com/',
        headers: {'Authorization': 'token ${github.trim()}'},
      ));
      await dio.get('/user');
      return true;
    } catch (e) {
      // Token is invalid, clear it and return false
      await storage.deleteAll();
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '/slash',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: SplashGate(_hasValidTokens),
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(seconds: 2));
    final tokens = await widget.hasTokens();
    if (mounted) setState(() => _hasTokens = tokens);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasTokens == null) {
      return const SplashScreen();
    }
    return _hasTokens! ? const HomeShell() : const AuthPage();
  }
}
