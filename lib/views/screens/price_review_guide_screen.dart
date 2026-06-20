import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/services/barcode_lookup_service.dart';
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
    final picker = ImagePicker();
    final XFile? shot = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (shot == null) return; // kullanici vazgecti -> isaretleme

    final labelGroup = _sendToLabelGroup;
    setState(() => _busy = true);
    // Fotoyu kalici sakla + degistirildi isaretle.
    await PriceChangeService.instance.markChanged(item.id!, shot.path);
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
      return const Scaffold(
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
        body: const Center(
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
      body: Stack(
        children: [
          Column(
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
              // Alt sheet acikken iceriklerin altinda bosluk birakir.
              const SizedBox(height: 64),
            ],
          ),
          // Butonlarin altinda bekleyen, yukari kaydirilinca acilan
          // etiket kontrol penceresi (kamera + barkod/fiyat dogrulama).
          LabelCheckSheet(
            key: ValueKey('lc_${item.barcode}_${item.newPrice}'),
            expectedBarcode: item.barcode,
            expectedNewPrice: item.newPrice,
            expectedOldPrice: item.oldPrice,
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
    return const Center(
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
            style: const TextStyle(
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
      decoration: const BoxDecoration(
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
                      side: const BorderSide(color: AppTheme.hairline),
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

/// Etiket kontrol sonucu rengi.
enum _LabelMatch { none, green, yellow, red }

/// ════════════════════════════════════════════════════════════════════
///  ETİKET KONTROL PENCERESİ
///  Butonlarin altinda bekleyen, yukari kaydirilinca acilan kayan pencere.
///  Acilinca kamera baslar ve etiket tarar:
///   - Yesil : barkod bu urune ait + fiyat YENİ (dogru) etiketle eslesiyor
///   - Kirmizi: barkod bu urune ait AMA fiyat hala ESKİ
///   - Sari  : barkod baska bir urune ait
///  Barkod canli okunur; fiyat ayni kareden OCR (ML Kit) ile cozulur.
/// ════════════════════════════════════════════════════════════════════
class LabelCheckSheet extends StatefulWidget {
  final String expectedBarcode;
  final double? expectedNewPrice;
  final double? expectedOldPrice;

  const LabelCheckSheet({
    super.key,
    required this.expectedBarcode,
    required this.expectedNewPrice,
    required this.expectedOldPrice,
  });

  @override
  State<LabelCheckSheet> createState() => _LabelCheckSheetState();
}

class _LabelCheckSheetState extends State<LabelCheckSheet> {
  final DraggableScrollableController _drag =
      DraggableScrollableController();
  MobileScannerController? _scanner;
  final TextRecognizer _ocr =
      TextRecognizer(script: TextRecognitionScript.latin);

  bool _open = false;
  bool _processing = false;
  _LabelMatch _result = _LabelMatch.none;
  String _message = 'Etiketi çerçeveye getirin';
  double? _readPrice;
  String? _readBarcode;
  DateTime _lastShot = DateTime.fromMillisecondsSinceEpoch(0);

  static const double _minSize = 0.10; // kapali (sadece tutamac + ipucu)
  static const double _maxSize = 0.82;

  @override
  void dispose() {
    _scanner?.dispose();
    _ocr.close();
    _drag.dispose();
    super.dispose();
  }

  Future<void> _ensureCamera() async {
    // Controller zaten varsa (sheet kapatilip ACILMIŞ, dispose EDİLMEMİŞ
    // durumda), sadece stop edilmis kamerayi yeniden baslat. Eskiden burada
    // "controller var diye hicbir sey yapma" mantigi vardi; bu, ikinci
    // acilista kameranin donmus/siyah kalmasina sebep oluyordu.
    if (_scanner != null) {
      try {
        await _scanner!.start();
      } catch (_) {
        // Baslatma basarisiz olduysa controller'i tamamen yenile.
        await _scanner!.dispose();
        _scanner = null;
        await _createAndStartCamera();
      }
      return;
    }
    await _createAndStartCamera();
  }

  Future<void> _createAndStartCamera() async {
    _scanner = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      returnImage: true, // fiyat OCR'i icin kare goruntusu
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.code128,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
      ],
    );
    await _scanner!.start();
  }

  Future<void> _stopCamera() async {
    await _scanner?.stop();
  }

  void _onSheetChanged(double size) {
    final open = size > (_minSize + 0.08);
    if (open == _open) return;
    setState(() => _open = open);
    if (open) {
      _ensureCamera();
    } else {
      _stopCamera();
    }
  }

  /// Fiyat iki ondalik tolerans ile esit mi?
  bool _priceEq(double a, double? b) {
    if (b == null) return false;
    return (a - b).abs() < 0.01;
  }

  /// OCR metninden TL fiyatlarini cikar (ornn "89,95", "109.90 TL").
  List<double> _extractPrices(String text) {
    final prices = <double>[];
    final re = RegExp(r'(\d{1,4})[.,](\d{2})');
    for (final m in re.allMatches(text)) {
      final v = double.tryParse('${m.group(1)}.${m.group(2)}');
      if (v != null && v > 0 && v < 100000) prices.add(v);
    }
    return prices;
  }

  Future<void> _handleDetect(BarcodeCapture cap) async {
    if (!_open || _processing) return;
    // Asiri islem yapmamak icin ~1.2 sn arayla.
    final now = DateTime.now();
    if (now.difference(_lastShot).inMilliseconds < 1200) return;

    final codes = cap.barcodes;
    if (codes.isEmpty) return;
    final raw = codes.first.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;

    _lastShot = now;
    _processing = true;

    // Fiyat OCR: scanner'in dondurdugu kareyi gecici dosyaya yazip oku.
    double? price;
    try {
      final bytes = cap.image;
      if (bytes != null) {
        final dir = await getTemporaryDirectory();
        final f = File(
            '${dir.path}/lblscan_${now.millisecondsSinceEpoch}.jpg');
        await f.writeAsBytes(bytes, flush: true);
        final input = InputImage.fromFilePath(f.path);
        final res = await _ocr.processImage(input);
        final prices = _extractPrices(res.text);
        // Beklenen yeni/eski fiyatla eslesen var mi? Once onu sec.
        for (final p in prices) {
          if (_priceEq(p, widget.expectedNewPrice) ||
              _priceEq(p, widget.expectedOldPrice)) {
            price = p;
            break;
          }
        }
        price ??= prices.isNotEmpty ? prices.first : null;
        try {
          await f.delete();
        } catch (_) {}
      }
    } catch (_) {
      // OCR basarisiz -> fiyat null kalir, sadece barkod degerlendirilir.
    }

    _evaluate(raw, price);
    if (mounted) setState(() {});
    // Kisa bir bekleme: kullanici sonucu gorsun.
    await Future.delayed(const Duration(milliseconds: 600));
    _processing = false;
  }

  void _evaluate(String barcode, double? price) {
    _readBarcode = barcode;
    _readPrice = price;

    final sameProduct =
        _normalize(barcode) == _normalize(widget.expectedBarcode);

    if (!sameProduct) {
      _result = _LabelMatch.yellow;
      _message = 'Farklı ürün! Bu etiket başka barkoda ait.';
      return;
    }

    // Ayni urun. Fiyat degerlendir.
    if (price != null && _priceEq(price, widget.expectedNewPrice)) {
      _result = _LabelMatch.green;
      _message = 'Doğru etiket — yeni fiyat takılı.';
      return;
    }
    if (price != null && _priceEq(price, widget.expectedOldPrice)) {
      _result = _LabelMatch.red;
      _message = 'Barkod doğru ama fiyat ESKİ! Değiştirilmeli.';
      return;
    }
    // Barkod dogru, fiyat okunamadi/eslesmedi -> temkinli kirmizi-uyari.
    _result = _LabelMatch.red;
    _message = price == null
        ? 'Barkod doğru, fiyat okunamadı. Etiketi netleştirin.'
        : 'Barkod doğru ama fiyat (${price.toStringAsFixed(2)} ₺) eşleşmiyor.';
  }

  String _normalize(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Color get _resultColor {
    switch (_result) {
      case _LabelMatch.green:
        return AppTheme.statusSafe;
      case _LabelMatch.yellow:
        return const Color(0xFFE6B800);
      case _LabelMatch.red:
        return AppTheme.statusExpired;
      case _LabelMatch.none:
        return AppTheme.surfaceHigh;
    }
  }

  IconData get _resultIcon {
    switch (_result) {
      case _LabelMatch.green:
        return Icons.check_circle_rounded;
      case _LabelMatch.yellow:
        return Icons.swap_horiz_rounded;
      case _LabelMatch.red:
        return Icons.error_rounded;
      case _LabelMatch.none:
        return Icons.qr_code_scanner_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _drag,
      initialChildSize: _minSize,
      minChildSize: _minSize,
      maxChildSize: _maxSize,
      snap: true,
      snapSizes: const [_minSize, _maxSize],
      builder: (context, scrollController) {
        // Boyut degisimini dinlemek icin NotificationListener kullaniyoruz.
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            _onSheetChanged(n.extent);
            return false;
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                  color: _open ? _resultColor : AppTheme.hairline,
                  width: _open ? 2 : 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.zero,
              children: [
                _handle(),
                if (_open) _expandedContent() else _collapsedHint(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _handle() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: AppTheme.textTertiary,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _collapsedHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.keyboard_arrow_up_rounded,
              color: AppTheme.accent, size: 22),
          const SizedBox(width: 8),
          const Text(
            'Etiket kontrolü için yukarı kaydır',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _expandedContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(
        children: [
          // Sonuc bandi
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: _resultColor.withOpacity(
                  _result == _LabelMatch.none ? 0.4 : 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _resultColor, width: 1.4),
            ),
            child: Row(
              children: [
                Icon(_resultIcon, color: _resultColor, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _message,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: _result == _LabelMatch.none
                          ? AppTheme.textSecondary
                          : _resultColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Kamera onizleme
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 280,
              width: double.infinity,
              child: _scanner == null
                  ? Container(
                      color: Colors.black,
                      child: const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primary),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _scanner!,
                          onDetect: _handleDetect,
                        ),
                        // Cerceve gostergesi
                        Center(
                          child: Container(
                            width: 220,
                            height: 150,
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: _resultColor, width: 3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          // Okunan degerler
          Row(
            children: [
              Expanded(
                child: _readoutTile(
                  'Okunan barkod',
                  _readBarcode ?? '—',
                  mono: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _readoutTile(
                  'Okunan fiyat',
                  _readPrice != null
                      ? '${_readPrice!.toStringAsFixed(2)} ₺'
                      : '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Beklenen: ${widget.expectedNewPrice?.toStringAsFixed(2) ?? '—'} ₺ '
            '(yeni)   •   ${widget.expectedOldPrice?.toStringAsFixed(2) ?? '—'} ₺ (eski)',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _readoutTile(String label, String value, {bool mono = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textTertiary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}
