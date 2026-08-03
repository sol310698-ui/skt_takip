import 'package:flutter/material.dart';

import '../../core/services/location_reveal_prefs.dart';
import '../../core/services/price_change_service.dart';
import '../../core/services/shelf_layout_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/location_reveal.dart';
import '../widgets/ui_kit.dart';

/// OCR sonucu onizleme + duzeltme.
/// Kullanici satirlari duzenler/siler/ekler; "Onayla" ile kesin liste doner.
/// Veri hata kabul etmedigi icin bu adim zorunludur.
class PriceChangeReviewScreen extends StatefulWidget {
  final List<PriceChangeItem> items;
  final String source; // 'Gemini AI' | 'Cihaz OCR'

  const PriceChangeReviewScreen({
    super.key,
    required this.items,
    required this.source,
  });

  @override
  State<PriceChangeReviewScreen> createState() =>
      _PriceChangeReviewScreenState();
}

class _PriceChangeReviewScreenState extends State<PriceChangeReviewScreen> {
  late List<PriceChangeItem> _items;

  @override
  void initState() {
    super.initState();
    _items = [...widget.items];
  }

  Future<void> _editItem(int index) async {
    final item = _items[index];
    final result = await _showEditDialog(item);
    if (result != null) {
      setState(() => _items[index] = result);
    }
  }

  Future<void> _addItem() async {
    final blank = PriceChangeItem(
      batchId: 'manual',
      sessionId: widget.items.isNotEmpty ? widget.items.first.sessionId : 0,
      barcode: '',
      createdAt: DateTime.now(),
    );
    final result = await _showEditDialog(blank, isNew: true);
    if (result != null && result.barcode.length >= 12) {
      setState(() => _items.add(result));
    }
  }

  /// REYONDA GÖSTER: bu barkodun reyon dizilimindeki yerini bulup
  /// konum canlandırmasını oynatır — etiketi değiştirirken doğru rafa
  /// gitmeyi kolaylaştırır.
  Future<void> _showInShelf(PriceChangeItem item) async {
    if (item.barcode.trim().isEmpty) return;
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

  Future<PriceChangeItem?> _showEditDialog(PriceChangeItem item,
      {bool isNew = false}) async {
    final bcCtrl = TextEditingController(text: item.barcode);
    final nameCtrl = TextEditingController(text: item.productName ?? '');
    final newCtrl = TextEditingController(
        text: item.newPrice?.toStringAsFixed(2) ?? '');
    final oldCtrl = TextEditingController(
        text: item.oldPrice?.toStringAsFixed(2) ?? '');
    final aisleCtrl = TextEditingController(text: item.aisle ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isNew ? 'Satır Ekle' : 'Satırı Düzelt'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bcCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Barkod (12-13 hane)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Ürün adı'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: newCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Yeni fiyat'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: oldCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Eski fiyat'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: aisleCtrl,
                decoration: const InputDecoration(labelText: 'Reyon'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaydet')),
        ],
      ),
    );

    if (saved != true) return null;
    double? p(String s) => s.trim().isEmpty
        ? null
        : double.tryParse(s.replaceAll(',', '.'));

    final bc = bcCtrl.text.trim();
    return PriceChangeItem(
      id: item.id,
      batchId: item.batchId,
      sessionId: item.sessionId,
      barcode: bc.isNotEmpty ? bc : item.barcode,
      productName:
          nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      newPrice: p(newCtrl.text),
      oldPrice: p(oldCtrl.text),
      aisle: aisleCtrl.text.trim().isEmpty ? null : aisleCtrl.text.trim(),
      createdAt: item.createdAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final issues = _items
        .where((i) => i.newPrice == null || i.productName == null)
        .length;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // ── GRADYAN HERO ──
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(8, topPad + 8, 16, 14),
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Okunan Liste — Kontrol',
                              style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white)),
                          Text('Satıra dokunup düzeltebilirsiniz',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppTheme.rMd),
                  ),
                  child: Row(
                    children: [
                      _heroStat('${_items.length}', 'satır'),
                      _heroDivider(),
                      _heroStat('${_items.length - issues}', 'tam'),
                      _heroDivider(),
                      _heroStat('$issues', 'eksik'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Kaynak bilgisi.
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: AppTheme.card(accentColor: AppTheme.accent),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: AppTheme.accent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.source} ile okundu. Eksik/yanlış satırları '
                    'düzeltin, ürünün reyondaki yerini görmek için '
                    'konum ikonuna dokunun.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? const EmptyState(
                    icon: Icons.playlist_remove_rounded,
                    title: 'Satır kalmadı',
                    subtitle: 'Elle satır ekleyin veya geri dönün')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final item = _items[i];
                      final hasIssue = item.newPrice == null ||
                          item.productName == null;
                      return InkWell(
                        borderRadius:
                            BorderRadius.circular(AppTheme.rLg),
                        onTap: () => _editItem(i),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: AppTheme.card(
                              accentColor: hasIssue
                                  ? AppTheme.statusWarning
                                  : null),
                          child: Row(
                            children: [
                              if (hasIssue)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(Icons.warning_rounded,
                                      color: AppTheme.statusWarning,
                                      size: 18),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        item.productName ??
                                            '(ad okunamadı)',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.5,
                                            color: item.productName ==
                                                    null
                                                ? AppTheme.statusWarning
                                                : AppTheme.textPrimary)),
                                    Text(item.barcode,
                                        style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            color:
                                                AppTheme.textTertiary)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                children: [
                                  Text(
                                      item.newPrice != null
                                          ? '${item.newPrice!.toStringAsFixed(2)} ₺'
                                          : '— ₺',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: item.newPrice != null
                                              ? AppTheme.statusSafe
                                              : AppTheme.statusWarning)),
                                  if (item.oldPrice != null)
                                    Text(
                                        '${item.oldPrice!.toStringAsFixed(2)} ₺',
                                        style: TextStyle(
                                            fontSize: 11,
                                            decoration: TextDecoration
                                                .lineThrough,
                                            color:
                                                AppTheme.textTertiary)),
                                ],
                              ),
                              const SizedBox(width: 4),
                              // Reyonda göster (animasyon).
                              InkWell(
                                onTap: () => _showInShelf(item),
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                      Icons.travel_explore_rounded,
                                      size: 20,
                                      color: AppTheme.primary),
                                ),
                              ),
                              InkWell(
                                onTap: () =>
                                    setState(() => _items.removeAt(i)),
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(Icons.close_rounded,
                                      size: 18,
                                      color: AppTheme.textTertiary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
            color: AppTheme.surface, boxShadow: AppTheme.shadowMd),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Satır Ekle'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _items.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_items),
                    icon: const Icon(Icons.check_rounded),
                    label: Text('Onayla (${_items.length})',
                        style:
                            const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroStat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Colors.white70)),
          ],
        ),
      );

  Widget _heroDivider() => Container(
      width: 1, height: 26, color: Colors.white.withOpacity(0.25));
}
