import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';
import 'web_search_screen.dart';

/// Barkod liste oge detay sayfasi.
/// - Urun adi VERITABANINDAN (dizinden) gelir.
/// - Gorsel + ek bilgi (kategori/miktar) Open Food Facts'ten cekilir.
/// - Duzenle / Sil aksiyonlari altta sabit.
class BarcodeDetailScreen extends ConsumerStatefulWidget {
  final BarcodeEntry entry;
  const BarcodeDetailScreen({super.key, required this.entry});

  @override
  ConsumerState<BarcodeDetailScreen> createState() =>
      _BarcodeDetailScreenState();
}

class _BarcodeDetailScreenState extends ConsumerState<BarcodeDetailScreen> {
  late BarcodeEntry _entry;
  bool _loadingWeb = true;
  String? _imageUrl;
  String? _category;
  String? _quantity;
  bool _changed = false; // geri donerken listeyi yenilemek icin

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _fetchWeb();
  }

  /// OFF'tan gorsel + ek bilgi. Ad'a dokunmaz (o veritabanindan).
  Future<void> _fetchWeb() async {
    try {
      final r =
          await BarcodeLookupService.instance.lookupDetailed(_entry.barcode);
      if (!mounted) return;
      setState(() {
        _imageUrl = r.imageUrl;
        _category = r.category;
        _quantity = r.quantity;
        _loadingWeb = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingWeb = false);
    }
  }

  Future<void> _edit() async {
    final nameCtrl = TextEditingController(text: _entry.productName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ürün Adını Düzenle'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ürün adı'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;

    // UPSERT (ayni barkod -> uzerine yazar).
    await ref.read(barcodeDirectoryRepositoryProvider).importAll([
      BarcodeEntry(
        barcode: _entry.barcode,
        productName: result,
        importedAt: DateTime.now(),
      ),
    ]);
    if (mounted) {
      setState(() {
        _entry = BarcodeEntry(
          id: _entry.id,
          barcode: _entry.barcode,
          productName: result,
          importedAt: DateTime.now(),
        );
        _changed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncellendi')),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sil'),
        content: Text('"${_entry.productName}" listeden silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: AppTheme.statusExpired),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true && _entry.id != null) {
      await ref
          .read(barcodeDirectoryRepositoryProvider)
          .deleteById(_entry.id!);
      if (mounted) Navigator.of(context).pop(true); // silindi -> yenile
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: CustomScrollView(
          slivers: [
            _buildHeader(),
            SliverToBoxAdapter(child: _buildBody()),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildHeader() {
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(_changed),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(gradient: AppTheme.bannerGradient),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Buyuk gorsel (OFF)
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.4), width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _loadingWeb
                          ? const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              ),
                            )
                          : (_imageUrl != null
                              ? Image.network(
                                  _imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _ph(),
                                  loadingBuilder: (c, w, p) =>
                                      p == null ? w : _ph(),
                                )
                              : _ph()),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _entry.productName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ph() => const Icon(Icons.inventory_2_rounded,
      color: Colors.white, size: 52);

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barkod karti
          _infoCard(
            icon: Icons.qr_code_rounded,
            label: 'Barkod',
            value: _entry.barcode,
            monospace: true,
            trailing: IconButton(
              icon: const Icon(Icons.search, color: AppTheme.accent),
              tooltip: "Google'da Ara",
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WebSearchScreen(query: _entry.barcode),
                ),
              ),
            ),
          ),
          if (_category != null && _category!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.category_rounded,
              label: 'Kategori',
              value: _category!,
            ),
          ],
          if (_quantity != null && _quantity!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.straighten_rounded,
              label: 'Miktar / Ağırlık',
              value: _quantity!,
            ),
          ],
          if (!_loadingWeb &&
              _imageUrl == null &&
              _category == null &&
              _quantity == null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.card(),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppTheme.textTertiary, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bu barkod için internette ek bilgi/görsel bulunamadı.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
    bool monospace = false,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: monospace ? 'monospace' : null)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.statusExpired,
                    side: const BorderSide(color: AppTheme.statusExpired),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Sil'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _edit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Düzenle',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
