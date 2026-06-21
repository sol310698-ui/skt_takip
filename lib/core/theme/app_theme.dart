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

  // ─── Ana renkler (her iki temada da ayni) ──────────────────────────
  // Indigo: guven veren, profesyonel; uzun bakista yormaz.
  static const Color primary = Color(0xFF5B6CF0);      // indigo
  static const Color primaryLight = Color(0xFF8693F5);
  static const Color primaryDark = Color(0xFF3D4BD4);
  static const Color accent = Color(0xFF2DD4BF);        // teal/turkuaz
  static const Color amber = Color(0xFFFBBF24);         // sicak vurgu
  static const Color coral = Color(0xFFFB7185);         // mercan/uyari

  // ─── Durum renkleri (SKT) — her iki temada ortak ───────────────────
  static const Color statusSafe = Color(0xFF34D399);     // yesil - guvenli
  static const Color statusWarning = Color(0xFFFBBF24);  // amber - yaklasiyor
  static const Color statusCritical = Color(0xFFFB923C); // turuncu - kritik
  static const Color statusExpired = Color(0xFFF43F5E);  // kirmizi - doldu

  // ════════════════════════════════════════════════════════════════════
  //  TEMAYA GORE DEGISEN RENKLER
  // ────────────────────────────────────────────────────────────────────
  //  Bu renkler `const` DEGIL, statik DEGISKEN'dir. Tum ekranlar
  //  `AppTheme.background` gibi okudugu icin, tema degisince applyMode()
  //  bu degiskenleri gunceller ve TUM uygulama otomatik dogru rengi alir.
  //  (Tek dosyada cozum — yuzlerce ekrani tek tek degistirmeye gerek yok.)
  // ════════════════════════════════════════════════════════════════════

  // Koyu palet (varsayilan).
  static const Color _dkBackground = Color(0xFF0E1017);
  static const Color _dkSurface = Color(0xFF171A23);
  static const Color _dkSurfaceAlt = Color(0xFF1F232E);
  static const Color _dkSurfaceHigh = Color(0xFF2A2F3D);
  static const Color _dkHairline = Color(0xFF2E3340);
  static const Color _dkTextPrimary = Color(0xFFF1F3F9);
  static const Color _dkTextSecondary = Color(0xFF9AA1B4);
  static const Color _dkTextTertiary = Color(0xFF5E6577);

  // Aydinlik palet.
  static const Color _ltBackground = Color(0xFFF4F5FA);  // en dip (acik gri)
  static const Color _ltSurface = Color(0xFFFFFFFF);     // kart (beyaz)
  static const Color _ltSurfaceAlt = Color(0xFFEEF0F6);  // input/alt yuzey
  static const Color _ltSurfaceHigh = Color(0xFFE3E6EF); // menu/yukseltilmis
  static const Color _ltHairline = Color(0xFFD9DDE8);    // ince ayrac/kenar
  static const Color _ltTextPrimary = Color(0xFF1A1D27);
  static const Color _ltTextSecondary = Color(0xFF5E6577);
  static const Color _ltTextTertiary = Color(0xFF9AA1B4);

  // Aktif renkler (varsayilan koyu; applyMode ile degisir).
  static Color background = _dkBackground;
  static Color surface = _dkSurface;
  static Color surfaceAlt = _dkSurfaceAlt;
  static Color surfaceHigh = _dkSurfaceHigh;
  static Color hairline = _dkHairline;
  static Color textPrimary = _dkTextPrimary;
  static Color textSecondary = _dkTextSecondary;
  static Color textTertiary = _dkTextTertiary;

  static bool _isLight = false;
  static bool get isLight => _isLight;

  /// Aktif renk paletini belirler (ThemeData kurulmadan ONCE cagrilir).
  static void applyBrightness(bool light) {
    _isLight = light;
    background = light ? _ltBackground : _dkBackground;
    surface = light ? _ltSurface : _dkSurface;
    surfaceAlt = light ? _ltSurfaceAlt : _dkSurfaceAlt;
    surfaceHigh = light ? _ltSurfaceHigh : _dkSurfaceHigh;
    hairline = light ? _ltHairline : _dkHairline;
    textPrimary = light ? _ltTextPrimary : _dkTextPrimary;
    textSecondary = light ? _ltTextSecondary : _dkTextSecondary;
    textTertiary = light ? _ltTextTertiary : _dkTextTertiary;
  }

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

  // ─── Sistem cubugu (status bar) ────────────────────────────────────
  /// Verilen arka plan rengine gore SADECE ikon parlaginini uretir.
  ///
  /// ONEMLI: Modern Android'de (edge-to-edge zorunlu) `statusBarColor` ARTIK
  /// CALISMAZ — sistem onu yok sayar. Cubuk her zaman seffaftir ve uygulama
  /// icerigi (AppBar/header) onun ARKASINA uzanir. Dolayisiyla "cubugu
  /// boyamak" yerine, ekranin ust renkli alani cubuk bolgesine uzatilir
  /// (Scaffold/AppBar bunu otomatik yapar) ve burada yalnizca saat/pil
  /// ikonlarinin rengini (acik/koyu) arka plana gore ayarlariz.
  static SystemUiOverlayStyle systemBarForColor(Color bg) {
    final isLight = bg.computeLuminance() > 0.5;
    return SystemUiOverlayStyle(
      // statusBarColor VERILMIYOR: seffaf kalir, arkasindaki AppBar/header
      // rengi gorunur. (Gondersek bile modern Android yok sayardi.)
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          isLight ? Brightness.dark : Brightness.light, // Android ikonlari
      statusBarBrightness:
          isLight ? Brightness.light : Brightness.dark, // iOS
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isLight ? Brightness.dark : Brightness.light,
    );
  }

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
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    // Renk paletini bu brightness'e gore aktif et (degiskenler guncellenir).
    applyBrightness(brightness == Brightness.light);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        surface: surface,
        primary: primary,
        secondary: accent,
        error: statusExpired,
      ),
      scaffoldBackgroundColor: background,
    );

    final barIcons =
        brightness == Brightness.light ? Brightness.dark : Brightness.light;

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
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // Status bar AppBar'in arkasindaki rengi alir (seffaf); ikonlar
        // temaya gore acik/koyu.
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: barIcons,
          statusBarBrightness: brightness,
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
        hintStyle: TextStyle(color: textTertiary),
        labelStyle: TextStyle(color: textSecondary),
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
        titleTextStyle: TextStyle(
            color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: textPrimary),
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
      dividerTheme: DividerThemeData(color: hairline, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        side: BorderSide(color: hairline),
        labelStyle: TextStyle(color: textSecondary, fontSize: 12),
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
