import 'package:flutter/material.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import '../../ui/components/slash_button.dart';
import '../../ui/components/slash_diff_viewer.dart';

class FileDiff {
  final String fileName;
  final String oldContent;
  final String newContent;
  FileDiff({
    required this.fileName,
    required this.oldContent,
    required this.newContent,
  });
}

class ReviewPage extends StatelessWidget {
  final List<FileDiff> diffs;
  final String summary;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const ReviewPage({
    super.key,
    required this.diffs,
    required this.summary,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SlashText("Review Slash's Changes"),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.only(
                  top: 16,
                  left: 16,
                  right: 16,
                  bottom: 90,
                ), // extra bottom padding for buttons
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SlashText('Summary: $summary'),
                    const SizedBox(height: 24),
                    ...diffs.map(
                      (diff) => Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SlashText(diff.fileName),
                            const SizedBox(height: 8),
                            SlashDiffViewer(
                              oldContent: diff.oldContent,
                              newContent: diff.newContent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Row(
                children: [
                  Expanded(
                    child: SlashButton(text: 'PR', onPressed: onApprove),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SlashButton(text: 'Reject', onPressed: onReject),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
