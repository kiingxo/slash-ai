import 'package:flutter/material.dart';
import 'package:slash_flutter/ui/components/slash_text.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';

class OptionSelection extends StatelessWidget {
  final List<String> options;
  final String? selectedValue;
  final double? margin;
  final double? padding;
  final Color? unselectedColor;
  final ValueChanged<String> onChanged;

  const OptionSelection({
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    this.margin,
    this.padding,
    this.unselectedColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: margin ?? 10,
      runSpacing: margin ?? 10,
      alignment: WrapAlignment.center,
      children:
          options.map((option) {
            final bool isSelected =
                option.toLowerCase() == selectedValue?.toLowerCase();
            return ThemeBuilder(
              useScaffold: false,
              builder: (context, colors, ref) {
                return GestureDetector(
                  onTap: () => onChanged(option),
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: margin ?? 8),
                    padding: EdgeInsets.all(padding ?? 12),
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? colors.always8B5CF6
                              : unselectedColor ??
                                  colors.always909090.withValues(alpha: 0.1),
                      border: Border.all(
                        color:
                            isSelected
                                ? colors.always8B5CF6
                                : unselectedColor ??
                                    colors.always909090.withValues(alpha: 0.1),
                      ),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: SlashText(
                      option,
                      color:
                          isSelected ? colors.alwaysWhite : colors.always909090,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                );
              },
            );
          }).toList(),
    );
  }
}
