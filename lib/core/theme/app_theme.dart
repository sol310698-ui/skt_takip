import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ════════════════════════════════════════════════════════════════════
///  SKT Takip — "Soft Glass" Tasarım Sistemi
/// ────────────────────────────────────────────────────────────────────
///  Acik, ferah, pastel-gradyanli glassmorphism. Apple/iOS'un yumusak
///  cam dili: bulanik (frosted) yuzeyler, ince beyaz kenarlar, derin
///  ama dogal gölgeler, canli ama yorulmayan pastel gradyanlar.
///
///  Token tabanli: renk / spacing / radius / tipografi / golge / blur
///  tek yerden yonetilir. Eski API isimleri (primary, accent, card()...)
///  AYNEN KORUNDU — tum uygulama hicbir ekran kodu degismeden yeni
///  tasarimi otomatik alir.
/// ════════════════════════════════════════════════════════════════════
class AppTheme {
  AppTheme._();

  // ════════════════════════════════════════════════════════════════════
  //  IMZA PALETI — pastel gradyan ailesi (Soft Glass'in kalbi)
  // ════════════════════════════════════════════════════════════════════
  // Indigo -> Orkide -> Pembe gecisi: sicak, guven veren, modern.
  static const Color primary = Color(0xFF7C8CF8);      // yumusak indigo
  static const Color primaryLight = Color(0xFFA5B0FB);
  static const Color primaryDark = Color(0xFF5B6CE8);
  static const Color accent = Color(0xFF5EEAD4);        // yumusak turkuaz
  static const Color amber = Color(0xFFFBBF85);         // pastel sicak vurgu
  static const Color coral = Color(0xFFFB9CAE);         // pastel mercan/uyari

  // İmza gradyan paleti — header'lar, FAB'lar, vurgu yuzeyleri icin.
  static const Color orchid = Color(0xFFC4B5FD);  // yumusak mor
  static const Color blush = Color(0xFFF0ABFC);   // pastel pembe
  static const Color sky = Color(0xFF93C5FD);     // yumusak gokyuzu mavisi

  // ─── Durum renkleri (SKT) — okunabilirlik icin doygunlugu korunur ──
  static const Color statusSafe = Color(0xFF34D399);
  static const Color statusWarning = Color(0xFFFBBF24);
  static const Color statusCritical = Color(0xFFFB923C);
  static const Color statusExpired = Color(0xFFF43F5E);

  // ════════════════════════════════════════════════════════════════════
  //  TEMAYA GORE DEGISEN RENKLER
  // ────────────────────────────────────────────────────────────────────
  //  `const` DEGIL, statik DEGISKEN — applyBrightness() ile her ekran
  //  otomatik guncellenir.
  // ════════════════════════════════════════════════════════════════════

  // Koyu palet — derin lavanta-gece (duz siyah degil, sicakligini korur).
  static const Color _dkBackground = Color(0xFF14121F);
  static const Color _dkSurface = Color(0xFF1E1B2E);
  static const Color _dkSurfaceAlt = Color(0xFF272338);
  static const Color _dkSurfaceHigh = Color(0xFF332D47);
  static const Color _dkHairline = Color(0xFF3A3450);
  static const Color _dkTextPrimary = Color(0xFFF5F3FA);
  static const Color _dkTextSecondary = Color(0xFFAFA8C4);
  static const Color _dkTextTertiary = Color(0xFF6F6889);
  // Koyu temada "cam" beyaz degil, hafif aydinlatilmis lavanta katmanidir.
  static const Color _dkGlassTint = Color(0xFFFFFFFF);
  static const double _dkGlassOpacity = 0.06;

  // Acik palet — "Soft Glass" varsayilani: lavanta-beyaz zemin.
  static const Color _ltBackground = Color(0xFFF6F7FD); // hafif lavanta-gri
  static const Color _ltSurface = Color(0xFFFFFFFF);
  static const Color _ltSurfaceAlt = Color(0xFFF0F1FA);
  static const Color _ltSurfaceHigh = Color(0xFFE6E8F7);
  static const Color _ltHairline = Color(0xFFE2E4F3);
  static const Color _ltTextPrimary = Color(0xFF211E33);
  static const Color _ltTextSecondary = Color(0xFF6B6585);
  static const Color _ltTextTertiary = Color(0xFFA29DB8);
  // Acik temada cam: beyazin yari-seffaf hali (frosted).
  static const Color _ltGlassTint = Color(0xFFFFFFFF);
  static const double _ltGlassOpacity = 0.62;

  // Aktif renkler (varsayilan ACIK — Soft Glass; applyBrightness ile degisir).
  static Color background = _ltBackground;
  static Color surface = _ltSurface;
  static Color surfaceAlt = _ltSurfaceAlt;
  static Color surfaceHigh = _ltSurfaceHigh;
  static Color hairline = _ltHairline;
  static Color textPrimary = _ltTextPrimary;
  static Color textSecondary = _ltTextSecondary;
  static Color textTertiary = _ltTextTertiary;
  static Color glassTint = _ltGlassTint;
  static double glassOpacity = _ltGlassOpacity;

  static bool _isLight = true;
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
    glassTint = light ? _ltGlassTint : _dkGlassTint;
    glassOpacity = light ? _ltGlassOpacity : _dkGlassOpacity;
  }

  // ─── Spacing olcegi (4'un katlari, tutarli ritim) ──────────────────
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  // ─── Radius olcegi — Soft Glass daha yumusak/yuvarlak ──────────────
  static const double rSm = 14;
  static const double rMd = 18;
  static const double rLg = 24;
  static const double rXl = 32;
  static const double rPill = 999;

  // ─── Imza gradyanlar — "Aurora" (pastel, yumusak) ──────────────────
  static const LinearGradient bannerGradient = LinearGradient(
    colors: [Color(0xFF8B93F8), Color(0xFFB69FF5), Color(0xFFF0ABFC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF5EEAD4), Color(0xFF7DD3FC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient scannerGradient = LinearGradient(
    colors: [Color(0xFF1A1730), Color(0xFF2D2350)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Aurora gradyani — header arka planlarinda yavasca kayan, daha cok
  /// renk katmani iceren versiyon (animasyonlu kullanim icin tasarlandi).
  static const List<Color> auroraColors = [
    Color(0xFF2563EB), // blue
    Color(0xFF60A5FA), // light blue
    Color(0xFFEF4444), // red
    Color(0xFFB91C1C), // deep red
  ];

  // ─── Sistem cubugu (status bar) ────────────────────────────────────
  static SystemUiOverlayStyle systemBarForColor(Color bg) {
    final isLightBg = bg.computeLuminance() > 0.5;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          isLightBg ? Brightness.dark : Brightness.light,
      statusBarBrightness: isLightBg ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isLightBg ? Brightness.dark : Brightness.light,
    );
  }

  // ─── Golge tokenleri — Soft Glass: daha yumusak, daha dagilmis ─────
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: (isLight ? const Color(0xFF7C8CF8) : Colors.black)
              .withOpacity(isLight ? 0.10 : 0.24),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: (isLight ? const Color(0xFF7C8CF8) : Colors.black)
              .withOpacity(isLight ? 0.14 : 0.32),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> glow(Color c) => [
        BoxShadow(
          color: c.withOpacity(0.32),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ];

  /// Kart dekorasyonu — artik CAM: yari-seffaf zemin + ince beyaz kenar +
  /// yumusak golge. Gercek arka plan bulaniklastirma icin GlassPanel'i
  /// kullan; bu sadece renk/kenar/golge verir (BoxDecoration).
  static BoxDecoration card({Color? accentColor, bool elevated = false}) {
    return BoxDecoration(
      color: glassTint.withOpacity(glassOpacity),
      borderRadius: BorderRadius.circular(rLg),
      border: Border.all(
        color: accentColor?.withOpacity(0.4) ??
            Colors.white.withOpacity(isLight ? 0.7 : 0.08),
        width: 1.2,
      ),
      boxShadow: elevated ? shadowMd : shadowSm,
    );
  }

  /// Cam efektli kart (eski API uyumu) — card() ile ayni.
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
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SoftGlassTransitionsBuilder(),
          TargetPlatform.iOS: _SoftGlassTransitionsBuilder(),
          TargetPlatform.fuchsia: _SoftGlassTransitionsBuilder(),
          TargetPlatform.linux: _SoftGlassTransitionsBuilder(),
          TargetPlatform.macOS: _SoftGlassTransitionsBuilder(),
          TargetPlatform.windows: _SoftGlassTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
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
        color: glassTint.withOpacity(glassOpacity),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: BorderSide(
              color: Colors.white.withOpacity(isLight ? 0.7 : 0.08)),
        ),
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
          borderSide: const BorderSide(color: primary, width: 1.8),
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
          foregroundColor: primaryDark,
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
          foregroundColor: primaryDark,
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: BorderSide(
              color: Colors.white.withOpacity(isLight ? 0.7 : 0.08)),
        ),
        titleTextStyle: TextStyle(
            color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(rXl)),
        ),
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
            color: selected ? primaryDark : textSecondary,
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

/// Tüm sayfa geçişleri için: hafif yukari kayma + fade + cok hafif
/// olceklenme (derinlik hissi). "Cam panel kayiyor" hissi veren bir egri.
class _SoftGlassTransitionsBuilder extends PageTransitionsBuilder {
  const _SoftGlassTransitionsBuilder();

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
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

/// ════════════════════════════════════════════════════════════════════
///  GLASS PANEL — gercek frosted-glass efekti (BackdropFilter blur).
///
///  AppTheme.card() sadece RENK/KENAR veriyor (BoxDecoration), gercek
///  ARKA PLAN BULANIKLASTIRMA icin bu widget'i kullan. Performans icin
///  blur sigma'si dusuk tutulur (asiri blur = dusuk cihazda kasma).
/// ════════════════════════════════════════════════════════════════════
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blurSigma;
  final Color? accentColor;
  final bool elevated;
  final EdgeInsetsGeometry? padding;

  const GlassPanel({
    super.key,
    required this.child,
    this.radius = AppTheme.rLg,
    this.blurSigma = 14,
    this.accentColor,
    this.elevated = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration:
              AppTheme.card(accentColor: accentColor, elevated: elevated),
          child: child,
        ),
      ),
    );
  }
}

/// ════════════════════════════════════════════════════════════════════
///  AURORA BACKGROUND — yavasca kayan pastel gradyan (header imza ogesi).
///
///  Statik bannerGradient'in animasyonlu versiyonu. Dusuk maliyetli:
///  sadece bir Alignment tween'i (GPU'da gradyan yeniden hesaplanir,
///  agir bir efekt degildir).
/// ════════════════════════════════════════════════════════════════════
class AuroraBackground extends StatefulWidget {
  final Widget? child;
  final BorderRadius? borderRadius;

  const AuroraBackground({super.key, this.child, this.borderRadius});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final angle = _ctrl.value * 2 * math.pi;
        final begin = Alignment(0.7 * math.cos(angle), 0.7 * math.sin(angle));
        final end = Alignment(
            -0.7 * math.cos(angle), -0.7 * math.sin(angle));
        return Container(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              colors: AppTheme.auroraColors,
              begin: begin,
              end: end,
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}
