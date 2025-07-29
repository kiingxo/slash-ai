import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slash_flutter/features/file_browser/file_browser_controller.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'package:slash_flutter/ui/components/slash_button.dart';
import 'package:slash_flutter/ui/components/option_selection.dart';
import 'prompt_controller.dart';

// Context control widget to be added to your prompt page
class ContextControlWidget extends ConsumerWidget {
  const ContextControlWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promptState = ref.watch(promptControllerProvider);
    final promptController = ref.read(promptControllerProvider.notifier);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.settings_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const SlashText(
                'Context Strategy',
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              const Spacer(),
              _buildContextIndicator(promptState),
            ],
          ),
          const SizedBox(height: 12),
          
          // Strategy selection
          OptionSelection(
            options: const ["Smart", "Always", "First Only", "On Demand"],
            selectedValue: _getStrategyDisplayName(promptState.contextStrategy),
            onChanged: (value) {
              final strategy = _getStrategyFromDisplayName(value);
              promptController.setContextStrategy(strategy);
            },
            margin: 0,
            padding: 6,
          ),
          
          const SizedBox(height: 8),
          
          // Strategy description
          SlashText(
            _getStrategyDescription(promptState.contextStrategy),
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
          
          const SizedBox(height: 12),
          
          // Action buttons
          Row(
            children: [
              // Force include context button
              Expanded(
                child: SlashButton(
                  text: promptState.includeContextInNextMessage 
                      ? 'Context Queued' 
                      : 'Include Context Next',
                  onPressed: () => promptController.forceIncludeContextInNextMessage(),
                  validator: () => !promptState.includeContextInNextMessage,
                  smallPadding: true,
                ),
              ),
              const SizedBox(width: 8),
              
              // Reset conversation context
              Expanded(
                child: SlashButton(
                  text: 'Reset Context',
                  onPressed: () => promptController.resetConversationContext(),
                  smallPadding: true,
                ),
              ),
            ],
          ),
          
          // Context files info
          if (promptState.repoContextFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.file_copy_outlined,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                SlashText(
                  '${promptState.repoContextFiles.length} files selected',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const Spacer(),
                SlashText(
                  promptState.contextSentInConversation 
                      ? 'Context sent' 
                      : 'Context pending',
                  fontSize: 10,
                  color: promptState.contextSentInConversation 
                      ? Colors.green 
                      : Colors.orange,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContextIndicator(PromptState state) {
    Color color;
    IconData icon;
    String tooltip;

    if (state.includeContextInNextMessage) {
      color = Colors.blue;
      icon = Icons.schedule;
      tooltip = 'Context will be included in next message';
    } else if (state.contextSentInConversation) {
      color = Colors.green;
      icon = Icons.check_circle_outline;
      tooltip = 'Context has been sent in this conversation';
    } else {
      color = Colors.grey;
      icon = Icons.circle_outlined;
      tooltip = 'Context not yet sent';
    }

    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        size: 16,
        color: color,
      ),
    );
  }

  String _getStrategyDisplayName(ContextStrategy strategy) {
    switch (strategy) {
      case ContextStrategy.always:
        return 'Always';
      case ContextStrategy.firstOnly:
        return 'First Only';
      case ContextStrategy.onDemand:
        return 'On Demand';
      case ContextStrategy.smart:
        return 'Smart';
    }
  }

  ContextStrategy _getStrategyFromDisplayName(String displayName) {
    switch (displayName) {
      case 'Always':
        return ContextStrategy.always;
      case 'First Only':
        return ContextStrategy.firstOnly;
      case 'On Demand':
        return ContextStrategy.onDemand;
      case 'Smart':
      default:
        return ContextStrategy.smart;
    }
  }

  String _getStrategyDescription(ContextStrategy strategy) {
    switch (strategy) {
      case ContextStrategy.always:
        return 'Sends full context with every message (highest cost, most accurate)';
      case ContextStrategy.firstOnly:
        return 'Sends context only with the first message (lowest cost, may miss updates)';
      case ContextStrategy.onDemand:
        return 'Sends context only when explicitly requested';
      case ContextStrategy.smart:
        return 'Intelligently decides when to send context (recommended)';
    }
  }
}

// Enhanced message bubble that shows context status
class EnhancedChatMessageBubble extends ConsumerWidget {
  final ChatMessage message;

  const EnhancedChatMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: message.isUser
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: message.isUser
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Context indicator for user messages
            if (message.isUser && message.hasContext)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.attach_file,
                      size: 12,
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    SlashText(
                      'with context',
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ],
                ),
              ),
            
            // Main message content
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!message.isUser)
                  Container(
                    padding: const EdgeInsets.only(right: 8),
                    child: slashIconButton(
                      asset: 'assets/icons/bot.svg',
                      iconSize: 24,
                      onPressed: () {},
                    ),
                  ),
                Flexible(
                  child: Container(
                    padding: EdgeInsets.all(!message.isUser ? 8 : 0),
                    decoration: BoxDecoration(
                      color: !message.isUser
                          ? Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.12)
                          : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SlashText(
                      message.text,
                      color: message.isUser
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            
            // Timestamp and context status
            Container(
              margin: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: message.isUser 
                    ? MainAxisAlignment.end 
                    : MainAxisAlignment.start,
                children: [
                  SlashText(
                    _formatTimestamp(message.timestamp),
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  if (!message.isUser && message.hasContext) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.info_outline,
                      size: 10,
                      color: Colors.blue.withOpacity(0.7),
                    ),
                    const SizedBox(width: 2),
                    SlashText(
                      'used context',
                      fontSize: 10,
                      color: Colors.blue.withOpacity(0.7),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}

// Context summary dialog
class ContextSummaryDialog extends StatelessWidget {
  final List<FileItem> contextFiles;
  final Map<String, String> contextSummaries;

  const ContextSummaryDialog({
    super.key,
    required this.contextFiles,
    required this.contextSummaries,  
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.summarize, size: 20),
          SizedBox(width: 8),
          SlashText('Context Summary'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView.builder(
          itemCount: contextFiles.length,
          itemBuilder: (context, index) {
            final file = contextFiles[index];
            final summary = contextSummaries[file.name] ?? 'No summary available';
            
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.insert_drive_file,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SlashText(
                            file.name,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SlashText(
                      summary,
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const SlashText('Close'),
        ),
      ],
    );
  }
}