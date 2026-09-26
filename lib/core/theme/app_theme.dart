import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Material 3 tasarım sistemi. Soft glass saltanati yerine temiz, okunabilir,
/// sistematik ve mobil odaklı bir temel uygulanır.
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryLight = Color(0xFF93C5FD);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryContainer = Color(0xFFEAF1FF);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFF14B8A6);
  static const Color secondaryContainer = Color(0xFFE6FFFB);
  static const Color accent = secondary;
  static const Color amber = Color(0xFFF59E0B);
  static const Color coral = Color(0xFFF97316);

  static const Color statusSafe = Color(0xFF14B8A6);
  static const Color statusWarning = Color(0xFFF59E0B);
  static const Color statusSuccess = Color(0xFF22C55E);
  static const Color statusCritical = Color(0xFFF97316);
  static const Color statusExpired = Color(0xFFEF4444);

  static const Color _dkBackground = Color(0xFF111827);
  static const Color _dkSurface = Color(0xFF1F2937);
  static const Color _dkSurfaceAlt = Color(0xFF111827);
  static const Color _dkSurfaceHigh = Color(0xFF374151);
  static const Color _dkHairline = Color(0xFF374151);
  static const Color _dkTextPrimary = Color(0xFFF9FAFB);
  static const Color _dkTextSecondary = Color(0xFFCBD5E1);
  static const Color _dkTextTertiary = Color(0xFF94A3B8);
  static const Color _dkGlassTint = Color(0xFFFFFFFF);
  static const double _dkGlassOpacity = 0.06;

  static const Color _ltBackground = Color(0xFFF5F7FB);
  static const Color _ltSurface = Color(0xFFFFFFFF);
  static const Color _ltSurfaceAlt = Color(0xFFF3F6FF);
  static const Color _ltSurfaceHigh = Color(0xFFEAF1FF);
  static const Color _ltHairline = Color(0xFFE5E7EB);
  static const Color _ltTextPrimary = Color(0xFF111827);
  static const Color _ltTextSecondary = Color(0xFF4B5563);
  static const Color _ltTextTertiary = Color(0xFF9CA3AF);
  static const Color _ltGlassTint = Color(0xFFFFFFFF);
  static const double _ltGlassOpacity = 0.72;

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

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 20;
  static const double rXl = 28;
  static const double rPill = 999;

  static const LinearGradient bannerGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF14B8A6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF14B8A6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient scannerGradient = LinearGradient(
    colors: [Color(0xFF0F172A), Color(0xFF111827)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const List<Color> auroraColors = [
    Color(0xFF2563EB),
    Color(0xFF1D4ED8),
    Color(0xFF14B8A6),
  ];

  static SystemUiOverlayStyle systemBarForColor(Color bg) {
    final isLightBg = bg.computeLuminance() > 0.5;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isLightBg ? Brightness.dark : Brightness.light,
      statusBarBrightness: isLightBg ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isLightBg ? Brightness.dark : Brightness.light,
    );
  }

  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: Colors.black.withOpacity(isLight ? 0.06 : 0.2),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withOpacity(isLight ? 0.08 : 0.25),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> glow(Color c) => [
        BoxShadow(
          color: c.withOpacity(0.25),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  static BoxDecoration card({Color? accentColor, bool elevated = false}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(rLg),
      border: Border.all(
        color: accentColor?.withOpacity(0.25) ?? hairline,
        width: 1,
      ),
      boxShadow: elevated ? shadowMd : shadowSm,
    );
  }

  static BoxDecoration glassCard({Color? accent}) => card(accentColor: accent);

  static BoxDecoration softTint(Color c, {double radius = rMd}) => BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.withOpacity(0.22), width: 1),
      );

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
        primary: primary,
        secondary: secondary,
        tertiary: statusSafe,
        error: statusExpired,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
    );

    final barIcons =
        brightness == Brightness.light ? Brightness.dark : Brightness.light;

    return base.copyWith(
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
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
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: BorderSide(color: hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: textTertiary),
        labelStyle: TextStyle(color: textSecondary),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: surfaceHigh,
          disabledForegroundColor: textTertiary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: hairline),
          padding: const EdgeInsets.symmetric(vertical: 15),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: base.textTheme.apply(bodyColor: textPrimary, displayColor: textPrimary).copyWith(
        headlineSmall: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.4),
        titleLarge: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.1),
        bodyMedium: const TextStyle(height: 1.45),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: BorderSide(color: hairline),
        ),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
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
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withOpacity(0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primary : textSecondary,
          );
        }),
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        side: BorderSide(color: hairline),
        labelStyle: TextStyle(color: textSecondary, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rPill)),
      ),
    );
  }
}

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
      position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
          .animate(curved),
      child: FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

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
    this.blurSigma = 10,
    this.accentColor,
    this.elevated = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: AppTheme.card(accentColor: accentColor, elevated: elevated),
      child: child,
    );
  }
}

class _AuroraSync {
  static final _AuroraSync instance = _AuroraSync._();
  _AuroraSync._();

  AnimationController? _ctrl;

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
    _sync = _AuroraSync.instance.ensure(this);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sync,
      builder: (context, child) {
        final t = _AuroraSync.instance.value * 2 * math.pi;
        final mid = 0.5 + 0.12 * math.sin(t);
        final blue = const Color(0xFF2563EB);
        final teal = const Color(0xFF14B8A6);
        return Container(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [blue, blue, teal, teal],
              stops: [
                0.0,
                (mid - 0.12).clamp(0.0, 1.0),
                (mid + 0.12).clamp(0.0, 1.0),
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
