import 'package:flutter/material.dart';
import 'colors.dart';
import 'app_colors.dart';
import 'typography.dart';

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
    final isDark = brightness == Brightness.dark;

    // Build a base color scheme then override surface colors so the app
    // feels like a clean AI tool rather than a tinted Material app.
    final baseScheme = ColorScheme.fromSeed(
      seedColor: SlashColors.primary,
      brightness: brightness,
    );
    final colorScheme = baseScheme.copyWith(
      surface: isDark ? const Color(0xFF0C0C10) : const Color(0xFFF8FAFC),
      surfaceContainer:
          isDark ? const Color(0xFF131318) : const Color(0xFFFFFFFF),
      surfaceContainerHighest:
          isDark ? const Color(0xFF1E1E28) : const Color(0xFFF1F5F9),
      onSurface: isDark ? const Color(0xFFF0F0F5) : const Color(0xFF111827),
      onSurfaceVariant:
          isDark ? const Color(0xFF9A9AB0) : const Color(0xFF6B7280),
      outline:
          isDark
              ? const Color(0xFF2A2A38)
              : const Color(0xFFE5E7EB),
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: 'Inter',
      textTheme: SlashTypography.textTheme(isDark),
      scaffoldBackgroundColor: colorScheme.surface,

      // ── AppBar ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(
          color: colorScheme.onSurface.withValues(alpha: 0.75),
          size: 22,
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: colorScheme.onSurface,
        ),
      ),

      // ── Buttons ─────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SlashColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            letterSpacing: -0.1,
          ),
          minimumSize: const Size(44, 40),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide(
            color:
                isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : const Color(0xFFD1D5DB),
          ),
          foregroundColor: colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          foregroundColor: SlashColors.primary,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),

      // ── Inputs ──────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isDark ? const Color(0xFF17171F) : const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color:
                isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : const Color(0xFFE5E7EB),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color:
                isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : const Color(0xFFE5E7EB),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SlashColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SlashColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.28)
                  : const Color(0xFF9CA3AF),
        ),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.55)
                  : const Color(0xFF6B7280),
        ),
        helperStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.4)
                  : const Color(0xFF9CA3AF),
        ),
      ),

      // ── Cards ───────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color:
            isDark ? const Color(0xFF131318) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color:
                isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFE5E7EB),
          ),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Chips ───────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor:
            isDark ? const Color(0xFF1A1A24) : const Color(0xFFF3F4F6),
        selectedColor: SlashColors.primary.withValues(alpha: 0.18),
        disabledColor:
            isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF3F4F6),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color:
              isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF374151),
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: SlashColors.primary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        elevation: 0,
        pressElevation: 0,
      ),

      // ── Divider ─────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color:
            isDark
                ? Colors.white.withValues(alpha: 0.07)
                : const Color(0xFFE5E7EB),
        thickness: 1,
        space: 1,
      ),

      // ── Switch ──────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark
              ? Colors.white.withValues(alpha: 0.4)
              : Colors.grey.shade400;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return SlashColors.primary;
          return isDark
              ? Colors.white.withValues(alpha: 0.1)
              : const Color(0xFFD1D5DB);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // ── SnackBar ────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            isDark ? const Color(0xFF1E1E28) : const Color(0xFF1F2937),
        contentTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // ── Dialog ──────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor:
            isDark ? const Color(0xFF16161E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: isDark ? Colors.white : const Color(0xFF111111),
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.7)
                  : const Color(0xFF374151),
        ),
      ),

      // ── Bottom sheet ────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            isDark ? const Color(0xFF13131A) : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        elevation: 0,
        dragHandleColor:
            isDark
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.15),
      ),

      // ── List tile ───────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}
