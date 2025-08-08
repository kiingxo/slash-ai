import 'package:flutter/material.dart';
import 'colors.dart';
import 'app_colors.dart';

class AppTheme {
  final AppColors colors;
  final ThemeMode mode;

  const AppTheme._({required this.colors, required this.mode});

  factory AppTheme.light() {
    return AppTheme._(
      mode: ThemeMode.light,
      colors: AppColors(
        alwaysWhite: Colors.white,
        alwaysBlack: const Color(0xFF111111),
        lightWhiteDarkBlack: Colors.white,
        lightBlackDarkWhite: const Color(0xFF111111),
        always8B5CF6: const Color(0xff8B5CF6),
        always343434: const Color(0xff343434),
        always909090: const Color(0xff909090),
        alwaysEDEDED: const Color(0xffEDEDED),
      ),
    );
  }

  factory AppTheme.dark() {
    return AppTheme._(
      mode: ThemeMode.dark,
      colors: AppColors(
        alwaysWhite: Colors.white,
        alwaysBlack: const Color(0xFF111111),
        lightWhiteDarkBlack: const Color(0xFF111111),
        lightBlackDarkWhite: Colors.white,
        always8B5CF6: const Color(0xff8B5CF6),
        always343434: const Color(0xff343434),
        always909090: const Color(0xff909090),
        alwaysEDEDED: const Color(0xffEDEDED),
      ),
    );
  }

  static ThemeData buildAppTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: SlashColors.primary,
      brightness: brightness,
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: "DMSans",
      useMaterial3: true,
    );

    return base.copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          minimumSize: const Size(44, 40),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          side: BorderSide(color: colorScheme.outline.withOpacity(0.4)),
          minimumSize: const Size(44, 40),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.6), width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: TextStyle(color: colorScheme.onSurface, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: const StadiumBorder(),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outline.withOpacity(0.12),
        thickness: 1,
        space: 1,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: const DialogThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 6,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface.withOpacity(0.8)),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurface.withOpacity(0.8),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}
