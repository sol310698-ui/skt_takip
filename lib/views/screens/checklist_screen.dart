import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/services/checklist_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/checklist.dart';
import 'checklist_detail_screen.dart';

/// Kontrol listeleri ana ekrani — oturumlar (listeler) burada listelenir.
/// Kullanici yeni liste olusturabilir, acabilir, silebilir.
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  List<ChecklistWithCount> _lists = [];
  bool _loading = true;

  // Yeni liste icin secilebilir renkler.
  static const _palette = [
    AppTheme.primary,
    AppTheme.accent,
    AppTheme.amber,
    AppTheme.coral,
    AppTheme.statusSafe,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final lists = await ChecklistService.instance.getAllWithCounts();
    if (!mounted) return;
    setState(() {
      _lists = lists;
      _loading = false;
    });
  }

  Future<void> _createList() async {
    final res = await _showCreateSheet();
    if (res == null) return;
    await ChecklistService.instance.createList(res.$1, color: res.$2);
    await _load();
  }

  /// Yeni liste olusturma sheet'i (baslik + renk). (title, color) doner.
  Future<(String, int)?> _showCreateSheet() async {
    final ctrl = TextEditingController();
    int selectedColor = _palette.first.value;
    return showModalBottomSheet<(String, int)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppTheme.textTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('Yeni Liste',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Liste adı (örn. Sabah Yapılacaklar)',
                    prefixIcon: Icon(Icons.checklist_rounded),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (final c in _palette)
                      GestureDetector(
                        onTap: () =>
                            setSheet(() => selectedColor = c.value),
                        child: Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selectedColor == c.value
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: selectedColor == c.value
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 18)
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () {
                    final t = ctrl.text.trim();
                    if (t.isEmpty) return;
                    Navigator.of(ctx).pop((t, selectedColor));
                  },
                  child: const Text('Oluştur'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Checklist cl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Listeyi sil?'),
        content: Text(
            '"${cl.title}" listesi ve tüm maddeleri silinecek. Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.coral),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true && cl.id != null) {
      await ChecklistService.instance.deleteList(cl.id!);
      await _load();
    }
  }

  Future<void> _open(Checklist cl) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChecklistDetailScreen(checklist: cl),
    ));
    _load(); // donunce sayilari guncelle
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createList,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Yeni Liste',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _lists.isEmpty
                    ? _buildEmpty()
                    : ListView.separated(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: _lists.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) => _listCard(_lists[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 16 + topInset, 20, 22),
      decoration: const BoxDecoration(
        gradient: AppTheme.bannerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kontrol Listeleri',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('${_lists.length} liste',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.8), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _listCard(ChecklistWithCount item) {
    final cl = item.checklist;
    final color = cl.color != null ? Color(cl.color!) : AppTheme.primary;
    final allDone = item.total > 0 && item.done == item.total;
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        onTap: () => _open(cl),
        onLongPress: () => _confirmDelete(cl),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rLg),
            border: Border.all(color: color.withOpacity(0.35), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      allDone
                          ? Icons.check_circle_rounded
                          : Icons.checklist_rounded,
                      color: color,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cl.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                          item.total == 0
                              ? 'Henüz madde yok'
                              : '${item.done}/${item.total} tamamlandı',
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textTertiary),
                ],
              ),
              if (item.total > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: item.progress,
                    minHeight: 6,
                    backgroundColor: AppTheme.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rtl_rounded,
                size: 64, color: AppTheme.textTertiary),
            const SizedBox(height: 16),
            const Text('Henüz liste yok',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Sabah yapılacaklar, açılış kontrolü, kapanış kontrolü gibi listeler oluştur. Her liste ayrı bir oturumdur.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.textSecondary,
                  height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
