import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/price_check_channel.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';

/// ════════════════════════════════════════════════════════════════════
///  VERI TOPLAMA EKRANI
/// ────────────────────────────────────────────────────────────────────
///  Kullanici bu ekrani acip sirket uygulamasina gectiginde, urun DETAY
///  ekranlarinda gezinirken erisilebilirlik servisi her yeni urunu
///  (barkod + urun adi + stok kodu) OTOMATIK olarak okur ve dogrudan
///  barkod dizinine (barcode_directory) yazar. Kullanici hicbir sey
///  yapmaz; sadece sirket uygulamasinda urunden urune gezer.
///
///  Bu veri 'screen' kaynagiyla, EN YUKSEK oncelikle (Excel dahil her
///  seyin uzerine yazacak sekilde) kaydedilir — cunku sirketin kendi
///  sistemindeki guncel gercegi yansitir.
///
///  Fiyat Kontrol ekranindan TAMAMEN BAGIMSIZDIR; ayni erisilebilirlik
///  servisini kullanir ama farkli bir modda (collectMode).
/// ════════════════════════════════════════════════════════════════════
class DataCollectScreen extends ConsumerStatefulWidget {
  const DataCollectScreen({super.key});

  @override
  ConsumerState<DataCollectScreen> createState() => _DataCollectScreenState();
}

class _DataCollectScreenState extends ConsumerState<DataCollectScreen>
    with WidgetsBindingObserver {
  bool _serviceOn = false;
  bool _collecting = false;
  Timer? _serviceStatusTimer;
  Timer? _debugTimer;
  StreamSubscription<CollectedProduct>? _sub;

  // TANI: servisin ekrandan en son ne okudugunu gosterir (node sayisi +
  // ornek metinler). "Hic urun gelmiyor" durumunda ekranin gercekte
  // okunup okunmadigini gormek icin.
  String _debugSample = '';

  // Bu oturumda toplanan urunler (en yeni ustte). Sadece gosterim icin;
  // asil kayit aninda DB'ye yazilir.
  final List<CollectedProduct> _collected = [];
  int _savedCount = 0;

  // Ayni barkodu bu oturumda tekrar islememek icin.
  final Set<String> _seenBarcodes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceStatusTimer?.cancel();
    _debugTimer?.cancel();
    _sub?.cancel();
    // Ekran kapaninca toplama modunu MUTLAKA durdur (servis bos yere
    // urun detaylarini taramaya devam etmesin).
    PriceCheckChannel.stopCollectMode();
    super.dispose();
  }

  Future<void> _init() async {
    final on = await PriceCheckChannel.isServiceRunning();
    if (!mounted) return;
    setState(() => _serviceOn = on);

    // Servis durumunu periyodik kontrol (kullanici Ayarlar'dan acarsa
    // ekran guncellensin).
    _serviceStatusTimer =
        Timer.periodic(const Duration(seconds: 1), (_) async {
      final running = await PriceCheckChannel.isServiceRunning();
      if (mounted && running != _serviceOn) {
        setState(() => _serviceOn = running);
      }
    });

    // Gelen urunleri dinle ve aninda DB'ye yaz.
    _sub = PriceCheckChannel.collectedProductStream.listen(_onProductCollected);

    // TANI: 1 sn'de bir servisin ekrandan ne okudugunu cek (sadece bu
    // ekran acikken; pil dostu, sadece gosterim icin).
    _debugTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final info = await PriceCheckChannel.getDebugInfo();
      final sample = (info['screenSample'] as String?) ?? '';
      if (mounted && sample != _debugSample) {
        setState(() => _debugSample = sample);
      }
    });

    // Servis aciksa toplamayi hemen baslat.
    if (on) {
      await _startCollecting();
    }
  }

  Future<void> _startCollecting() async {
    await PriceCheckChannel.startCollectMode();
    if (mounted) setState(() => _collecting = true);
  }

  Future<void> _stopCollecting() async {
    await PriceCheckChannel.stopCollectMode();
    if (mounted) setState(() => _collecting = false);
  }

  Future<void> _onProductCollected(CollectedProduct p) async {
    if (!p.isValid) return;
    // Ayni barkodu bu oturumda tekrar yazma.
    if (_seenBarcodes.contains(p.barcode)) return;
    _seenBarcodes.add(p.barcode);

    // ── DB'ye yaz: 'screen' kaynagi + forceOverwrite ──
    // screen kaynagi en yuksek oncelikli; forceOverwrite ile Excel dahil
    // mevcut her kaydin uzerine yazar (kullanicinin istedigi davranis).
    final repo = ref.read(barcodeDirectoryRepositoryProvider);
    try {
      await repo.importAll(
        [
          BarcodeEntry(
            barcode: p.barcode,
            productName: p.productName,
            stockCode: p.stockCode,
            importedAt: DateTime.now(),
            source: BarcodeSource.screen,
          ),
        ],
        forceOverwrite: true,
      );
      if (!mounted) return;
      setState(() {
        _collected.insert(0, p);
        _savedCount++;
        // Listeyi makul tut (gosterim icin son 50 yeterli).
        if (_collected.length > 50) _collected.removeLast();
      });
    } catch (_) {
      // Yazma hatasi olursa barkodu "gorulduler"den cikar ki tekrar
      // denenebilsin.
      _seenBarcodes.remove(p.barcode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Veri Toplama'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (!_serviceOn) _serviceWarning(),
          _statusCard(),
          const Divider(height: 1),
          _debugPanel(),
          Expanded(child: _collectedList()),
        ],
      ),
    );
  }

  Widget _serviceWarning() {
    return Container(
      width: double.infinity,
      color: AppTheme.statusWarning.withOpacity(0.18),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Erişilebilirlik servisi kapalı',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Veri toplamak için erişilebilirlik servisini açmanız gerekiyor.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: PriceCheckChannel.openAccessibilitySettings,
            icon: const Icon(Icons.settings_accessibility_rounded),
            label: const Text('Erişilebilirlik Ayarları'),
          ),
        ],
      ),
    );
  }

  Widget _debugPanel() {
    final empty = _debugSample.trim().isEmpty;
    final String statusLine;
    if (!_serviceOn) {
      statusLine = 'Servis KAPALI — erişilebilirlik servisini açın.';
    } else if (!_collecting) {
      statusLine = 'Servis açık ama toplama DURDU — "Başlat"a basın.';
    } else if (empty) {
      statusLine = 'Toplama açık, ama ekrandan hiç event/metin gelmedi. '
          'Şirket uygulamasında bir ürün detayına girin.';
    } else {
      statusLine = 'Okunan ekran (canlı):';
    }
    return Container(
      width: double.infinity,
      color: Colors.black.withOpacity(0.05),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report_outlined,
                  size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text('Ekran okuma (tanı)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(statusLine,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: (empty || !_serviceOn || !_collecting)
                      ? AppTheme.statusWarning
                      : Colors.green.shade700)),
          if (!empty) ...[
            const SizedBox(height: 4),
            Text(
              _debugSample,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Colors.black54,
                  height: 1.3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusCard() {
    final active = _serviceOn && _collecting;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppTheme.statusSafe : Colors.grey,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  active
                      ? 'Toplama aktif — şirket uygulamasında ürünlerde gezinin'
                      : 'Toplama duraklatıldı',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('Bu oturumda', '$_savedCount', 'kaydedildi'),
              Container(width: 1, height: 40, color: Colors.black12),
              _stat('Listede', '${_collected.length}', 'ürün'),
            ],
          ),
          const SizedBox(height: 14),
          if (_serviceOn)
            SizedBox(
              width: double.infinity,
              child: _collecting
                  ? OutlinedButton.icon(
                      onPressed: _stopCollecting,
                      icon: const Icon(Icons.pause_rounded),
                      label: const Text('Toplamayı Duraklat'),
                    )
                  : ElevatedButton.icon(
                      onPressed: _startCollecting,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.statusSafe,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Toplamayı Başlat'),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String top, String value, String bottom) {
    return Column(
      children: [
        Text(top, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        Text(value,
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.primary)),
        Text(bottom,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  Widget _collectedList() {
    if (_collected.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _serviceOn
                    ? 'Henüz ürün toplanmadı.\nŞirket uygulamasında bir ürün detayına girin.'
                    : 'Erişilebilirlik servisi açık değil.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _collected.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = _collected[i];
        return ListTile(
          leading: const Icon(Icons.check_circle_rounded,
              color: AppTheme.statusSafe),
          title: Text(p.productName,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'Barkod: ${p.barcode}'
            '${p.stockCode != null ? '   •   Stok: ${p.stockCode}' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
        );
      },
    );
  }
}
