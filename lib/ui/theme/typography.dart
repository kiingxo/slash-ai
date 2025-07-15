import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SlashTypography {
  static TextTheme textTheme(bool isDark) => GoogleFonts.interTextTheme(
    isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
  ).copyWith(
    headlineSmall: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 22),
    bodyMedium: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 16),
    labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
  );

  static final button = GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, letterSpacing: 0.5);
} 