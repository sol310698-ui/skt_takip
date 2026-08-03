import 'package:flutter/material.dart';

import '../../core/services/label_pending_queue_service.dart';
import '../../core/services/teshir_service.dart';
import '../../core/theme/app_theme.dart';
import '../screens/label_print_screen.dart';

/// Etiket hedefi secim sonucu.
class LabelTargetChoice {
  /// Secilen liste anahtari (LabelGroup.name) — null ise gonderilmeyecek.
  final String? groupKey;

  /// Urun teshirde ise TESHIR ETIKETI de istendi mi.
  final bool alsoTeshir;

  /// Teshir etiketinin gidecegi liste (LabelGroup.name). Teshir etiketleri
  /// genelde A4 sablonlarindan biridir; kullanici burada secer.
  /// NOT: Gecerli bir LabelGroup adi OLMALI — aksi halde Etiket Basim
  /// ekrani onu taniyamaz.
  final String? teshirGroupKey;

  /// Teshir grubunun TUM uyeleri (barkod, ad). Ayni A4 kagidina
  /// basildiklari icin biri degisse bile HEPSI listeye gitmelidir.
  final List<(String, String)> teshirMembers;

  const LabelTargetChoice({
    this.groupKey,
    this.alsoTeshir = false,
    this.teshirGroupKey,
    this.teshirMembers = const [],
  });
}

/// ════════════════════════════════════════════════════════════════════
///  ETIKET HEDEFI SECICI (v158)
/// ────────────────────────────────────────────────────────────────────
///  Onceki hali sadece 5 satirlik duz bir listeydi; hangi listenin ne
///  ise yaradigi ve icinde kac urun bekledigi gorunmuyordu. Yeni hali:
///   • Ustte URUN baglami (ad, barkod, fiyat degisimi)
///   • TESHIR ENTEGRASYONU: urun teshirdeyse uyarir ve "teshir etiketi
///     de basilsin" secenegi sunar (reyon etiketi tek basina yetmez)
///   • Her liste icin ACIKLAMA + o listede BEKLEYEN SAYISI rozeti
/// ════════════════════════════════════════════════════════════════════
Future<LabelTargetChoice?> showLabelTargetSheet(
  BuildContext context, {
  required String barcode,
  required String productName,
  String? currentGroupKey,
  bool currentAlsoTeshir = false,
  String? currentTeshirGroupKey,
  double? oldPrice,
  double? newPrice,
}) {
  return showModalBottomSheet<LabelTargetChoice>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => _LabelTargetSheet(
      barcode: barcode,
      productName: productName,
      currentGroupKey: currentGroupKey,
      currentAlsoTeshir: currentAlsoTeshir,
      currentTeshirGroupKey: currentTeshirGroupKey,
      oldPrice: oldPrice,
      newPrice: newPrice,
    ),
  );
}

class _LabelTargetSheet extends StatefulWidget {
  final String barcode;
  final String productName;
  final String? currentGroupKey;
  final bool currentAlsoTeshir;
  final String? currentTeshirGroupKey;
  final double? oldPrice;
  final double? newPrice;
  const _LabelTargetSheet({
    required this.barcode,
    required this.productName,
    this.currentGroupKey,
    this.currentAlsoTeshir = false,
    this.currentTeshirGroupKey,
    this.oldPrice,
    this.newPrice,
  });

  @override
  State<_LabelTargetSheet> createState() => _LabelTargetSheetState();
}

class _LabelTargetSheetState extends State<_LabelTargetSheet> {
  String? _group;
  bool _alsoTeshir = false;

  /// Teshir etiketi hangi listeye gitsin (varsayilan A4).
  String _teshirGroup = LabelGroup.a4.name;
  Map<String, int> _counts = {};
  Map<String, Object?>? _teshir; // urun teshirdeyse kaydi
  List<Map<String, Object?>> _members = const []; // ayni A4 grubundakiler
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _group = widget.currentGroupKey;
    _alsoTeshir = widget.currentAlsoTeshir;
    if (widget.currentTeshirGroupKey != null) {
      _teshirGroup = widget.currentTeshirGroupKey!;
    }
    _load();
  }

  Future<void> _load() async {
    Map<String, int> counts = {};
    Map<String, Object?>? teshir;
    try {
      counts = await LabelPendingQueueService.instance.pendingCountsByGroup();
    } catch (_) {}
    List<Map<String, Object?>> members = const [];
    try {
      teshir = await TeshirService.instance.find(widget.barcode);
      if (teshir != null) {
        members = await TeshirService.instance.groupOf(widget.barcode);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _teshir = teshir;
      _members = members;
      // GRUP LISTEYI BELIRLER: 2'li grup → A4 İkili, 3'lü → A4 Üçlü.
      final size = members.isEmpty
          ? ((teshir?['group_size'] as int?) ?? 1)
          : members.length;
      _teshirGroup = switch (size) {
        2 => LabelGroup.a4Double.name,
        3 => LabelGroup.a4Triple.name,
        _ => LabelGroup.a4.name,
      };
      _loading = false;
    });
  }

  /// Her listenin ne ise yaradigi — kullanici dogru listeyi secsin.
  String _desc(LabelGroup g) {
    switch (g) {
      case LabelGroup.kalinRon:
        return 'Reyon rafı — geniş etiket';
      case LabelGroup.inceRon:
        return 'Reyon rafı — dar etiket';
      case LabelGroup.a4:
        return 'A4 sayfada tek etiket';
      case LabelGroup.a4Double:
        return 'A4 sayfada 2 etiket';
      case LabelGroup.a4Triple:
        return 'A4 sayfada 3 etiket';
    }
  }

  IconData _icon(LabelGroup g) {
    switch (g) {
      case LabelGroup.kalinRon:
        return Icons.view_agenda_rounded;
      case LabelGroup.inceRon:
        return Icons.view_stream_rounded;
      case LabelGroup.a4:
        return Icons.crop_portrait_rounded;
      case LabelGroup.a4Double:
        return Icons.calendar_view_day_rounded;
      case LabelGroup.a4Triple:
        return Icons.table_rows_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = (widget.oldPrice != null && widget.newPrice != null)
        ? widget.newPrice! - widget.oldPrice!
        : null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: AppTheme.textTertiary,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              // ── URUN BAGLAMI ──
              Text(widget.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(widget.barcode,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: AppTheme.textTertiary)),
                  if (diff != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: (diff >= 0
                                ? AppTheme.statusExpired
                                : AppTheme.statusSafe)
                            .withOpacity(0.14),
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: Text(
                        '${widget.oldPrice!.toStringAsFixed(2)} → '
                        '${widget.newPrice!.toStringAsFixed(2)} ₺',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: diff >= 0
                                ? AppTheme.statusExpired
                                : AppTheme.statusSafe),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              // ── TESHIR ENTEGRASYONU ──
              if (_teshir != null) _teshirCard(),
              Text('ETİKET LİSTESİ',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: AppTheme.textTertiary)),
              const SizedBox(height: 6),
              for (final g in LabelGroup.values) _groupTile(g),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(
                          context,
                          const LabelTargetChoice(
                              groupKey: null, alsoTeshir: false)),
                      child: const Text('Gönderme'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: (_group == null && !_alsoTeshir)
                          ? null
                          : () => Navigator.pop(
                              context,
                              LabelTargetChoice(
                                  groupKey: _group,
                                  alsoTeshir: _alsoTeshir,
                                  teshirGroupKey:
                                      _alsoTeshir ? _teshirGroup : null,
                                  teshirMembers: _alsoTeshir
                                      ? _members
                                          .map((m) => (
                                                m['barcode'] as String,
                                                ((m['product_name']
                                                            as String?)
                                                        ?.trim()
                                                        .isNotEmpty ??
                                                    false)
                                                    ? m['product_name']
                                                        as String
                                                    : m['barcode'] as String
                                              ))
                                          .toList()
                                      : const [])),
                      child: Text(_group == null && _alsoTeshir
                          ? 'Sadece teşhir etiketi'
                          : 'Onayla'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Urun teshirdeyse: uyari + ikinci etiket secenegi.
  Widget _teshirCard() {
    final note = (_teshir!['note'] as String?)?.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.coral.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.coral.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded,
                  size: 18, color: AppTheme.coral),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Bu ürün TEŞHİRDE',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.coral)),
              ),
              if (note != null && note.isNotEmpty)
                Flexible(
                  child: Text(note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.coral)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              _members.length > 1
                  ? 'Bu ürün ${_members.length}\'li A4 grubunda — aynı kağıt '
                      'yeniden basılacağı için GRUBUN TAMAMI listeye eklenir:'
                  : 'Reyon etiketi tek başına yetmez — teşhirdeki etiket de '
                      'değişmeli.',
              style: TextStyle(
                  fontSize: 11.5, color: AppTheme.textSecondary)),
          // GRUP UYELERI: kagitta birlikte duran urunler.
          if (_members.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 5,
                runSpacing: 4,
                children: [
                  for (final m in _members)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: (m['barcode'] == widget.barcode
                                ? AppTheme.coral
                                : AppTheme.textTertiary)
                            .withOpacity(0.18),
                        borderRadius:
                            BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: Text(
                        ((m['product_name'] as String?)?.trim().isNotEmpty ??
                                false)
                            ? m['product_name'] as String
                            : m['barcode'] as String,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: m['barcode'] == widget.barcode
                                ? FontWeight.w900
                                : FontWeight.w600,
                            color: AppTheme.textPrimary),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _alsoTeshir = !_alsoTeshir),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                      _alsoTeshir
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color: _alsoTeshir
                          ? AppTheme.coral
                          : AppTheme.textTertiary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Teşhir etiketi de listeye eklensin',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
          if (_alsoTeshir && _members.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  '→ ${LabelGroup.values.firstWhere((g) => g.name == _teshirGroup, orElse: () => LabelGroup.a4).title} '
                  'listesine ${_members.length} ürün eklenecek',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.coral)),
            ),
          // TESHIR ETIKETI HANGI LISTEYE: A4 sablonlari (grupsuzsa).
          if (_alsoTeshir && _members.length <= 1) ...[
            const SizedBox(height: 2),
            Text('Teşhir etiketi şu listeye eklensin:',
                style: TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final g in const [
                  LabelGroup.a4,
                  LabelGroup.a4Double,
                  LabelGroup.a4Triple,
                ])
                  ChoiceChip(
                    label: Text(g.title,
                        style: const TextStyle(fontSize: 12)),
                    selected: _teshirGroup == g.name,
                    selectedColor: AppTheme.coral.withOpacity(0.25),
                    onSelected: (_) =>
                        setState(() => _teshirGroup = g.name),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _groupTile(LabelGroup g) {
    final selected = _group == g.name;
    final count = _counts[g.name] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        onTap: () => setState(() => _group = selected ? null : g.name),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withOpacity(0.12)
                : AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
                color: selected ? AppTheme.accent : AppTheme.hairline,
                width: selected ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color:
                      selected ? AppTheme.accent : AppTheme.textTertiary),
              const SizedBox(width: 10),
              Icon(_icon(g),
                  size: 18,
                  color:
                      selected ? AppTheme.accent : AppTheme.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(_desc(g),
                        style: TextStyle(
                            fontSize: 11.5, color: AppTheme.textTertiary)),
                  ],
                ),
              ),
              // O listede KAC URUN bekliyor.
              if (_loading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.textTertiary),
                )
              else if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: Text('$count bekliyor',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
