import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared app theme for the SKT Takip app.
///
/// [lightTheme]/[darkTheme] (aliased as [light]/[dark]) drive Flutter's own
/// Theme-based widgets. A handful of screens also read [isLight] directly
/// to pick an alternate color outside of `Theme.of(context)`; call
/// [applyBrightness] whenever the effective app brightness changes so that
/// flag stays in sync with the active `ThemeMode`.
class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------------
  // Brand / semantic colors (brightness independent)
  // ---------------------------------------------------------------------
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryStrong = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFF93C5FD);
  static const Color secondary = Color(0xFF7C3AED);
  static const Color accent = Color(0xFF0EA5E9);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color coral = Color(0xFFFF6B5B);
  static const Color amber = Color(0xFFF59E0B);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF0F172A);

  // Status colors used across scan/label/price screens.
  static const Color statusSafe = Color(0xFF16A34A);
  static const Color statusWarning = Color(0xFFF59E0B);
  static const Color statusExpired = Color(0xFFEF4444);
  static const Color statusCritical = Color(0xFFDC2626);

  // ---------------------------------------------------------------------
  // Surface / text palette
  //
  // NOTE: several call sites reference these as compile-time constants
  // (e.g. `const BorderSide(color: AppTheme.border)`), so they stay as a
  // single static palette rather than brightness-aware getters. Only the
  // handful of screens that explicitly branch on [isLight] pick an
  // alternate (usually darker) color themselves.
  // ---------------------------------------------------------------------
  static const Color background = Color(0xFFF5F7FB);
  static const Color scaffold = background;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFEAF2FF);
  static const Color surfaceHigh = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color hairline = border;
  static const Color text = Color(0xFF0F172A);
  static const Color textPrimary = text;
  static const Color textSecondary = Color(0xFF475569);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Dark equivalents, used only inside [darkTheme] for Flutter's own
  // Theme-driven widgets (AppBar, Card, inputs, ...).
  static const Color _darkScaffold = Color(0xFF0B1220);
  static const Color _darkSurface = Color(0xFF111C2E);
  static const Color _darkSurfaceAlt = Color(0xFF16233B);
  static const Color _darkBorder = Color(0xFF24314D);
  static const Color _darkText = Color(0xFFE5EEF9);
  static const Color _darkTextSecondary = Color(0xFFB9C7DA);

  /// Global brightness flag, toggled by [applyBrightness]. A handful of
  /// widgets read this directly (outside of `Theme.of(context)`) to pick
  /// an alternate color/asset for dark mode.
  static bool _isLight = true;
  static bool get isLight => _isLight;
  static void applyBrightness(bool isLight) => _isLight = isLight;

  // ---------------------------------------------------------------------
  // Spacing
  // ---------------------------------------------------------------------
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

  // ---------------------------------------------------------------------
  // Radii
  // ---------------------------------------------------------------------
  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 16;
  static const double rXl = 24;
  static const double rPill = 999;

  // ---------------------------------------------------------------------
  // Gradients
  // ---------------------------------------------------------------------
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, primary],
  );

  static const LinearGradient bannerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  // ---------------------------------------------------------------------
  // Shadows
  // ---------------------------------------------------------------------
  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withOpacity(_isLight ? 0.08 : 0.32),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> glow(Color color) => [
        BoxShadow(
          color: color.withOpacity(0.45),
          blurRadius: 18,
          spreadRadius: 1,
        ),
      ];

  // ---------------------------------------------------------------------
  // Decoration helpers
  // ---------------------------------------------------------------------
  static BoxDecoration card({Color? accentColor, bool elevated = false}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(rLg),
      border: Border.all(
        color: accentColor?.withOpacity(0.45) ?? border,
        width: accentColor != null ? 1.4 : 1,
      ),
      boxShadow: elevated ? shadowMd : null,
    );
  }

  static BoxDecoration glassCard({double opacity = 0.65}) {
    return BoxDecoration(
      color: surface.withOpacity(opacity),
      borderRadius: BorderRadius.circular(rLg),
      border: Border.all(color: border),
    );
  }

  static BoxDecoration softTint(Color color,
      {double opacity = 0.12, double radius = 12}) {
    return BoxDecoration(
      color: color.withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  /// Picks a status-bar/icon style with enough contrast against [color].
  static SystemUiOverlayStyle systemBarForColor(Color color) {
    return color.computeLuminance() > 0.5
        ? SystemUiOverlayStyle.dark
        : SystemUiOverlayStyle.light;
  }

  // ---------------------------------------------------------------------
  // ThemeData
  // ---------------------------------------------------------------------

  /// Alias kept for call sites using `AppTheme.light` / `AppTheme.dark`.
  static ThemeData get light => lightTheme;
  static ThemeData get dark => darkTheme;

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: background,
        foregroundColor: text,
      ),
      cardTheme: CardThemeData(
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      textTheme: ThemeData.light().textTheme.copyWith(
            headlineLarge: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: text,
                height: 1.2),
            headlineMedium: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: text,
                height: 1.25),
            titleLarge: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: text,
                height: 1.3),
            titleMedium: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: text,
                height: 1.4),
            bodyLarge: const TextStyle(
                fontSize: 16, color: textSecondary, height: 1.55),
            bodyMedium: const TextStyle(
                fontSize: 14, color: textSecondary, height: 1.5),
            labelLarge: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: primary),
          ),
    );
  }

  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _darkScaffold,
      primaryColor: primary,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: _darkScaffold,
        foregroundColor: _darkText,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _darkBorder, width: 1),
        ),
      ),
      dividerColor: _darkBorder,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _darkSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withOpacity(0.18),
        shadowColor: Colors.black.withOpacity(0.18),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _darkSurfaceAlt,
        selectedColor: primary.withOpacity(0.18),
        secondarySelectedColor: primary.withOpacity(0.24),
        labelStyle: const TextStyle(color: _darkText),
        side: const BorderSide(color: _darkBorder),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      textTheme: ThemeData.dark().textTheme.copyWith(
            headlineLarge: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: _darkText,
                height: 1.2),
            headlineMedium: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: _darkText,
                height: 1.25),
            titleLarge: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _darkText,
                height: 1.3),
            titleMedium: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _darkText,
                height: 1.4),
            bodyLarge: const TextStyle(
                fontSize: 16, color: _darkTextSecondary, height: 1.55),
            bodyMedium: const TextStyle(
                fontSize: 14, color: _darkTextSecondary, height: 1.5),
            labelLarge: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: primary),
          ),
    );
  }
}
