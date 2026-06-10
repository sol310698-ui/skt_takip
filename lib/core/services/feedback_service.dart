import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

/// Reyon kontrol ekranı için ses + titreşim geri bildirimi.
///
/// Her durum için farklı kombinasyon:
///   • matchFirst / matchSame  → 1 kısa yüksek bip, titreşim yok
///   • product                 → 1 kısa orta bip, titreşim yok
///   • noPrice                 → 2 tonlu bip, 1 hafif titreşim
///   • priceDiff               → 2 artan tonlu bip, 3 kuvvetli titreşim
///   • mismatch                → 3 alçalan agresif bip, 2 titreşim + bildirim tarzı
///
/// Kullanım:
///   await FeedbackService.instance.play(ScanFeedback.mismatch);
class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  final AudioPlayer _player = AudioPlayer();
  bool _vibrationSupported = false;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _vibrationSupported = (await Vibration.hasVibrator()) ?? false;
      // Ses oynatıcıyı düşük gecikmeli modda başlat.
      await _player.setPlayerMode(PlayerMode.lowLatency);
      await _player.setVolume(1.0);
    } catch (_) {}
    _initialized = true;
  }

  /// Belirtilen geri bildirimi oynatır.
  /// Önceki ses bitmeden yeni istek gelirse üstüne yazar (reyon hızı için).
  Future<void> play(ScanFeedback feedback) async {
    if (!_initialized) await init();
    // Ses ve titreşimi paralel başlat (await etme — gecikme olmasın).
    _playSound(feedback.soundAsset);
    _vibrate(feedback.pattern);
  }

  Future<void> _playSound(String asset) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (_) {}
  }

  void _vibrate(List<int> pattern) {
    if (!_vibrationSupported || pattern.isEmpty) return;
    try {
      if (pattern.length == 1) {
        // Tek titreşim: sadece süre
        Vibration.vibrate(duration: pattern[0]);
      } else {
        // Örüntü: [bekleme, titreşim, bekleme, titreşim, ...]
        Vibration.vibrate(pattern: pattern, intensities: [
          for (int i = 0; i < pattern.length; i++)
            i.isOdd ? 255 : 0, // sadece titreşim adımlarında tam güç
        ]);
      }
    } catch (_) {}
  }

  void dispose() {
    _player.dispose();
  }
}

/// Tarama durumlarına karşılık gelen geri bildirim tanımları.
enum ScanFeedback {
  /// Ürün barkodu başarıyla okundu.
  product(
    soundAsset: 'sounds/beep_product.wav',
    pattern: [],               // titreşim yok
  ),

  /// İlk etiket — fiyat referans alındı (✅ eşleşme).
  matchFirst(
    soundAsset: 'sounds/beep_ok.wav',
    pattern: [],
  ),

  /// Aynı fiyat — etiket doğru (✅).
  matchSame(
    soundAsset: 'sounds/beep_ok.wav',
    pattern: [],
  ),

  /// Etikette fiyat bilgisi yok (❓).
  /// 1 hafif kısa titreşim.
  noPrice(
    soundAsset: 'sounds/beep_no_price.wav',
    pattern: [0, 80],          // 80 ms tek titreşim
  ),

  /// Fiyat farklı (⚠️ — önemli uyarı).
  /// 3 kuvvetli titreşim: 150ms × 3, aralarında 60ms boşluk.
  priceDiff(
    soundAsset: 'sounds/beep_price_diff.wav',
    pattern: [0, 150, 60, 150, 60, 150],
  ),

  /// Barkod uyuşmazlığı (❌ — kritik hata).
  /// 2 güçlü uzun titreşim: 200ms + 200ms, 80ms boşluk.
  mismatch(
    soundAsset: 'sounds/beep_mismatch.wav',
    pattern: [0, 200, 80, 200],
  );

  const ScanFeedback({
    required this.soundAsset,
    required this.pattern,
  });

  final String soundAsset;

  /// Vibration.vibrate(pattern: ...) için ms listesi.
  /// Boş liste = titreşim yok.
  final List<int> pattern;
}
