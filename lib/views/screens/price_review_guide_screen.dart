import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/services/camera_helper.dart';
import '../../core/services/label_pending_queue_service.dart';
import '../../core/services/price_change_service.dart';
import '../../core/theme/app_theme.dart';
import 'label_print_screen.dart' show LabelGroup, LabelGroupX;

/// ════════════════════════════════════════════════════════════════════
///  FİYAT DEĞİŞİM REHBERİ — gorme dostu, tek tek urun gosterimi.
///  Ust: urun fotosu (OFF'tan otomatik indirilir).
///  Orta: BUYUK urun adi + BUYUK eski->yeni fiyat + reyon.
///  Alt: "Çekildi" (degistirildi isaretle) + "Atla" butonlari.
///  Isaretleyince otomatik sonraki urune gecer.
/// ════════════════════════════════════════════════════════════════════
class PriceReviewGuideScreen extends StatefulWidget {
  final int sessionId;
  const PriceReviewGuideScreen({super.key, required this.sessionId});

  @override
  State<PriceReviewGuideScreen> createState() => _PriceReviewGuideScreenState();
}

class _PriceReviewGuideScreenState extends State<PriceReviewGuideScreen> {
  List<PriceChangeItem> _items = [];
  int _index = 0;
  bool _loading = true;
  bool _busy = false;

  // "Etiket Basim'a da gonder" secimi — gosterilen URUNE OZEL.
  // Urun degisince (index degisince) sifirlanir.
  String? _sendToLabelGroup;

  // Barkod -> resim URL onbellegi (tekrar sorgulamamak icin).
  final Map<String, String?> _imageCache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await PriceChangeService.instance.getItems(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
      // Ilk degistirilmemis urunden basla.
      final firstPending = items.indexWhere((e) => !e.changed);
      _index = firstPending >= 0 ? firstPending : 0;
    });
    _prefetchImage();
  }

  /// Mevcut + sonraki urunun resmini OFF'tan onceden indir.
  Future<void> _prefetchImage() async {
    for (final i in [_index, _index + 1]) {
      if (i < 0 || i >= _items.length) continue;
      final bc = _items[i].barcode;
      if (bc.isEmpty || _imageCache.containsKey(bc)) continue;
      _imageCache[bc] = null; // sorgulaniyor isareti
      try {
        final r = await BarcodeLookupService.instance.lookupDetailed(bc);
        if (mounted) setState(() => _imageCache[bc] = r.imageUrl);
      } catch (_) {}
    }
  }

  void _goTo(int i) {
    if (i < 0 || i >= _items.length) return;
    setState(() {
      _index = i;
      _sendToLabelGroup = null;
    });
    _prefetchImage();
  }

  Future<void> _markDone() async {
    if (_busy) return;
    final item = _items[_index];
    if (item.id == null) return;

    // Foto ZORUNLU: kamerayi ac, etiket kanitini cek.
    final XFile? shot = await CameraHelper.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (shot == null) return; // kullanici vazgecti -> isaretleme

    final labelGroup = _sendToLabelGroup;
    setState(() => _busy = true);
    // Fotoyu KALICI dizine kopyala (onbellek temizlense de kaybolmasin),
    // sonra kalici yolu isaretlemeye ver.
    final persistentPath = await CameraHelper.persistPhoto(shot.path);
    await PriceChangeService.instance.markChanged(item.id!, persistentPath);
    if (labelGroup != null) {
      await LabelPendingQueueService.instance.push(
        barcode: item.barcode,
        productName: item.productName ?? item.barcode,
        groupKey: labelGroup,
        source: 'price_change_guide',
      );
    }
    _items[_index] = item.copyWith(changed: true, photoPath: shot.path);
    setState(() {
      _busy = false;
      _sendToLabelGroup = null;
    });
    if (labelGroup != null && mounted) {
      final title =
          LabelGroup.values.firstWhere((g) => g.name == labelGroup).title;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Etiket Basım → $title\'a gönderildi'),
          backgroundColor: AppTheme.accent,
          duration: const Duration(milliseconds: 1200),
        ),
      );
    }
    _nextOrFinish();
  }

  /// Etiket Basim'daki 5 listeyi gosteren secim sheet'i (price_change_
  /// session_screen.dart'taki ile ayni mantik). Secilen grup
  /// _sendToLabelGroup'a yazilir.
  Future<void> _pickLabelGroup() async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.hairline,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Hangi listeye gönderilsin?',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            for (final g in LabelGroup.values)
              ListTile(
                leading: Icon(
                  _sendToLabelGroup == g.name
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: _sendToLabelGroup == g.name
                      ? AppTheme.accent
                      : AppTheme.textTertiary,
                ),
                title: Text(g.title),
                onTap: () => Navigator.pop(context, g.name),
              ),
            if (_sendToLabelGroup != null)
              ListTile(
                leading: const Icon(Icons.close_rounded,
                    color: AppTheme.statusExpired),
                title: const Text('Gönderme (vazgeç)',
                    style: TextStyle(color: AppTheme.statusExpired)),
                onTap: () => Navigator.pop(context, ''),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _sendToLabelGroup = result.isEmpty ? null : result);
  }

  Future<void> _undo() async {
    final item = _items[_index];
    if (item.id == null) return;
    await PriceChangeService.instance.unmarkChanged(item.id!);
    setState(() => _items[_index] = item.copyWith(changed: false));
  }

  void _nextOrFinish() {
    // Sonraki degistirilmemis urune atla.
    final next = _items.indexWhere((e) => !e.changed, _index + 1);
    if (next >= 0) {
      _goTo(next);
      return;
    }
    // Bastan kalan var mi?
    final anyPending = _items.indexWhere((e) => !e.changed);
    if (anyPending >= 0) {
      _goTo(anyPending);
      return;
    }
    // Hepsi tamam.
    _showAllDone();
  }

  void _showAllDone() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        icon: const Icon(Icons.celebration_rounded,
            color: AppTheme.statusSafe, size: 48),
        title: const Text('Tüm ürünler tamam!',
            textAlign: TextAlign.center),
        content: const Text(
          'Bu oturumdaki tüm fiyat değişimleri işaretlendi.',
          textAlign: TextAlign.center,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('Bitir'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.primary),
          title: const Text('Fiyat Rehberi'),
        ),
        body: Center(
          child: Text('Bu oturumda ürün yok',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
      );
    }

    final item = _items[_index];
    final doneCount = _items.where((e) => e.changed).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.primary),
        title: Text('${_index + 1} / ${_items.length}'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '$doneCount ✓',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Ilerleme cubugu
          LinearProgressIndicator(
            value: _items.isEmpty ? 0 : doneCount / _items.length,
            backgroundColor: AppTheme.surfaceAlt,
            color: AppTheme.statusSafe,
            minHeight: 6,
          ),
          Expanded(child: _itemView(item)),
          _bottomBar(item),
        ],
      ),
    );
  }

  Widget _itemView(PriceChangeItem item) {
    final imageUrl = _imageCache[item.barcode];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // ── Ust: urun fotosu (OFF) ──
          Container(
            width: double.infinity,
            height: 220,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: imageUrl != null && imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary, strokeWidth: 2),
                    ),
                    errorWidget: (_, __, ___) => _noImage(),
                  )
                : (_imageCache.containsKey(item.barcode)
                    ? _noImage()
                    : const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primary, strokeWidth: 2),
                      )),
          ),
          const SizedBox(height: 20),

          // ── Urun adi (BUYUK) ──
          Text(
            item.productName ?? 'İsimsiz Ürün',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          // Barkod + reyon
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip(Icons.qr_code_rounded, item.barcode),
              if (item.aisle != null && item.aisle!.isNotEmpty)
                _chip(Icons.shelves, 'Reyon: ${item.aisle}'),
            ],
          ),
          const SizedBox(height: 24),

          // ── Eski -> Yeni fiyat (BUYUK) ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.hairline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _priceBlock(
                  'ESKİ ETİKET',
                  item.oldPrice,
                  AppTheme.textSecondary,
                  strike: true,
                ),
                const Icon(Icons.arrow_forward_rounded,
                    size: 32, color: AppTheme.primary),
                _priceBlock(
                  'YENİ ETİKET',
                  item.newPrice,
                  AppTheme.statusSafe,
                ),
              ],
            ),
          ),

          // Fiyat farki bilgisi
          if (item.oldPrice != null && item.newPrice != null) ...[
            const SizedBox(height: 12),
            _diffInfo(item.oldPrice!, item.newPrice!),
          ],
        ],
      ),
    );
  }

  Widget _noImage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_rounded,
              color: AppTheme.textTertiary, size: 48),
          SizedBox(height: 8),
          Text('Görsel bulunamadı',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _priceBlock(String label, double? price, Color color,
      {bool strike = false}) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textTertiary,
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Text(
          price != null ? '${price.toStringAsFixed(2)} ₺' : '—',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: color,
            decoration: strike ? TextDecoration.lineThrough : null,
            decorationColor: AppTheme.textTertiary,
            decorationThickness: 2,
          ),
        ),
      ],
    );
  }

  Widget _diffInfo(double oldP, double newP) {
    final diff = newP - oldP;
    final isUp = diff > 0;
    final color = isUp ? AppTheme.statusExpired : AppTheme.statusSafe;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            color: color, size: 20),
        const SizedBox(width: 6),
        Text(
          '${isUp ? '+' : ''}${diff.toStringAsFixed(2)} ₺ '
          '(${isUp ? 'zam' : 'indirim'})',
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  Widget _bottomBar(PriceChangeItem item) {
    final isDone = item.changed;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "Etiket Basim'a da gonder" secimi — sadece henuz
            // isaretlenmemis urunlerde gosterilir.
            if (!isDone)
              InkWell(
                onTap: _busy ? null : _pickLabelGroup,
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _sendToLabelGroup != null
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        color: _sendToLabelGroup != null
                            ? AppTheme.accent
                            : AppTheme.textTertiary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _sendToLabelGroup == null
                              ? 'Etiket Basım listesine de gönder'
                              : 'Etiket Basım → ${LabelGroup.values.firstWhere((g) => g.name == _sendToLabelGroup!).title}',
                          style: TextStyle(
                            fontSize: 13,
                            color: _sendToLabelGroup != null
                                ? AppTheme.accent
                                : AppTheme.textSecondary,
                            fontWeight: _sendToLabelGroup != null
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppTheme.textTertiary),
                    ],
                  ),
                ),
              ),
            // Ana eylem: Cekildi / Geri al
            SizedBox(
              width: double.infinity,
              child: isDone
                  ? FilledButton.icon(
                      onPressed: _undo,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.surfaceAlt,
                        foregroundColor: AppTheme.textSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.undo_rounded, size: 20),
                      label: const Text('Bu ürün çekildi ✓ (geri al)',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    )
                  : FilledButton.icon(
                      onPressed: _busy ? null : _markDone,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.statusSafe,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt_rounded, size: 22),
                      label: const Text('Fotoğraf Çek ve İşaretle',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
            ),
            const SizedBox(height: 10),
            // Gezinme: Onceki / Sonraki
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _index > 0 ? () => _goTo(_index - 1) : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: BorderSide(color: AppTheme.hairline),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    label: const Text('Önceki'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _index < _items.length - 1
                        ? () => _goTo(_index + 1)
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: BorderSide(
                          color: AppTheme.primary.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    label: const Text('Sonraki / Atla'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

