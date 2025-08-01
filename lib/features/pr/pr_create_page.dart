import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/features/pr/pr_controller.dart';
import 'package:slash_flutter/features/repo/repo_controller.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';

class PrCreatePage extends ConsumerStatefulWidget {
  const PrCreatePage({super.key});

  @override
  ConsumerState<PrCreatePage> createState() => _PrCreatePageState();
}

class _PrCreatePageState extends ConsumerState<PrCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String? _base;
  String? _head;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(repoControllerProvider).selectedRepo;
    // Simple defaults; user can change
    _base = 'main';
    // Head should normally be "user:branch" or just "branch"
    _head = repo != null ? '' : null;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ctrl = ref.read(prControllerProvider.notifier);
    await ctrl.createPr(
      title: _titleCtrl.text.trim(),
      body: _bodyCtrl.text.trim(),
      head: _head!.trim(),
      base: _base!.trim(),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final prState = ref.watch(prControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const SlashText('Create Pull Request', fontWeight: FontWeight.bold),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const SlashText('Title', fontWeight: FontWeight.bold),
              const SizedBox(height: 6),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  hintText: 'Enter PR title',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              const SlashText('Body (optional)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _bodyCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Describe the changes...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SlashText('Base branch', fontWeight: FontWeight.bold),
                        const SizedBox(height: 6),
                        TextFormField(
                          initialValue: _base,
                          onChanged: (v) => _base = v,
                          decoration: const InputDecoration(
                            hintText: 'e.g. main',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Base is required' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SlashText('Head (branch or user:branch)', fontWeight: FontWeight.bold),
                        const SizedBox(height: 6),
                        TextFormField(
                          initialValue: _head,
                          onChanged: (v) => _head = v,
                          decoration: const InputDecoration(
                            hintText: 'e.g. feature/new-ui or user:feature/new-ui',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Head is required' : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: prState.loading ? null : _submit,
                icon: const Icon(Icons.send),
                label: const SlashText('Create PR'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
