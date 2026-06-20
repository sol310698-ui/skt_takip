import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';
import '../widgets/ui_kit.dart';
import 'image_zoom_screen.dart';
import 'web_search_screen.dart';

/// Barkod liste oge detay sayfasi.
/// - Urun adi VERITABANINDAN (dizinden) gelir.
/// - Gorsel + ek bilgi (kategori/miktar) Open Food Facts'ten cekilir.
/// - Duzenle / Sil aksiyonlari altta sabit.
class BarcodeDetailScreen extends ConsumerStatefulWidget {
  final BarcodeEntry entry;
  const BarcodeDetailScreen({super.key, required this.entry});

  @override
  ConsumerState<BarcodeDetailScreen> createState() =>
      _BarcodeDetailScreenState();
}

class _BarcodeDetailScreenState extends ConsumerState<BarcodeDetailScreen> {
  late BarcodeEntry _entry;
  bool _loadingWeb = true;
  String? _imageUrl;
  String? _category;
  String? _quantity;
  bool _changed = false; // geri donerken listeyi yenilemek icin

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _fetchWeb();
  }

  /// OFF'tan gorsel + ek bilgi. Ad'a dokunmaz (o veritabanindan).
  Future<void> _fetchWeb() async {
    try {
      final r =
          await BarcodeLookupService.instance.lookupDetailed(_entry.barcode);
      if (!mounted) return;
      setState(() {
        _imageUrl = r.imageUrl;
        _category = r.category;
        _quantity = r.quantity;
        _loadingWeb = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingWeb = false);
    }
  }

  Future<void> _edit() async {
    final nameCtrl = TextEditingController(text: _entry.productName);
    final stockCtrl =
        TextEditingController(text: _entry.stockCode ?? '');
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Ürün adı',
                hintText: 'Ürün adı',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: stockCtrl,
              decoration: const InputDecoration(
                labelText: 'Stok kodu (opsiyonel)',
                hintText: 'Stok kodu',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                    'name': nameCtrl.text.trim(),
                    'stock': stockCtrl.text.trim(),
                  }),
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (result == null) return;
    final newName = result['name'] ?? '';
    if (newName.isEmpty) return;
    final newStock = result['stock'] ?? '';

    await ref.read(barcodeDirectoryRepositoryProvider).importAll([
      BarcodeEntry(
        barcode: _entry.barcode,
        productName: newName,
        // Bos birakilirsa eski stok kodu importAll tarafindan korunur.
        stockCode: newStock.isEmpty ? null : newStock,
        importedAt: DateTime.now(),
        // Elle duzenleme: mevcut kaydin kaynagini KORU ki (esit oncelik)
        // degisiklik her zaman uygulansin. Boylece bir Excel kaydini elle
        // duzeltince "excel" onceligi korunur ama ad/stok yine guncellenir.
        source: _entry.source == BarcodeSource.unknown
            ? BarcodeSource.manual
            : _entry.source,
      ),
    ]);

    // id artik importAll merge davranisiyla degismez; yine de guncel kaydi cek.
    final fresh = await ref
        .read(barcodeDirectoryRepositoryProvider)
        .findEntryByBarcode(_entry.barcode);

    if (mounted) {
      setState(() {
        _entry = fresh ??
            BarcodeEntry(
              barcode: _entry.barcode,
              productName: newName,
              stockCode: newStock.isEmpty ? _entry.stockCode : newStock,
              importedAt: DateTime.now(),
            );
        _changed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncellendi')),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sil'),
        content: Text('"${_entry.productName}" listeden silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: AppTheme.statusExpired),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true && _entry.id != null) {
      await ref
          .read(barcodeDirectoryRepositoryProvider)
          .deleteById(_entry.id!);
      if (mounted) Navigator.of(context).pop(true); // silindi -> yenile
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: CustomScrollView(
          slivers: [
            _buildHeader(),
            SliverToBoxAdapter(child: _buildBody()),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildHeader() {
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      stretch: true,
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.primary),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(_changed),
      ),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Container(
          decoration: const BoxDecoration(gradient: AppTheme.bannerGradient),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Buyuk gorsel (OFF) - dokununca zoom.
                    GestureDetector(
                      onTap: _imageUrl == null
                          ? null
                          : () => openImageZoom(context,
                              networkUrl: _imageUrl,
                              heroTag: 'bc_img',
                              title: _entry.productName),
                      child: Hero(
                        tag: 'bc_img',
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                                width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _loadingWeb
                              ? const Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  ),
                                )
                              : (_imageUrl != null
                                  ? CachedImage(
                                      url: _imageUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: _ph,
                                    )
                                  : _ph()),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _entry.productName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ph() => const Icon(Icons.inventory_2_rounded,
      color: Colors.white, size: 52);

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barkod karti — tikla: kopyala, uzun bas: barkod/QR goster.
          _infoCard(
            icon: Icons.qr_code_rounded,
            label: 'Barkod',
            value: _entry.barcode,
            monospace: true,
            copyable: true,
            showCode: true,
            isBarcode: true,
          ),
          // Stok kodu karti (Excel'den geldiyse).
          if (_entry.stockCode != null && _entry.stockCode!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.tag_rounded,
              label: 'Stok Kodu',
              value: _entry.stockCode!,
              monospace: true,
              copyable: true,
              showCode: true,
              isBarcode: false,
            ),
          ],
          if (_category != null && _category!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.category_rounded,
              label: 'Kategori',
              value: _category!,
            ),
          ],
          if (_quantity != null && _quantity!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.straighten_rounded,
              label: 'Miktar / Ağırlık',
              value: _quantity!,
            ),
          ],
          if (!_loadingWeb &&
              _imageUrl == null &&
              _category == null &&
              _quantity == null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.card(),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppTheme.textTertiary, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bu barkod için internette ek bilgi/görsel bulunamadı.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
    bool monospace = false,
    Widget? trailing,
    bool copyable = false,
    bool showCode = false,
    bool isBarcode = false,
  }) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: monospace ? 'monospace' : null)),
                if (copyable || showCode) ...[
                  const SizedBox(height: 4),
                  Text(
                    showCode
                        ? 'Kopyalamak için dokun • Kod için basılı tut'
                        : 'Kopyalamak için dokun',
                    style: const TextStyle(
                        fontSize: 10.5, color: AppTheme.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          if (copyable)
            Icon(Icons.copy_rounded,
                size: 16, color: AppTheme.textTertiary),
          if (trailing != null) trailing,
        ],
      ),
    );

    if (!copyable && !showCode) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        onTap: copyable ? () => _copyValue(label, value) : null,
        onLongPress:
            showCode ? () => _showCodeSheet(label, value, isBarcode) : null,
        child: card,
      ),
    );
  }

  /// Degeri panoya kopyala + kisa bildirim.
  void _copyValue(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label kopyalandı: $value'),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Alttan kayan pencerede degerin barkod + QR gorselini gosterir.
  void _showCodeSheet(String label, String value, bool isBarcode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CodeSheet(
        label: label,
        value: value,
        // Barkod yalnizca EAN-13/EAN-8/UPC gibi gecerli sayisal kodlarda
        // cizilebilir; degilse sadece QR gosterilir.
        preferBarcode: isBarcode,
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _edit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Düzenle',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WebSearchScreen(query: _entry.barcode),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: BorderSide(color: AppTheme.accent.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  icon: const Icon(Icons.search_rounded),
                  label: const Text("İnternette Ara"),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.statusExpired,
                    side: const BorderSide(color: AppTheme.statusExpired),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Sil'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bir degerin (barkod/stok kodu) barkod + QR gorselini gosteren alt sheet.
/// Gecerli EAN-13/EAN-8/UPC ise 1D barkod cizilir; her durumda QR gosterilir.
class _CodeSheet extends StatelessWidget {
  final String label;
  final String value;
  final bool preferBarcode;

  const _CodeSheet({
    required this.label,
    required this.value,
    this.preferBarcode = false,
  });

  /// value'ye uygun bir 1D barkod tipi sec (yoksa null -> sadece QR).
  Barcode? _pick1DBarcode() {
    final v = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(v)) return null; // salt rakam degil
    switch (v.length) {
      case 13:
        return Barcode.ean13();
      case 12:
        return Barcode.upcA();
      case 8:
        return Barcode.ean8();
      default:
        // Diger uzunluklar icin Code128 (rakam+harf destekler).
        return Barcode.code128();
    }
  }

  @override
  Widget build(BuildContext context) {
    final barcode = preferBarcode ? _pick1DBarcode() : null;

    return Container(
      decoration: const BoxDecoration(
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
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace'),
          ),
          const SizedBox(height: 20),

          // 1D Barkod (varsa) — beyaz zemin uzerine, taranabilir olsun.
          if (barcode != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.rMd),
              ),
              child: BarcodeWidget(
                barcode: barcode,
                data: value.trim(),
                drawText: true,
                height: 90,
                color: Colors.black,
                errorBuilder: (context, error) => Text(
                  'Barkod oluşturulamadı',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Center(
              child: Text('— veya —',
                  style: TextStyle(
                      color: AppTheme.textTertiary, fontSize: 12)),
            ),
            const SizedBox(height: 18),
          ],

          // QR kod — her zaman.
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.rMd),
              ),
              child: QrImageView(
                data: value.trim(),
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
                // ignore: deprecated_member_use
                foregroundColor: Colors.black,
              ),
            ),
          ),

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label kopyalandı'),
                  duration: const Duration(milliseconds: 1200),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Kopyala'),
          ),
        ],
      ),
    );
  }
}
