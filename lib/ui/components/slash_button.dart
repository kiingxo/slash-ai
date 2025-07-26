import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';

import 'slash_loading.dart';

class SlashButton extends StatelessWidget {
  final bool expanded;
  final Widget? icon;
  final String text;
  final Color? color;
  final BorderRadius? radius;
  final Border? border;
  final VoidCallback onPressed;
  final EdgeInsets? padding;
  final bool Function()? validator;
  final double? width;
  final Color? textColor;
  final bool? smallPadding;
  final Color? borderColor;
  final bool loading;

  const SlashButton({
    super.key,
    this.expanded = false,
    required this.text,
    this.color,
    this.icon,
    required this.onPressed,
    this.padding,
    this.validator,
    this.radius,
    this.border,
    this.width,
    this.textColor,
    this.borderColor,
    this.loading = false,
    this.smallPadding = false,
  });

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      useScaffold: false,
      builder: (context, colors, ref) {
        return Container(
          width: width ?? 300,
          decoration: BoxDecoration(borderRadius: radius, border: border),
          child: ElevatedButton(
            onPressed:
                (validator == null ? true : validator!()) ? onPressed : null,
            style: ButtonStyle(
              padding: WidgetStateProperty.all(
                smallPadding!
                    ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                    : const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              elevation: WidgetStateProperty.all(0.0),
              backgroundColor:
                  (validator == null ? true : validator!())
                      ? WidgetStateProperty.all(color ?? colors.always8B5CF6)
                      : WidgetStateProperty.all(
                        (color ?? colors.always8B5CF6).withValues(alpha: 0.5),
                      ),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  side: BorderSide(color: borderColor ?? Colors.transparent),
                  borderRadius: radius ?? BorderRadius.circular(20),
                ),
              ),
            ),
            child:
                loading
                    ? SlashLoading(color: colors.alwaysWhite)
                    : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          text,
                          style: TextStyle(
                            color: textColor ?? colors.alwaysWhite,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: icon ?? const SizedBox.shrink(),
                        ),
                      ],
                    ),
          ),
        );
      },
    );
  }
}

Widget slashIconButton({
  bool hasContainer = true,
  double? padding,
  double? iconSize,
  String? asset,
  IconData? icon,
  Color? color,
  required VoidCallback onPressed,
}) {
  return ThemeBuilder(
    useScaffold: false,
    builder: (context, colors, ref) {
      return GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.all(padding ?? 10),
          decoration: BoxDecoration(
            color:
                hasContainer
                    ? colors.always8B5CF6
                    : color ?? Colors.transparent,
            shape: BoxShape.circle,
          ),
          child:
              asset == null
                  ? Icon(
                    icon,
                    size: iconSize ?? 24,
                    color:
                        hasContainer ? colors.alwaysWhite : colors.always909090,
                  )
                  : SvgPicture.asset(
                    asset,
                    width: iconSize ?? 24,
                    height: iconSize ?? 24,
                    colorFilter: ColorFilter.mode(
                      hasContainer ? colors.alwaysWhite : colors.always909090,
                      BlendMode.srcIn,
                    ),
                  ),
        ),
      );
    },
  );
}
