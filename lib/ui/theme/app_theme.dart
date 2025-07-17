import 'package:flutter/material.dart';
import 'colors.dart';
import 'typography.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    
    brightness: brightness,
    scaffoldBackgroundColor: isDark ? SlashColors.bgDark : SlashColors.bgLight,
    colorScheme: ColorScheme.fromSeed(
      seedColor: SlashColors.primary,
      brightness: brightness,
    ),
    textTheme: SlashTypography.textTheme(isDark),
    useMaterial3: true,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? SlashColors.inputDark : SlashColors.inputLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? SlashColors.cardDark : SlashColors.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      shadowColor: Colors.black.withOpacity(0.04),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SlashColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: SlashTypography.button,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      ),
    ),
  );
} 