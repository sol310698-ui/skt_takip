import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/label_history_service.dart';
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
        return 'Kalın Rön';
      case LabelGroup.inceRon:
        return 'İnce Rön';
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
///  - Ust tarafta 5 sekme (5 ayri liste): Kalın Rön, İnce Rön, A4, A4 İkili,
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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: LabelGroup.values.length, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
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

  void _removeAt(int i) => setState(() => _items.removeAt(i));

  void _changeQty(int i, int delta) {
    setState(() {
      final q = _items[i].quantity + delta;
      if (q <= 0) {
        _items.removeAt(i);
      } else {
        _items[i].quantity = q;
      }
    });
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
      return;
    }
    final delta = result - item.quantity;
    setState(() => item.quantity = result);
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
      setState(() => _items.clear());
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
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('Tara, Listeden veya Kısa Kod ile ürün ekleyin',
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
                      style: const TextStyle(
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
        decoration: const BoxDecoration(
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
                  ? const Center(
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
  Barcode _pick1DBarcode(String value) {
    final v = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(v)) return Barcode.code128();
    switch (v.length) {
      case 13:
        return Barcode.ean13();
      case 12:
        return Barcode.upcA();
      case 8:
        return Barcode.ean8();
      default:
        return Barcode.code128();
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
                  child: BarcodeWidget(
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
                      const Text('Son 30 günde kayıt yok',
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
                                          style: const TextStyle(
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
                                style: const TextStyle(
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
    final value = barcodes.first.rawValue?.trim();
    if (value == null || value.isEmpty) return;

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
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        systemOverlayStyle: AppTheme.systemBarForColor(Colors.black),
        title: Text('Tara  •  $_scanCount eklendi'),
        actions: [
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

