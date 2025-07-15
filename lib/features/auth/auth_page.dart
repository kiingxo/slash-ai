import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_controller.dart';
import '../../ui/components/slash_text_field.dart';
import '../../ui/components/slash_button.dart';
import '../../home_shell.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  late TextEditingController geminiController;
  late TextEditingController githubController;
  String? successMessage;
  bool isValid = false;

  @override
  void initState() {
    super.initState();
    final authState = ref.read(authControllerProvider);
    geminiController = TextEditingController(text: authState.geminiApiKey ?? '');
    githubController = TextEditingController(text: authState.githubPat ?? '');
    geminiController.addListener(_validate);
    githubController.addListener(_validate);
    _validate();
  }

  void _validate() {
    setState(() {
      isValid = geminiController.text.isNotEmpty && githubController.text.isNotEmpty;
    });
  }

  @override
  void dispose() {
    geminiController.dispose();
    githubController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => successMessage = null);
    await ref.read(authControllerProvider.notifier).saveGeminiApiKey(geminiController.text);
    await ref.read(authControllerProvider.notifier).saveGitHubPat(githubController.text);
    setState(() => successMessage = 'Credentials saved!');
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_outline, size: 48, color: Color(0xFF6366F1)),
                  const SizedBox(height: 24),
                  Text('Connect your APIs', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your Gemini API key and GitHub Personal Access Token (PAT) to continue.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  SlashTextField(
                    controller: geminiController,
                    hint: 'Paste your Gemini API key',
                    obscure: true,
                  ),
                  const SizedBox(height: 20),
                  SlashTextField(
                    controller: githubController,
                    hint: 'Paste your GitHub Personal Access Token',
                    obscure: true,
                  ),
                  const SizedBox(height: 32),
                  if (authState.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    SlashButton(
                      label: 'Continue',
                      onTap: isValid ? _connect : () {},
                      loading: authState.isLoading,
                    ),
                  if (successMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(successMessage!, style: const TextStyle(color: Colors.green), textAlign: TextAlign.center),
                  ],
                  if (authState.error != null) ...[
                    const SizedBox(height: 16),
                    Text(authState.error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
} 