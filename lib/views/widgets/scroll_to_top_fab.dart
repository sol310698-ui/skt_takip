import 'package:flutter/material.dart';

import '../../core/nav_bar_visibility.dart';
import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  YUKARI CIK FAB — sol altta, scroll'a ve nav bar gorunurlugune gore
///  davranan kucuk yuvarlak buton.
///
///  Davranis kurallari:
///  1) Liste yeterince kaydirilmadiysa (esik altinda) GIZLI kalir; sadece
///     kullanici listede "derinlere" indiginde belirir (cok kaydirinca).
///  2) Alt nav bar (varsa) scroll yonune gore gizlenip gosterildiginde,
///     bu FAB da AYNI ANDA senkronize sekilde asagi inip yukari cikar
///     (navBarVisible global notifier'i dinleyerek).
///  3) Nav bar olmayan (tam sayfa push edilmis) ekranlarda showNavBarSync
///     false birakilarak sadece scroll esigine gore calismasi saglanir.
///
///  Sag alt kosede genelde baska bir FAB (Manuel Ekle, Speed-Dial vb.)
///  oldugu icin bu buton bilerek SOL ALT koseye yerlestirilir; boylece
///  hicbir ekranda cakisma olmaz.
/// ════════════════════════════════════════════════════════════════════
class ScrollToTopFab extends StatefulWidget {
  final ScrollController controller;

  /// Bu mesafe (px) kaydirildiktan sonra buton belirir.
  final double showThreshold;

  /// true ise navBarVisible notifier'ina gore de gizlenir/gosterilir
  /// (nav bar'i olan ekranlarda kullanilir). Nav bar'i olmayan tam sayfa
  /// ekranlarda false birakilmalidir.
  final bool syncWithNavBar;

  /// Nav bar gizliyken bile bu kadar alt bosluk birakilir (SafeArea payi).
  final double baseBottomPadding;

  const ScrollToTopFab({
    super.key,
    required this.controller,
    this.showThreshold = 400,
    this.syncWithNavBar = true,
    this.baseBottomPadding = 16,
  });

  @override
  State<ScrollToTopFab> createState() => _ScrollToTopFabState();
}

class _ScrollToTopFabState extends State<ScrollToTopFab> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ScrollToTopFab old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final offset = widget.controller.offset;
    final shouldShow = offset > widget.showThreshold;
    if (shouldShow != _visible) {
      setState(() => _visible = shouldShow);
    }
  }

  void _scrollToTop() {
    widget.controller.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildButton() {
    return Material(
      color: AppTheme.surfaceHigh,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.3),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _scrollToTop,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.keyboard_arrow_up_rounded,
              color: AppTheme.primaryLight, size: 26),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final button = AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _visible ? 1 : 0,
      child: IgnorePointer(
        ignoring: !_visible,
        child: _buildButton(),
      ),
    );

    if (!widget.syncWithNavBar) {
      return Positioned(
        left: 16,
        bottom: widget.baseBottomPadding,
        child: button,
      );
    }

    // Nav bar ile senkron: nav bar gizlenince bu FAB de ayni mesafede
    // asagi kayar (MainShell'deki nav bar animasyonuyla aynı sure/egri).
    return Positioned(
      left: 16,
      bottom: widget.baseBottomPadding,
      child: ValueListenableBuilder<bool>(
        valueListenable: navBarVisible,
        builder: (_, navVisible, child) => AnimatedSlide(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          // Nav bar gizliyken FAB, nav bar'in kapladigi mesafe kadar
          // (yaklasik 78px) asagi inip onunla birlikte ekran disina cikar.
          offset: navVisible ? Offset.zero : const Offset(0, 1.6),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: navVisible ? 1 : 0,
            child: child,
          ),
        ),
        child: button,
      ),
    );
  }
}
