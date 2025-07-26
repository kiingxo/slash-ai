import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';

class SlashDropDown extends StatefulWidget {
  final List<DropdownMenuItem<dynamic>>? items;
  final String? mapKey;
  final String hintText;
  final bool headerLess;
  final double? width;
  final bool filled;
  final Widget? prefix;
  final String? value;
  final void Function(dynamic)? onChanged;
  final String? prefixText;
  final String? headerText;
  final String emptyMessage;
  final Color? color;

  const SlashDropDown({
    super.key,
    required this.items,
    this.hintText = "Select an option",
    this.mapKey,
    this.onChanged,
    this.value,
    this.width,
    this.filled = true,
    this.prefix,
    this.headerLess = true,
    this.prefixText,
    this.color,
    this.headerText,
    this.emptyMessage = "No items available",
  });

  @override
  State<SlashDropDown> createState() => _SlashDropDownState();
}

class _SlashDropDownState extends State<SlashDropDown> {
  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      useScaffold: false,
      builder: (context, colors, ref) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            !widget.headerLess
                ? Text(
                  widget.headerText!,
                  style: TextStyle(
                    color: colors.lightBlackDarkWhite,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                )
                : const SizedBox.shrink(),
            const SizedBox(height: 6),
            Container(
              width: widget.width,
              padding:
                  widget.width == null
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
                      : const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
              decoration: BoxDecoration(
                color:
                    widget.color ?? colors.alwaysEDEDED.withValues(alpha: 0.1),
                border: Border.all(color: widget.color ?? colors.always909090),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  widget.prefix ?? const SizedBox.shrink(),
                  Expanded(
                    child: DropdownButtonFormField2<dynamic>(
                      isExpanded: true,
                      isDense: false,
                      autofocus: false,
                      value: widget.value,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: colors.lightBlackDarkWhite,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 0,
                        ),
                        border: InputBorder.none,
                        labelStyle: TextStyle(
                          color: colors.always909090,
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                        ),
                        hintStyle: TextStyle(
                          color: colors.always909090,
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                        ),
                      ),
                      hint: SlashText(
                        widget.hintText,
                        color: colors.always909090,
                        fontSize: 14,
                      ),
                      items:
                          widget.items!.isEmpty
                              ? [
                                DropdownMenuItem<dynamic>(
                                  enabled: false,
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.exclamationmark_circle,
                                        color: colors.always909090,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      SlashText(
                                        widget.emptyMessage,
                                        color: colors.always909090,
                                        fontSize: 14,
                                      ),
                                    ],
                                  ),
                                ),
                              ]
                              : widget.items,
                      validator: (value) {
                        if (value == null) {
                          return 'please select an item.';
                        }
                        return null;
                      },
                      onChanged:
                          widget.items!.isEmpty ? null : widget.onChanged,
                      iconStyleData: IconStyleData(
                        icon: Padding(
                          padding: const EdgeInsets.only(right: 4.0),
                          child: Icon(
                            CupertinoIcons.chevron_down,
                            color:
                                widget.color != null
                                    ? colors.alwaysWhite
                                    : colors.always909090,
                            size: 12,
                          ),
                        ),
                      ),
                      dropdownStyleData: DropdownStyleData(
                        elevation: 0,
                        maxHeight: 200,
                        isOverButton: false,
                        decoration: BoxDecoration(
                          color: colors.alwaysBlack,
                          border: Border.all(color: colors.always909090),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      menuItemStyleData: const MenuItemStyleData(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
