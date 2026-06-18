import 'package:flutter/material.dart';

import '../../core/services/checklist_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/checklist.dart';

/// Tek bir kontrol listesinin maddeleri — isaretleme, ekleme, silme.
class ChecklistDetailScreen extends StatefulWidget {
  final Checklist checklist;
  const ChecklistDetailScreen({super.key, required this.checklist});

  @override
  State<ChecklistDetailScreen> createState() =>
      _ChecklistDetailScreenState();
}

class _ChecklistDetailScreenState extends State<ChecklistDetailScreen> {
  List<ChecklistItem> _items = [];
  bool _loading = true;

  Color get _color =>
      widget.checklist.color != null
          ? Color(widget.checklist.color!)
          : AppTheme.primary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final id = widget.checklist.id;
      if (id == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final items = await ChecklistService.instance.getItems(id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      // Hata olsa bile donen simge takili kalmasin.
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Liste yüklenemedi: $e')),
        );
      }
    }
  }

  int get _doneCount => _items.where((e) => e.done).length;

  Future<void> _toggle(ChecklistItem item) async {
    await ChecklistService.instance.toggleItem(item.id!, !item.done);
    await _load();
  }

  Future<void> _addItem() async {
    final text = await _showItemDialog();
    if (text == null || text.trim().isEmpty) return;
    await ChecklistService.instance.addItem(widget.checklist.id!, text.trim());
    await _load();
  }

  Future<void> _editItem(ChecklistItem item) async {
    final text = await _showItemDialog(initial: item.text);
    if (text == null || text.trim().isEmpty) return;
    await ChecklistService.instance.updateItemText(item.id!, text.trim());
    await _load();
  }

  Future<String?> _showItemDialog({String? initial}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? 'Yeni Madde' : 'Maddeyi Düzenle'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Madde metni'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İşaretleri temizle?'),
        content: const Text(
            'Tüm maddelerin işareti kaldırılacak (maddeler silinmez). Yeni gün için listeyi sıfırlamak istediğine emin misin?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ChecklistService.instance.resetItems(widget.checklist.id!);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _items.isEmpty ? 0.0 : _doneCount / _items.length;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.checklist.title),
        backgroundColor: _color,
        foregroundColor: Colors.white,
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded),
              tooltip: 'İşaretleri temizle',
              onPressed: _resetAll,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItem,
        backgroundColor: _color,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          // Ilerleme ozeti
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            color: _color.withOpacity(0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _items.isEmpty
                      ? 'Madde ekleyerek başla'
                      : '$_doneCount / ${_items.length} tamamlandı',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _color),
                ),
                if (_items.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: AppTheme.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(_color),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? _buildEmpty()
                    : ListView.separated(
                        padding:
                            const EdgeInsets.fromLTRB(12, 12, 12, 100),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) => _itemTile(_items[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(ChecklistItem item) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.coral,
          borderRadius: BorderRadius.circular(AppTheme.rLg),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) async {
        await ChecklistService.instance.deleteItem(item.id!);
        await _load();
      },
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          onTap: () => _toggle(item),
          onLongPress: () => _editItem(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: item.done ? _color : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: item.done ? _color : AppTheme.textTertiary,
                      width: 2,
                    ),
                  ),
                  child: item.done
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 18)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.text,
                    style: TextStyle(
                      fontSize: 15.5,
                      color: item.done
                          ? AppTheme.textTertiary
                          : AppTheme.textPrimary,
                      decoration: item.done
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: AppTheme.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
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
            Icon(Icons.playlist_add_rounded,
                size: 60, color: AppTheme.textTertiary),
            const SizedBox(height: 14),
            const Text('Madde yok',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Sağ alttaki + ile madde ekle.',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}
