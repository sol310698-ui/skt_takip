import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ════════════════════════════════════════════════════════════════════
///  SKT Takip — Tasarim Sistemi
/// ────────────────────────────────────────────────────────────────────
///  Modern, sicak-profesyonel koyu tema. Indigo ana renk + amber vurgu.
///  Token tabanli: renk / spacing / radius / tipografi / elevation tek
///  yerden yonetilir. Eski API isimleri (primary, accent, card()...)
///  geriye donuk uyum icin korunur.
/// ════════════════════════════════════════════════════════════════════
class AppTheme {
  AppTheme._();

  // ─── Ana renkler ───────────────────────────────────────────────────
  // Indigo: guven veren, profesyonel; uzun bakista yormaz.
  static const Color primary = Color(0xFF5B6CF0);      // indigo
  static const Color primaryLight = Color(0xFF8693F5);
  static const Color primaryDark = Color(0xFF3D4BD4);
  static const Color accent = Color(0xFF2DD4BF);        // teal/turkuaz
  static const Color amber = Color(0xFFFBBF24);         // sicak vurgu
  static const Color coral = Color(0xFFFB7185);         // mercan/uyari

  // ─── Zemin katmanlari (mavi-gri tonlu koyu, saf siyah degil) ────────
  static const Color background = Color(0xFF0E1017);    // en dip
  static const Color surface = Color(0xFF171A23);       // kart
  static const Color surfaceAlt = Color(0xFF1F232E);    // input/alt yuzey
  static const Color surfaceHigh = Color(0xFF2A2F3D);   // menu/yukseltilmis
  static const Color hairline = Color(0xFF2E3340);      // ince ayrac/kenar

  // ─── Metin ─────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF1F3F9);
  static const Color textSecondary = Color(0xFF9AA1B4);
  static const Color textTertiary = Color(0xFF5E6577);

  // ─── Durum renkleri (SKT) ──────────────────────────────────────────
  static const Color statusSafe = Color(0xFF34D399);     // yesil - guvenli
  static const Color statusWarning = Color(0xFFFBBF24);  // amber - yaklasiyor
  static const Color statusCritical = Color(0xFFFB923C); // turuncu - kritik
  static const Color statusExpired = Color(0xFFF43F5E);  // kirmizi - doldu

  // ─── Spacing olcegi (4'un katlari, tutarli ritim) ──────────────────
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  // ─── Radius olcegi ─────────────────────────────────────────────────
  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 20;
  static const double rXl = 28;
  static const double rPill = 999;

  // ─── Gradyanlar ────────────────────────────────────────────────────
  static const LinearGradient bannerGradient = LinearGradient(
    colors: [Color(0xFF5B6CF0), Color(0xFF7C3AED), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF2DD4BF), Color(0xFF06B6D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient scannerGradient = LinearGradient(
    colors: [Color(0xFF151229), Color(0xFF241B45)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ─── Golge tokenleri ───────────────────────────────────────────────
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: Colors.black.withOpacity(0.22),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> glow(Color c) => [
        BoxShadow(
          color: c.withOpacity(0.35),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  /// Kart dekorasyonu — yumusak golge, ince hairline kenar.
  static BoxDecoration card({Color? accentColor, bool elevated = false}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(rLg),
      border: Border.all(
        color: accentColor?.withOpacity(0.35) ?? hairline,
        width: 1,
      ),
      boxShadow: elevated ? shadowMd : shadowSm,
    );
  }

  /// Cam efektli kart (eski API uyumu).
  static BoxDecoration glassCard({Color? accent}) => card(accentColor: accent);

  /// Yumusak renkli arka plan (chip/rozet zemini icin).
  static BoxDecoration softTint(Color c, {double radius = rMd}) =>
      BoxDecoration(
        color: c.withOpacity(0.14),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.withOpacity(0.28), width: 1),
      );

  // ════════════════════════════════════════════════════════════════════
  //  ThemeData
  // ════════════════════════════════════════════════════════════════════
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
        error: statusExpired,
      ),
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      // Tüm sayfa geçişleri alttan yukarı kayar.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SlideUpTransitionsBuilder(),
          TargetPlatform.iOS: _SlideUpTransitionsBuilder(),
          TargetPlatform.fuchsia: _SlideUpTransitionsBuilder(),
          TargetPlatform.linux: _SlideUpTransitionsBuilder(),
          TargetPlatform.macOS: _SlideUpTransitionsBuilder(),
          TargetPlatform.windows: _SlideUpTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // Status bar AppBar'in arkasindaki rengi alir (seffaf) ve ikonlar acik.
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: const TextStyle(color: textTertiary),
        labelStyle: const TextStyle(color: textSecondary),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: hairline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: surfaceHigh,
          disabledForegroundColor: textTertiary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryLight,
          side: BorderSide(color: primary.withOpacity(0.45)),
          padding: const EdgeInsets.symmetric(vertical: 15),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryLight,
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: base.textTheme
          .apply(bodyColor: textPrimary, displayColor: textPrimary)
          .copyWith(
            titleLarge: const TextStyle(
                fontWeight: FontWeight.w800, letterSpacing: -0.4),
            titleMedium: const TextStyle(
                fontWeight: FontWeight.w700, letterSpacing: -0.2),
            bodyMedium: const TextStyle(height: 1.4),
          ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
        titleTextStyle: const TextStyle(
            color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
        insetPadding: const EdgeInsets.all(16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withOpacity(0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primaryLight : textSecondary,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(color: hairline, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        side: BorderSide(color: hairline),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(rPill)),
      ),
    );
  }
}

/// Tüm sayfa geçişleri için alttan yukarı kayma animasyonu.
class _SlideUpTransitionsBuilder extends PageTransitionsBuilder {
  const _SlideUpTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(opacity: animation, child: child),
    );
  }
}
