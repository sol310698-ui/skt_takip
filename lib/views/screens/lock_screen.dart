import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/services/app_lock_service.dart';
import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  Kilit ekrani — uygulama her acilista (soguk baslatma + arka plandan
///  one gelme) once burası gosterilir.
///
///  Iki mod:
///   - KURULUM modu (PIN hic belirlenmemisse): kullanici PIN belirler
///     (2 kez girip onaylar), ardindan otomatik icer girer.
///   - GIRIS modu (PIN zaten varsa): PIN ister, biyometri actiysa ayrica
///     hizli parmak izi/yuz butonu sunar. Konum izni varsa ve is yeri
///     tanimliysa, konuma yakinsa "İş yerindesiniz" notu gosterilir
///     (kilit yine de PIN/biyometri ister — atlanmaz).
///   Konum alinamazsa (izin yok, GPS kapali, hata) sessizce gecilir;
///   sadece BIR KEZ bilgilendirme snackbar'i gosterilir, zorunlu degildir.
/// ════════════════════════════════════════════════════════════════════
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _loading = true;
  bool _isSetupMode = false; // PIN hic yoksa kurulum modu
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  // Kurulum modu icin: ilk girilen PIN, onay asamasinda karsilastirilir.
  String? _setupFirstPin;

  final List<String> _entered = [];
  static const int _pinLength = 6;
  String? _errorText;
  String? _workLocationNote; // "İş yerindesiniz" gibi bilgi notu
  bool _checkingLocation = false;

  @override
  void initState() {
    super.initState();
    _init();
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

    if (!_isSetupMode) {
      _checkWorkLocation();
      // Biyometri aciksa, ekran acilir acilmaz otomatik dene (kullanici
      // isterse PIN'e gecebilir, zorunlu degil).
      if (bioEnabled && bioAvailable) {
        // Kisa bir gecikme: ekran tam render olsun, ani modal sicramasin.
        Future.delayed(const Duration(milliseconds: 300), _tryBiometric);
      }
    }
  }

  /// Konum alip is yerine yakin mi diye kontrol eder. ZORUNLU DEGIL:
  /// izin yoksa/hata olursa sessizce gecer, sadece bir kez bilgi verir.
  Future<void> _checkWorkLocation() async {
    final hasWork = await AppLockService.instance.hasWorkLocation();
    if (!hasWork || !mounted) return;

    setState(() => _checkingLocation = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          _showLocationInfoOnce(
              'Konum izni verilmediği için iş yeri tespiti yapılamadı.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showLocationInfoOnce(
            'Konum izni kapalı olduğu için iş yeri tespiti yapılamadı.');
        return;
      }

      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        _showLocationInfoOnce(
            'Konum servisi kapalı olduğu için iş yeri tespiti yapılamadı.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      final isAtWork = await AppLockService.instance
          .isWithinWorkLocation(pos.latitude, pos.longitude);
      if (!mounted) return;
      if (isAtWork) {
        setState(() => _workLocationNote = '📍 İş yerindesiniz');
      }
    } catch (_) {
      // Konum alinamadi (timeout, GPS kapali, vb.) — sessizce gec.
      _showLocationInfoOnce(
          'Konum alınamadı, iş yeri tespiti bu seferlik yapılamadı.');
    } finally {
      if (mounted) setState(() => _checkingLocation = false);
    }
  }

  bool _locationInfoShown = false;
  void _showLocationInfoOnce(String message) {
    if (_locationInfoShown || !mounted) return;
    _locationInfoShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          backgroundColor: AppTheme.surfaceHigh,
        ),
      );
    });
  }

  Future<void> _tryBiometric() async {
    final ok = await AppLockService.instance.authenticateWithBiometrics();
    if (ok && mounted) widget.onUnlocked();
  }

  void _onDigit(String d) {
    if (_entered.length >= _pinLength) return;
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
    if (_entered.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _entered.removeLast());
  }

  Future<void> _onPinComplete() async {
    final pin = _entered.join();

    if (_isSetupMode) {
      if (_setupFirstPin == null) {
        // 1. giris: onay asamasina gec.
        setState(() {
          _setupFirstPin = pin;
          _entered.clear();
        });
        return;
      }
      // 2. giris: onayla.
      if (pin == _setupFirstPin) {
        await AppLockService.instance.setPin(pin);
        await AppLockService.instance.setLockEnabled(true);
        widget.onUnlocked();
      } else {
        setState(() {
          _errorText = 'PIN’ler eşleşmedi, tekrar deneyin';
          _setupFirstPin = null;
          _entered.clear();
        });
      }
      return;
    }

    // Giris modu: PIN dogrula.
    final ok = await AppLockService.instance.verifyPin(pin);
    if (ok) {
      widget.onUnlocked();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _errorText = 'Yanlış PIN, tekrar deneyin';
        _entered.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBarForColor(AppTheme.background),
        child: const Scaffold(
          backgroundColor: AppTheme.background,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final title = _isSetupMode
        ? (_setupFirstPin == null
            ? 'Bir PIN belirleyin'
            : 'PIN’i tekrar girin')
        : 'PIN girin';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemBarForColor(AppTheme.background),
      child: Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Icon(Icons.lock_rounded, size: 56, color: AppTheme.primary),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            if (_workLocationNote != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.statusSafe.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text(_workLocationNote!,
                    style: const TextStyle(
                        color: AppTheme.statusSafe,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ] else if (_checkingLocation) ...[
              const SizedBox(height: 10),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
            const SizedBox(height: 28),
            // PIN noktalari
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pinLength, (i) {
                final filled = i < _entered.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppTheme.primary : AppTheme.surfaceHigh,
                    border: Border.all(
                        color: filled
                            ? AppTheme.primary
                            : AppTheme.hairline),
                  ),
                );
              }),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 20,
              child: _errorText != null
                  ? Text(_errorText!,
                      style: const TextStyle(
                          color: AppTheme.statusExpired,
                          fontWeight: FontWeight.w600,
                          fontSize: 13))
                  : null,
            ),
            const Spacer(flex: 2),
            // Numara tuş takımı
            _buildKeypad(),
            const SizedBox(height: 12),
            if (!_isSetupMode && _biometricAvailable && _biometricEnabled)
              TextButton.icon(
                onPressed: _tryBiometric,
                icon: const Icon(Icons.fingerprint_rounded,
                    color: AppTheme.accent),
                label: const Text('Parmak izi / Yüz ile aç',
                    style: TextStyle(
                        color: AppTheme.accent, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      ),
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
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final d in row) _keypadButton(d),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 72, height: 72),
              _keypadButton('0'),
              SizedBox(
                width: 72,
                height: 72,
                child: IconButton(
                  onPressed: _onBackspace,
                  icon: const Icon(Icons.backspace_outlined,
                      color: AppTheme.textSecondary),
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
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        onTap: () => _onDigit(digit),
        borderRadius: BorderRadius.circular(36),
        child: Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.surface,
          ),
          child: Text(digit,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
        ),
      ),
    );
  }
}
