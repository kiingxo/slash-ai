import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app_colors.dart';
import 'app_theme.dart';
import 'app_theme_provider.dart';

class ThemeBuilder extends HookConsumerWidget {
  final Widget Function(BuildContext context, AppColors colors, WidgetRef ref)
  builder;
  final bool isSplash;
  final bool useScaffold;
  final Widget? child;
  final Widget? bottomSheet;
  final PreferredSizeWidget? appBar;
  const ThemeBuilder({
    super.key,
    this.useScaffold = true,
    this.isSplash = false,
    required this.builder,
    this.child,
    this.bottomSheet,
    this.appBar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme appTheme = ref.watch(appThemeProvider);

    AppColors appColors = appTheme.colors;

    Widget child = builder(context, appColors, ref);

    return useScaffold
        ? Scaffold(
          backgroundColor:
              isSplash ? appColors.always8B5CF6 : appColors.lightWhiteDarkBlack,
          body: child,
          appBar: appBar,
          bottomSheet: bottomSheet,
          resizeToAvoidBottomInset: true,
        )
        : child;
  }
}
