import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/shelf_layout_service.dart';
import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  TOPLU SÜTUN TAŞIMA — bir reyonun sütun(lar)ındaki rafları (ürünleri)
///  başka reyona toplu taşı. Yanlış reyona eklenen ürünleri tek tek silip
///  yeniden eklemek yerine tek işlemle taşımak için.
/// ────────────────────────────────────────────────────────────────────
///  Adımlar:
///   1) KAYNAK reyon + taşınacak sütun(lar) seç (çoklu seçim).
///   2) HEDEF reyon seç.
///   3) MOD seç: "Ek olarak" (mevcut sütuna alta ekle) ya da "Yeni sütun".
///   4) Önizleme + onayla → moveColumn çalışır.
/// ════════════════════════════════════════════════════════════════════
class ShelfBulkMoveScreen extends StatefulWidget {
  const ShelfBulkMoveScreen({super.key});
  @override
  State<ShelfBulkMoveScreen> createState() => _ShelfBulkMoveScreenState();
}

class _ShelfBulkMoveScreenState extends State<ShelfBulkMoveScreen> {
  List<ShelfUnitSummary> _units = [];
  bool _loading = true;
  bool _busy = false;

  int? _sourceUnitId;
  final Set<int> _sourceSections = {}; // secili sutunlar (coklu)
  Map<int, int> _sectionCounts = {}; // sutun -> urun sayisi

  int? _targetUnitId;
  int? _targetSection; // 'append' modunda hedef sutun
  String _mode = 'newColumn'; // 'append' | 'newColumn'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final units = await ShelfLayoutService.instance.getUnitSummaries();
    if (!mounted) return;
    setState(() {
      _units = units;
      _loading = false;
    });
  }

  Future<void> _onSourceUnit(int unitId) async {
    final sections =
        await ShelfLayoutService.instance.sectionsWithItems(unitId);
    final counts = <int, int>{};
    for (final s in sections) {
      counts[s] =
          await ShelfLayoutService.instance.itemCountInColumn(unitId, s);
    }
    if (!mounted) return;
    setState(() {
      _sourceUnitId = unitId;
      _sourceSections.clear();
      _sectionCounts = counts;
      // Hedef kaynakla ayni olamaz.
      if (_targetUnitId == unitId) _targetUnitId = null;
    });
  }

  int get _totalToMove =>
      _sourceSections.fold(0, (s, sec) => s + (_sectionCounts[sec] ?? 0));

  bool get _canMove =>
      _sourceUnitId != null &&
      _sourceSections.isNotEmpty &&
      _targetUnitId != null &&
      _targetUnitId != _sourceUnitId &&
      (_mode == 'newColumn' || _targetSection != null);

  Future<void> _confirmMove() async {
    if (!_canMove) return;
    final srcName =
        _units.firstWhere((u) => u.unit.id == _sourceUnitId).unit.name;
    final tgtName =
        _units.firstWhere((u) => u.unit.id == _targetUnitId).unit.name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Taşımayı Onayla'),
        content: Text(
          '"$srcName" reyonundan ${_sourceSections.length} sütun '
          '($_totalToMove ürün) "$tgtName" reyonuna '
          '${_mode == 'append' ? 'Sütun $_targetSection\'a ek olarak' : 'yeni sütun(lar) olarak'} '
          'taşınacak.\n\nFotoğraflar ve barkodlar korunur; kaynak sütunlar '
          'boşalır. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Taşı')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    int moved = 0;
    // Coklu sutun: her birini sirayla tasi. 'newColumn' modunda her kaynak
    // sutun hedefte AYRI yeni sutuna gider; 'append' modunda hepsi ayni
    // hedef sutuna alta eklenir.
    final sections = _sourceSections.toList()..sort();
    for (final srcSec in sections) {
      int tgtSec;
      if (_mode == 'append') {
        tgtSec = _targetSection!;
      } else {
        tgtSec =
            await ShelfLayoutService.instance.firstEmptySection(_targetUnitId!);
      }
      moved += await ShelfLayoutService.instance.moveColumn(
        sourceUnitId: _sourceUnitId!,
        sourceSection: srcSec,
        targetUnitId: _targetUnitId!,
        targetSection: tgtSec,
        mode: _mode,
      );
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$moved ürün taşındı.')),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // ── HERO ──
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(8, topPad + 8, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary,
                  Color.lerp(AppTheme.primary, AppTheme.accent, 0.45)!,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppTheme.rLg)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white),
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Toplu Sütun Taşı',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.white)),
                      Text('Sütundaki rafları başka reyona taşı',
                          style: TextStyle(
                              fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _units.length < 2
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Taşıma için en az iki reyon gerekir.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: AppTheme.textTertiary),
                          ),
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.fromLTRB(16, 16, 16,
                            bottomPad + 100),
                        children: [
                          _stepLabel('1', 'Kaynak reyon'),
                          const SizedBox(height: 8),
                          _unitDropdown(
                            value: _sourceUnitId,
                            onChanged: (v) {
                              if (v != null) _onSourceUnit(v);
                            },
                          ),
                          if (_sourceUnitId != null) ...[
                            const SizedBox(height: 16),
                            _stepLabel('2', 'Taşınacak sütun(lar)'),
                            const SizedBox(height: 8),
                            _sectionPicker(),
                          ],
                          if (_sourceSections.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _stepLabel('3', 'Hedef reyon'),
                            const SizedBox(height: 8),
                            _unitDropdown(
                              value: _targetUnitId,
                              exclude: _sourceUnitId,
                              onChanged: (v) => setState(() {
                                _targetUnitId = v;
                                _targetSection = null;
                              }),
                            ),
                          ],
                          if (_targetUnitId != null) ...[
                            const SizedBox(height: 16),
                            _stepLabel('4', 'Nasıl eklensin?'),
                            const SizedBox(height: 8),
                            _modePicker(),
                          ],
                        ],
                      ),
          ),
        ],
      ),
      bottomSheet: (_loading || _units.length < 2)
          ? null
          : Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(
                    top: BorderSide(color: AppTheme.hairline)),
              ),
              child: FilledButton.icon(
                onPressed: (_canMove && !_busy) ? _confirmMove : null,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.swap_horiz_rounded),
                label: Text(_sourceSections.isEmpty
                    ? 'Taşı'
                    : 'Taşı ($_totalToMove ürün)'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50)),
              ),
            ),
    );
  }

  Widget _stepLabel(String no, String label) => Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppTheme.primary, shape: BoxShape.circle),
            child: Text(no,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      );

  Widget _unitDropdown({
    required int? value,
    int? exclude,
    required ValueChanged<int?> onChanged,
  }) {
    final items = _units
        .where((u) => u.unit.id != exclude)
        .map((u) => DropdownMenuItem(
              value: u.unit.id,
              child: Text('${u.unit.name}  ·  ${u.itemCount} ürün',
                  overflow: TextOverflow.ellipsis),
            ))
        .toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: AppTheme.card(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isExpanded: true,
          hint: const Text('Reyon seçin'),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _sectionPicker() {
    final sections = _sectionCounts.keys.toList()..sort();
    if (sections.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(),
        child: Text('Bu reyonda ürünü olan sütun yok.',
            style: TextStyle(
                fontSize: 12.5, color: AppTheme.textTertiary)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sections.map((s) {
        final sel = _sourceSections.contains(s);
        final count = _sectionCounts[s] ?? 0;
        return InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          onTap: () => setState(() {
            if (sel) {
              _sourceSections.remove(s);
            } else {
              _sourceSections.add(s);
            }
          }),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sel
                  ? AppTheme.primary
                  : AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(AppTheme.rPill),
              border: Border.all(
                  color: sel
                      ? AppTheme.primary
                      : AppTheme.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    sel
                        ? Icons.check_circle_rounded
                        : Icons.view_column_rounded,
                    size: 16,
                    color: sel ? Colors.white : AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text('Sütun $s',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color:
                            sel ? Colors.white : AppTheme.textPrimary)),
                const SizedBox(width: 4),
                Text('($count)',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: sel
                            ? Colors.white70
                            : AppTheme.textTertiary)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _modePicker() {
    Widget opt(String mode, IconData icon, String title, String sub) {
      final sel = _mode == mode;
      return InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        onTap: () => setState(() {
          _mode = mode;
          if (mode == 'newColumn') _targetSection = null;
        }),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sel
                ? AppTheme.primary.withOpacity(0.10)
                : AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
                color:
                    sel ? AppTheme.primary : AppTheme.hairline),
          ),
          child: Row(
            children: [
              Icon(
                  sel
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color:
                      sel ? AppTheme.primary : AppTheme.textTertiary,
                  size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: sel
                                ? FontWeight.w800
                                : FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textTertiary)),
                  ],
                ),
              ),
              Icon(icon, color: AppTheme.textTertiary, size: 20),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        opt('newColumn', Icons.add_box_rounded, 'Yeni sütun olarak',
            'Hedef reyonda boş/yeni sütuna yerleşir; raf numaraları korunur'),
        opt('append', Icons.playlist_add_rounded, 'Mevcut sütuna ek olarak',
            'Seçilen hedef sütunun raflarının altına eklenir'),
        // 'append' modunda hedef sutun secimi.
        if (_mode == 'append') _targetSectionPicker(),
      ],
    );
  }

  Widget _targetSectionPicker() {
    final tgt = _units.firstWhere((u) => u.unit.id == _targetUnitId);
    final n = tgt.unit.sections;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hedef sütun',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(n, (i) => i + 1).map((s) {
              final sel = _targetSection == s;
              return InkWell(
                borderRadius: BorderRadius.circular(AppTheme.rPill),
                onTap: () => setState(() => _targetSection = s),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel
                        ? AppTheme.primary
                        : AppTheme.surfaceAlt,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: sel
                            ? AppTheme.primary
                            : AppTheme.hairline),
                  ),
                  child: Text('$s',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: sel
                              ? Colors.white
                              : AppTheme.textPrimary)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
