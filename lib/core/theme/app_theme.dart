import 'package:flutter/material.dart';

/// Shared app theme for the SKT Takip app.
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryStrong = Color(0xFF1D4ED8);
  static const Color secondary = Color(0xFF7C3AED);
  static const Color accent = Color(0xFF0EA5E9);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  static const Color scaffold = Color(0xFFF5F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFEAF2FF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color text = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF0F172A);

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s56 = 56;
  static const double s64 = 64;

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: scaffold,
      primaryColor: primary,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: scaffold,
        foregroundColor: text,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      dividerColor: border,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withOpacity(0.12),
        shadowColor: Colors.black.withOpacity(0.06),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: primary.withOpacity(0.12),
        secondarySelectedColor: primary.withOpacity(0.14),
        labelStyle: const TextStyle(color: text),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      textTheme: ThemeData.light().textTheme.copyWith(
        headlineLarge: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: text, height: 1.2),
        headlineMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: text, height: 1.25),
        titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: text, height: 1.3),
        titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text, height: 1.4),
        bodyLarge: const TextStyle(fontSize: 16, color: textSecondary, height: 1.55),
        bodyMedium: const TextStyle(fontSize: 14, color: textSecondary, height: 1.5),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
      ),
    );
  }

  static ThemeData get darkTheme {
    const darkBackground = Color(0xFF0B1220);
    const darkSurface = Color(0xFF111C2E);
    const darkSurfaceAlt = Color(0xFF16233B);
    const darkBorder = Color(0xFF24314D);
    const darkText = Color(0xFFE5EEF9);
    const darkTextSecondary = Color(0xFFB9C7DA);

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      primaryColor: primary,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: darkBackground,
        foregroundColor: darkText,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      dividerColor: darkBorder,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withOpacity(0.18),
        shadowColor: Colors.black.withOpacity(0.18),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkSurfaceAlt,
        selectedColor: primary.withOpacity(0.18),
        secondarySelectedColor: primary.withOpacity(0.24),
        labelStyle: const TextStyle(color: darkText),
        side: const BorderSide(color: darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      textTheme: ThemeData.dark().textTheme.copyWith(
        headlineLarge: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: darkText, height: 1.2),
        headlineMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: darkText, height: 1.25),
        titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: darkText, height: 1.3),
        titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: darkText, height: 1.4),
        bodyLarge: const TextStyle(fontSize: 16, color: darkTextSecondary, height: 1.55),
        bodyMedium: const TextStyle(fontSize: 14, color: darkTextSecondary, height: 1.5),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
      ),
    );
  }
}
