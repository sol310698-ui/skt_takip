import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../../viewmodels/providers.dart';
import 'add_product_screen.dart';
import 'web_search_screen.dart';

/// Tarama sonrasi bilgileri gosteren kayan pencere.
class ScanResultSheet extends ConsumerStatefulWidget {
  final ScanResult result;
  const ScanResultSheet({super.key, required this.result});

  @override
  ConsumerState<ScanResultSheet> createState() => _ScanResultSheetState();
}

class _ScanResultSheetState extends ConsumerState<ScanResultSheet> {
  String? _knownName;
  bool _fromWeb = false;
  BarcodeLookupStatus? _webStatus;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  Future<void> _lookup() async {
    final bc = widget.result.barcode;
    if (bc == null || bc.trim().isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    String? name;
    bool fromWeb = false;

    // 1) Yerel barkod dizini.
    try {
      name = await ref
          .read(barcodeDirectoryRepositoryProvider)
          .findProductName(bc);
    } catch (_) {}

    // 2) Aktif/gecmis urunler.
    if (name == null) {
      try {
        name = (await ref.read(productRepositoryProvider).findByBarcode(bc))
            ?.name;
      } catch (_) {}
    }

    // 3) Open Food Facts (internet). Bu adim cokerse diğerleri etkilenmesin.
    if (name == null) {
      try {
        final r = await BarcodeLookupService.instance.lookupDetailed(bc);
        _webStatus = r.status;
        if (r.found && r.name != null && r.name!.trim().isNotEmpty) {
          name = r.name;
          fromWeb = true;
        }
      } catch (_) {
        _webStatus = BarcodeLookupStatus.error;
      }
    }

    if (mounted) {
      setState(() {
        _knownName = name;
        _fromWeb = fromWeb;
        _loading = false;
      });
    }
  }

  /// Internet aramasi sonucunu kullaniciya aciklayan kisa metin.
  String? get _webStatusMessage {
    if (_knownName != null) return null; // bulundu, mesaja gerek yok
    switch (_webStatus) {
      case BarcodeLookupStatus.notFound:
        return 'Bu barkod internette de bulunamadı.';
      case BarcodeLookupStatus.timeout:
        return 'İnternet yanıt vermedi (zaman aşımı). Bağlantını kontrol et.';
      case BarcodeLookupStatus.httpError:
      case BarcodeLookupStatus.error:
        return 'İnternetten sorgulanırken hata oluştu.';
      case BarcodeLookupStatus.invalid:
        return 'Geçersiz barkod.';
      case BarcodeLookupStatus.disabled:
        return 'İnternet veri tabanı kapalı (Ayarlar\'dan açabilirsiniz).';
      case BarcodeLookupStatus.found:
      case null:
        return null;
    }
  }

  void _addProduct() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(
          prefillBarcode: widget.result.barcode,
          prefillName: _knownName,
          // scannedExpiry kasitli olarak gonderilmiyor:
          // QR'daki 3. alan fiyat/bakim tarihi, gercek SKT degil.
          // Kullanici SKT'yi form ekraninda kendi girecek.
        ),
      ),
    );
  }

  void _searchWeb() {
    final bc = widget.result.barcode;
    if (bc == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WebSearchScreen(query: bc)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Baslik
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.qr_code_2,
                    color: AppTheme.primary, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _loading
                          ? 'Aranıyor...'
                          : (_knownName ?? 'Bilinmeyen ürün'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (r.barcode != null)
                      Text(r.barcode!,
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: AppTheme.textSecondary)),
                    if (_fromWeb && !_loading)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.public_rounded,
                                size: 12, color: AppTheme.accent),
                            const SizedBox(width: 4),
                            Text('İnternetten bulundu',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Detaylar
          if (r.price != null)
            _DetailRow(
                icon: Icons.local_offer_outlined,
                label: 'Fiyat',
                value: '${r.price!.toStringAsFixed(2)} ₺'),
          if (r.expiryDate != null)
            _DetailRow(
                icon: Icons.event_busy_outlined,
                label: 'Son Kullanma',
                value: DateFormat('dd.MM.yyyy').format(r.expiryDate!),
                highlight: true),
          if (r.labelDateTime != null)
            _DetailRow(
                icon: Icons.schedule,
                label: 'Etiket Tarihi',
                value: DateFormat('dd.MM.yyyy HH:mm')
                    .format(r.labelDateTime!)),
          if (_knownName == null && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _webStatusMessage ??
                    'Bu barkod için kayıtlı bilgi yok. Webde arayabilir veya ürün ekleyebilirsiniz.',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
          const SizedBox(height: 20),
          // Aksiyonlar
          FilledButton.icon(
            onPressed: _addProduct,
            icon: const Icon(Icons.add),
            label: const Text('Ürün Ekle'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: r.barcode == null ? null : _searchWeb,
            icon: const Icon(Icons.search),
            label: const Text('Google\'da Ara'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(color: AppTheme.textSecondary)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: highlight ? 16 : 14,
                color:
                    highlight ? AppTheme.primary : AppTheme.textPrimary,
              )),
        ],
      ),
    );
  }
}
