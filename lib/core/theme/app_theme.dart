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
  // MAVI + TURKUAZ kimlik: ana renk MAVI (butonlar/basliklar), vurgu
  // TURKUAZ (ikincil basliklar, depo/reyon ailesi). KIRMIZI marka rengi
  // DEGILDIR — yalnizca hata/doldu anlamindadir (statusExpired). Boylece
  // "yanlis etiket" alarmi ile marka rengi asla karismaz.
  // Turkuaz ACIK bir renktir: ustunde SIYAH metin dogru kontrasti verir
  // (uygulamadaki accent-ustu-siyah kullanimlarla uyumludur).
  // Durum renkleri (statusSafe/Warning/Critical/Expired) DEGISMEZ.
  // DOA yesil kimlik: ana renk YESIL (butonlar/basliklar), vurgu daha acik
  // yesil. Durum renkleri (statusSafe/Warning/Critical/Expired) DEGISMEZ.
  // MARKA / VURGU PALETI — artik `const` DEGIL: kullanici Ayarlar'dan vurgu
  // rengini degistirebilir (#10). applyAccent() bu 7 rengi (ve gradyanlari)
  // birlikte gunceller; 298+ kullanim runtime'da statik okudugu icin tumu
  // otomatik yeni renge gecer. Varsayilan: DOA yesili.
  static Color primary = _accentDefault.primary;      // ana renk (butonlar)
  static Color primaryLight = _accentDefault.primaryLight; // acik ton
  static Color primaryDark = _accentDefault.primaryDark;  // koyu ton
  static Color accent = _accentDefault.accent;         // vurgu
  static const Color amber = Color(0xFFFBBF85);         // pastel sicak vurgu
  static const Color coral = Color(0xFFFB9CAE);         // pastel mercan/uyari

  // İmza gradyan paleti — header'lar, FAB'lar, vurgu yuzeyleri icin.
  static Color orchid = _accentDefault.gradB;  // orta ton
  static Color blush = _accentDefault.gradA;   // koyu ton (gradyan basi)
  static Color sky = _accentDefault.primaryLight; // acik ton

  // ─── VURGU PALETI SECIMI (#10) ─────────────────────────────────────
  static const AccentPalette _accentDefault = AccentPalette.green;
  static AccentPalette activeAccent = _accentDefault;

  /// Secilebilir vurgu paletleri (Ayarlar'da gosterilir).
  static const List<AccentPalette> accentPalettes = [
    AccentPalette.green,
    AccentPalette.blue,
    AccentPalette.purple,
    AccentPalette.orange,
    AccentPalette.teal,
  ];

  /// Vurgu paletini uygular (ThemeData kurulmadan ONCE, main.dart'ta cagrilir).
  /// Marka renklerini ve gradyanlari birlikte gunceller; boylece butonlarla
  /// header/aurora renkleri asla ayrisik kalmaz.
  static void applyAccent(AccentPalette p) {
    activeAccent = p;
    primary = p.primary;
    primaryLight = p.primaryLight;
    primaryDark = p.primaryDark;
    accent = p.accent;
    orchid = p.gradB;
    blush = p.gradA;
    sky = p.primaryLight;
  }

  /// id'den palet bul (kayitli tercih yuklenirken kullanilir).
  static AccentPalette accentById(String id) => accentPalettes.firstWhere(
        (p) => p.id == id,
        orElse: () => _accentDefault,
      );

  // ─── LISTE YOGUNLUGU (#10) ─────────────────────────────────────────
  // Ferah (standart) veya Kompakt. ThemeData.visualDensity'ye uygulanir.
  static VisualDensity uiDensity = VisualDensity.standard;

  // ─── Durum renkleri (SKT) — okunabilirlik icin doygunlugu korunur ──
  static const Color statusSafe = Color(0xFF34D399);
  static const Color statusWarning = Color(0xFFFBBF24);
  static const Color statusSuccess = Color(0xFF16A34A);
  static const Color statusCritical = Color(0xFFFB923C);
  static const Color statusExpired = Color(0xFFF43F5E);

  // ════════════════════════════════════════════════════════════════════
  //  TEMAYA GORE DEGISEN RENKLER
  // ────────────────────────────────────────────────────────────────────
  //  `const` DEGIL, statik DEGISKEN — applyBrightness() ile her ekran
  //  otomatik guncellenir.
  // ════════════════════════════════════════════════════════════════════

  // Koyu palet — DOA'nin koyu yesil-gece varyanti (duz siyah degil).
  static const Color _dkBackground = Color(0xFF0F1A14);
  static const Color _dkSurface = Color(0xFF17231B);
  static const Color _dkSurfaceAlt = Color(0xFF1F2E25);
  static const Color _dkSurfaceHigh = Color(0xFF29392F);
  static const Color _dkHairline = Color(0xFF31473A);
  static const Color _dkTextPrimary = Color(0xFFF1F6F2);
  static const Color _dkTextSecondary = Color(0xFFAAC0B2);
  static const Color _dkTextTertiary = Color(0xFF6E8378);
  // Koyu temada "cam" beyaz degil, hafif aydinlatilmis lavanta katmanidir.
  static const Color _dkGlassTint = Color(0xFFFFFFFF);
  static const double _dkGlassOpacity = 0.06;

  // Acik palet — DOA: mint-beyaz zemin, beyaz kartlar.
  static const Color _ltBackground = Color(0xFFE8F5EC); // mint zemin
  static const Color _ltSurface = Color(0xFFFFFFFF);
  static const Color _ltSurfaceAlt = Color(0xFFEAF5EE);
  static const Color _ltSurfaceHigh = Color(0xFFDCEEE3);
  static const Color _ltHairline = Color(0xFFDBEBE1);
  static const Color _ltTextPrimary = Color(0xFF1E2A22);
  static const Color _ltTextSecondary = Color(0xFF61706A);
  static const Color _ltTextTertiary = Color(0xFF9DA9A1);
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

  // ─── Imza gradyanlar — aktif vurgu paletine gore (artik getter) ────
  static LinearGradient get bannerGradient => LinearGradient(
        colors: [activeAccent.gradA, activeAccent.gradB, activeAccent.gradC],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get accentGradient => LinearGradient(
        colors: [orchid, primaryLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static const LinearGradient scannerGradient = LinearGradient(
    colors: [Color(0xFF0F1A33), Color(0xFF1A1020)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Aurora gradyani — header arka planlarinda yavasca kayan, daha cok
  /// renk katmani iceren versiyon (animasyonlu kullanim icin tasarlandi).
  static List<Color> get auroraColors => [
        activeAccent.gradA,
        activeAccent.gradB,
        activeAccent.gradC,
        activeAccent.gradB, // donguyu kapatir
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
          color: (isLight ? const Color(0xFF0E7A3D) : Colors.black)
              .withOpacity(isLight ? 0.10 : 0.24),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: (isLight ? const Color(0xFF0E7A3D) : Colors.black)
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
    // KENDI paletini yerelden kurar; global statikleri DEGISTIRMEZ/OKUMAZ
    // (yan etkisiz). Boylece theme/darkTheme kurulurken statikler bozulmaz;
    // statikleri yalnizca main.dart aktif temaya gore ayarlar.
    final light = brightness == Brightness.light;
    final bg = light ? _ltBackground : _dkBackground;
    final surf = light ? _ltSurface : _dkSurface;
    final surfAlt = light ? _ltSurfaceAlt : _dkSurfaceAlt;
    final surfHigh = light ? _ltSurfaceHigh : _dkSurfaceHigh;
    final hair = light ? _ltHairline : _dkHairline;
    final txP = light ? _ltTextPrimary : _dkTextPrimary;
    final txS = light ? _ltTextSecondary : _dkTextSecondary;
    final txT = light ? _ltTextTertiary : _dkTextTertiary;
    final gTint = light ? _ltGlassTint : _dkGlassTint;
    final gOp = light ? _ltGlassOpacity : _dkGlassOpacity;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      visualDensity: uiDensity,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        surface: surf,
        primary: primary,
        secondary: accent,
        error: statusExpired,
      ),
      scaffoldBackgroundColor: bg,
    );

    final barIcons =
        brightness == Brightness.light ? Brightness.dark : Brightness.light;

    return base.copyWith(
      scaffoldBackgroundColor: bg,
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
        backgroundColor: bg,
        foregroundColor: txP,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: barIcons,
          statusBarBrightness: brightness,
        ),
        titleTextStyle: TextStyle(
          color: txP,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: gTint.withOpacity(gOp),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: BorderSide(
              color: Colors.white.withOpacity(light ? 0.7 : 0.08)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfAlt,
        hintStyle: TextStyle(color: txT),
        labelStyle: TextStyle(color: txS),
        prefixIconColor: txS,
        suffixIconColor: txS,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: hair, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: primary, width: 1.8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: surfHigh,
          disabledForegroundColor: txT,
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
          .apply(bodyColor: txP, displayColor: txP)
          .copyWith(
            titleLarge: const TextStyle(
                fontWeight: FontWeight.w800, letterSpacing: -0.4),
            titleMedium: const TextStyle(
                fontWeight: FontWeight.w700, letterSpacing: -0.2),
            bodyMedium: const TextStyle(height: 1.4),
          ),
      dialogTheme: DialogThemeData(
        backgroundColor: surf,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: BorderSide(
              color: Colors.white.withOpacity(light ? 0.7 : 0.08)),
        ),
        titleTextStyle: TextStyle(
            color: txP, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surf,
        modalBackgroundColor: surf,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(rXl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfHigh,
        contentTextStyle: TextStyle(color: txP),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
        insetPadding: const EdgeInsets.all(16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surf,
        indicatorColor: primary.withOpacity(0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primaryDark : txS,
          );
        }),
      ),
      dividerTheme: DividerThemeData(color: hair, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surfAlt,
        side: BorderSide(color: hair),
        labelStyle: TextStyle(color: txS, fontSize: 12),
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
///
///  SENKRON: Tum ekranlardaki (SKT/Mesai/Barkod) aurora ayni anda ayni
///  kareyi gostersin diye TEK bir global controller (_AuroraSync) kullanir.
///  Her ekran kendi controller'ini yaratmaz; uygulama acildiginda bir kez
///  baslayan ortak saata baglanir. Boylece sekme degistirince animasyon
///  "sicramaz", kaldigi yerden devam eder ve hepsi es zamanlidir.
/// ════════════════════════════════════════════════════════════════════

/// Uygulama omru boyunca tek sefer yasayan, surekli donen global aurora
/// saati. Ilk erisimde baslar, hicbir zaman dispose edilmez (uygulama
/// kapanana kadar yasamasi gerekir — zaten cok hafif).
class _AuroraSync {
  static final _AuroraSync instance = _AuroraSync._();
  _AuroraSync._();

  AnimationController? _ctrl;

  /// TickerProvider gerektigi icin ilk dinleyici ekranindan vsync alir.
  Listenable ensure(TickerProvider vsync) {
    if (_ctrl == null) {
      _ctrl = AnimationController(
        vsync: vsync,
        duration: const Duration(seconds: 12),
      )..repeat();
    }
    return _ctrl!;
  }

  double get value => _ctrl?.value ?? 0.0;
}

class AuroraBackground extends StatefulWidget {
  final Widget? child;
  final BorderRadius? borderRadius;

  const AuroraBackground({super.key, this.child, this.borderRadius});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final Listenable _sync;

  @override
  void initState() {
    super.initState();
    // Global senkron saata baglan (ilk ekran baslatir, digerleri ortak
    // saata baglanir -> hepsi es zamanli).
    _sync = _AuroraSync.instance.ensure(this);
  }

  // NOT: dispose'da global controller'i KAPATMIYORUZ; baska ekranlar da
  // ona bagli olabilir ve uygulama boyunca yasamasi gerekir.

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sync,
      builder: (context, child) {
        // Yatay olarak SOL=mavi, SAG=kirmizi. Ortadaki bolunme cizgisi
        // canli dursun diye yavasca sola-saga salinir (hep yari mavi/yari
        // kirmizi kalir, renkler birbirine karismaz).
        final t = _AuroraSync.instance.value * 2 * math.pi;
        final mid = 0.5 + 0.12 * math.sin(t); // 0.38 ↔ 0.62 arasi salinim
        // Aktif vurgu paletine gore (isim eski API — blue/red tarihsel).
        final blue = AppTheme.blush; // koyu ton
        final red = AppTheme.accent; // acik ton
        return Container(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [blue, blue, red, red],
              stops: [
                0.0,
                (mid - 0.10).clamp(0.0, 1.0),
                (mid + 0.10).clamp(0.0, 1.0),
                1.0,
              ],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// ════════════════════════════════════════════════════════════════════
///  VURGU PALETI (#10) — kullanicinin secebilecegi renk aileleri.
/// ────────────────────────────────────────────────────────────────────
///  Her palet; ana renk (primary) + acik/koyu tonlar + vurgu + uclu
///  header gradyanini birlikte tanimlar. Boylece buton, header, aurora,
///  secili durum — hepsi tek renk ailesinde kalir.
/// ════════════════════════════════════════════════════════════════════
class AccentPalette {
  final String id;
  final String label;
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color accent;
  final Color gradA; // gradyan basi (koyu)
  final Color gradB; // gradyan ortasi
  final Color gradC; // gradyan sonu (acik)

  const AccentPalette({
    required this.id,
    required this.label,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.accent,
    required this.gradA,
    required this.gradB,
    required this.gradC,
  });

  /// Onizleme rozeti icin temsili renk.
  Color get swatch => primary;

  // ── Hazir paletler ──────────────────────────────────────────────
  static const green = AccentPalette(
    id: 'green',
    label: 'Yeşil',
    primary: Color(0xFF1E9E52),
    primaryLight: Color(0xFF52C07E),
    primaryDark: Color(0xFF157A3E),
    accent: Color(0xFF34C77B),
    gradA: Color(0xFF157A3E),
    gradB: Color(0xFF23A055),
    gradC: Color(0xFF3BB873),
  );

  static const blue = AccentPalette(
    id: 'blue',
    label: 'Mavi',
    primary: Color(0xFF2563EB),
    primaryLight: Color(0xFF60A5FA),
    primaryDark: Color(0xFF1D4ED8),
    accent: Color(0xFF38BDF8),
    gradA: Color(0xFF1D4ED8),
    gradB: Color(0xFF2563EB),
    gradC: Color(0xFF3B82F6),
  );

  static const purple = AccentPalette(
    id: 'purple',
    label: 'Mor',
    primary: Color(0xFF7C3AED),
    primaryLight: Color(0xFFA78BFA),
    primaryDark: Color(0xFF5B21B6),
    accent: Color(0xFFC084FC),
    gradA: Color(0xFF5B21B6),
    gradB: Color(0xFF7C3AED),
    gradC: Color(0xFF9333EA),
  );

  static const orange = AccentPalette(
    id: 'orange',
    label: 'Turuncu',
    primary: Color(0xFFEA7317),
    primaryLight: Color(0xFFFB923C),
    primaryDark: Color(0xFFC2560E),
    accent: Color(0xFFFDBA74),
    gradA: Color(0xFFC2560E),
    gradB: Color(0xFFEA7317),
    gradC: Color(0xFFF97316),
  );

  static const teal = AccentPalette(
    id: 'teal',
    label: 'Deniz',
    primary: Color(0xFF0D9488),
    primaryLight: Color(0xFF2DD4BF),
    primaryDark: Color(0xFF0F766E),
    accent: Color(0xFF5EEAD4),
    gradA: Color(0xFF0F766E),
    gradB: Color(0xFF0D9488),
    gradC: Color(0xFF14B8A6),
  );
}
