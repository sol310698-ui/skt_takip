import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/pending_products_queue.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';
import '../widgets/ui_kit.dart';

/// ════════════════════════════════════════════════════════════════════
///  BEKLEYEN URUNLER — onay & kaydet sayfasi
/// ────────────────────────────────────────────────────────────────────
///  Fiyat Kontrol sirasinda erisilebilirlikle okunan urunler (barkod +
///  stok kodu + urun adi) burada listelenir. Kullanici kontrol eder,
///  yanlislari siler, sonra "Veritabanina Kaydet" ile barkod listesine
///  toplu yazar (Excel kesinliginde, forceOverwrite). Kaydedilenler
///  kuyruktan silinir.
/// ════════════════════════════════════════════════════════════════════
class PendingProductsScreen extends ConsumerStatefulWidget {
  const PendingProductsScreen({super.key});

  @override
  ConsumerState<PendingProductsScreen> createState() =>
      _PendingProductsScreenState();
}

class _PendingProductsScreenState
    extends ConsumerState<PendingProductsScreen> {
  bool _saving = false;

  Future<void> _saveAll() async {
    final items = pendingProductsQueue.value;
    if (items.isEmpty) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(barcodeDirectoryRepositoryProvider);
      final now = DateTime.now();
      final entries = items
          .map((p) => BarcodeEntry(
                barcode: p.barcode,
                productName: p.productName,
                stockCode: p.stockCode,
                importedAt: now,
                // Erisilebilirlikle dogrudan sistemden okundu: en kesin
                // veri. Kullanici da onayladi -> forceOverwrite ile yazilir.
                source: BarcodeSource.scan,
              ))
          .toList();

      await repo.importAll(entries, forceOverwrite: true);

      clearPendingProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entries.length} ürün barkod listesine kaydedildi.')),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kayıt hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Okunan Ürünler'),
        actions: [
          ValueListenableBuilder<List<PendingProduct>>(
            valueListenable: pendingProductsQueue,
            builder: (_, items, __) => items.isEmpty
                ? const SizedBox.shrink()
                : TextButton.icon(
                    onPressed: _saving ? null : clearPendingProducts,
                    icon: const Icon(Icons.delete_sweep_rounded,
                        size: 18, color: AppTheme.statusExpired),
                    label: const Text('Temizle',
                        style: TextStyle(color: AppTheme.statusExpired)),
                  ),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<PendingProduct>>(
        valueListenable: pendingProductsQueue,
        builder: (_, items, __) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Bekleyen ürün yok',
              subtitle:
                  'Fiyat Kontrol ekranında ürün okuttukça burada listelenir. '
                  'Kontrol edip kaydedebilirsiniz.',
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _tile(items[i]),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveAll,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_saving
                          ? 'Kaydediliyor...'
                          : 'Veritabanına Kaydet (${items.length})'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(PendingProduct p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          const Icon(Icons.qr_code_2_rounded,
              color: AppTheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.productName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 3),
                Text('Barkod: ${p.barcode}',
                    style: TextStyle(
                        fontSize: 12.5, color: AppTheme.textSecondary)),
                if (p.stockCode != null && p.stockCode!.isNotEmpty)
                  Text('Stok kodu: ${p.stockCode}',
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.textSecondary)),
                if (p.systemPrice != null)
                  Text('Sistem fiyatı: ${p.systemPrice!.toStringAsFixed(2)} ₺',
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.textTertiary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                size: 22, color: AppTheme.statusExpired),
            tooltip: 'Listeden çıkar',
            onPressed: () => removePendingProduct(p.barcode),
          ),
        ],
      ),
    );
  }
}
