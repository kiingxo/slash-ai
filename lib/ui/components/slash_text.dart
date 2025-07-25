import 'package:flutter/material.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';

class SlashText extends StatelessWidget {
  final String text;
  final double? fontSize;
  // FONT WEIGHT, TEXT SIZE,
  final FontWeight? fontWeight;
  final Color? color;
  final String? fontFamily;
  final int? maxLines;
  final TextAlign? textAlign;
  final double textHeight;
  final double? letterSpacing;
  final FontStyle? fontStyle;
  final TextOverflow? overflow;
  const SlashText(
    this.text, {
    super.key,
    this.fontSize,
    this.fontWeight,
    this.color,
    this.maxLines,
    this.fontFamily,
    this.textAlign,
    this.overflow,
    this.textHeight = 0,
    this.letterSpacing,
    this.fontStyle,
  });

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      useScaffold: false,
      builder: (context, colors, ref) {
        return Text(
          text,
          textAlign: textAlign,
          maxLines: maxLines,
          style: TextStyle(
            fontSize: fontSize ?? 14,
            fontFamily: fontFamily ?? "DMSans",
            height: textHeight,
            fontStyle: fontStyle,
            fontWeight: fontWeight ?? FontWeight.w400,
            letterSpacing: letterSpacing,
            overflow: overflow,
            color: color ?? colors.lightBlackDarkWhite,
          ),
        );
      },
    );
  }
}
