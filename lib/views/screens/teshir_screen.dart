import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/database_service.dart';
import '../../core/services/teshir_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../../data/datasources/barcode_directory_datasource.dart';
import '../../data/models/barcode_entry.dart';
import '../../data/repositories/barcode_directory_repository.dart';
import '../widgets/ui_kit.dart';
import 'barcode_detail_screen.dart';

/// ════════════════════════════════════════════════════════════════════
///  TESHIR EKRANI (v144)
///  Barkod okut → urun teshir listesine eklenir. Buradaki urunler
///  "teshirde duruyor" demektir; fiyat degisiminde bu urunler yakalanip
///  teshir etiketi icin soru sorulur.
/// ════════════════════════════════════════════════════════════════════
class TeshirScreen extends StatefulWidget {
  final bool isTabRoot;
  const TeshirScreen({super.key, this.isTabRoot = false});
  @override
  State<TeshirScreen> createState() => _TeshirScreenState();
}

class _TeshirScreenState extends State<TeshirScreen> {
  List<Map<String, Object?>> _items = [];
  final Map<String, String?> _photoCache = {};
  bool _cameraOn = false;

  /// AKTIF GRUP: sablon secilince baslar, kapasite dolunca kapanir.
  String? _groupId;
  int _groupSize = 1;
  int _groupFilled = 0;

  final TextEditingController _hidCtrl = TextEditingController();
  final FocusNode _hidFocus = FocusNode();
  MobileScannerController? _scanner;
  DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);

  late final BarcodeDirectoryRepository _dirRepo = BarcodeDirectoryRepository(
      BarcodeDirectoryDataSource(DatabaseService.instance));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hidCtrl.dispose();
    _hidFocus.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await TeshirService.instance.list();
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<String?> _photo(String barcode) async {
    if (_photoCache.containsKey(barcode)) return _photoCache[barcode];
    String? p;
    try {
      final path = await _dirRepo.getLocalImage(barcode);
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        p = path;
      }
    } catch (_) {}
    _photoCache[barcode] = p;
    return p;
  }

  // ── OKUTMA ──────────────────────────────────────────────────────────
  Future<void> _onHidSubmit(String v) async {
    final t = v.trim();
    _hidCtrl.clear();
    if (t.isNotEmpty) await _addScan(t);
    if (mounted) _hidFocus.requestFocus();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastScan).inMilliseconds < 1200) return;
    _lastScan = now;
    await _addScan(raw);
  }

  Future<void> _addScan(String raw) async {
    final code = ScanParser.parse(raw).barcode ?? raw.trim();
    if (code.isEmpty) return;
    String? name;
    try {
      name = await _dirRepo.findProductName(code);
    } catch (_) {}
    final inGroup = _groupId != null && _groupFilled < _groupSize;
    await TeshirService.instance.add(
      code,
      productName: name,
      groupId: inGroup ? _groupId : null,
      groupSize: inGroup ? _groupSize : null,
    );
    HapticFeedback.mediumImpact();
    if (inGroup) {
      setState(() => _groupFilled++);
      if (_groupFilled >= _groupSize) {
        // Sablon doldu: grup kapanir, istenirse yenisi baslatilir.
        final size = _groupSize;
        setState(() {
          _groupId = null;
          _groupFilled = 0;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$size\'li grup tamamlandı'),
            backgroundColor: AppTheme.statusSafe,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Teşhire eklendi: ${name ?? code}'),
      duration: const Duration(milliseconds: 900),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// ══════════════════════════════════════════════════════════════════
  ///  A4 GRUBU BASLAT (v162)
  ///  Ayni kagida basilacak urunleri birlikte kaydeder. Fiyat degisiminde
  ///  gruptan BIRI degisse bile KAGIDIN TAMAMI etiket listesine gider.
  /// ══════════════════════════════════════════════════════════════════
  Future<void> _startGroup() async {
    final size = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
              child: Row(
                children: [
                  const Icon(Icons.dashboard_customize_rounded,
                      color: AppTheme.coral),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('A4 Grubu Oluştur',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900)),
                        Text(
                            'Aynı kağıda basılacak ürünleri arka arkaya '
                            'okut; grup kalıcı olur',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textTertiary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (final o in const [
              (1, 'Tekli', 'A4 · kağıtta 1 ürün'),
              (2, 'İkili', 'A4 İkili · kağıtta 2 ürün'),
              (3, 'Üçlü', 'A4 Üçlü · kağıtta 3 ürün'),
            ])
              ListTile(
                leading: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.coral.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${o.$1}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.coral)),
                ),
                title: Text(o.$2,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(o.$3,
                    style: const TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, o.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (size == null || !mounted) return;
    setState(() {
      _groupId = TeshirService.instance.newGroupId();
      _groupSize = size;
      _groupFilled = 0;
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$size ürün okut — aynı A4 kağıdına yazılacaklar'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Aktif grup durumu cubugu.
  Widget _groupBar() {
    final label = switch (_groupSize) {
      2 => 'A4 İkili',
      3 => 'A4 Üçlü',
      _ => 'A4',
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.coral.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.coral.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.dashboard_customize_rounded,
              size: 18, color: AppTheme.coral),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                '$label grubu oluşturuluyor · $_groupFilled/$_groupSize okutuldu',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.coral)),
          ),
          TextButton(
            onPressed: () => setState(() {
              _groupId = null;
              _groupFilled = 0;
            }),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppTheme.coral),
            child: const Text('İptal', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Future<void> _openHub(String barcode, String name) async {
    BarcodeEntry? entry;
    try {
      entry = await _dirRepo.findEntryByBarcode(barcode);
    } catch (_) {}
    entry ??= BarcodeEntry(
        barcode: barcode, productName: name, importedAt: DateTime.now());
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BarcodeDetailScreen(entry: entry!)));
  }

  /// Teshir yeri notu (ör. "Kasa önü ada", "Giriş standı").
  Future<void> _editNote(Map<String, Object?> it) async {
    final ctrl =
        TextEditingController(text: (it['note'] as String?) ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teşhir yeri'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'ör. Kasa önü ada, Giriş standı'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (v != null) {
      await TeshirService.instance
          .setNote(it['id'] as int, v.isEmpty ? null : v);
      _load();
    }
  }

  /// Adi cozulememis (ad == barkod ya da bos) kayit sayisi.
  int get _missingNameCount => _items.where((it) {
        final n = (it['product_name'] as String?)?.trim() ?? '';
        return n.isEmpty || n == (it['barcode'] as String);
      }).length;

  /// ADLARI TAZELE: barkod dizininde artik karsiligi olan kayitlarin
  /// adini gunceller. (Koli↔perakende capraz eslesme sayesinde onceden
  /// bulunamayan adlar simdi bulunabiliyor.)
  Future<void> _refreshNames() async {
    var fixed = 0;
    for (final it in List<Map<String, Object?>>.from(_items)) {
      final barcode = it['barcode'] as String;
      final cur = (it['product_name'] as String?)?.trim() ?? '';
      if (cur.isNotEmpty && cur != barcode) continue;
      try {
        final name = await _dirRepo.findProductName(barcode);
        if (name != null && name.trim().isNotEmpty && name != barcode) {
          await TeshirService.instance.add(barcode, productName: name);
          fixed++;
        }
      } catch (_) {}
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fixed == 0
          ? 'Dizinde karşılığı bulunan yeni ad yok'
          : '$fixed ürünün adı güncellendi'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: fixed == 0 ? null : AppTheme.statusSafe,
    ));
  }

  // ── UI ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _hero(),
          if (_cameraOn)
            SizedBox(
              height: 170,
              child: MobileScanner(
                  controller: _scanner ??= MobileScannerController(),
                  onDetect: _onDetect),
            ),
          _hidBar(),
          if (_groupId != null) _groupBar(),
          Expanded(
            child: _items.isEmpty
                ? const EmptyState(
                    icon: Icons.storefront_rounded,
                    title: 'Teşhir listesi boş',
                    subtitle:
                        'Teşhirde (ada, stand, palet teşhiri) duran '
                        'ürünlerin barkodlarını okutun. Bu ekran yalnızca '
                        'GRUPLAMA yapar; etiket gönderimi Fiyat Değişim '
                        'akışında, ürün eşleştiğinde sorulur.',
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 8, 16,
                        MediaQuery.of(context).padding.bottom + 16),
                    itemCount: _items.length,
                    itemBuilder: (_, i) => _card(_items[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, topPad + 6, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.coral,
            Color.lerp(AppTheme.coral, AppTheme.amber, 0.6)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppTheme.rLg)),
      ),
      child: Row(
        children: [
          if (!widget.isTabRoot)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon:
                  const Icon(Icons.arrow_back_rounded, color: Colors.white),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Teşhir',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
                Text('${_items.length} ürün teşhirde',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
          // A4 TESHIR ETIKETLERI: tekli/ikili/uclu sablon.
          // Adi cozulmemis kayitlari dizinden tazele.
          if (_missingNameCount > 0)
            IconButton(
              tooltip: '$_missingNameCount ürünün adı eksik — tazele',
              onPressed: _refreshNames,
              icon: const Icon(Icons.sync_rounded, color: Colors.white),
            ),
          IconButton(
            tooltip: 'A4 grubu oluştur',
            onPressed: _groupId == null ? _startGroup : null,
            icon: Icon(Icons.dashboard_customize_rounded,
                color: _groupId == null ? Colors.white : Colors.white38),
          ),
          IconButton(
            tooltip: _cameraOn ? 'Kamerayı kapat' : 'Kamerayla okut',
            onPressed: () {
              setState(() => _cameraOn = !_cameraOn);
              if (!_cameraOn) {
                _scanner?.dispose();
                _scanner = null;
              }
            },
            icon: Icon(
                _cameraOn
                    ? Icons.no_photography_rounded
                    : Icons.photo_camera_rounded,
                color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _hidBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
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
                autofocus: true, // imlec burada
                keyboardType: TextInputType.none, // klavye ACILMAZ
                textInputAction: TextInputAction.done,
                onSubmitted: _onHidSubmit,
                style:
                    const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: 'Teşhirdeki ürünü okutun',
                  hintStyle: TextStyle(
                      fontSize: 12, color: AppTheme.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Map<String, Object?> it) {
    final barcode = it['barcode'] as String;
    final name = (it['product_name'] as String?) ?? barcode;
    final note = it['note'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: AppTheme.card(accentColor: AppTheme.coral),
      child: Row(
        children: [
          // Foto (varsa) — dokununca urun sayfasi.
          GestureDetector(
            onTap: () => _openHub(barcode, name),
            child: FutureBuilder<String?>(
              future: _photo(barcode),
              builder: (_, snap) {
                final p = snap.data;
                return Container(
                  width: 46,
                  height: 46,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppTheme.coral.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: p != null
                      ? Image.file(File(p), fit: BoxFit.cover)
                      : const Icon(Icons.storefront_rounded,
                          size: 22, color: AppTheme.coral),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _openHub(barcode, name),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  Text(barcode,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: AppTheme.textTertiary)),
                  if (note != null && note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.place_rounded,
                              size: 12, color: AppTheme.coral),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.coral)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Teşhir yeri notu',
            onPressed: () => _editNote(it),
            icon: Icon(Icons.edit_location_alt_outlined,
                size: 18, color: AppTheme.textTertiary),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Teşhirden çıkar',
            onPressed: () async {
              await TeshirService.instance.remove(it['id'] as int);
              _load();
            },
            icon: Icon(Icons.close_rounded,
                size: 18, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }
}
