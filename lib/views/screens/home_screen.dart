import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/export_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../../data/models/product.dart';
import '../../viewmodels/providers.dart';
import '../widgets/product_card.dart';
import '../widgets/speed_dial_fab.dart';
import '../widgets/ui_kit.dart';
import 'add_product_screen.dart';
import 'disposal_sheet.dart';
import 'label_inspect_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import 'web_search_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _exporting = false;
  bool _searchVisible = true; // asagi kaydirinca gizlenir

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    final dir = _scrollCtrl.position.userScrollDirection;
    // Asagi kaydiriliyor -> arama cubugunu gizle; yukari -> goster.
    if (dir == ScrollDirection.reverse && _searchVisible) {
      setState(() => _searchVisible = false);
    } else if (dir == ScrollDirection.forward && !_searchVisible) {
      setState(() => _searchVisible = true);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final filtered = ref.watch(filteredProductsProvider);

    return Scaffold(
      body: Column(
          children: [
            _buildBanner(),
            Expanded(
              child: productsAsync.when(
                loading: () => const LoadingState(),
                error: (e, _) => ErrorStateView(
                  message: 'Ürünler yüklenemedi',
                  onRetry: () =>
                      ref.read(productListProvider.notifier).refresh(),
                ),
                data: (products) {
                  final activeFilter = ref.watch(statusFilterProvider);
                  if (filtered.isEmpty &&
                      _searchCtrl.text.isEmpty &&
                      activeFilter == null) {
                    return Column(children: [
                      _buildStats(products),
                      Expanded(child: _buildEmpty())
                    ]);
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(productListProvider.notifier).refresh(),
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.only(top: 4, bottom: 100),
                      itemCount: _buildSectionedItems(filtered).length + 2,
                      itemBuilder: (context, i) {
                        if (i == 0) return _buildStats(products);
                        if (i == 1) return _buildFilterBanner(activeFilter);
                        final item = _buildSectionedItems(filtered)[i - 2];
                        if (item is _SectionHeader) {
                          return _buildGroupHeader(item.label, item.color);
                        }
                        final product = item as Product;
                        return ProductCard(
                          product: product,
                          onDelete: () => _confirmDelete(product),
                          onTap: () => _openEditSheet(product),
                          onDispose: () => _openDisposalSheet(product),
                          onSearch: product.barcode == null
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => WebSearchScreen(
                                          query: product.barcode!),
                                    ),
                                  ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.endFloat,
      floatingActionButton: SpeedDialFab(
        actions: [
          SpeedDialAction(
            icon: Icons.document_scanner_rounded,
            label: 'Etiket Tara',
            color: AppTheme.accent,
            onTap: _openLabelInspect,
          ),
          SpeedDialAction(
            icon: Icons.event_available_rounded,
            label: 'SKT Tara',
            color: AppTheme.primary,
            onTap: _openScanner,
          ),
        ],
      ),
    );
  }

  Widget _buildBanner() {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16 + topInset, 20, 20),
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
                  // Ayarlar (eski 5 ikon buraya toplandı)
                  _BannerIconBtn(
                    icon: Icons.settings_rounded,
                    tooltip: 'Ayarlar',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
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
          // Arama cubugu: asagi kaydirinca gizlenir (AnimatedSize ile).
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _searchVisible
                ? Column(
                    children: [
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (v) => ref
                                  .read(searchQueryProvider.notifier)
                                  .state = v,
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
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(List<Product> products) {
    final expired = products.where((p) => p.daysUntilExpiry < 0).length;
    final critical = products
        .where((p) =>
            p.daysUntilExpiry >= 0 &&
            p.daysUntilExpiry <= AppConstants.criticalDays)
        .length;
    final warning = products
        .where((p) =>
            p.daysUntilExpiry > AppConstants.criticalDays &&
            p.daysUntilExpiry <= AppConstants.warningDays)
        .length;

    final activeFilter = ref.watch(statusFilterProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _filterTile(
              label: 'Doldu',
              count: expired,
              color: AppTheme.statusExpired,
              icon: Icons.dangerous_rounded,
              status: ExpiryStatus.expired,
              active: activeFilter == ExpiryStatus.expired,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _filterTile(
              label: 'Kritik',
              count: critical,
              color: AppTheme.statusCritical,
              icon: Icons.warning_rounded,
              status: ExpiryStatus.critical,
              active: activeFilter == ExpiryStatus.critical,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _filterTile(
              label: 'Yaklaşan',
              count: warning,
              color: AppTheme.statusWarning,
              icon: Icons.schedule_rounded,
              status: ExpiryStatus.warning,
              active: activeFilter == ExpiryStatus.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterTile({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    required ExpiryStatus status,
    required bool active,
  }) {
    return GestureDetector(
      onTap: () {
        // Zaten aktifse filtre kaldir; degilse uygula.
        final notifier = ref.read(statusFilterProvider.notifier);
        notifier.state = active ? null : status;
        // Filtre degisince arama metnini temizle.
        if (!active) ref.read(searchQueryProvider.notifier).state = '';
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.18) : AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          border: Border.all(
            color: active ? color : color.withOpacity(0.3),
            width: active ? 1.5 : 1,
          ),
          boxShadow: active ? AppTheme.glow(color) : AppTheme.shadowSm,
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text('$count',
                style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
            if (active) ...[
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text('Filtreli',
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroupHeader(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Urunleri durum gruplarina ayirir: [Header, Product, Product, Header, ...]
  List<dynamic> _buildSectionedItems(List<Product> products) {
    final sections = <_SectionDef>[
      _SectionDef('Süresi Doldu', ExpiryStatus.expired,
          AppTheme.statusExpired),
      _SectionDef('Kritik (≤3 gün)', ExpiryStatus.critical,
          AppTheme.statusCritical),
      _SectionDef('Yaklaşan (≤7 gün)', ExpiryStatus.warning,
          AppTheme.statusWarning),
      _SectionDef('Güvenli', ExpiryStatus.safe, AppTheme.statusSafe),
    ];
    final result = <dynamic>[];
    for (final section in sections) {
      final items =
          products.where((p) => p.status == section.status).toList();
      if (items.isEmpty) continue;
      result.add(_SectionHeader(section.label, section.color));
      result.addAll(items);
    }
    return result;
  }

  Widget _buildFilterBanner(ExpiryStatus? filter) {
    if (filter == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: filter.color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(color: filter.color.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.filter_list_rounded,
                color: filter.color, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${filter.label} filtresi aktif',
                style: TextStyle(
                    color: filter.color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600),
              ),
            ),
            GestureDetector(
              onTap: () =>
                  ref.read(statusFilterProvider.notifier).state = null,
              child: Icon(Icons.close_rounded,
                  color: filter.color, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const EmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'Henüz ürün yok',
      subtitle: 'SKT taramak için aşağıdaki "SKT Tara" butonunu kullanın',
    );
  }

  void _openBackupMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('Veri Yedekleme',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Yedek alarak verilerinizi koruyun.',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await BackupService.instance.exportDb();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Yedek alınamadı: $e')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.cloud_upload_rounded),
              label: const Text('Yedek Al'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                // Dosya secimi — kullaniciya yol soruluyor.
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Geri Yükle'),
                    content: const Text(
                      'Mevcut tüm veriler silinip yedeğinizle değiştirilecek. '
                      'Devam etmek istiyor musunuz?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('İptal'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.statusExpired),
                        child: const Text('Geri Yükle'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Yedek dosyasının yolunu dosya yöneticisinden kopyalayıp '
                      'BackupService.instance.importDb(yol) ile çağırın.',
                    ),
                    duration: Duration(seconds: 4),
                  ),
                );
              },
              icon: const Icon(Icons.cloud_download_rounded),
              label: const Text('Yedekten Geri Yükle'),
            ),
          ],
        ),
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
    // Arama kutusundaki degeri tasi: barkod formatindaysa barkod alanina,
    // degilse urun adi alanina koy (ad yazip ekle deyince barkod kirlenmez).
    final searchText = _searchCtrl.text.trim();
    String? prefillBarcode;
    String? prefillName;

    if (searchText.isNotEmpty) {
      if (ScanResult.looksLikeBarcode(searchText)) {
        // Barkod: ad aramasini form ekrani (akilli) kendisi yapacak.
        prefillBarcode = searchText;
      } else {
        prefillName = searchText;
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(
          prefillBarcode: prefillBarcode,
          prefillName: prefillName,
        ),
      ),
    );
  }

  Future<void> _openEditSheet(Product product) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(existing: product),
      ),
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

  Future<void> _openLabelInspect() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LabelInspectScreen()),
    );
  }

  Future<void> _openScanner() async {
    final result = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (result == null || !mounted) return;
    final scanned = result.year == 1900 ? null : result;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(scannedExpiry: scanned),
      ),
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
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
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

class _SectionHeader {
  final String label;
  final Color color;
  _SectionHeader(this.label, this.color);
}

class _SectionDef {
  final String label;
  final ExpiryStatus status;
  final Color color;
  _SectionDef(this.label, this.status, this.color);
}
