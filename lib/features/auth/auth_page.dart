import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_controller.dart';
import '../../ui/components/slash_text_field.dart';
import '../../ui/components/slash_button.dart';
import '../../home_shell.dart';
import 'package:dio/dio.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  late TextEditingController geminiController;
  late TextEditingController openAIController;
  late TextEditingController githubController;
  String? successMessage;
  String? errorMessage;
  bool isValid = false;
  String model = 'gemini';

  @override
  void initState() {
    super.initState();
    final authState = ref.read(authControllerProvider);
    geminiController = TextEditingController(text: authState.geminiApiKey ?? '');
    openAIController = TextEditingController(text: authState.openAIApiKey ?? '');
    githubController = TextEditingController(text: authState.githubPat ?? '');
    geminiController.addListener(_validate);
    openAIController.addListener(_validate);
    githubController.addListener(_validate);
    model = authState.model;
    _validate();
  }

  void _validate() {
    setState(() {
      if (model == 'gemini') {
        isValid = geminiController.text.isNotEmpty && githubController.text.isNotEmpty;
      } else {
        isValid = openAIController.text.isNotEmpty && githubController.text.isNotEmpty;
      }
    });
  }

  @override
  void dispose() {
    geminiController.dispose();
    openAIController.dispose();
    githubController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      successMessage = null;
      errorMessage = null;
    });
    final githubPat = githubController.text.trim();
    final geminiKey = geminiController.text.trim();
    final openAIKey = openAIController.text.trim();
    // Validate tokens before saving
    if (githubPat.isEmpty || (model == 'gemini' ? geminiKey.isEmpty : openAIKey.isEmpty)) {
      setState(() => errorMessage = 'All fields are required.');
      return;
    }
    // Validate GitHub token
    try {
      final dio = Dio(BaseOptions(
        baseUrl: 'https://api.github.com/',
        headers: {'Authorization': 'token $githubPat'},
      ));
      await dio.get('/user');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        setState(() => errorMessage = 'Your GitHub token is invalid or expired. Please try again.');
        return;
      }
      setState(() => errorMessage = 'Failed to validate GitHub token: ${e.message}');
      return;
    } catch (e) {
      setState(() => errorMessage = 'Failed to validate tokens: ${e.toString()}');
      return;
    }
    // Save tokens if valid
    await ref.read(authControllerProvider.notifier).saveModel(model);
    if (model == 'gemini') {
      await ref.read(authControllerProvider.notifier).saveGeminiApiKey(geminiKey);
    } else {
      await ref.read(authControllerProvider.notifier).saveOpenAIApiKey(openAIKey);
    }
    await ref.read(authControllerProvider.notifier).saveGitHubPat(githubPat);
    setState(() => successMessage = 'Credentials saved!');
    geminiController.clear();
    openAIController.clear();
    githubController.clear();
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
                  if (errorMessage != null) ...[
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Icon(Icons.lock_outline, size: 48, color: Color(0xFF6366F1)),
                  const SizedBox(height: 24),
                  Text('Connect your APIs', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your API key for the selected model and GitHub Personal Access Token (PAT) to continue.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Radio<String>(
                        value: 'gemini',
                        groupValue: model,
                        onChanged: (val) {
                          if (val != null) setState(() { model = val; _validate(); });
                        },
                      ),
                      const Text('Gemini'),
                      const SizedBox(width: 16),
                      Radio<String>(
                        value: 'openai',
                        groupValue: model,
                        onChanged: (val) {
                          if (val != null) setState(() { model = val; _validate(); });
                        },
                      ),
                      const Text('OpenAI'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (model == 'gemini')
                    SlashTextField(
                      controller: geminiController,
                      hint: 'Paste your Gemini API key',
                      obscure: true,
                    )
                  else
                    SlashTextField(
                      controller: openAIController,
                      hint: 'Paste your OpenAI API key',
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