import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/export_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/product.dart';
import '../../viewmodels/providers.dart';
import '../widgets/product_card.dart';
import 'add_product_screen.dart';
import 'disposal_sheet.dart';
import 'history_screen.dart';
import 'import_screen.dart';
import 'scanner_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _exporting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final filtered = ref.watch(filteredProductsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildBanner(),
            Expanded(
              child: productsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Hata: $e')),
                data: (_) {
                  if (filtered.isEmpty) return _buildEmpty();
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(productListProvider.notifier).refresh(),
                    child: ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 100),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final product = filtered[i];
                        return ProductCard(
                          product: product,
                          onDelete: () => _confirmDelete(product),
                          onTap: () => _openEditSheet(product),
                          onDispose: () => _openDisposalSheet(product),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScanner,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('SKT Tara'),
      ),
    );
  }

  Widget _buildBanner() {
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
              const Text(
                AppConstants.appName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Row(
                children: [
                  // Excel Export
                  _BannerIconBtn(
                    icon: _exporting
                        ? Icons.hourglass_empty
                        : Icons.table_chart_outlined,
                    tooltip: 'Excel Export',
                    onTap: _exporting ? null : _export,
                  ),
                  // Gecmis
                  _BannerIconBtn(
                    icon: Icons.history,
                    tooltip: 'İmha & İade Geçmişi',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const HistoryScreen()),
                    ),
                  ),
                  // Excel Import
                  _BannerIconBtn(
                    icon: Icons.upload_file_outlined,
                    tooltip: 'Barkod Import',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ImportScreen()),
                    ),
                  ),
                  // Yeni urun
                  _BannerIconBtn(
                    icon: Icons.add,
                    tooltip: 'Yeni Ürün',
                    onTap: () => _openAddSheet(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      ref.read(searchQueryProvider.notifier).state = v,
                  decoration: const InputDecoration(
                    hintText: 'Ürün veya barkod ara...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _scanBarcodeForSearch,
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Icon(Icons.qr_code_scanner,
                        color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 64, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text('Henüz ürün yok',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 16)),
          SizedBox(height: 4),
          Text('SKT taramak için aşağıdaki butonu kullan',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final repo = ref.read(productRepositoryProvider);
      final active = await repo.getProducts();
      final history = await repo.getDisposalHistory();
      await ExportService.instance.exportToExcel(
        activeProducts: active,
        historyProducts: history,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export hatası: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _scanBarcodeForSearch() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _BarcodeSearchPage()),
    );
    if (code != null && mounted) {
      _searchCtrl.text = code;
      ref.read(searchQueryProvider.notifier).state = code;
    }
  }

  Future<void> _openAddSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProductFormSheet(),
    );
  }

  Future<void> _openEditSheet(Product product) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductFormSheet(existing: product),
    );
  }

  Future<void> _openDisposalSheet(Product product) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DisposalSheet(product: product),
    );
  }

  Future<void> _openScanner() async {
    final result = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (result == null || !mounted) return;
    final scanned = result.year == 1900 ? null : result;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductFormSheet(scannedExpiry: scanned),
    );
  }

  Future<void> _confirmDelete(Product product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sil'),
        content: Text('"${product.name}" kalıcı olarak silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true && product.id != null) {
      await ref.read(productListProvider.notifier).remove(product.id!);
    }
  }
}

/// Banner ikon butonu yardimcisi.
class _BannerIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _BannerIconBtn(
      {required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}

/// Sadece arama icin barkod okutan hafif sayfa.
class _BarcodeSearchPage extends StatefulWidget {
  const _BarcodeSearchPage();

  @override
  State<_BarcodeSearchPage> createState() => _BarcodeSearchPageState();
}

class _BarcodeSearchPageState extends State<_BarcodeSearchPage> {
  final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barkod ile Ara')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          Container(
            width: 260, height: 140,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const Positioned(
            bottom: 60,
            child: Text('Barkodu okutunca arama yapılır',
                style: TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
