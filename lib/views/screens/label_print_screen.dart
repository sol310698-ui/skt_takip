import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/label_active_lists_service.dart';
import '../../core/services/label_deleted_service.dart';
import '../../core/services/price_check_channel.dart';
import '../../core/utils/scan_parser.dart';
import '../../core/services/label_history_service.dart';
import '../../core/services/label_pending_queue_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/label_history_entry.dart';
import '../../data/models/label_item.dart';
import '../../viewmodels/providers.dart';

/// Etiket gruplari (ust sekmeler). Her grup AYRI bir urun listesi tutar.
/// Amac: kutudaki barkodlari gruplayip seri sekilde lazerle okutmak.
enum LabelGroup { kalinRon, inceRon, a4, a4Double, a4Triple }

extension LabelGroupX on LabelGroup {
  String get title {
    switch (this) {
      case LabelGroup.kalinRon:
        return 'Kalın Reyon';
      case LabelGroup.inceRon:
        return 'İnce Reyon';
      case LabelGroup.a4:
        return 'A4';
      case LabelGroup.a4Double:
        return 'A4 İkili';
      case LabelGroup.a4Triple:
        return 'A4 Üçlü';
    }
  }
}

/// Etiket Basım Sayfasi.
///
///  - Ust tarafta 5 sekme (5 ayri liste): Kalın Reyon, İnce Reyon, A4, A4 İkili,
///    A4 Üçlü. Her sekme kendi urun listesini tutar.
///  - Alt butonlar: Listeden / Kısa Kod / Tara ile aktif sekmeye urun ekler.
///  - Sag ust "Akış" (▶): aktif sekmedeki barkodlari tek tek tam ekran buyuk
///    gosterir; lazer/harici okuyucu ile seri okutma icin.
class LabelPrintScreen extends ConsumerStatefulWidget {
  const LabelPrintScreen({super.key});

  @override
  ConsumerState<LabelPrintScreen> createState() => _LabelPrintScreenState();
}

class _LabelPrintScreenState extends ConsumerState<LabelPrintScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  /// Her grup icin ayri urun listesi.
  final Map<LabelGroup, List<LabelItem>> _lists = {
    for (final g in LabelGroup.values) g: <LabelItem>[],
  };

  LabelGroup get _active => LabelGroup.values[_tab.index];
  List<LabelItem> get _items => _lists[_active]!;

  bool _restoring = true; // ilk acilista kayitli listeler yuklenirken true

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: LabelGroup.values.length, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) setState(() {});
    });
    _restoreActiveLists();
  }

  /// Kayitli (kalici) listeleri veritabanindan yukler. Ekrandan cikip
  /// geri girince veya uygulama kapanip acilinca listeler KAYBOLMAZ.
  Future<void> _restoreActiveLists() async {
    final saved = await LabelActiveListsService.instance.loadAll();
    if (!mounted) return;
    setState(() {
      for (final entry in saved.entries) {
        LabelGroup? group;
        for (final g in LabelGroup.values) {
          if (g.name == entry.key) {
            group = g;
            break;
          }
        }
        if (group != null) _lists[group] = entry.value;
      }
      _restoring = false;
    });
    // Baska ekranlardan (orn. Fiyat Degisim) "Etikete Gonder" ile
    // gelmis bekleyen urunleri kuyruktan al, ilgili sekmelere ekle.
    await _drainPendingQueue();
  }

  /// Aktif grubun listesini kalici depoya yazar. Liste degisen HER
  /// islemden sonra cagrilmalidir (ekleme, adet degisimi, silme).
  Future<void> _persist(LabelGroup group) async {
    if (_restoring) return; // ilk yukleme sirasinda gereksiz yazma yapma
    await LabelActiveListsService.instance
        .saveGroup(group.name, _lists[group]!);
  }

  Future<void> _drainPendingQueue() async {
    final pending = await LabelPendingQueueService.instance.drainAll();
    if (pending.isEmpty || !mounted) return;
    final touchedGroups = <LabelGroup>{};
    setState(() {
      for (final p in pending) {
        final group = LabelGroup.values.firstWhere(
          (g) => g.name == p.groupKey,
          orElse: () => LabelGroup.a4,
        );
        touchedGroups.add(group);
        final list = _lists[group]!;
        final idx = list.indexWhere((e) => e.barcode == p.barcode);
        if (idx >= 0) {
          list[idx].quantity += p.quantity;
        } else {
          list.add(LabelItem(
            barcode: p.barcode,
            productName: p.productName,
            stockCode: p.stockCode,
            quantity: p.quantity,
          ));
        }
      }
    });
    for (final group in touchedGroups) {
      await LabelActiveListsService.instance
          .saveGroup(group.name, _lists[group]!);
    }
    for (final p in pending) {
      final group = LabelGroup.values.firstWhere(
        (g) => g.name == p.groupKey,
        orElse: () => LabelGroup.a4,
      );
      unawaited(LabelHistoryService.instance.log(
        barcode: p.barcode,
        productName: p.productName,
        stockCode: p.stockCode,
        groupKey: group.name,
        groupTitle: group.title,
        quantity: p.quantity,
      ));
    }
    final names = pending.map((p) => p.productName).take(3).join(', ');
    final extra = pending.length > 3 ? ' +${pending.length - 3} ürün' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Fiyat Değişim\'den eklendi: $names$extra'),
        backgroundColor: AppTheme.statusSafe,
      ),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Aktif sekmedeki TUM etiketleri sil ──────────────────────────────
  // ── SILINENLER sayfasi: parti halinde geri al ──────────────────────────
  Future<void> _openDeleted() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DeletedLabelsPage(
          onRestore: (batch) async {
            // Partiyi, silindigi gruba geri yukle. Ayni barkod varsa adetleri
            // birlestir.
            final group = LabelGroup.values.firstWhere(
              (g) => g.name == batch.groupKey,
              orElse: () => _active,
            );
            final list = _lists[group]!;
            for (final item in batch.items) {
              final idx = list.indexWhere((e) => e.barcode == item.barcode);
              if (idx >= 0) {
                list[idx].quantity += item.quantity;
              } else {
                list.add(item);
              }
            }
            await _persist(group);
            if (mounted) setState(() {});
          },
        ),
      ),
    );
    // Geri donunce ekran guncel kalsin.
    if (mounted) setState(() {});
  }

  // ── OTOMATIK KAYIT: aktif sekmedeki barkodlari sirket uygulamasina gir ──
  Future<void> _openAutoEntry() async {
    // Her etiketin ADEDI kadar barkodu tekrarla: adet 5 ise barkod 5 kez
    // girilir (sirket uygulamasina o kadar kayit dusmesi icin).
    final barcodes = <String>[];
    for (final item in _items) {
      final bc = item.barcode.trim();
      if (bc.isEmpty) continue;
      final qty = item.quantity < 1 ? 1 : item.quantity;
      for (var i = 0; i < qty; i++) {
        barcodes.add(bc);
      }
    }
    if (barcodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu sekmede barkod yok')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AutoEntrySheet(barcodes: barcodes),
    );
  }

  Future<void> _clearActiveList() async {
    final group = _active;
    final count = _lists[group]!.length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm etiketleri sil'),
        content: Text(
            '"${group.title}" sekmesindeki $count etiketin tümü silinecek. '
            'Emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tümünü Sil',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    // Silinecek tum etiketleri parti olarak "silinenler"e kaydet.
    final removedItems = List<LabelItem>.from(_lists[group]!);
    await LabelDeletedService.instance.recordBatch(group.name, removedItems);
    setState(() => _lists[group]!.clear());
    await _persist(group);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${group.title}: $count etiket silindi'),
          backgroundColor: AppTheme.statusSafe,
        ),
      );
    }
  }

  // ── Aktif sekmeye urun ekleme: barkod tara ─────────────────────────────
  // Surekli tarama ekranini acar; ekran kapanana kadar her okutulan barkod
  // anlik olarak _addByBarcode ile aktif sekmeye eklenir (ekran kapanmaz).
  Future<void> _addByScan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ContinuousScanScreen(
          onScan: _scanAndGetQty,
          onEditQuantity: _editQuantityByBarcode,
        ),
      ),
    );
  }

  /// Tarama ekranindan cagrilir: barkodu ekler/artirir ve aktif sekmedeki
  /// GUNCEL adedini doner (buyuk rakam gosterimi icin).
  Future<int> _scanAndGetQty(String barcode) async {
    await _addByBarcode(barcode);
    final idx = _items.indexWhere((e) => e.barcode == barcode);
    return idx >= 0 ? _items[idx].quantity : 1;
  }

  /// Tarama ekranindaki buyuk rakama dokununca cagrilir: adet giris
  /// dialogunu acar, onaylanirsa o barkodun adedini SET eder ve yeni
  /// adedi doner (dialog iptal edilirse null doner).
  Future<int?> _editQuantityByBarcode(String barcode, int currentQty) async {
    final idx = _items.indexWhere((e) => e.barcode == barcode);
    final name = idx >= 0 ? _items[idx].productName : barcode;
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _QuantityInputDialog(
        title: name,
        initialValue: currentQty,
      ),
    );
    if (result == null || !mounted) return null;
    final safe = result <= 0 ? 1 : result;
    await _addByBarcode(barcode, setQuantity: safe);
    return safe;
  }

  /// Barkodu dizinde arar; bulursa ad+kisa kod ile, bulamazsa sadece
  /// barkod ile aktif sekmeye ekler. Ayni barkod varsa adedi artirir
  /// (varsayilan +1), ancak [setQuantity] verilirse adet O SAYIYA esitlenir
  /// (klavyeden direkt adet yazma senaryosu icin).
  /// Her ekleme/artirma ayrica 30 gunluk gecmise (LabelHistoryService) loglanir.
  Future<void> _addByBarcode(String barcode, {int? setQuantity}) async {
    if (barcode.isEmpty) return;
    final entry = await ref
        .read(barcodeDirectoryRepositoryProvider)
        .findEntryByBarcode(barcode);
    if (!mounted) return;
    final productName = entry?.productName ?? 'Bilinmeyen ürün';
    final stockCode = entry?.stockCode;
    int loggedQuantity = 1;
    setState(() {
      final list = _items;
      final idx = list.indexWhere((e) => e.barcode == barcode);
      if (idx >= 0) {
        if (setQuantity != null) {
          loggedQuantity = setQuantity - list[idx].quantity;
          list[idx].quantity = setQuantity;
        } else {
          list[idx].quantity++;
        }
      } else {
        final qty = setQuantity ?? 1;
        loggedQuantity = qty;
        list.add(LabelItem(
          barcode: barcode,
          productName: productName,
          stockCode: stockCode,
          quantity: qty,
        ));
      }
    });
    _persist(_active);
    // Gecmis kaydi: aktif liste sifirlansa bile bu kayit 30 gun durur.
    // Net degisim 0 ise (adet aynen onaylandi) anlamsiz kayit atilmaz.
    if (loggedQuantity != 0) {
      unawaited(LabelHistoryService.instance.log(
        barcode: barcode,
        productName: productName,
        stockCode: stockCode,
        groupKey: _active.name,
        groupTitle: _active.title,
        quantity: loggedQuantity,
      ));
    }
  }

  // ── Aktif sekmeye urun ekleme: dizinden sec ────────────────────────────
  Future<void> _addFromDirectory() async {
    final all = await ref.read(barcodeDirectoryRepositoryProvider).getAll();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DirectoryPickerSheet(entries: all),
    );
    if (picked == null || !mounted) return;
    await _addByBarcode(picked);
  }

  // ── Aktif sekmeye urun ekleme: kisa kod (stok kodu) ────────────────────
  Future<void> _addByShortCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _ShortCodeDialog(),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    final entry = await ref
        .read(barcodeDirectoryRepositoryProvider)
        .findEntryByStockCode(code.trim());
    if (!mounted) return;
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kısa kod bulunamadı: $code')),
      );
      return;
    }
    await _addByBarcode(entry.barcode);
  }

  void _removeAt(int i) {
    final removed = _items[i];
    setState(() => _items.removeAt(i));
    _persist(_active);
    // Silinen etiketi "silinenler"e kaydet (parti halinde geri alinabilsin).
    unawaited(
        LabelDeletedService.instance.recordBatch(_active.name, [removed]));
  }

  void _changeQty(int i, int delta) {
    setState(() {
      final q = _items[i].quantity + delta;
      if (q <= 0) {
        _items.removeAt(i);
      } else {
        _items[i].quantity = q;
      }
    });
    _persist(_active);
  }

  /// Adet rakamina dokununca acilan buyuk klavyeli adet giris dialogu.
  /// Onaylanirsa adet O SAYIYA esitlenir (gecmise fark olarak loglanir).
  Future<void> _editQtyDialog(int i) async {
    final item = _items[i];
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _QuantityInputDialog(
        title: item.productName,
        initialValue: item.quantity,
      ),
    );
    if (result == null || !mounted) return;
    if (result <= 0) {
      setState(() => _items.removeAt(i));
      _persist(_active);
      return;
    }
    final delta = result - item.quantity;
    setState(() => item.quantity = result);
    _persist(_active);
    if (delta != 0) {
      unawaited(LabelHistoryService.instance.log(
        barcode: item.barcode,
        productName: item.productName,
        stockCode: item.stockCode,
        groupKey: _active.name,
        groupTitle: _active.title,
        quantity: delta,
      ));
    }
  }

  // ── Akis: aktif sekme barkodlarini tam ekran buyuk goster (lazer) ──────
  // Akis sonuna kadar gidip "Bitir"e basilirsa (true doner) o sekmenin
  // listesi otomatik temizlenir. Yarida geri cikilirsa liste korunur.
  Future<void> _startFlow() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu listeye önce ürün ekleyin.')),
      );
      return;
    }
    final finished = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _LabelFlowScreen(title: _active.title, items: List.of(_items)),
      ),
    );
    if (finished == true && mounted) {
      final clearedGroup = _active;
      setState(() => _items.clear());
      await LabelActiveListsService.instance.clearGroup(clearedGroup.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${_active.title}" listesi temizlendi.')),
      );
    }
  }

  // ── Gecmis: son 30 gunde eklenen tum barkodlari gun gun goster ─────────
  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _LabelHistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Etiket Basım'),
        actions: [
          IconButton(
            tooltip: 'Geçmiş',
            icon: const Icon(Icons.history_rounded),
            onPressed: _openHistory,
          ),
          IconButton(
            tooltip: 'Silinenler (geri al)',
            icon: const Icon(Icons.restore_from_trash_rounded),
            onPressed: _openDeleted,
          ),
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Bu sekmedeki tüm etiketleri sil',
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: _clearActiveList,
            ),
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Otomatik Kayıt (şirket uygulamasına gir)',
              icon: const Icon(Icons.settings_suggest_rounded),
              onPressed: _openAutoEntry,
            ),
          IconButton(
            tooltip: 'Akışı Başlat',
            icon: const Icon(Icons.play_circle_fill_rounded),
            color: AppTheme.accent,
            onPressed: _startFlow,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.accent,
          tabs: [
            for (final g in LabelGroup.values)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(g.title),
                    if (_lists[g]!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_lists[g]!.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          for (final g in LabelGroup.values)
            _items.isEmpty && g == _active
                ? _buildEmpty()
                : _buildItemList(_lists[g]!),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addFromDirectory,
                  icon: const Icon(Icons.list_alt_rounded),
                  label: const Text('Listeden'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addByShortCode,
                  icon: const Icon(Icons.tag_rounded),
                  label: const Text('Kısa Kod'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _addByScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Tara'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.label_outline_rounded,
              size: 64, color: AppTheme.textTertiary),
          const SizedBox(height: 12),
          Text('“${_active.title}” listesi boş',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 15)),
          const SizedBox(height: 4),
          Text('Tara, Listeden veya Kısa Kod ile ürün ekleyin',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildItemList(List<LabelItem> list) {
    if (list.isEmpty) return _buildEmpty();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final it = list[i];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.card(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      it.barcode,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (it.stockCode != null && it.stockCode!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Kısa kod: ${it.stockCode}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _QtyBtn(icon: Icons.remove, onTap: () => _changeQty(i, -1)),
              GestureDetector(
                onTap: () => _editQtyDialog(i),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 36),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '${it.quantity}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppTheme.accent),
                  ),
                ),
              ),
              _QtyBtn(icon: Icons.add, onTap: () => _changeQty(i, 1)),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppTheme.textTertiary,
                onPressed: () => _removeAt(i),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.rSm),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(AppTheme.rSm),
        ),
        child: Icon(icon, size: 18, color: AppTheme.textPrimary),
      ),
    );
  }
}

/// Buyuk, goz yormayan adet giris dialogu — gorme zorlugu olanlar icin
/// buyuk rakam, buyuk butonlar. Adet rakamina dokununca acilir.
/// "Tamam" ile sonucu doner, "Vazgec" ile null doner.
class _QuantityInputDialog extends StatefulWidget {
  final String title;
  final int initialValue;
  const _QuantityInputDialog(
      {required this.title, required this.initialValue});

  @override
  State<_QuantityInputDialog> createState() => _QuantityInputDialogState();
}

class _QuantityInputDialogState extends State<_QuantityInputDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.initialValue}');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_ctrl.text.trim());
    Navigator.of(context).pop(v ?? widget.initialValue);
  }

  void _bump(int delta) {
    final cur = int.tryParse(_ctrl.text.trim()) ?? widget.initialValue;
    final next = (cur + delta).clamp(0, 9999);
    setState(() => _ctrl.text = '$next');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rLg)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _BigStepBtn(icon: Icons.remove, onTap: () => _bump(-1)),
                const SizedBox(width: 16),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accent,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 16),
                _BigStepBtn(icon: Icons.add, onTap: () => _bump(1)),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18)),
                    child: const Text('Vazgeç', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18)),
                    child: const Text('Tamam',
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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

/// Adet dialogundaki buyuk +/- butonlari (parmak icin genis dokunma alani).
class _BigStepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _BigStepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
        ),
        child: Icon(icon, size: 26, color: AppTheme.textPrimary),
      ),
    );
  }
}

// ── Dizinden urun secme sayfasi ──────────────────────────────────────────
class _DirectoryPickerSheet extends StatefulWidget {
  final List entries; // List<BarcodeEntry>
  const _DirectoryPickerSheet({required this.entries});

  @override
  State<_DirectoryPickerSheet> createState() => _DirectoryPickerSheetState();
}

class _DirectoryPickerSheetState extends State<_DirectoryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list = widget.entries.where((e) {
      if (q.isEmpty) return true;
      final name = (e.productName as String).toLowerCase();
      final code = (e.barcode as String).toLowerCase();
      final stock = ((e.stockCode as String?) ?? '').toLowerCase();
      return name.contains(q) || code.contains(q) || stock.contains(q);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppTheme.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Ürün adı, barkod veya kısa kod ara',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text('Sonuç yok',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    )
                  : ListView.builder(
                      controller: controller,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final e = list[i];
                        final stock = e.stockCode as String?;
                        return ListTile(
                          title: Text(e.productName as String),
                          subtitle: Text(
                            stock != null && stock.isNotEmpty
                                ? '${e.barcode}  •  Kısa kod: $stock'
                                : e.barcode as String,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12),
                          ),
                          trailing:
                              const Icon(Icons.add_circle_outline_rounded),
                          onTap: () =>
                              Navigator.of(context).pop(e.barcode as String),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Kisa kod giris dialogu ───────────────────────────────────────────────
class _ShortCodeDialog extends StatefulWidget {
  const _ShortCodeDialog();

  @override
  State<_ShortCodeDialog> createState() => _ShortCodeDialogState();
}

class _ShortCodeDialogState extends State<_ShortCodeDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kısa Kod ile Ekle'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.text,
        decoration: const InputDecoration(hintText: 'Stok / kısa kod'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}

// ── AKIS: tam ekran buyuk barkod (lazer okutma) ──────────────────────────
class _LabelFlowScreen extends StatefulWidget {
  final String title;
  final List<LabelItem> items;
  const _LabelFlowScreen({required this.title, required this.items});

  @override
  State<_LabelFlowScreen> createState() => _LabelFlowScreenState();
}

class _LabelFlowScreenState extends State<_LabelFlowScreen> {
  final PageController _pageCtrl = PageController();
  int _index = 0;

  /// value'ye uygun 1D barkod tipi sec.
  bw.Barcode _pick1DBarcode(String value) {
    final v = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(v)) return bw.Barcode.code128();
    switch (v.length) {
      case 13:
        return bw.Barcode.ean13();
      case 12:
        return bw.Barcode.upcA();
      case 8:
        return bw.Barcode.ean8();
      default:
        return bw.Barcode.code128();
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    return Scaffold(
      backgroundColor: Colors.white, // lazer okuyucu icin beyaz zemin
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        systemOverlayStyle: AppTheme.systemBarForColor(Colors.white),
        title: Text('${widget.title}  ${_index + 1}/$total',
            style: const TextStyle(color: Colors.black)),
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: total,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          final it = widget.items[i];
          final barcode = _pick1DBarcode(it.barcode);
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  it.productName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (it.stockCode != null && it.stockCode!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Kısa kod: ${it.stockCode}',
                    style: const TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                ],
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: bw.BarcodeWidget(
                    barcode: barcode,
                    data: it.barcode.trim(),
                    drawText: true,
                    height: 160,
                    color: Colors.black,
                    errorBuilder: (context, error) => const Text(
                      'Barkod oluşturulamadı',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('ADET',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          )),
                      const SizedBox(width: 14),
                      Text(
                        '${it.quantity}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Kaydır → sonraki ürün',
                    style: TextStyle(color: Colors.black38, fontSize: 12)),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _index > 0
                      ? () => _pageCtrl.previousPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                          )
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Önceki'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _index < total - 1
                      ? () => _pageCtrl.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                          )
                      : () => Navigator.of(context).pop(true),
                  icon: Icon(_index < total - 1
                      ? Icons.chevron_right_rounded
                      : Icons.check_rounded),
                  label: Text(_index < total - 1 ? 'Sonraki' : 'Bitir'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etiket Basım — Geçmiş ekranı.
/// Son 30 günde listeye eklenen TÜM barkodları, ekleme tarihine göre
/// gün gün gruplanmış olarak gösterir (Bugün / Dün / dd MMMM gibi).
/// Aktif liste sıfırlansa/akış bitse bile bu kayıtlar burada kalır.
class _LabelHistoryScreen extends StatefulWidget {
  const _LabelHistoryScreen();

  @override
  State<_LabelHistoryScreen> createState() => _LabelHistoryScreenState();
}

class _LabelHistoryScreenState extends State<_LabelHistoryScreen> {
  bool _loading = true;
  List<LabelHistoryEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await LabelHistoryService.instance.getRecent(
      days: 30,
    );
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Geçmişi temizle'),
        content: const Text(
            'Son 30 güne ait tüm etiket geçmişi kalıcı olarak silinecek. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.statusExpired),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await LabelHistoryService.instance.clearAll();
      _load();
    }
  }

  /// Verilen gunu "Bugün", "Dün" veya "dd MMMM" olarak etiketler.
  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    return DateFormat('d MMMM yyyy', 'tr').format(day);
  }

  @override
  Widget build(BuildContext context) {
    // Gun gun grupla (added_at zaten DESC siralı geliyor).
    final Map<String, List<LabelHistoryEntry>> grouped = {};
    for (final e in _entries) {
      final key = _dayLabel(e.addedAt);
      grouped.putIfAbsent(key, () => []).add(e);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Etiket Geçmişi'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.primary),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: 'Geçmişi Temizle',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded,
                          size: 64, color: AppTheme.textTertiary),
                      const SizedBox(height: 12),
                      Text('Son 30 günde kayıt yok',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 15)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    for (final dayKey in grouped.keys) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                        child: Text(
                          dayKey,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.accent,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      for (final e in grouped[dayKey]!)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: AppTheme.card(),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.productName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          e.barcode,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primary
                                                .withOpacity(0.15),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            e.groupTitle,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primaryLight,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                DateFormat('HH:mm').format(e.addedAt),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textTertiary),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }
}

/// Surekli barkod tarama ekrani — Etiket Basim icin.
/// Normal tarama ekraninin aksine (BarcodeScanPage) bir barkod okununca
/// ekran KAPANMAZ: ayni veya farkli barkodlar ust uste, art arda okutulabilir.
/// Her okutmada [onScan] cagrilir (listeye eklenir + gecmise loglanir) ve
/// O URUNUN GUNCEL ADEDINI doner; bu adet ekranda BUYUK rakam olarak
/// gosterilir. Rakama dokununca [onEditQuantity] ile buyuk klavyeli adet
/// giris dialogu acilir (gorme zorlugu olanlar icin).
/// "Bitti" butonuna basilinca veya geri tusu ile cikilir.
class _ContinuousScanScreen extends StatefulWidget {
  final Future<int> Function(String barcode) onScan;
  final Future<int?> Function(String barcode, int currentQty) onEditQuantity;
  const _ContinuousScanScreen(
      {required this.onScan, required this.onEditQuantity});

  @override
  State<_ContinuousScanScreen> createState() => _ContinuousScanScreenState();
}

class _ContinuousScanScreenState extends State<_ContinuousScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );

  int _scanCount = 0;
  String? _lastBarcode;
  DateTime? _lastScanTime;
  String? _banner; // ekranda kisaca gosterilen "eklendi" mesaji
  Timer? _bannerTimer;
  int? _lastQuantity; // son okutulan urunun guncel adedi (buyuk rakam icin)

  // Sag ustteki switch ile kontrol edilir: acikken SADECE EAN-13 formati
  // kabul edilir (12/8 haneli UPC, code128 vb. okutulsa da yoksayilir).
  // Kapaliyken tum desteklenen formatlar (varsayilan) okunur.
  bool _ean13Only = false;

  // Ayni barkodun yanlislikla cift okunmasini onlemek icin minimum sure.
  static const _cooldown = Duration(milliseconds: 1200);

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first;
    final rawText = raw.rawValue?.trim();
    if (rawText == null || rawText.isEmpty) return;

    // ── MAGAZA ETIKETI QR'I veya DUZ BARKOD ──
    // QR ise icinden urun barkodunu cikar (format: *barkod*fiyat*SKT*tarih).
    // Duz barkod ise oldugu gibi kullanilir. ScanParser ikisini de cozer.
    final parsed = ScanParser.parse(rawText);
    final String value;
    if (parsed.hasUsableBarcode && parsed.barcode != null) {
      // QR icinden cikan barkod (veya duz barkod).
      value = parsed.barcode!;
    } else if (ScanResult.looksLikeBarcode(rawText)) {
      // Yapilandirilmamis ama barkod gorunumlu ham deger.
      value = rawText;
    } else {
      // Barkod cikarilamadi (serbest metin/taninmayan QR) — yoksay.
      return;
    }

    // EAN-13 filtresi acikken: cikan barkod 13 haneli sayisal degilse yoksay.
    if (_ean13Only) {
      final isEan13Shape = RegExp(r'^\d{13}$').hasMatch(value);
      if (!isEan13Shape) return;
    }

    final now = DateTime.now();
    if (value == _lastBarcode &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < _cooldown) {
      return; // ayni barkod cok kisa surede tekrar okundu, yoksay
    }
    _lastBarcode = value;
    _lastScanTime = now;

    HapticFeedback.mediumImpact();
    final newQty = await widget.onScan(value);
    if (!mounted) return;

    setState(() {
      _scanCount++;
      _banner = 'Eklendi: $value';
      _lastQuantity = newQty;
    });
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  Future<void> _editLastQuantity() async {
    final barcode = _lastBarcode;
    final qty = _lastQuantity;
    if (barcode == null || qty == null) return;
    final result = await widget.onEditQuantity(barcode, qty);
    if (result != null && mounted) {
      setState(() => _lastQuantity = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Kamera onizlemesi status bar arkasina kadar uzansin.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        title: Text('Tara  •  $_scanCount eklendi'),
        actions: [
          // EAN-13 filtresi: acikken sadece 13 haneli EAN-13 barkodlar
          // kabul edilir, diger formatlar (UPC, code128 vb.) yoksayilir.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('EAN-13',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              Switch(
                value: _ean13Only,
                onChanged: (v) => setState(() => _ean13Only = v),
                activeColor: AppTheme.accent,
              ),
            ],
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Bitti',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Container(
            width: 260,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.accent, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const Positioned(
            bottom: 90,
            child: Text(
              'Aynı veya farklı ürünleri art arda okutabilirsiniz',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          // Son okutulan urunun adedi — BUYUK rakam, dokununca duzenlenir.
          if (_lastQuantity != null)
            Positioned(
              bottom: 130,
              child: GestureDetector(
                onTap: _editLastQuantity,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.3), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_lastQuantity',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.edit_rounded,
                          color: Colors.white70, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          // "Eklendi" bandi — ust tarafta kisa sureli gorunur.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _banner != null ? 16 : -60,
            left: 16,
            right: 16,
            child: AnimatedOpacity(
              opacity: _banner != null ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.statusSafe,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.black, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _banner ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// ══════════════════════════════════════════════════════════════════════
///  OTOMATIK KAYIT alt sayfasi.
///  Aktif sekmedeki barkodlari sirket uygulamasinin giris kutusuna otomatik
///  yazar + Ekle butonuna basar. Kullanici baslat'a basip sirket ekranina
///  gecer; uygulama sirayla girer. Sen izlersin.
/// ══════════════════════════════════════════════════════════════════════
class _AutoEntrySheet extends StatefulWidget {
  final List<String> barcodes;
  const _AutoEntrySheet({required this.barcodes});

  @override
  State<_AutoEntrySheet> createState() => _AutoEntrySheetState();
}

class _AutoEntrySheetState extends State<_AutoEntrySheet> {
  StreamSubscription<Map<dynamic, dynamic>>? _sub;
  bool _running = false;
  bool _finished = false;
  int _done = 0;
  int _total = 0;
  int _countdown = 0;
  Timer? _countdownTimer;
  final List<String> _log = [];

  @override
  void dispose() {
    _sub?.cancel();
    _countdownTimer?.cancel();
    PriceCheckChannel.stopAutoEntry();
    super.dispose();
  }

  void _start() {
    setState(() {
      _log.clear();
      _finished = false;
      _done = 0;
      _total = widget.barcodes.length;
      _countdown = 5;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) {
        t.cancel();
        _begin();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _begin() {
    setState(() {
      _countdown = 0;
      _running = true;
    });
    _sub?.cancel();
    _sub = PriceCheckChannel.autoEntryStream.listen((event) {
      final type = event['type'] as String?;
      if (type == 'progress') {
        final done = (event['done'] as int?) ?? 0;
        final total = (event['total'] as int?) ?? 0;
        final bc = (event['barcode'] as String?) ?? '';
        final ok = (event['ok'] as bool?) ?? false;
        setState(() {
          _done = done;
          _total = total;
          _log.insert(0, '${ok ? "✓" : "✗"} $bc');
          if (_log.length > 30) _log.removeLast();
        });
      } else if (type == 'finished') {
        setState(() {
          _running = false;
          _finished = true;
          _done = (event['done'] as int?) ?? _done;
        });
      }
    });
    PriceCheckChannel.startAutoEntry(widget.barcodes, 1000);
  }

  void _stop() {
    PriceCheckChannel.stopAutoEntry();
    setState(() {
      _running = false;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings_suggest_rounded, color: AppTheme.accent),
              const SizedBox(width: 8),
              const Text('Otomatik Kayıt',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${widget.barcodes.length} barkod',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
            ],
          ),
          const SizedBox(height: 12),
          if (_countdown > 0) ...[
            Center(
              child: Column(
                children: [
                  Text('$_countdown',
                      style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent)),
                  const Text('Şirket uygulamasının barkod giriş ekranına geçin!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ] else if (_running) ...[
            LinearProgressIndicator(
              value: _total > 0 ? _done / _total : null,
            ),
            const SizedBox(height: 8),
            Text('Giriliyor: $_done / $_total',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Text('Şirket uygulamasında kalın, dokunmayın.',
                style: TextStyle(fontSize: 12)),
          ] else if (_finished) ...[
            Text('Bitti: $_done / $_total girildi',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ] else ...[
            const Text(
              'Aktif sekmedeki barkodlar şirket uygulamasının giriş '
              'kutusuna sırayla yazılıp Ekle butonuna basılacak. '
              '"Başlat"a bastıktan sonra 5 saniye içinde şirket '
              'uygulamasının barkod giriş ekranına geçin.\n\n'
              'Önce metin yazılır, sonra butona tıklanır. Her barkod '
              'arası ~1 saniye.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              height: 120,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView(
                children: _log
                    .map((l) => Text(l,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (_running)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Durdur'),
                  ),
                )
              else
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _countdown > 0 ? null : _start,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(_finished ? 'Tekrar Başlat' : 'Başlat'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ══════════════════════════════════════════════════════════════════════
///  SILINENLER sayfasi.
///  Silinen etiket partilerini (batch) listeler; her parti tek tusla geri
///  alinabilir veya kalici silinebilir. Parti = ayni anda silinen etiketler.
/// ══════════════════════════════════════════════════════════════════════
class _DeletedLabelsPage extends StatefulWidget {
  final Future<void> Function(DeletedBatch batch) onRestore;
  const _DeletedLabelsPage({required this.onRestore});

  @override
  State<_DeletedLabelsPage> createState() => _DeletedLabelsPageState();
}

class _DeletedLabelsPageState extends State<_DeletedLabelsPage> {
  List<DeletedBatch> _batches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await LabelDeletedService.instance.loadBatches();
    if (mounted) {
      setState(() {
        _batches = b;
        _loading = false;
      });
    }
  }

  String _groupTitle(String key) {
    for (final g in LabelGroup.values) {
      if (g.name == key) return g.title;
    }
    return key;
  }

  String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _restore(DeletedBatch batch) async {
    await LabelDeletedService.instance.restoreBatch(batch.batchId);
    await widget.onRestore(batch);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${batch.items.length} etiket geri alındı'),
          backgroundColor: AppTheme.statusSafe,
        ),
      );
    }
  }

  Future<void> _delete(DeletedBatch batch) async {
    await LabelDeletedService.instance.deleteBatch(batch.batchId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Silinen Etiketler'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_batches.isNotEmpty)
            IconButton(
              tooltip: 'Tümünü kalıcı sil',
              icon: const Icon(Icons.delete_forever_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Silinenleri temizle'),
                    content: const Text(
                        'Tüm silinen etiket geçmişi kalıcı olarak silinecek. '
                        'Bu işlem geri alınamaz.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Vazgeç')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Temizle',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (ok == true) {
                  await LabelDeletedService.instance.clearAll();
                  await _load();
                }
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _batches.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.restore_from_trash_rounded,
                          size: 56, color: cs.onSurface.withOpacity(0.3)),
                      const SizedBox(height: 12),
                      Text('Silinen etiket yok',
                          style:
                              TextStyle(color: cs.onSurface.withOpacity(0.5))),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _batches.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final b = _batches[i];
                    final totalQty =
                        b.items.fold<int>(0, (s, e) => s + e.quantity);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.label_off_rounded,
                                    size: 18, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Text(_groupTitle(b.groupKey),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const Spacer(),
                                Text(_fmtTime(b.deletedAt),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurface.withOpacity(0.5))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${b.items.length} çeşit • $totalQty adet',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurface.withOpacity(0.7)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              b.items
                                  .take(3)
                                  .map((e) => e.productName)
                                  .join(', ') +
                                  (b.items.length > 3 ? '...' : ''),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _restore(b),
                                    icon: const Icon(Icons.undo_rounded,
                                        size: 18),
                                    label: const Text('Geri Al'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.statusSafe,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Kalıcı sil',
                                  onPressed: () => _delete(b),
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
