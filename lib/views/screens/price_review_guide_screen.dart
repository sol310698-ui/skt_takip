import '../widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/services/camera_helper.dart';
import '../../core/services/label_pending_queue_service.dart';
import '../../core/services/price_change_service.dart';
import '../../core/services/teshir_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/label_target_sheet.dart';
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

  /// Urun teshirdeyse "teshir etiketi de gonderilsin" secimi.
  bool _alsoTeshirLabel = false;

  /// Teshir etiketinin gidecegi GECERLI liste (LabelGroup.name).
  String? _teshirGroupKey;

  /// Ayni A4 kagidindaki TUM urunler (grup). Biri degisince hepsi basilir.
  List<(String, String)> _teshirMembers = const [];

  /// Gosterilen urun teshirde mi (rozet + secici icin) — index degisince
  /// yeniden sorgulanir.
  Map<String, Object?>? _teshirRec;

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
    _loadTeshir();
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

  /// Gosterilen urun teshirde mi — index degisince tazelenir.
  Future<void> _loadTeshir() async {
    if (_items.isEmpty) return;
    final b = _items[_index].barcode;
    try {
      final rec = await TeshirService.instance.find(b);
      if (mounted) setState(() => _teshirRec = rec);
    } catch (_) {
      if (mounted) setState(() => _teshirRec = null);
    }
  }

  void _goTo(int i) {
    if (i < 0 || i >= _items.length) return;
    setState(() {
      _index = i;
      _sendToLabelGroup = null;
    });
    _prefetchImage();
    _loadTeshir();
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
    final alsoTeshir = _alsoTeshirLabel;
    if (labelGroup != null) {
      await LabelPendingQueueService.instance.push(
        barcode: item.barcode,
        productName: item.productName ?? item.barcode,
        groupKey: labelGroup,
        source: 'price_change_guide',
      );
    }
    // TESHIR ETIKETI: urun teshirde ve kullanici istediyse IKINCI etiket
    // ayri "Teşhir" grubuna dusulur (basimda ayirt edilebilsin).
    if (alsoTeshir) {
      // GRUBUN TAMAMI: ayni A4 kagidindaki tum urunler listeye gider
      // (kagit yeniden basilacagi icin biri yetmez). Grup yoksa tek urun.
      final gKey = _teshirGroupKey ?? LabelGroup.a4.name;
      final members = _teshirMembers.isEmpty
          ? [(item.barcode, item.productName ?? item.barcode)]
          : _teshirMembers;
      for (final m in members) {
        await LabelPendingQueueService.instance.push(
          barcode: m.$1,
          productName: m.$2,
          groupKey: gKey,
          source: 'teshir',
        );
      }
    }
    _items[_index] = item.copyWith(changed: true, photoPath: shot.path);
    setState(() {
      _busy = false;
      _sendToLabelGroup = null;
      _alsoTeshirLabel = false;
      _teshirGroupKey = null;
      _teshirMembers = const [];
    });
    if ((labelGroup != null || alsoTeshir) && mounted) {
      final shownKey = labelGroup ?? _teshirGroupKey ?? LabelGroup.a4.name;
      final title = LabelGroup.values
          .firstWhere((g) => g.name == shownKey,
              orElse: () => LabelGroup.a4)
          .title;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Etiket Basım → $title'
              '${alsoTeshir ? ' + teşhir (${_teshirMembers.isEmpty ? 1 : _teshirMembers.length} ürün)' : ''}'),
          backgroundColor: AppTheme.accent,
          duration: const Duration(milliseconds: 1400),
        ),
      );
    }
    _nextOrFinish();
  }

  /// ZENGIN ETIKET HEDEFI SECICI (v158): liste aciklamalari, o listede
  /// bekleyen sayisi ve TESHIR entegrasyonu ile.
  Future<void> _pickLabelGroup() async {
    final item = _items[_index];
    final res = await showLabelTargetSheet(
      context,
      barcode: item.barcode,
      productName: item.productName ?? item.barcode,
      currentGroupKey: _sendToLabelGroup,
      currentAlsoTeshir: _alsoTeshirLabel,
      currentTeshirGroupKey: _teshirGroupKey,
      oldPrice: item.oldPrice,
      newPrice: item.newPrice,
    );
    if (res == null || !mounted) return;
    setState(() {
      _sendToLabelGroup = res.groupKey;
      _alsoTeshirLabel = res.alsoTeshir;
      _teshirGroupKey = res.teshirGroupKey;
      _teshirMembers = res.teshirMembers;
    });
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
      body: Column(
        children: [
          _hero(doneCount),
          Expanded(child: _itemView(item)),
          _bottomBar(item),
        ],
      ),
    );
  }

  /// GRADYAN HERO — uygulamanin tasarim dili: sira, tamamlanan sayisi ve
  /// ilerleme cubugu tek panelde.
  Widget _hero(int doneCount) {
    final topPad = MediaQuery.of(context).padding.top;
    final total = _items.length;
    final ratio = total == 0 ? 0.0 : doneCount / total;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, topPad + 6, 8, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary,
            Color.lerp(AppTheme.primary, AppTheme.accent, 0.5)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppTheme.rLg)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_index + 1} / $total',
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    Text('$doneCount tamam · ${total - doneCount} kaldı',
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.white70)),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_rounded,
                        size: 15, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('$doneCount',
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                backgroundColor: Colors.black.withOpacity(0.18),
                color: Colors.white,
                minHeight: 6,
              ),
            ),
          ),
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
            // ONCELIK: telefondaki (yerel) foto 1., internet 2. planda.
            child: SmartProductImage(
              key: ValueKey('prg_${item.barcode}'),
              barcode: item.barcode,
              networkUrl: imageUrl,
              fit: BoxFit.contain,
              placeholder: () => _imageCache.containsKey(item.barcode)
                  ? _noImage()
                  : const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary, strokeWidth: 2),
                    ),
            ),
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

  /// ETIKET HEDEFI SATIRI (detayli): secilmediyse yonlendirir; secildiyse
  /// hangi listeye gidecegini ve teshir etiketi durumunu ACIKCA gosterir.
  Widget _labelTargetRow() {
    final hasGroup = _sendToLabelGroup != null;
    final onTeshir = _teshirRec != null;
    final active = hasGroup || _alsoTeshirLabel;
    final groupTitle = hasGroup
        ? LabelGroup.values
            .firstWhere((g) => g.name == _sendToLabelGroup!)
            .title
        : null;
    return InkWell(
      onTap: _busy ? null : _pickLabelGroup,
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withOpacity(0.10)
              : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(
              color: active
                  ? AppTheme.accent.withOpacity(0.5)
                  : AppTheme.hairline),
        ),
        child: Row(
          children: [
            Icon(
              active
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 21,
              color: active ? AppTheme.accent : AppTheme.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active
                        ? 'Etiket Basım → ${groupTitle ?? _teshirTitle()}'
                        : 'Etiket Basım listesine de gönder',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            active ? FontWeight.w800 : FontWeight.w600,
                        color: active
                            ? AppTheme.accent
                            : AppTheme.textSecondary),
                  ),
                  // Teshir bilgisi: urun teshirdeyse HER ZAMAN gorunur.
                  if (onTeshir)
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded,
                            size: 12, color: AppTheme.coral),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _alsoTeshirLabel
                                ? 'Teşhir etiketi de eklenecek'
                                : 'Bu ürün teşhirde — teşhir etiketi de gerekli',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.coral),
                          ),
                        ),
                      ],
                    )
                  else if (!active)
                    Text('5 listeden birini seç',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textTertiary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }

  /// Teshir etiketinin gidecegi listenin adi.
  String _teshirTitle() => LabelGroup.values
      .firstWhere((g) => g.name == (_teshirGroupKey ?? LabelGroup.a4.name),
          orElse: () => LabelGroup.a4)
      .title;

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
            if (!isDone) _labelTargetRow(),
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

