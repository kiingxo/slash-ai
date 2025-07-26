import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/ui/components/option_selection.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';
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
    geminiController = TextEditingController(
      text: authState.geminiApiKey ?? '',
    );
    openAIController = TextEditingController(
      text: authState.openAIApiKey ?? '',
    );
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
        isValid =
            geminiController.text.isNotEmpty &&
            githubController.text.isNotEmpty;
      } else {
        isValid =
            openAIController.text.isNotEmpty &&
            githubController.text.isNotEmpty;
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
    if (githubPat.isEmpty ||
        (model == 'gemini' ? geminiKey.isEmpty : openAIKey.isEmpty)) {
      setState(() => errorMessage = 'All fields are required.');
      return;
    }
    // Validate GitHub token
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://api.github.com/',
          headers: {'Authorization': 'token $githubPat'},
        ),
      );
      await dio.get('/user');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        setState(
          () =>
              errorMessage =
                  'Your GitHub token is invalid or expired. Please try again.',
        );
        return;
      }
      setState(
        () => errorMessage = 'Failed to validate GitHub token: ${e.message}',
      );
      return;
    } catch (e) {
      setState(
        () => errorMessage = 'Failed to validate tokens: ${e.toString()}',
      );
      return;
    }
    // Save tokens if valid
    await ref.read(authControllerProvider.notifier).saveModel(model);
    if (model == 'gemini') {
      await ref
          .read(authControllerProvider.notifier)
          .saveGeminiApiKey(geminiKey);
    } else {
      await ref
          .read(authControllerProvider.notifier)
          .saveOpenAIApiKey(openAIKey);
    }
    await ref.read(authControllerProvider.notifier).saveGitHubPat(githubPat);
    setState(() => successMessage = 'Credentials saved!');
    geminiController.clear();
    openAIController.clear();
    githubController.clear();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    return ThemeBuilder(
      builder: (context, colors, ref) {
        return Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // const Icon(
                //   Icons.lock_outline,
                //   size: 48,
                //   color: Color(0xFF6366F1),
                // ),
                Image.asset('assets/slash2.png', width: 150, height: 150),
                // const SizedBox(height: 24),
                SlashText(
                  'Connect your APIs',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 300,
                  child: SlashText(
                    'Enter your API key for the selected model and GitHub Personal Access Token (PAT) to continue.',
                    fontSize: 14,
                    color: colors.always909090,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: colors.always343434.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (errorMessage != null) ...[
                          SlashText(
                            errorMessage!,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,

                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Row(
                        //   mainAxisAlignment: MainAxisAlignment.center,
                        //   children: [
                        //     Radio<String>(
                        //       value: 'gemini',
                        //       groupValue: model,
                        //       onChanged: (val) {
                        //         if (val != null) {
                        //           setState(() {
                        //             model = val;
                        //             _validate();
                        //           });
                        //         }
                        //       },
                        //     ),
                        //     const SlashText('Gemini'),
                        //     const SizedBox(width: 16),
                        //     Radio<String>(
                        //       value: 'openai',
                        //       groupValue: model,
                        //       onChanged: (val) {
                        //         if (val != null) {
                        //           setState(() {
                        //             model = val;
                        //             _validate();
                        //           });
                        //         }
                        //       },
                        //     ),
                        //     const SlashText('OpenAI'),
                        //   ],
                        // ),
                        OptionSelection(
                          options: const ['Gemini', 'OpenAI'],
                          selectedValue: model,
                          onChanged: (value) {
                            setState(() {
                              model = value.toLowerCase();
                              _validate();
                            });
                          },
                        ),
                        const SizedBox(height: 32),
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
                        const SizedBox(height: 24),
                        SlashTextField(
                          controller: githubController,
                          hint: 'Paste your GitHub PAT',
                          obscure: true,
                        ),
                        const SizedBox(height: 40),
                        SlashButton(
                          text: 'Continue',
                          onPressed: isValid ? _connect : () {},
                          loading: authState.isLoading,
                        ),
                        if (successMessage != null) ...[
                          const SizedBox(height: 16),
                          SlashText(
                            successMessage!,
                            textAlign: TextAlign.center,
                            color: Colors.green,
                          ),
                        ],
                        if (authState.error != null) ...[
                          const SizedBox(height: 16),
                          SlashText(
                            authState.error!,
                            color: Colors.red,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
