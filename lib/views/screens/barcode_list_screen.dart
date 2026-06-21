import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/nav_bar_visibility.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';
import '../widgets/ui_kit.dart';
import 'barcode_detail_screen.dart';
import 'barcode_entry_screen.dart';
import 'import_screen.dart';

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
  final ScrollController _scrollCtrl = ScrollController();
  String _query = '';
  List<BarcodeEntry> _all = [];
  bool _loading = true;
  bool _searchVisible = true; // asagi kaydirinca gizlenir

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load();
  }

  void _onScroll() {
    final dir = _scrollCtrl.position.userScrollDirection;
    if (dir == ScrollDirection.reverse && _searchVisible) {
      setState(() => _searchVisible = false);
    } else if (dir == ScrollDirection.forward && !_searchVisible) {
      setState(() => _searchVisible = true);
    }
    handleNavBarScroll(_scrollCtrl);
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
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
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
            e.productName.toLowerCase().contains(q) ||
            (e.stockCode?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemBarForColor(AppTheme.primary),
      child: Scaffold(
        body: Column(
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
                              controller: _scrollCtrl,
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
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 78),
          child: FloatingActionButton.extended(
            heroTag: 'bc_add_single',
            onPressed: _openAddEntry,
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Manuel Ekle',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16 + topInset, 20, 16),
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
              // Baslik + kayit sayisi yan yana (alan kazanmak icin).
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text('Barkod Listesi',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    Text('${_all.length} kayıt',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
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
          // Arama: asagi kaydirinca gizlenir.
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _searchVisible
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Barkod, ürün veya stok kodu ara...',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
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
        subtitle: Text(
            e.stockCode != null && e.stockCode!.isNotEmpty
                ? '${e.barcode}  •  Stok: ${e.stockCode}'
                : e.barcode,
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: AppTheme.textSecondary)),
        trailing: Icon(Icons.chevron_right_rounded,
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

  /// Manuel barkod + ad girisi (BarcodeEntryScreen).
  Future<void> _openAddEntry() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BarcodeEntryScreen()),
    );
    if (added == true) _load();
  }
}
