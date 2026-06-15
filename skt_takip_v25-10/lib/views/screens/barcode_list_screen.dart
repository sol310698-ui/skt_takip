import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';
import '../widgets/ui_kit.dart';
import 'barcode_detail_screen.dart';
import 'barcode_entry_screen.dart';
import 'import_screen.dart';
import 'label_inspect_screen.dart';

/// Barkod dizini liste ekrani (Excel'den import edilenler).
class BarcodeListScreen extends ConsumerStatefulWidget {
  final bool isActive;
  const BarcodeListScreen({super.key, this.isActive = true});

  @override
  ConsumerState<BarcodeListScreen> createState() =>
      _BarcodeListScreenState();
}

class _BarcodeListScreenState extends ConsumerState<BarcodeListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  List<BarcodeEntry> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BarcodeListScreen old) {
    super.didUpdateWidget(old);
    // Sekmeye geri donulunce listeyi yenile.
    if (widget.isActive && !old.isActive) {
      _load();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list =
        await ref.read(barcodeDirectoryRepositoryProvider).getAll();
    if (mounted) {
      setState(() {
        _all = list;
        _loading = false;
      });
    }
  }

  List<BarcodeEntry> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all
        .where((e) =>
            e.barcode.toLowerCase().contains(q) ||
            e.productName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const LoadingState()
                  : _all.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.only(
                                top: 8, bottom: 100),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, indent: 60),
                            itemBuilder: (context, i) =>
                                _tile(_filtered[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Manuel ekleme
          FloatingActionButton.small(
            heroTag: 'bc_add',
            onPressed: _openAddEntry,
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.black,
            child: const Icon(Icons.add_rounded),
          ),
          const SizedBox(height: 10),
          // Tarayarak ekleme
          FloatingActionButton.extended(
            heroTag: 'bc_scan',
            onPressed: _openScan,
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Tara'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: AppTheme.bannerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Barkod Listesi',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              IconButton(
                icon: const Icon(Icons.upload_file_outlined,
                    color: Colors.white),
                tooltip: 'Excel Import',
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ImportScreen()));
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${_all.length} kayıtlı barkod',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.85), fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Barkod veya ürün ara...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BarcodeEntry e) {
    return Dismissible(
      key: ValueKey('bc_${e.id}_${e.barcode}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppTheme.statusExpired,
          borderRadius: BorderRadius.circular(0),
        ),
        child: const Icon(Icons.delete_rounded,
            color: Colors.white, size: 26),
      ),
      confirmDismiss: (_) => _confirmDelete(e),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              const Icon(Icons.qr_code, color: AppTheme.primary, size: 22),
        ),
        title: Text(e.productName,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(e.barcode,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: AppTheme.textSecondary)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppTheme.textTertiary),
        onTap: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => BarcodeDetailScreen(entry: e),
            ),
          );
          if (changed == true) _load();
        },
      ),
    );
  }

  /// Silme onayi. Benzer barkod/ayni ad varsa ozel uyari gosterir.
  Future<bool> _confirmDelete(BarcodeEntry e) async {
    final similar = await ref
        .read(barcodeDirectoryRepositoryProvider)
        .countSimilar(
          excludeId: e.id ?? -1,
          productName: e.productName,
          barcode: e.barcode,
        );

    if (!mounted) return false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barkodu Sil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${e.productName}"\n${e.barcode}'),
            if (similar > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.statusWarning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppTheme.statusWarning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu ürünle aynı ad veya benzer barkoda sahip $similar kayıt daha var.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.statusExpired),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (ok == true && e.id != null) {
      await ref
          .read(barcodeDirectoryRepositoryProvider)
          .deleteById(e.id!);
      await _load();
      return true;
    }
    return false;
  }

  Widget _buildEmpty() {
    return EmptyState(
      icon: Icons.qr_code_2_rounded,
      title: 'Barkod listesi boş',
      subtitle: 'Excel ile barkod listesi yükleyin veya tarayarak ekleyin',
      action: FilledButton.icon(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ImportScreen()));
          _load();
        },
        icon: const Icon(Icons.upload_file),
        label: const Text('Excel Yükle'),
      ),
    );
  }

  Future<void> _openScan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LabelInspectScreen()),
    );
    _load();
  }

  /// Manuel barkod + ad girisi (BarcodeEntryScreen).
  Future<void> _openAddEntry() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BarcodeEntryScreen()),
    );
    if (added == true) _load();
  }
}
