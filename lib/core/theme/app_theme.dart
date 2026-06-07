import 'package:flutter/material.dart';

/// Uygulama teması ve görsel stil sabitleri.
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF5B6CF9);
  static const Color primaryDark = Color(0xFF3D4ACC);
  static const Color background = Color(0xFFF4F5FB);
  static const Color surface = Colors.white;

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

  /// Glass-style kart dekorasyonu.
  static BoxDecoration glassCard({Color? accent}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      border: accent != null
          ? Border(left: BorderSide(color: accent, width: 5))
          : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: background,
    );
    return base.copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
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
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
