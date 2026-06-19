import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/label_settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/label_item.dart';
import '../../viewmodels/providers.dart';
import 'add_product_screen.dart' show BarcodeScanPage;

/// Etiket Basim Sayfasi.
///
/// Akis:
///  1) Kullanici bir etiket formati secer (5 secenek; olculer ayarlanabilir).
///  2) Sayfaya urun ekler: barkod tarayarak VEYA dizinden secerek.
///     Tabanda kayitliysa kisa kod (stok kodu) da listede gosterilir.
///  3) Sag ustten "Akis" baslatir: barkodlar tek tek tam ekran buyuk
///     gosterilir, lazer/harici okuyucu ile okutulabilir.
class LabelPrintScreen extends ConsumerStatefulWidget {
  const LabelPrintScreen({super.key});

  @override
  ConsumerState<LabelPrintScreen> createState() => _LabelPrintScreenState();
}

class _LabelPrintScreenState extends ConsumerState<LabelPrintScreen> {
  LabelFormat _format = LabelFormat.bigRoll;
  final List<LabelItem> _items = [];

  // ── Urun ekleme: barkod tara ──────────────────────────────────────────
  Future<void> _addByScan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );
    if (code == null || !mounted) return;
    await _addByBarcode(code.trim());
  }

  /// Barkodu dizinde arar; bulursa ad+kisa kod ile, bulamazsa sadece
  /// barkod ile ekler. Ayni barkod zaten varsa adedi artirir.
  Future<void> _addByBarcode(String barcode) async {
    if (barcode.isEmpty) return;
    final entry =
        await ref.read(barcodeDirectoryRepositoryProvider).findEntryByBarcode(barcode);
    if (!mounted) return;
    setState(() {
      final idx = _items.indexWhere((e) => e.barcode == barcode);
      if (idx >= 0) {
        _items[idx].quantity++;
      } else {
        _items.add(LabelItem(
          barcode: barcode,
          productName: entry?.productName ?? 'Bilinmeyen ürün',
          stockCode: entry?.stockCode,
        ));
      }
    });
  }

  // ── Urun ekleme: dizinden sec ──────────────────────────────────────────
  Future<void> _addFromDirectory() async {
    final all = await ref.read(barcodeDirectoryRepositoryProvider).getAll();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DirectoryPickerSheet(entriesBarcodes: all),
    );
    if (picked == null || !mounted) return;
    await _addByBarcode(picked);
  }

  // ── Urun ekleme: kisa kod (stok kodu) ile ──────────────────────────────
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

  // ── Akis: tam ekran buyuk barkod (lazer okutma) ─────────────────────────
  void _startFlow() {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce ürün ekleyin.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _LabelFlowScreen(items: List.of(_items))),
    );
  }

  Future<void> _openSizeSettings() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SizeSettingsSheet(format: _format),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Etiket Basım'),
        actions: [
          IconButton(
            tooltip: 'Etiket ölçüleri',
            icon: const Icon(Icons.straighten_rounded),
            onPressed: _openSizeSettings,
          ),
          // Sag ust: akis baslatici (lazer okutma).
          IconButton(
            tooltip: 'Akışı Başlat',
            icon: const Icon(Icons.play_circle_fill_rounded),
            color: AppTheme.accent,
            onPressed: _startFlow,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFormatPicker(),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty ? _buildEmpty() : _buildItemList(),
          ),
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

  Widget _buildFormatPicker() {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: LabelFormat.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = LabelFormat.values[i];
          final selected = f == _format;
          return GestureDetector(
            onTap: () => setState(() => _format = f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 150,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected ? AppTheme.primary : AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                border: Border.all(
                  color: selected ? AppTheme.primaryLight : Colors.transparent,
                  width: 1.4,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    f.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: selected ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    f.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: selected
                          ? Colors.white.withOpacity(0.85)
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
          const Text('Henüz ürün eklenmedi',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('Tara, Listeden veya Kısa Kod ile ürün ekleyin',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildItemList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final it = _items[i];
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
              // Adet kontrolu
              _QtyBtn(icon: Icons.remove, onTap: () => _changeQty(i, -1)),
              SizedBox(
                width: 28,
                child: Text(
                  '${it.quantity}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
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

// ── Dizinden urun secme sayfasi ──────────────────────────────────────────
class _DirectoryPickerSheet extends StatefulWidget {
  final List entriesBarcodes; // List<BarcodeEntry>
  const _DirectoryPickerSheet({required this.entriesBarcodes});

  @override
  State<_DirectoryPickerSheet> createState() => _DirectoryPickerSheetState();
}

class _DirectoryPickerSheetState extends State<_DirectoryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list = widget.entriesBarcodes.where((e) {
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
                          trailing: const Icon(Icons.add_circle_outline_rounded),
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

// ── Etiket olcu ayarlari ─────────────────────────────────────────────────
class _SizeSettingsSheet extends StatefulWidget {
  final LabelFormat format;
  const _SizeSettingsSheet({required this.format});

  @override
  State<_SizeSettingsSheet> createState() => _SizeSettingsSheetState();
}

class _SizeSettingsSheetState extends State<_SizeSettingsSheet> {
  final _wCtrl = TextEditingController();
  final _hCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await LabelSettingsService.instance.getDimensions(widget.format);
    if (!mounted) return;
    setState(() {
      _wCtrl.text = d.widthMm.toStringAsFixed(0);
      _hCtrl.text = d.heightMm.toStringAsFixed(0);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final w = double.tryParse(_wCtrl.text.trim());
    final h = double.tryParse(_hCtrl.text.trim());
    if (w == null || h == null || w <= 0 || h <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli ölçü girin (mm).')),
      );
      return;
    }
    await LabelSettingsService.instance
        .setDimensions(widget.format, widthMm: w, heightMm: h);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await LabelSettingsService.instance.resetToDefault(widget.format);
    await _load();
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            Text('${widget.format.title} ölçüleri (mm)',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _wCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Genişlik (mm)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Yükseklik (mm)'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text('Varsayılana Dön'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Kaydet'),
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

// ── AKIS: tam ekran buyuk barkod (lazer okutma) ──────────────────────────
class _LabelFlowScreen extends StatefulWidget {
  final List<LabelItem> items;
  const _LabelFlowScreen({required this.items});

  @override
  State<_LabelFlowScreen> createState() => _LabelFlowScreenState();
}

class _LabelFlowScreenState extends State<_LabelFlowScreen> {
  final PageController _pageCtrl = PageController();
  int _index = 0;

  /// value'ye uygun 1D barkod tipi sec (yoksa null).
  Barcode? _pick1DBarcode(String value) {
    final v = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(v)) {
      return Barcode.code128(); // rakam degil -> code128 dene
    }
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
        title: Text('Akış  ${_index + 1} / $total',
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
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 14),
                  ),
                ],
                const SizedBox(height: 32),
                // Buyuk barkod - lazer okuyucu icin genis ve net.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: BarcodeWidget(
                    barcode: barcode!,
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
                Text(
                  'Adet: ${it.quantity}',
                  style: const TextStyle(
                      color: Colors.black, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Kaydır → sonraki ürün',
                  style: TextStyle(color: Colors.black38, fontSize: 12),
                ),
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
                      : () => Navigator.of(context).pop(),
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
