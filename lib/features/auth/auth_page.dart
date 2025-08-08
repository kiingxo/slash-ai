import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';
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
  // Model selection is now done via a bottom sheet with search

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

  Future<void> _showModelSelectorSheet() async {
    final key = openRouterKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        errorMessage = 'Enter your OpenRouter API key first to browse models.';
      });
      return;
    }
    if (openRouterModels.isEmpty && !loadingModels) {
      await _loadModelsIfNeeded(key);
      if (!mounted) return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.98),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = openRouterModels
                .where((m) => m.toLowerCase().contains(query.toLowerCase()))
                .toList();
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Icon(Icons.view_list_outlined, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Select OpenRouter model',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          autofocus: true,
                          onChanged: (val) => setSheetState(() => query = val),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Search models',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (loadingModels)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
                        )
                      else
                        Expanded(
                          child: filtered.isEmpty
                              ? const Center(
                                  child: Text('No models found'),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  itemBuilder: (_, idx) {
                                    final m = filtered[idx];
                                    final selected = m == openRouterModelController.text;
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        m,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      trailing: selected
                                          ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                                          : null,
                                      onTap: () {
                                        setState(() {
                                          openRouterModelController.text = m;
                                        });
                                        Navigator.of(context).pop();
                                      },
                                    );
                                  },
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemCount: filtered.length,
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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
    return ThemeBuilder(
      builder: (context, colors, ref) {
        return SlashBackground(
          showGrid: false,
          showSlashes: false,
          overlayOpacity: 0.50,
          animate: false,
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                // const Icon(
                //   Icons.lock_outline,
                //   size: 48,
                //   color: Color(0xFF6366F1),
                // ),
                Image.asset('assets/slash2.png', width: 96, height: 96),
                const SizedBox(height: 12),
                SlashText(
                  'Connect',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 300,
                  child: SlashText(
                    'Add your model key and GitHub PAT to continue.',
                    fontSize: 13,
                    color: colors.always909090,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 360),
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline, size: 14, color: Colors.white70),
                                SizedBox(width: 6),
                                Text('Secure setup', style: TextStyle(fontSize: 11, color: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                        _ModelSegmentedControl(
                          value: model,
                          onChanged: (value) {
                            setState(() {
                              model = value;
                              _validate();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
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
                          const SizedBox(height: 8),
                          // Button that opens bottom sheet model selector with search
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: TextFormField(
                                readOnly: true,
                                controller: openRouterModelController,
                                onTap: _showModelSelectorSheet,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: 'Model',
                                  hintText: 'Select model',
                                  suffixIcon: const Icon(Icons.arrow_drop_down, size: 18),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SlashTextField(
                          controller: githubController,
                          hint: 'Paste your GitHub PAT',
                          obscure: true,
                        ),
                        const SizedBox(height: 20),
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

class _ModelSegmentedControl extends StatelessWidget {
  final String value; // 'openrouter' | 'gemini'
  final ValueChanged<String> onChanged;
  const _ModelSegmentedControl({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOpenRouter = value == 'openrouter';
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.12)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              selected: isOpenRouter,
              label: 'OpenRouter',
              icon: Icons.router_outlined,
              onTap: () => onChanged('openrouter'),
            ),
          ),
          Expanded(
            child: _Segment(
              selected: !isOpenRouter,
              label: 'Gemini',
              icon: Icons.auto_awesome,
              onTap: () => onChanged('gemini'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _Segment({required this.selected, required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
