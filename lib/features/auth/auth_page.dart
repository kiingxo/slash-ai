import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/ui/components/option_selection.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';
import 'auth_controller.dart' as legacy_auth; // legacy controller (existing in project)
import 'auth_service.dart' as new_auth; // new controller with OpenRouter support
import '../../ui/components/slash_text_field.dart';
import 'package:slash_flutter/ui/components/cool_background.dart';
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
  late TextEditingController openRouterKeyController;
  late TextEditingController openRouterModelController;
  late TextEditingController githubController;
  String? successMessage;
  String? errorMessage;
  bool isValid = false;
  String model = 'openrouter';
  List<String> openRouterModels = const [];
  bool loadingModels = false;
  String modelSearch = '';

  @override
  void initState() {
    super.initState();
    final authState = ref.read(new_auth.authControllerProvider);
    geminiController = TextEditingController(
      text: authState.geminiApiKey ?? '',
    );
    openAIController = TextEditingController(
      text: '', // legacy OpenAI removed; keep field for backward compatibility if needed
    );
    openRouterKeyController = TextEditingController(
      text: authState.openRouterApiKey ?? '',
    );
    openRouterModelController = TextEditingController(
      text: authState.openRouterModel ?? '',
    );
    githubController = TextEditingController(text: authState.githubPat ?? '');
    geminiController.addListener(_validate);
    openAIController.addListener(_validate);
    githubController.addListener(_validate);
    openRouterKeyController.addListener(() {
      _validate();
      // Auto-load models when a plausible key is entered or changed.
      final key = openRouterKeyController.text.trim();
      if (model == 'openrouter' && key.isNotEmpty) {
        _loadModelsIfNeeded(key);
      }
    });
    openRouterModelController.addListener(_validate);
    model = (authState.model.isNotEmpty ? authState.model : 'openrouter');
    _validate();
  }

  void _validate() {
    setState(() {
      if (model == 'gemini') {
        isValid =
            geminiController.text.isNotEmpty &&
            githubController.text.isNotEmpty;
      } else if (model == 'openai') {
        isValid =
            openAIController.text.isNotEmpty &&
            githubController.text.isNotEmpty;
      } else {
        // openrouter
        isValid =
            openRouterKeyController.text.isNotEmpty &&
            githubController.text.isNotEmpty;
      }
    });
  }

  @override
  void dispose() {
    geminiController.dispose();
    openAIController.dispose();
    githubController.dispose();
    openRouterKeyController.dispose();
    openRouterModelController.dispose();
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
    final openRouterKey = openRouterKeyController.text.trim();
    final openRouterModel = openRouterModelController.text.trim();
    // Validate tokens before saving
    if (githubPat.isEmpty ||
        (model == 'gemini'
            ? geminiKey.isEmpty
            : (model == 'openai'
                ? openAIKey.isEmpty
                : openRouterKey.isEmpty))) {
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
    // Persist selected model in the new AuthController (auth_service.dart)
    await ref.read(new_auth.authControllerProvider.notifier).setModel(model);
    if (model == 'gemini') {
      await ref
          .read(new_auth.authControllerProvider.notifier)
          .setGeminiKey(geminiKey);
    } else {
      // openrouter
      await ref
          .read(new_auth.authControllerProvider.notifier)
          .setOpenRouterKey(openRouterKey);
      if (openRouterModel.isNotEmpty) {
        await ref
            .read(new_auth.authControllerProvider.notifier)
            .setOpenRouterModel(openRouterModel);
      }
    }

    await ref.read(new_auth.authControllerProvider.notifier).setGitHubPat(githubPat);
    setState(() => successMessage = 'Credentials saved!');
    geminiController.clear();
    openAIController.clear();
    githubController.clear();
    openRouterKeyController.clear();
    openRouterModelController.clear();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(new_auth.authControllerProvider);
    return ThemeBuilder(
      builder: (context, colors, ref) {
        return SlashBackground(
          child: Center(
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
                        // ),the
                        OptionSelection(
                          options: const ['OpenRouter', 'Gemini'],
                          selectedValue: model.toLowerCase() == 'openrouter' ? 'OpenRouter' : 'Gemini',
                          onChanged: (value) {
                            setState(() {
                              model = value.toLowerCase() == 'openrouter' ? 'openrouter' : 'gemini';
                              _validate();
                            });
                          },
                        ),
                        const SizedBox(height: 32),
                        if (model == 'gemini') ...[
                          SlashTextField(
                            controller: geminiController,
                            hint: 'Paste your Gemini API key',
                            obscure: true,
                          ),
                        ] else ...[
                          // OpenRouter fields
                          SlashTextField(
                            controller: openRouterKeyController,
                            hint: 'Paste your OpenRouter API key',
                            obscure: true,
                          ),
                          const SizedBox(height: 12),
                          // Auto-loaded, simple dropdown once key is present
                          DropdownButtonFormField<String>(
                            isDense: true,
                            value: openRouterModels.contains(openRouterModelController.text)
                                ? openRouterModelController.text
                                : null,
                            items: openRouterModels
                                .map((m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(
                                        m,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                openRouterModelController.text = val;
                                _validate();
                              }
                            },
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              labelText: 'Model',
                              hintText: '',
                            ),
                          ),
                        ],
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
                        ),
                        if (successMessage != null) ...[
                          const SizedBox(height: 16),
                          SlashText(
                            successMessage!,
                            textAlign: TextAlign.center,
                            color: Colors.green,
                          ),
                        ],
                        // No external error from auth state; errors shown via local errorMessage
                      ],
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadModelsIfNeeded(String key) async {
    if (loadingModels) return;
    if (key.isEmpty) return;
    setState(() {
      loadingModels = true;
      errorMessage = null;
    });
    try {
      final models = await _fetchOpenRouterModels(key);
      models.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      setState(() {
        openRouterModels = models;
        // Keep current selection if still valid; otherwise leave empty for user to select
        if (!openRouterModels.contains(openRouterModelController.text)) {
          openRouterModelController.text = '';
        }
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load models: $e';
      });
    } finally {
      setState(() {
        loadingModels = false;
      });
    }
  }

  Future<List<String>> _fetchOpenRouterModels(String apiKey) async {
    // Lightweight fetch using Dio already available in file, else could use http.
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://openrouter.ai/api/v1',
        headers: {'Authorization': 'Bearer $apiKey'},
      ),
    );
    final res = await dio.get('/models');
    final data = res.data;
    if (data is Map && data['data'] is List) {
      final List list = data['data'];
      // Extract 'id' for each model entry
      return list
          .map((e) => (e is Map && e['id'] is String) ? e['id'] as String : null)
          .whereType<String>()
          .toList();
    }
    return const <String>[];
  }
}
