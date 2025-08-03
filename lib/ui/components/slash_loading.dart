import 'package:flutter/material.dart';
import 'package:slash_flutter/ui/theme/app_theme_builder.dart';

class SlashLoading extends StatelessWidget {
  final Color? color;
  final double? value;
  const SlashLoading({super.key, this.color, this.value});
  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      useScaffold: false,
      builder: (context, colors, ref) {
        return Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              
              value: value,
              color: color ?? colors.always8B5CF6,
              strokeWidth: 1,
            ),
          ),
        );
      },
    );
  }
}
