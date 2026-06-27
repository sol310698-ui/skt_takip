import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/price_check_channel.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';

/// ════════════════════════════════════════════════════════════════════
///  KATEGORI TARAMA
/// ────────────────────────────────────────────────────────────────────
///  Sirket uygulamasinin "Denetim Urunler" liste ekranindaki urunleri
///  (ad + barkod) otomatik toplar. Akis:
///    1. Kullanici "Tara"ya basar.
///    2. 5 sn geri sayim — bu surede kullanici sirket uygulamasinin liste
///       ekranina gecer.
///    3. Servis otomatik kaydirarak listeyi tarar; toplanan urunler canli
///       olarak burada birikir.
///    4. Liste bitince tarama durur; kullanici "Dizine Kaydet" ile hepsini
///       barkod dizinine yazar.
/// ════════════════════════════════════════════════════════════════════
class CategoryScanScreen extends ConsumerStatefulWidget {
  const CategoryScanScreen({super.key});

  @override
  ConsumerState<CategoryScanScreen> createState() => _CategoryScanScreenState();
}

class _CategoryScanScreenState extends ConsumerState<CategoryScanScreen> {
  StreamSubscription<Map<dynamic, dynamic>>? _sub;
  final Map<String, String> _products = {}; // barkod -> ad
  bool _scanning = false;
  int _countdown = 0;
  Timer? _countdownTimer;
  bool _finished = false;
  bool _saving = false;

  @override
  void dispose() {
    _sub?.cancel();
    _countdownTimer?.cancel();
    PriceCheckChannel.stopCategoryScan();
    super.dispose();
  }

  void _startWithCountdown() {
    setState(() {
      _products.clear();
      _finished = false;
      _countdown = 5;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) {
        t.cancel();
        _beginScan();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _beginScan() {
    setState(() {
      _countdown = 0;
      _scanning = true;
    });
    _sub?.cancel();
    _sub = PriceCheckChannel.scanEventStream.listen((event) {
      final type = event['type'] as String?;
      if (type == 'product') {
        final bc = (event['barcode'] as String?) ?? '';
        final name = (event['productName'] as String?) ?? '';
        if (bc.isNotEmpty) {
          setState(() => _products[bc] = name);
        }
      } else if (type == 'finished') {
        setState(() {
          _scanning = false;
          _finished = true;
        });
      }
    });
    PriceCheckChannel.startCategoryScan();
  }

  void _stopScan() {
    PriceCheckChannel.stopCategoryScan();
    setState(() {
      _scanning = false;
      _finished = true;
    });
  }

  Future<void> _saveToDirectory() async {
    if (_products.isEmpty) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final entries = _products.entries
          .map((e) => BarcodeEntry(
                barcode: e.key,
                productName: e.value,
                importedAt: now,
                source: BarcodeSource.screen,
              ))
          .toList();
      await ref
          .read(barcodeDirectoryRepositoryProvider)
          .importAll(entries, forceOverwrite: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${entries.length} ürün dizine kaydedildi'),
            backgroundColor: AppTheme.statusSuccess,
          ),
        );
        setState(() => _products.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt hatası: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategori Tara'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _header(cs),
          const Divider(height: 1),
          Expanded(child: _list(cs)),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: AppTheme.primary.withOpacity(0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_countdown > 0) ...[
            Center(
              child: Column(
                children: [
                  Text('$_countdown',
                      style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary)),
                  const Text('Şirket uygulamasında liste ekranını açın!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ] else if (_scanning) ...[
            Row(
              children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Taranıyor... ${_products.length} ürün bulundu',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Kaydırmaya dokunmayın, otomatik tarıyor.',
                style: TextStyle(fontSize: 12)),
          ] else if (_finished) ...[
            Text('Tarama bitti — ${_products.length} ürün',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 2),
            const Text('Aşağıdan dizine kaydedebilirsiniz.',
                style: TextStyle(fontSize: 12)),
          ] else ...[
            const Text(
              'Şirket uygulamasında "Denetim Ürünler" liste ekranını '
              'hazırlayın. "Tara"ya bastıktan sonra 5 saniye içinde o '
              'ekrana geçin. Uygulama listeyi otomatik kaydırıp toplayacak.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _list(ColorScheme cs) {
    if (_products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _scanning ? 'Ürünler bekleniyor...' : 'Henüz ürün toplanmadı.',
            style: TextStyle(color: cs.onSurface.withOpacity(0.5)),
          ),
        ),
      );
    }
    final entries = _products.entries.toList();
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = entries[i];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: AppTheme.primary.withOpacity(0.15),
            child: Text('${i + 1}',
                style: TextStyle(fontSize: 11, color: AppTheme.primary)),
          ),
          title: Text(e.value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text('Barkod: ${e.key}',
              style: const TextStyle(fontSize: 12)),
        );
      },
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (_scanning)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _stopScan,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Durdur'),
                ),
              )
            else ...[
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _countdown > 0 ? null : _startWithCountdown,
                  icon: const Icon(Icons.radar_rounded),
                  label: Text(_finished ? 'Tekrar Tara' : 'Tara'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_products.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveToDirectory,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_rounded),
                    label: const Text('Dizine Kaydet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.statusSuccess,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
