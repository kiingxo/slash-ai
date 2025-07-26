import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';

class SlashTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? hint;
  final int minLines;
  final int maxLines;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final bool headerLess;
  final TextEditingController? editingController;
  final int? maxLength;
  final bool readOnly;
  final bool obscure;
  final bool autofocus;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final Widget? suffix;
  final TextInputAction textInputAction;
  final Border? border;
  final Color? backgroundColor;
  final String? prefixText;
  final String? headerText;

  const SlashTextField({
    super.key,
    required this.controller,
    this.hint,
    this.initialValue,
    this.onChanged,
    this.headerText = '',
    this.headerLess = true,
    this.editingController,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.readOnly = false,
    this.autofocus = false,
    this.obscure = false,
    this.prefix,
    this.keyboardType,
    this.inputFormatters,
    this.focusNode,
    this.suffix,
    this.textInputAction = TextInputAction.done,
    this.border,
    this.backgroundColor,
    this.prefixText,
  });

  @override
  State<SlashTextField> createState() => _SlashTextFieldState();
}

class _SlashTextFieldState extends State<SlashTextField> {
  @override
  void initState() {
    _node = widget.focusNode ?? FocusNode();
    super.initState();
  }

  FocusNode? _node;

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      useScaffold: false,
      builder: (context, colors, ref) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: colors.alwaysEDEDED.withValues(alpha: 0.1),
                border: Border.all(color: colors.always909090),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  widget.prefix ?? const SizedBox(width: 14),
                  Expanded(
                    child: TextFormField(
                      controller: widget.controller,
                      focusNode: _node,
                      autofocus: widget.autofocus,
                      readOnly: widget.readOnly,
                      onChanged: widget.onChanged,
                      initialValue: widget.initialValue,
                      textInputAction: widget.textInputAction,
                      obscureText: widget.obscure,
                      keyboardType: widget.keyboardType,
                      cursorColor: colors.always8B5CF6,
                      inputFormatters: widget.inputFormatters,
                      maxLength: widget.maxLength,
                      minLines: widget.minLines,
                      maxLines: widget.maxLines,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: colors.lightBlackDarkWhite,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        counter: const SizedBox.shrink(),
                        prefixText: widget.prefixText,
                        prefixStyle: TextStyle(
                          fontFamily: 'DMSans',
                          fontWeight: FontWeight.w600,
                          color: colors.always909090,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        labelStyle: TextStyle(
                          color: colors.always909090,
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                        ),
                        hintText: widget.hint ?? '',
                        hintStyle: TextStyle(
                          fontFamily: 'DMSans',
                          color: colors.always909090,
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  widget.suffix ?? const SizedBox(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
