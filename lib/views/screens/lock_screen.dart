import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/app_lock_service.dart';
import '../../core/services/database_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/shift_local_datasource.dart';
import '../../data/repositories/shift_repository.dart';

/// ════════════════════════════════════════════════════════════════════
///  Kilit ekrani — uygulama her acilista (soguk baslatma + arka plandan
///  one gelme) once burası gosterilir.
///
///  Iki mod:
///   - KURULUM modu (PIN hic belirlenmemisse): kullanici PIN belirler
///     (2 kez girip onaylar), ardindan otomatik icer girer.
///   - GIRIS modu (PIN zaten varsa): PIN ister, biyometri actiysa ayrica
///     hizli parmak izi/yuz butonu sunar.
///
///  KONUM MANTIGI (yeni):
///   Eskiden kilit ekraninda "is yerindesiniz / konum alinamadi" gibi
///   bilgilendirme notlari/snackbar'lari gosteriliyordu — bu yaniltici ve
///   gereksizdi. ARTIK: dogrulama (PIN/biyometri) BASARILI olunca, arka
///   planda sessizce konum kontrol edilir; kullanici GERCEKTEN is yerinde
///   ise dogrudan Mesai sekmesine acilir. Degilse normal (Anasayfa) acilir.
///   Hicbir yaniltici bilgilendirme yapilmaz.
/// ════════════════════════════════════════════════════════════════════
class LockScreen extends StatefulWidget {
  /// [goToShift] true ise kullanici is yerindeydi -> Mesai sekmesi acilir.
  final void Function({bool goToShift}) onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _isSetupMode = false; // PIN hic yoksa kurulum modu
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _verifying = false; // dogrulama + konum kontrolu surerken

  // Kurulum modu icin: ilk girilen PIN, onay asamasinda karsilastirilir.
  String? _setupFirstPin;

  final List<String> _entered = [];
  static const int _pinLength = 6;
  String? _errorText;

  // Hatali girişte tus takimini sallamak icin.
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _init();
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final hasPin = await AppLockService.instance.hasPin();
    final bioAvailable = await AppLockService.instance.isBiometricAvailable();
    final bioEnabled = await AppLockService.instance.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _isSetupMode = !hasPin;
      _biometricAvailable = bioAvailable;
      _biometricEnabled = bioEnabled;
      _loading = false;
    });

    if (!_isSetupMode && bioEnabled && bioAvailable) {
      // Biyometri aciksa, ekran acilir acilmaz otomatik dene.
      Future.delayed(const Duration(milliseconds: 300), _tryBiometric);
    }
  }

  /// Dogrulama basarili oldugunda cagrilir: konum kontrol edip uygun
  /// sekmeyle uygulamayi acar. Yaniltici hicbir bilgilendirme yapilmaz.
  ///
  /// Mesai sekmesine YALNIZCA su iki kosul birlikte saglanirsa atlanir:
  ///   1) Kullanici GERCEKTEN is yeri yariçapi icinde, VE
  ///   2) Acik (cikis yapilmamis) bir vardiya YOK (yani henuz giris
  ///      yapilmamis).
  /// Zaten mesaideyse (acik vardiya varsa) kullaniciyi Mesai'ye atmanin
  /// anlami yok — normal Anasayfa ile acilir.
  Future<void> _unlockSuccess() async {
    if (!mounted) return;
    setState(() => _verifying = true);

    var goToShift = false;
    final atWork = await AppLockService.instance.isCurrentlyAtWork();
    if (atWork) {
      // Acik vardiya var mi? Riverpod'a bagimli olmadan dogrudan kontrol.
      final repo =
          ShiftRepository(ShiftLocalDataSource(DatabaseService.instance));
      final open = await repo.getOpenShift();
      // Sadece HENUZ GIRIS YAPILMAMISSA Mesai sekmesine at.
      goToShift = open == null;
    }

    if (!mounted) return;
    widget.onUnlocked(goToShift: goToShift);
  }

  Future<void> _tryBiometric() async {
    final ok = await AppLockService.instance.authenticateWithBiometrics();
    if (ok && mounted) _unlockSuccess();
  }

  void _onDigit(String d) {
    if (_entered.length >= _pinLength || _verifying) return;
    HapticFeedback.lightImpact();
    setState(() {
      _entered.add(d);
      _errorText = null;
    });
    if (_entered.length == _pinLength) {
      _onPinComplete();
    }
  }

  void _onBackspace() {
    if (_entered.isEmpty || _verifying) return;
    HapticFeedback.lightImpact();
    setState(() => _entered.removeLast());
  }

  void _fail(String msg) {
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _errorText = msg;
      _entered.clear();
    });
  }

  Future<void> _onPinComplete() async {
    final pin = _entered.join();

    if (_isSetupMode) {
      if (_setupFirstPin == null) {
        setState(() {
          _setupFirstPin = pin;
          _entered.clear();
        });
        return;
      }
      if (pin == _setupFirstPin) {
        await AppLockService.instance.setPin(pin);
        await AppLockService.instance.setLockEnabled(true);
        _unlockSuccess();
      } else {
        setState(() => _setupFirstPin = null);
        _fail('PIN’ler eşleşmedi, tekrar deneyin');
      }
      return;
    }

    final ok = await AppLockService.instance.verifyPin(pin);
    if (ok) {
      _unlockSuccess();
    } else {
      _fail('Yanlış PIN, tekrar deneyin');
    }
  }

  @override
  Widget build(BuildContext context) {
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    );

    if (_loading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: Scaffold(
          backgroundColor: AppTheme.background,
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final title = _isSetupMode
        ? (_setupFirstPin == null ? 'Bir PIN belirleyin' : 'PIN’i tekrar girin')
        : 'PIN girin';
    final subtitle = _isSetupMode
        ? (_setupFirstPin == null
            ? 'Uygulamayı korumak için 6 haneli bir PIN seçin'
            : 'Onaylamak için aynı PIN’i tekrar girin')
        : 'Devam etmek için PIN’inizi girin';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(
          children: [
            // Ust kosede yumusak indigo isiltisi (derinlik hissi).
            Positioned(
              top: -120,
              left: -60,
              right: -60,
              child: Container(
                height: 320,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.primary.withOpacity(0.22),
                      AppTheme.background.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  _lockBadge(),
                  const SizedBox(height: 22),
                  Text(title,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: AppTheme.textSecondary)),
                  ),
                  const SizedBox(height: 30),
                  _buildDots(),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 20,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _errorText != null ? 1 : 0,
                      child: Text(_errorText ?? '',
                          style: const TextStyle(
                              color: AppTheme.statusExpired,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ),
                  ),
                  const Spacer(flex: 3),
                  _buildKeypad(),
                  const SizedBox(height: 14),
                  _buildBiometricRow(),
                  const SizedBox(height: 18),
                ],
              ),
            ),
            // Dogrulama + konum kontrolu surerken hafif perde.
            if (_verifying)
              Positioned.fill(
                child: Container(
                  color: AppTheme.background.withOpacity(0.55),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Gradyanli, golgeli kilit rozeti.
  Widget _lockBadge() {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        gradient: AppTheme.bannerGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.45),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(Icons.lock_rounded, size: 38, color: Colors.white),
    );
  }

  /// PIN noktalari — hatali girişte yatay sallanir.
  Widget _buildDots() {
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // Sonumlenen sinus dalgasiyla sallama.
        final t = _shake.value;
        final dx =
            (t == 0) ? 0.0 : (1 - t) * 18 * math.sin(t * 3 * math.pi * 2);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_pinLength, (i) {
          final filled = i < _entered.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            width: filled ? 15 : 13,
            height: filled ? 15 : 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: filled ? AppTheme.bannerGradient : null,
              color: filled ? null : AppTheme.surfaceHigh,
              border: filled
                  ? null
                  : Border.all(color: AppTheme.hairline, width: 1.4),
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.5),
                        blurRadius: 8,
                      )
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBiometricRow() {
    if (_isSetupMode || !_biometricAvailable || !_biometricEnabled) {
      return const SizedBox(height: 44);
    }
    return TextButton.icon(
      onPressed: _verifying ? null : _tryBiometric,
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.accent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
      icon: const Icon(Icons.fingerprint_rounded, size: 22),
      label: const Text('Parmak izi / Yüz ile aç',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    );
  }

  Widget _buildKeypad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final d in row) _keypadButton(d)],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 78, height: 78),
              _keypadButton('0'),
              SizedBox(
                width: 78,
                height: 78,
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _onBackspace,
                    customBorder: const CircleBorder(),
                    child: Icon(Icons.backspace_outlined,
                        color: AppTheme.textSecondary, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _keypadButton(String digit) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Material(
        color: AppTheme.surface,
        shape: CircleBorder(
          side: BorderSide(color: AppTheme.hairline, width: 1),
        ),
        child: InkWell(
          onTap: () => _onDigit(digit),
          customBorder: const CircleBorder(),
          splashColor: AppTheme.primary.withOpacity(0.25),
          highlightColor: AppTheme.primary.withOpacity(0.10),
          child: SizedBox(
            width: 78,
            height: 78,
            child: Center(
              child: Text(digit,
                  style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
            ),
          ),
        ),
      ),
    );
  }
}
