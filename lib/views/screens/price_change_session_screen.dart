import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/camera_helper.dart';
import '../../core/services/gemini_ocr_service.dart';
import '../../core/services/price_check_channel.dart';
import '../../core/services/label_pending_queue_service.dart';
import '../../core/services/price_change_service.dart';
import '../../core/services/database_service.dart';
import '../../data/datasources/barcode_directory_datasource.dart';
import '../../data/models/barcode_entry.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/scan_overlay.dart';
import '../../core/utils/scan_parser.dart';
import '../widgets/label_target_sheet.dart';
import '../widgets/ui_kit.dart';
import 'image_zoom_screen.dart';
import 'label_print_screen.dart' show LabelGroup, LabelGroupX;
import 'price_change_review_screen.dart';
import 'quick_photo_capture_screen.dart';
import 'price_review_guide_screen.dart';
import 'web_search_screen.dart';
import '../../core/services/shelf_layout_service.dart';
import '../../core/services/teshir_service.dart';
import '../../core/services/location_reveal_prefs.dart';
import '../widgets/location_reveal.dart';

/// Tek fiyat degisim oturumunun detayi.
/// Aktif: kamera ile uygula (foto kanitli). Tamamlanmis: rapor + kanitlar.
class PriceChangeSessionScreen extends StatefulWidget {
  final int sessionId;
  const PriceChangeSessionScreen({super.key, required this.sessionId});

  @override
  State<PriceChangeSessionScreen> createState() =>
      _PriceChangeSessionScreenState();
}

class _PriceChangeSessionScreenState
    extends State<PriceChangeSessionScreen> {
  // ── EL TERMINALI (HID): odakli ama klavyesiz giris (v138 kalibi) ──
  final TextEditingController _hidCtrl = TextEditingController();
  final FocusNode _hidFocus = FocusNode();
  // Rota modu: kalanlar reyon dizilim sirasina gore siralanir.
  bool _routeSorted = false;

  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: false,
  );

  PriceChangeSession? _session;
  List<PriceChangeItem> _items = [];
  bool _busy = false;
  PriceChangeItem? _matched;
  String? _scanMessage;
  // Eslesen urunu onaylarken "Etiket Basim'a da gonder" secimi.
  // null = gonderilmeyecek; doluysa secilen grubun key'i (kalinRon, a4, ...).
  // v2: SON SECIM OTURUM BOYUNCA HATIRLANIR — reyonda ayni etiket tipi pes
  // pese kullanilir; her urunde yeniden secmek akisi yavaslatiyordu.
  String? _sendToLabelGroup;
  /// Teshir etiketi de gonderilsin mi (urun teshirdeyse).
  bool _alsoTeshirLabel = false;
  static String? _lastLabelGroup; // oturumlar arasi da hatirla

  // ── LISTE FILTRE + ARAMA ──
  // Uzun listelerde (100+ satir A4) kalanlari bulmak zordu. Varsayilan
  // filtre KALAN'dir: is bitmemis urunler ustte, biten kalabalik yapmaz.
  _ItemFilter _filter = _ItemFilter.pending;
  final TextEditingController _listSearchCtrl = TextEditingController();
  String _listQuery = '';

  List<PriceChangeItem> get _visibleItems {
    Iterable<PriceChangeItem> it = _items;
    switch (_filter) {
      case _ItemFilter.pending:
        it = it.where((i) => !i.changed);
        break;
      case _ItemFilter.done:
        it = it.where((i) => i.changed);
        break;
      case _ItemFilter.all:
        break;
    }
    final q = _listQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      it = it.where((i) =>
          i.barcode.toLowerCase().contains(q) ||
          (i.productName?.toLowerCase().contains(q) ?? false));
    }
    return it.toList();
  }
  // Excel'den okunan, stok kodu dahil barkod dizini kayitlari.
  // Onay sonrasi dizine (oncelik: excel) yazilir.
  List<BarcodeEntry> _pendingDirEntries = [];

  bool get _completed => _session?.isCompleted ?? false;

  @override
  void initState() {
    super.initState();
    _load(startCamera: true);
  }

  @override
  void dispose() {
    _hidCtrl.dispose();
    _hidFocus.dispose();
    _scanner.dispose();
    _listSearchCtrl.dispose();
    super.dispose();
  }

  /// Excel'den okunan stok kodlu dizin kayitlarini barkod dizinine yazar.
  /// Yalnizca onaylanan barkodlara ait olanlar yazilir. importAll oncelik
  /// mantigi geregi BarcodeSource.excel mevcut ad/stok kodunun uzerine yazar.
  Future<void> _writePendingDirEntries(
      List<PriceChangeItem> confirmed) async {
    if (_pendingDirEntries.isEmpty) return;
    final okBarcodes = confirmed.map((e) => e.barcode.trim()).toSet();
    final toWrite = _pendingDirEntries
        .where((e) => okBarcodes.contains(e.barcode.trim()))
        .toList();
    _pendingDirEntries = [];
    if (toWrite.isEmpty) return;
    try {
      final ds = BarcodeDirectoryDataSource(DatabaseService.instance);
      await ds.importAll(toWrite);
    } catch (_) {
      // Dizin yazimi fiyat degisim akisini bloke etmesin.
    }
  }

  Future<void> _load({bool startCamera = false}) async {
    final s =
        await PriceChangeService.instance.getSession(widget.sessionId);
    final items =
        await PriceChangeService.instance.getItems(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _session = s;
      _items = items;
    });
    if (startCamera && !(s?.isCompleted ?? true)) {
      await _startCameraSafe();
    }
  }

  /// Kamerayi guvenli baslatir. Onceki bir ekranin kamerasi henuz tam
  /// serbest kalmadiysa (ozellikle hizli ekran gecislerinde) ilk deneme
  /// basarisiz olabilir; kisa bir bekleme ile bir kez daha denenir.
  Future<void> _startCameraSafe() async {
    try {
      await _scanner.start();
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      try {
        await _scanner.start();
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Kamera başlatılamadı. Geri gidip tekrar deneyin veya uygulamayı yeniden açın.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // ─────────────────────────── A4 ekleme (Gemini -> ML Kit) ──────────
  Future<void> _captureA4() async {
    final photo = await CameraHelper.pickImage(
        source: ImageSource.camera, imageQuality: 92);
    if (photo == null) return;

    setState(() => _busy = true);
    await _scanner.stop();

    List<PriceChangeItem> parsed = [];
    String source = 'Gemini AI';

    // 1) Gemini (online, dogruluk yuksek)
    try {
      parsed = await GeminiOcrService.instance
          .extractTable(File(photo.path), widget.sessionId);
    } catch (e) {
      // 2) Fallback: ML Kit yerel
      source = 'Cihaz OCR';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Online okuma yapılamadı ($e) — cihaz OCR kullanılıyor')),
        );
      }
      final recognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final input = InputImage.fromFilePath(photo.path);
        final result = await recognizer.processImage(input);
        parsed = PriceChangeParser.parse(result.text, widget.sessionId);
      } catch (_) {
      } finally {
        recognizer.close();
      }
    }

    if (!mounted) return;

    if (parsed.isEmpty) {
      setState(() => _busy = false);
      await _scanner.start();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Sayfadan satır okunamadı. Daha net çekmeyi deneyin.')),
      );
      return;
    }

    // 3) ONIZLEME — kullanici duzeltir/onaylar (hata kabul yok).
    final confirmed =
        await Navigator.of(context).push<List<PriceChangeItem>>(
      MaterialPageRoute(
        builder: (_) =>
            PriceChangeReviewScreen(items: parsed, source: source),
      ),
    );

    if (confirmed == null || confirmed.isEmpty) {
      setState(() => _busy = false);
      await _scanner.start();
      return;
    }

    final added = await PriceChangeService.instance.addA4ToSession(
      sessionId: widget.sessionId,
      tempPhotoPath: photo.path,
      items: confirmed,
    );
    // Barkod dizinini zenginlestir (yeni barkod+ad ciftleri).
    final enriched =
        await PriceChangeService.instance.enrichDirectory(confirmed);
    await _load();
    if (mounted) {
      setState(() => _busy = false);
      await _scanner.start();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$added ürün eklendi (toplam ${_items.length})'
              '${enriched > 0 ? " • $enriched yeni ürün dizine kaydedildi" : ""}'),
          backgroundColor: AppTheme.statusSafe,
        ),
      );
    }
  }

  // ─────────────────────────── Excel ice aktarma ─────────────────────
  /// Baska uygulamadan taranmis Excel'i (Barkod|Ad|StokKodu|Fiyat|Eski|Reyon)
  /// oturuma yukler. OCR'siz, %100 dogru veri kaynagi.
  Future<void> _importExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dosya okunamadı')),
        );
      }
      return;
    }

    setState(() => _busy = true);
    await _scanner.stop();

    final parsed = <PriceChangeItem>[];
    final dirEntries = <BarcodeEntry>[]; // barkod dizinine yazilacak (stok kodlu)
    try {
      final excel = Excel.decodeBytes(bytes);
      final sheetName = excel.sheets.keys.first;
      final sheet = excel.sheets[sheetName]!;
      final now = DateTime.now();
      final seen = <String>{};

      double? toPrice(String? s) {
        if (s == null || s.trim().isEmpty) return null;
        return double.tryParse(s.trim().replaceAll(',', '.'));
      }

      for (int i = 0; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        String cell(int c) =>
            c < row.length ? (row[c]?.value?.toString().trim() ?? '') : '';

        final barcode = cell(0);

        // Baslik satirini atla.
        if (i == 0) {
          final lower = barcode.toLowerCase();
          if (lower.contains('barkod') ||
              lower.contains('barcode') ||
              !RegExp(r'\d').hasMatch(barcode)) {
            continue;
          }
        }

        // Gecerli barkod: 12-13 hane sayi.
        if (!RegExp(r'^\d{12,13}$').hasMatch(barcode)) continue;
        if (seen.contains(barcode)) continue;
        seen.add(barcode);

        final name = cell(1).replaceAll('*', '').trim();
        final stockCode = cell(2).trim(); // Stok Kodu (barkod dizinine yazilir)
        final newPrice = toPrice(cell(3));
        final oldPrice = toPrice(cell(4));
        final aisle = cell(5);

        parsed.add(PriceChangeItem(
          batchId: 'excel',
          sessionId: widget.sessionId,
          barcode: barcode,
          productName: name.isEmpty ? null : name,
          newPrice: newPrice,
          oldPrice: oldPrice,
          aisle: aisle.isEmpty ? null : aisle,
          createdAt: now,
        ));

        // Bu Excel ayni zamanda barkod dizinini de stok koduyla zenginlestirir.
        // Excel en yuksek oncelik (BarcodeSource.excel) oldugu icin mevcut
        // kayitlarin ad/stok kodunu gunceller.
        if (name.isNotEmpty && ScanResult.looksLikeBarcode(barcode)) {
          dirEntries.add(BarcodeEntry(
            barcode: barcode,
            productName: name,
            stockCode: stockCode.isEmpty ? null : stockCode,
            importedAt: now,
            source: BarcodeSource.excel,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await _scanner.start();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel okunamadı: $e')),
        );
      }
      return;
    }

    if (!mounted) return;

    // Excel'den okunan stok kodlu kayitlari sakla (onay sonrasi dizine yazilir).
    _pendingDirEntries = dirEntries;

    if (parsed.isEmpty) {
      setState(() => _busy = false);
      await _scanner.start();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Excel\'de geçerli satır bulunamadı. Format: '
                'Barkod | Stok Adı | Stok Kodu | Fiyatı | Eski Fiyatı | Reyonu')),
      );
      return;
    }

    // Onizleme — Excel verisi de kontrol edilir (tutarlilik).
    final confirmed =
        await Navigator.of(context).push<List<PriceChangeItem>>(
      MaterialPageRoute(
        builder: (_) =>
            PriceChangeReviewScreen(items: parsed, source: 'Excel'),
      ),
    );

    if (confirmed == null || confirmed.isEmpty) {
      setState(() => _busy = false);
      await _scanner.start();
      return;
    }

    final added = await PriceChangeService.instance
        .addItemsToSession(widget.sessionId, confirmed);
    // Barkod dizinini zenginlestir: yeni barkod+ad ciftlerini kaydet.
    final enriched =
        await PriceChangeService.instance.enrichDirectory(confirmed);
    // Stok kodlu kayitlari dizine yaz (Excel oncelikli -> mevcut ad/stok
    // kodunun uzerine yazar). Onay ekraninda kullanici barkodlari
    // degistirmis olabilir; sadece onaylanan barkodlara ait olanlari yaz.
    await _writePendingDirEntries(confirmed);
    await _load();
    if (mounted) {
      setState(() => _busy = false);
      await _scanner.start();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$added ürün eklendi (toplam ${_items.length})'
              '${enriched > 0 ? " • $enriched yeni ürün dizine kaydedildi" : ""}'),
          backgroundColor: AppTheme.statusSafe,
        ),
      );
    }
  }

  // ─────────────────────────── Reyon uygulama ────────────────────────
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _matched != null || _completed) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    await _processScanRaw(raw);
  }

  /// El terminali Enter'i: alani temizle, kamerayla AYNI hattan isle.
  Future<void> _onHidSubmit(String v) async {
    final t = v.trim();
    _hidCtrl.clear();
    if (t.isEmpty || _busy || _matched != null || _completed) {
      if (mounted) _hidFocus.requestFocus();
      return;
    }
    await _processScanRaw(t);
    if (mounted) _hidFocus.requestFocus();
  }

  /// KAMERA + EL TERMINALI ortak eslestirme hatti.
  Future<void> _processScanRaw(String raw) async {
    final code = ScanParser.parse(raw).barcode;
    if (code == null) return;
    HapticFeedback.mediumImpact(); // okuma basarili — titresimle uyar

    final item = await PriceChangeService.instance
        .findInSession(widget.sessionId, code);
    if (!mounted) return;
    if (item == null) {
      setState(() => _scanMessage = 'Listede yok: $code');
      HapticFeedback.heavyImpact();
      PriceCheckChannel.speak('Listede yok');
      return;
    }
    if (item.changed) {
      setState(() => _scanMessage =
          '${item.productName ?? code} zaten değiştirildi ✓');
      PriceCheckChannel.speak('Zaten değiştirildi');
      return;
    }
    await _scanner.stop();
    setState(() {
      _matched = item;
      _scanMessage = null;
      _sendToLabelGroup = _lastLabelGroup; // son secim hazir gelsin
    });
    // Sesli: urun adi + yeni fiyat — ekrana bakmadan dogrulama.
    final fiyat = item.newPrice != null
        ? ', yeni fiyat ${item.newPrice!.toStringAsFixed(2)} lira'
        : '';
    PriceCheckChannel.speak('${item.productName ?? 'Ürün'} eşleşti$fiyat');
  }

  Future<void> _confirmChange() async {
    final item = _matched;
    if (item == null || item.id == null) return;
    // v2 — UYGULAMA ICI HIZLI CEKIM: sistem kamera uygulamasi ACILMAZ
    // (pil/hiz kaybi yok, uygulama arka plana atilmaz). 1 sn geri sayimla
    // OTOMATIK ceker; kullanici isterse erken ceker ya da vazgecer.
    final photoPath = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => QuickPhotoCaptureScreen(
          productName: item.productName ?? item.barcode,
          barcode: item.barcode,
        ),
      ),
    );
    if (photoPath == null || photoPath.isEmpty) return; // foto ZORUNLU

    final labelGroup = _sendToLabelGroup;
    setState(() => _busy = true);
    // QuickPhoto zaten kucultup KALICI dizine yazar; dogrudan kullan.
    final persistentPath = photoPath;
    await PriceChangeService.instance.markChanged(item.id!, persistentPath);
    if (labelGroup != null) {
      // Etiket Basim ekrani acildiginda bu kuyruktan okunup eklenecek.
      await LabelPendingQueueService.instance.push(
        barcode: item.barcode,
        productName: item.productName ?? item.barcode,
        groupKey: labelGroup,
        source: 'price_change',
      );
    }
    // ── TESHIR ETIKETI ───────────────────────────────────────────
    // Kullanici etiket hedefi seciciden "teshir etiketi de" dediyse
    // DOGRUDAN eklenir (tekrar SORULMAZ). Secici hic acilmadiysa eski
    // davranis: urun teshirdeyse sorulur.
    if (_alsoTeshirLabel) {
      await LabelPendingQueueService.instance.push(
        barcode: item.barcode,
        productName: item.productName ?? item.barcode,
        groupKey: labelGroup ?? 'Teşhir',
        source: 'teshir',
      );
      _alsoTeshirLabel = false;
    } else {
      await _maybeAskTeshirLabel(item, labelGroup);
    }
    await _load();
    if (!mounted) return;
    _lastLabelGroup = labelGroup; // bir sonraki urun icin hatirla
    setState(() {
      _matched = null;
      _busy = false;
      _sendToLabelGroup = labelGroup;
    });

    final pending = _items.where((i) => !i.changed).length;
    if (pending == 0 && _items.isNotEmpty) {
      // KUSURSUZ AKIS: hepsi bitti -> tamamlama onerisi.
      PriceCheckChannel.speak('Tebrikler, liste tamamlandı');
      _offerComplete();
    } else {
      PriceCheckChannel.speak('Kaydedildi, $pending kaldı');
      await _scanner.start();
      final groupTitle = labelGroup == null
          ? null
          : LabelGroup.values
              .firstWhere((g) => g.name == labelGroup)
              .title;
      final labelNote =
          groupTitle != null ? ' • $groupTitle\'a gönderildi' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✓ ${item.productName ?? item.barcode} — Kalan: $pending$labelNote'),
          backgroundColor: AppTheme.statusSafe,
          duration: const Duration(milliseconds: 1300),
        ),
      );
    }
  }

  /// Eslesen urun TESHIRDE ise teshir etiketi icin sorar; onaylanirsa
  /// barkodu etiket basim kuyruguna ekler (ikinci etiket).
  Future<void> _maybeAskTeshirLabel(
      PriceChangeItem item, String? labelGroup) async {
    Map<String, Object?>? teshir;
    try {
      teshir = await TeshirService.instance.find(item.barcode);
    } catch (_) {}
    if (teshir == null || !mounted) return;

    final note = (teshir['note'] as String?)?.trim();
    PriceCheckChannel.speak('Bu ürün teşhirde');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.storefront_rounded,
            color: AppTheme.coral, size: 30),
        title: const Text('Bu ürün TEŞHİRDE'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.productName ?? item.barcode,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.place_rounded,
                      size: 14, color: AppTheme.coral),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(note,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.coral)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            const Text(
                'Teşhirdeki etiket de değişmeli. Bu barkod etiket basım '
                'listesine eklensin mi?',
                style: TextStyle(fontSize: 13.5)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hayır')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.playlist_add_rounded, size: 18),
            label: const Text('Listeye Ekle'),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.coral),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await LabelPendingQueueService.instance.push(
      barcode: item.barcode,
      productName: item.productName ?? item.barcode,
      // Kullanici bir grup sectiyse ayni gruba, secmediyse TESHIR grubuna.
      groupKey: labelGroup ?? 'Teşhir',
      source: 'teshir',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Teşhir etiketi listeye eklendi: ${item.productName ?? item.barcode}'),
      duration: const Duration(milliseconds: 1600),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.coral,
    ));
  }

  Future<void> _cancelMatch() async {
    setState(() => _matched = null);
    await _scanner.start();
  }

  /// Etiket Basim'daki 5 listeyi (Kalin Reyon, Ince Reyon, A4, A4 Ikili,
  /// A4 Uclu) gosteren secim sheet'i. Secilen grup _sendToLabelGroup'a
  /// yazilir; tekrar dokunup "Gonderme" secilirse iptal edilir.
  /// ETIKET HEDEFI SATIRI (detayli) — rehber ekranindakiyle ayni dil.
  Widget _labelTargetRow() {
    final hasGroup = _sendToLabelGroup != null;
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
                color: active ? AppTheme.accent : AppTheme.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active
                        ? 'Etiket Basım → ${groupTitle ?? 'Teşhir'}'
                        : 'Etiket Basım listesine de gönder',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            active ? FontWeight.w800 : FontWeight.w600,
                        color: active
                            ? AppTheme.accent
                            : AppTheme.textSecondary),
                  ),
                  Text(
                    _alsoTeshirLabel
                        ? 'Teşhir etiketi de eklenecek'
                        : '5 listeden birini seç · teşhirdeyse uyarır',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: _alsoTeshirLabel
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: _alsoTeshirLabel
                            ? AppTheme.coral
                            : AppTheme.textTertiary),
                  ),
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

  /// ZENGIN ETIKET HEDEFI SECICI (v158) — liste aciklamalari, bekleyen
  /// sayilari ve TESHIR entegrasyonu ortak bilesende.
  Future<void> _pickLabelGroup() async {
    final item = _matched;
    final res = await showLabelTargetSheet(
      context,
      barcode: item?.barcode ?? '',
      productName: item?.productName ?? item?.barcode ?? 'Ürün',
      currentGroupKey: _sendToLabelGroup,
      currentAlsoTeshir: _alsoTeshirLabel,
      oldPrice: item?.oldPrice,
      newPrice: item?.newPrice,
    );
    if (res == null || !mounted) return;
    setState(() {
      _sendToLabelGroup = res.groupKey;
      _alsoTeshirLabel = res.alsoTeshir;
    });
  }

  Future<void> _offerComplete() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.celebration_rounded,
                color: AppTheme.statusSafe, size: 26),
            SizedBox(width: 10),
            Text('Hepsi Tamam!'),
          ],
        ),
        content: const Text(
            'Listedeki tüm etiketler değiştirildi. Oturumu bitirelim mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Henüz değil')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Oturumu Bitir')),
        ],
      ),
    );
    if (ok == true) {
      await _finishSession();
    } else {
      await _scanner.start();
    }
  }

  Future<void> _finishSession({bool force = false}) async {
    final pending = _items.where((i) => !i.changed).length;
    if (pending > 0 && !force) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Eksik Var'),
          content: Text(
              '$pending etiket henüz değiştirilmedi. Yine de bitirilsin mi? '
              '(Eksikler raporda görünür)'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Devam Et')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.statusWarning),
              child: const Text('Yine de Bitir'),
            ),
          ],
        ),
      );
      if (ok != true) {
        await _scanner.start();
        return;
      }
    }
    await _scanner.stop();
    await PriceChangeService.instance.completeSession(widget.sessionId);
    await _load();
  }

  // ─────────────────────────── Rapor paylas ──────────────────────────
  Future<void> _shareReport() async {
    final pending = _items.where((i) => !i.changed).toList();
    final done = _items.where((i) => i.changed).toList();
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    final buf = StringBuffer();
    buf.writeln('FİYAT DEĞİŞİM RAPORU');
    if (_session != null) {
      buf.writeln('Oturum: ${fmt.format(_session!.createdAt)}'
          '${_session!.completedAt != null ? " → ${fmt.format(_session!.completedAt!)}" : ""}');
      buf.writeln('A4 sayfa: ${_session!.a4Count}');
    }
    buf.writeln('Toplam: ${_items.length} | '
        'Değiştirildi: ${done.length} | Kalan: ${pending.length}');
    buf.writeln('');
    if (pending.isNotEmpty) {
      buf.writeln('═══ DEĞİŞTİRİLMEYEN ETİKETLER ═══');
      for (final i in pending) {
        final price =
            i.newPrice != null ? '${i.newPrice!.toStringAsFixed(2)} ₺' : '-';
        buf.writeln('• ${i.barcode}  ${i.productName ?? ""}  → $price'
            '${i.aisle != null ? "  [${i.aisle}]" : ""}');
      }
    } else {
      buf.writeln('✓ Tüm etiketler değiştirildi.');
    }
    await Share.share(buf.toString(), subject: 'Fiyat Değişim Raporu');
  }

  // ─────────────────────────── Kanit galerisi ────────────────────────
  // Yanlis OCR edilen urunu duzenle (uzun basinca acilir).
  Future<void> _openEditItem(PriceChangeItem item) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditItemSheet(item: item),
    );
    if (changed == true && mounted) _load();
  }

  // Gorme dostu rehber moduna gec (tek tek, buyuk gosterim).
  // Rehber ekraninin kendi kamerasi var; bu ekranin kamerasi durdurulmazsa
  // iki ekran ayni anda kamera donanimina erismeye calisip cakisabilir.
  Future<void> _openGuide() async {
    await _scanner.stop();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PriceReviewGuideScreen(sessionId: widget.sessionId),
      ),
    );
    // Donunce listeyi tazele (rehberde isaretlemeler yapilmis olabilir).
    if (!mounted) return;
    await _load();
    if (mounted && _matched == null && !_completed) {
      await _startCameraSafe();
    }
  }

  void _openEvidence() {
    final proofs = _items
        .where((i) => i.photoPath != null)
        .map((i) => (i.photoPath!, i.productName ?? i.barcode))
        .toList();
    final a4s = _session?.a4Photos ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text('Kanıtlar',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              if (a4s.isNotEmpty) ...[
                const SectionLabel('A4 Listeler'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: a4s.length,
                    itemBuilder: (_, i) => _thumb(
                        a4s[i], 'A4 Sayfa ${i + 1}',
                        width: 86, height: 110),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              SectionLabel('Etiket Kanıtları (${proofs.length})'),
              const SizedBox(height: 8),
              if (proofs.isEmpty)
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('Henüz kanıt fotoğrafı yok',
                        style:
                            TextStyle(color: AppTheme.textSecondary)),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: proofs.length,
                  itemBuilder: (_, i) =>
                      _thumb(proofs[i].$1, proofs[i].$2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(String path, String title,
      {double? width, double? height}) {
    final exists = File(path).existsSync();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: exists
            ? () =>
                openImageZoom(context, filePath: path, title: title)
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          child: exists
              ? Image.file(File(path),
                  width: width, height: height, fit: BoxFit.cover)
              : Container(
                  width: width ?? 86,
                  height: height ?? 86,
                  color: AppTheme.surfaceAlt,
                  child: Icon(Icons.broken_image_rounded,
                      color: AppTheme.textTertiary),
                ),
        ),
      ),
    );
  }

  /// REYONDA GOSTER: bu barkodun reyon dizilimindeki yerini bulup
  /// canlandirmayi oynatir. Fiyat degisim sirasinda "urun rafta nerede"
  /// gormek icin — etiketi degistirirken dogru rafa gitmeyi kolaylastirir.
  Future<void> _showInShelf(PriceChangeItem item) async {
    final hit =
        await ShelfLayoutService.instance.locateBarcode(item.barcode);
    if (!mounted) return;
    if (hit == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${item.productName ?? item.barcode} reyon diziliminde kayıtlı değil.')));
      return;
    }
    if (!LocationRevealPrefs.instance.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Konum canlandırması Ayarlar > Görünüm’den kapalı.')));
    }
    showLocationFlythrough(
      context,
      title: hit.unitName,
      cols: hit.cols,
      rows: hit.rows,
      targetCol: hit.section,
      targetRow: hit.row,
      subtitle: 'Sütun ${hit.section} · Raf ${hit.row}',
      productName: hit.productName ?? item.productName,
      photoPath: hit.photoPath,
      allAisles: hit.allUnitNames,
      targetAisleIndex: hit.unitIndex,
      shelfProducts: hit.shelf
          .map((e) => RevealShelfProduct(
                name: e.name,
                photoPath: e.photoPath,
                sectionNo: e.sectionNo,
                isTarget: e.isTarget,
              ))
          .toList(),
    );
  }

  // ─────────────────────────── UI ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM', 'tr');
    final base = _completed ? AppTheme.statusSafe : AppTheme.primary;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemBarForColor(base),
      child: Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _sessionHero(fmt),
          Expanded(
            child: _session == null
                ? const LoadingState()
                : (_completed
                    ? _buildCompletedView()
                    : _buildActiveView()),
          ),
        ],
      ),
    ),
    );
  }

  Widget _sessionHero(DateFormat fmt) {
    final topPad = MediaQuery.of(context).padding.top;
    final base = _completed ? AppTheme.statusSafe : AppTheme.primary;
    final onColor = _completed ? Colors.black : Colors.white;
    final done = _items.where((i) => i.changed).length;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, topPad + 8, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, AppTheme.coral, 0.4)!],
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
                icon: Icon(Icons.arrow_back_rounded, color: onColor),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _session != null
                            ? 'Oturum — ${fmt.format(_session!.createdAt)}'
                            : 'Oturum',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: onColor)),
                    Text(_completed ? 'Tamamlandı' : 'Devam ediyor',
                        style: TextStyle(
                            fontSize: 12,
                            color: onColor.withOpacity(0.8))),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.visibility_rounded, color: onColor),
                tooltip: 'Rehberle Gör (büyük görünüm)',
                onPressed: _items.isEmpty ? null : _openGuide,
              ),
              IconButton(
                icon: Icon(Icons.photo_library_rounded, color: onColor),
                tooltip: 'Kanıtlar',
                onPressed: _openEvidence,
              ),
              IconButton(
                icon: Icon(Icons.share_rounded, color: onColor),
                tooltip: 'Raporu Paylaş',
                onPressed: _items.isEmpty ? null : _shareReport,
              ),
              if (!_completed)
                IconButton(
                  icon: Icon(Icons.flag_rounded, color: onColor),
                  tooltip: 'Oturumu Bitir',
                  onPressed: _items.isEmpty ? null : () => _finishSession(),
                ),
            ],
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: onColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                ),
                child: Row(
                  children: [
                    _shStat('${_items.length}', 'ürün', onColor),
                    _shDiv(onColor),
                    _shStat('$done', 'değişti', onColor),
                    _shDiv(onColor),
                    _shStat('${_items.length - done}', 'kalan', onColor),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shStat(String v, String l, Color c) => Expanded(
        child: Column(children: [
          Text(v,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: c)),
          Text(l,
              style: TextStyle(fontSize: 10.5, color: c.withOpacity(0.8))),
        ]),
      );

  Widget _shDiv(Color c) =>
      Container(width: 1, height: 24, color: c.withOpacity(0.25));

  /// REYON ROTASI: kalan urunleri reyon dizilimindeki konumlarina gore
  /// sirala (reyon adi -> sutun -> raf). Konumu bilinmeyenler sona gider.
  /// Magazada tek yuruyusle listeyi bitirmek icin.
  Future<void> _sortByRoute() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final keys = <int, String>{}; // item.id -> siralama anahtari
      for (final it in _items) {
        String key = 'zz~9999~9999'; // konumsuz: sona
        final bc = it.barcode;
        if (bc != null && bc.isNotEmpty) {
          try {
            final hit =
                await ShelfLayoutService.instance.locateBarcode(bc);
            if (hit != null) {
              key = '${hit.unitName}~'
                  '${hit.section.toString().padLeft(4, '0')}~'
                  '${hit.row.toString().padLeft(4, '0')}';
            }
          } catch (_) {}
        }
        keys[it.id ?? -1] = key;
      }
      _items.sort((a, b) {
        // Degisenler her zaman sonda; kalanlar rota sirasinda.
        if (a.changed != b.changed) return a.changed ? 1 : -1;
        return (keys[a.id ?? -1] ?? 'zz')
            .compareTo(keys[b.id ?? -1] ?? 'zz');
      });
      _routeSorted = true;
      HapticFeedback.mediumImpact();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildActiveView() {
    final pending = _items.where((i) => !i.changed).length;
    final total = _items.length;

    if (total == 0) {
      return EmptyState(
        icon: Icons.receipt_long_rounded,
        iconColor: AppTheme.amber,
        title: 'Liste Ekleyin',
        subtitle:
            'İmzalı A4 sayfasını tarayın (fotoğraf + AI okuma) ya da '
            'başka uygulamadan aldığınız Excel dosyasını içe aktarın. '
            'Birden fazla kaynak ekleyebilirsiniz.',
        action: Column(
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _captureA4,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.document_scanner_rounded),
              label: Text(_busy ? 'Okunuyor...' : 'A4 Tara'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importExcel,
              icon: const Icon(Icons.table_chart_rounded),
              label: const Text('Excel İçe Aktar'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── EL TERMINALI GIRIS CUBUGU: odakli, klavyesiz ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.hairline),
            ),
            child: Row(
              children: [
                Icon(Icons.settings_remote_rounded,
                    size: 16, color: AppTheme.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _hidCtrl,
                    focusNode: _hidFocus,
                    keyboardType: TextInputType.none, // klavye ACILMAZ
                    textInputAction: TextInputAction.done,
                    onSubmitted: _onHidSubmit,
                    style: const TextStyle(
                        fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                      hintText: 'El terminali: barkodu buraya okutun',
                      hintStyle: TextStyle(
                          fontSize: 12, color: AppTheme.textTertiary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 230,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _scanner, onDetect: _onDetect),
              const ScanOverlay(hint: 'Barkodu çerçeveye getirin'),
              if (_scanMessage != null)
                Positioned(
                  bottom: 12,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.statusWarning.withOpacity(0.94),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(_scanMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ),
              if (_busy)
                Container(
                  color: Colors.black54,
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: Colors.white)),
                ),
            ],
          ),
        ),
        if (_matched != null) _buildMatchedPanel(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kalan: $pending / $total',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total == 0
                            ? 0
                            : (total - pending) / total,
                        minHeight: 5,
                        backgroundColor: AppTheme.surfaceAlt,
                        color: AppTheme.statusSafe,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_busy,
                onSelected: (v) {
                  if (v == 'a4') _captureA4();
                  if (v == 'excel') _importExcel();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'a4',
                    child: Row(
                      children: [
                        Icon(Icons.document_scanner_rounded,
                            size: 18, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text('A4 Tara'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'excel',
                    child: Row(
                      children: [
                        Icon(Icons.table_chart_rounded,
                            size: 18, color: AppTheme.accent),
                        SizedBox(width: 8),
                        Text('Excel İçe Aktar'),
                      ],
                    ),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.add_rounded,
                          size: 18, color: AppTheme.primary),
                      SizedBox(width: 4),
                      Text('Ekle',
                          style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildItemList()),
      ],
    );
  }

  Widget _buildMatchedPanel() {
    final item = _matched!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(accentColor: AppTheme.statusSafe),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.productName ?? item.barcode,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              if (item.oldPrice != null) ...[
                Text('${item.oldPrice!.toStringAsFixed(2)} ₺',
                    style: TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: AppTheme.textTertiary)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 16, color: AppTheme.textSecondary),
                ),
              ],
              Text(
                item.newPrice != null
                    ? '${item.newPrice!.toStringAsFixed(2)} ₺'
                    : 'Fiyat yok',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.statusSafe),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ETIKET HEDEFI (detayli): secilen liste, teshir durumu ve
          // yonlendirme tek satirda net gorunur.
          _labelTargetRow(),
          const SizedBox(height: 8),
          // REYONDA GOSTER: bu urun rafta nerede? canlandirma oynatir.
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _showInShelf(_matched!),
            icon: const Icon(Icons.travel_explore_rounded, size: 18),
            label: const Text('Reyonda göster'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary.withOpacity(0.5)),
              minimumSize: const Size.fromHeight(42),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _cancelMatch,
                  child: const Text('İptal'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _confirmChange,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Foto Çek & Onayla',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.statusSafe),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemList() {
    if (_items.isEmpty) {
      return const Center(child: Text('Liste boş'));
    }
    final visible = _visibleItems;
    final done = _items.where((i) => i.changed).length;
    final total = _items.length;
    final progress = total == 0 ? 0.0 : done / total;

    return Column(
      children: [
        // ── BUYUK ILERLEME: X/Y + animasyonlu bar + ROTA ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              // REYON ROTASI: tek yuruyusle bitirmek icin sirala.
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Reyon rotasına göre sırala',
                onPressed: _busy ? null : _sortByRoute,
                icon: Icon(Icons.route_rounded,
                    size: 20,
                    color: _routeSorted
                        ? AppTheme.statusSafe
                        : AppTheme.textTertiary),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 10,
                      backgroundColor: AppTheme.surfaceHigh,
                      valueColor: AlwaysStoppedAnimation(
                          progress >= 1.0
                              ? AppTheme.statusSafe
                              : AppTheme.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$done / $total',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15)),
            ],
          ),
        ),
        // ── FILTRE CIPLERI + ARAMA ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              _filterChip('Kalan', _ItemFilter.pending,
                  _items.where((i) => !i.changed).length),
              const SizedBox(width: 6),
              _filterChip('Bitti', _ItemFilter.done, done),
              const SizedBox(width: 6),
              _filterChip('Tümü', _ItemFilter.all, total),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _listSearchCtrl,
                    onChanged: (v) => setState(() => _listQuery = v),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Ara...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: 18),
                      prefixIconConstraints: const BoxConstraints(
                          minWidth: 34, minHeight: 34),
                      suffixIcon: _listQuery.isEmpty
                          ? null
                          : InkWell(
                              onTap: () => setState(() {
                                _listSearchCtrl.clear();
                                _listQuery = '';
                              }),
                              child: const Icon(Icons.close_rounded,
                                  size: 16),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                      _filter == _ItemFilter.pending
                          ? 'Kalan ürün yok 🎉'
                          : 'Sonuç yok',
                      style: TextStyle(color: AppTheme.textSecondary)),
                )
              : _itemsListView(visible),
        ),
      ],
    );
  }

  Widget _filterChip(String label, _ItemFilter f, int count) {
    final sel = _filter == f;
    return InkWell(
      onTap: () => setState(() => _filter = f),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? AppTheme.primary : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel ? AppTheme.primary : AppTheme.hairline),
        ),
        child: Text('$label $count',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : AppTheme.textSecondary)),
      ),
    );
  }

  Widget _itemsListView(List<PriceChangeItem> visible) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      itemCount: visible.length,
      itemBuilder: (_, i) {
        final item = visible[i];
        return InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          onLongPress: () => _openEditItem(item),
          onTap: () {
            // Degistirilmis -> kanit fotografi; degilse -> internette ara.
            if (item.changed && item.photoPath != null) {
              openImageZoom(context,
                  filePath: item.photoPath!,
                  title: item.productName ?? item.barcode);
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WebSearchScreen(query: item.barcode),
              ));
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: AppTheme.card(
                accentColor: item.changed ? AppTheme.statusSafe : null),
            child: Row(
              children: [
                Icon(
                  item.changed
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: item.changed
                      ? AppTheme.statusSafe
                      : AppTheme.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName ?? item.barcode,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: item.changed
                                  ? AppTheme.textSecondary
                                  : AppTheme.textPrimary)),
                      Text(
                          '${item.barcode}'
                          '${item.aisle != null ? "  •  ${item.aisle}" : ""}',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: AppTheme.textTertiary)),
                    ],
                  ),
                ),
                // Kanit fotografi gostergesi
                if (item.changed && item.photoPath != null)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.photo_camera_rounded,
                        size: 16, color: AppTheme.accent),
                  ),
                if (item.newPrice != null)
                  Text('${item.newPrice!.toStringAsFixed(2)} ₺',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: item.changed
                              ? AppTheme.textTertiary
                              : AppTheme.statusSafe)),
                // Reyonda göster (animasyon) — ürünün rafta yerini canlandırır.
                InkWell(
                  onTap: () => _showInShelf(item),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.travel_explore_rounded,
                        size: 19, color: AppTheme.primary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompletedView() {
    final pending = _items.where((i) => !i.changed).toList();
    final done = _items.where((i) => i.changed).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                    label: 'Toplam',
                    count: _items.length,
                    color: AppTheme.primary,
                    icon: Icons.list_alt_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                    label: 'Değişti',
                    count: done,
                    color: AppTheme.statusSafe,
                    icon: Icons.check_circle_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                    label: 'Eksik',
                    count: pending.length,
                    color: pending.isEmpty
                        ? AppTheme.statusSafe
                        : AppTheme.statusExpired,
                    icon: pending.isEmpty
                        ? Icons.task_alt_rounded
                        : Icons.error_rounded),
              ),
            ],
          ),
        ),
        if (pending.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Değiştirilmeyenler:',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(child: _buildItemList()),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  DÜZENLEME SHEET — yanlis OCR edilen urunu duzelt (animasyonlu).
// ════════════════════════════════════════════════════════════════════
class _EditItemSheet extends StatefulWidget {
  final PriceChangeItem item;
  const _EditItemSheet({required this.item});

  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<_EditItemSheet>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _name;
  late final TextEditingController _barcode;
  late final TextEditingController _oldPrice;
  late final TextEditingController _newPrice;
  late final TextEditingController _aisle;
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _name = TextEditingController(text: it.productName ?? '');
    _barcode = TextEditingController(text: it.barcode);
    _oldPrice =
        TextEditingController(text: it.oldPrice?.toStringAsFixed(2) ?? '');
    _newPrice =
        TextEditingController(text: it.newPrice?.toStringAsFixed(2) ?? '');
    _aisle = TextEditingController(text: it.aisle ?? '');
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _oldPrice.dispose();
    _newPrice.dispose();
    _aisle.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.item.id == null) return;
    setState(() => _busy = true);
    await PriceChangeService.instance.updateItem(
      widget.item.id!,
      productName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      barcode: _barcode.text.trim(),
      oldPrice: double.tryParse(_oldPrice.text.replaceAll(',', '.')),
      newPrice: double.tryParse(_newPrice.text.replaceAll(',', '.')),
      aisle: _aisle.text.trim().isEmpty ? null : _aisle.text.trim(),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    if (widget.item.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Ürünü sil'),
        content: const Text('Bu ürün listeden silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.statusExpired),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true) return;
    await PriceChangeService.instance.deleteItem(widget.item.id!);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          margin: EdgeInsets.only(bottom: bottomInset),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppTheme.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.edit_rounded,
                          color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Ürünü Düzenle',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _field('Ürün adı', _name, Icons.label_outline_rounded),
                const SizedBox(height: 12),
                _field('Barkod', _barcode, Icons.qr_code_rounded,
                    keyboard: TextInputType.number),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field('Eski fiyat', _oldPrice,
                          Icons.sell_outlined,
                          keyboard: const TextInputType.numberWithOptions(
                              decimal: true)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field('Yeni fiyat', _newPrice,
                          Icons.local_offer_rounded,
                          keyboard: const TextInputType.numberWithOptions(
                              decimal: true)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _field('Reyon', _aisle, Icons.shelves),
                const SizedBox(height: 22),
                Row(
                  children: [
                    IconButton(
                      onPressed: _busy ? null : _delete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: AppTheme.statusExpired,
                      style: IconButton.styleFrom(
                        backgroundColor:
                            AppTheme.statusExpired.withOpacity(0.12),
                        padding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_rounded, size: 20),
                        label: const Text('Kaydet',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, IconData icon,
      {TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: AppTheme.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Fiyat degisim listesi filtresi: kalanlar (varsayilan), bitenler, tumu.
enum _ItemFilter { pending, done, all }
