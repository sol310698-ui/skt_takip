import 'package:flutter/material.dart';

/// Canli perakende - koyu tema. Zengin renk paleti, guclu hiyerarsi.
class AppTheme {
  AppTheme._();

  // Ana renkler - canli perakende vurgulari
  static const Color primary = Color(0xFF6C5CE7);     // canli mor
  static const Color primaryLight = Color(0xFF8B7DF0);
  static const Color accent = Color(0xFF00D9A3);       // turkuaz vurgu
  static const Color coral = Color(0xFFFF6B6B);        // mercan

  // Zemin katmanlari (derinlik icin 3 seviye)
  static const Color background = Color(0xFF0D0E14);
  static const Color surface = Color(0xFF181A24);
  static const Color surfaceAlt = Color(0xFF22252F);
  static const Color surfaceHigh = Color(0xFF2C3040);

  // Metin
  static const Color textPrimary = Color(0xFFF5F6FA);
  static const Color textSecondary = Color(0xFF9BA1B4);
  static const Color textTertiary = Color(0xFF646A7D);

  // Durum renkleri (canli)
  static const Color statusSafe = Color(0xFF00D9A3);
  static const Color statusWarning = Color(0xFFFFB627);
  static const Color statusCritical = Color(0xFFFF8A3D);
  static const Color statusExpired = Color(0xFFFF5470);

  // Gradyanlar
  static const LinearGradient bannerGradient = LinearGradient(
    colors: [Color(0xFF6C5CE7), Color(0xFF9B6CF0), Color(0xFFB85CF0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF00D9A3), Color(0xFF00B8D9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient scannerGradient = LinearGradient(
    colors: [Color(0xFF1A1428), Color(0xFF2D1B4E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Kart dekorasyonu - yumusak golge, ince kenar.
  static BoxDecoration card({Color? accentColor, bool elevated = false}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: accentColor?.withOpacity(0.25) ??
            Colors.white.withOpacity(0.04),
        width: 1,
      ),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ]
          : [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
    );
  }

  /// Eski API uyumlulugu icin (glassCard cagrilari).
  static BoxDecoration glassCard({Color? accent}) =>
      card(accentColor: accent);

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        surface: surface,
        primary: primary,
        secondary: accent,
      ),
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: const TextStyle(color: textTertiary),
        labelStyle: const TextStyle(color: textSecondary),
        prefixIconColor: textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 17),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryLight,
          side: BorderSide(color: primary.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(vertical: 15),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
