import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/ui/components/slash_loading.dart';
import 'package:slash_flutter/ui/theme/app_theme.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';
import 'package:slash_flutter/ui/components/cool_background.dart';
import 'package:toastification/toastification.dart';
import 'features/auth/auth_page.dart';
import 'home_shell.dart';
import 'services/cache_storage_service.dart';
import 'services/secure_storage_service.dart';
import 'dart:async';
import 'features/repo/repo_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CacheStorage.init();
  runApp(const ProviderScope(child: SlashApp()));
}

class SplashScreen extends StatelessWidget {
  final bool showLoader;
  const SplashScreen({super.key, this.showLoader = false});

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      builder:
          (context, colors, ref) => SlashBackground(
            overlayOpacity: 0.45,
            showGrid: false,
            showSlashes: false,
            animate: false,
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/slash2.png', width: 120, height: 120),
                      const SizedBox(height: 24),
                      if (showLoader) const SlashLoading(),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'by Blueprintlabs',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.4,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
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
    final model = await storage.getApiKey(StoredKeys.model) ?? 'openai';
    final github = await storage.getGitHubAccessToken();

    String? aiKey;
    if (model == 'openrouter') {
      aiKey = await storage.getApiKey(StoredKeys.openRouterApiKey);
    } else {
      aiKey = await storage.getApiKey(StoredKeys.openAIApiKey);
    }

    final hasAIKey = aiKey != null && aiKey.isNotEmpty;
    final hasGitHub = github != null && github.isNotEmpty;
    return hasAIKey && hasGitHub;
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
    if (tokens && mounted) {
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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}
