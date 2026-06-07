import 'package:flutter/material.dart';

/// Uygulama teması (koyu) ve görsel stil sabitleri.
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF7C8CFF);
  static const Color primaryDark = Color(0xFF5B6CF9);
  static const Color background = Color(0xFF0F1117);
  static const Color surface = Color(0xFF1A1D27);
  static const Color surfaceAlt = Color(0xFF232735);
  static const Color textPrimary = Color(0xFFECEEF5);
  static const Color textSecondary = Color(0xFF9AA0B4);

  static const LinearGradient bannerGradient = LinearGradient(
    colors: [Color(0xFF5B6CF9), Color(0xFF7C4DFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient scannerGradient = LinearGradient(
    colors: [Color(0xFF1A1F3D), Color(0xFF2D1B4E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Glass-style kart dekorasyonu (koyu).
  static BoxDecoration glassCard({Color? accent}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      border: accent != null
          ? Border(left: BorderSide(color: accent, width: 5))
          : Border.all(color: Colors.white.withOpacity(0.05)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: const TextStyle(color: textSecondary),
        labelStyle: const TextStyle(color: textSecondary),
        prefixIconColor: textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: surface),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
      ),
    );
  }
}
