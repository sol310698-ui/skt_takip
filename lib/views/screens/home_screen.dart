import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/export_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/nav_bar_visibility.dart';
import '../../core/utils/scan_parser.dart';
import '../../data/models/product.dart';
import '../../viewmodels/providers.dart';
import '../widgets/product_card.dart';
import '../widgets/smart_day_strip.dart';
import '../widgets/scroll_to_top_fab.dart';
import '../widgets/speed_dial_fab.dart';
import '../widgets/ui_kit.dart';
import 'add_product_screen.dart';
import 'disposal_sheet.dart';
import 'label_inspect_screen.dart';
import 'label_print_screen.dart';
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
  final FocusNode _searchFocus = FocusNode();
  bool _exporting = false;
  bool _searchVisible = true; // asagi kaydirinca gizlenir
  // Liste giris animasyonu: sadece ekran ACILIRKEN kartlar sirayla
  // (staggered) belirir. Sonrasinda (scroll, filtre degisimi vb.) tekrar
  // oynatilmaz — yoksa her scroll'da kartlar yanip soner (kotu UX).
  bool _listEntryAnimDone = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    // Klavye odakta oldugu surece arama kutusunu HER ZAMAN gorunur tut.
    // BUG FIX: klavye acilip kapanirken ListView'in boyutu degisir, bu da
    // bazen sahte bir scroll-yonu sinyali uretip arama cubugunu
    // gizleyip/tekrar gosterebiliyordu (klavye kapaninca cubuk "geri
    // geliyor" gibi gorunen hata). Focus'ta iken bu mantigi devre disi
    // birakarak bunu onluyoruz.
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus && !_searchVisible) {
        setState(() => _searchVisible = true);
      }
    });
    // Liste giris animasyonunun oynayacagi pencere (ekran acilisinda
    // gorunen kartlar icin yeterli sure); sonra bayrak kapanir ve
    // itemBuilder bir daha animasyon eklemez.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _listEntryAnimDone = true);
    });
  }

  void _onScroll() {
    // Klavye aciksa (arama kutusu odakta) scroll'a bagli gizle/goster
    // mantigini calistirma — klavye acilip kapanirken olusan sahte scroll
    // sinyalleri arama cubugunu istemsizce gizleyip geri getirebiliyordu.
    if (_searchFocus.hasFocus) return;

    final dir = _scrollCtrl.position.userScrollDirection;
    // Asagi kaydiriliyor -> arama cubugunu gizle; yukari -> goster.
    if (dir == ScrollDirection.reverse && _searchVisible) {
      setState(() => _searchVisible = false);
    } else if (dir == ScrollDirection.forward && !_searchVisible) {
      setState(() => _searchVisible = true);
    }
    // Nav bar'i da ayni yonde gizle/goster.
    handleNavBarScroll(_scrollCtrl);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final filtered = ref.watch(filteredProductsProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemBarForColor(AppTheme.primary),
      child: Scaffold(
        body: Stack(
          children: [
            Column(
            children: [
              _buildBanner(),
              // AKILLI GUN: bugunku isler tek bakista (SKT/etiket/vardiya).
              const SmartDayStrip(),
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
                    // PERFORMANS: sectioned liste BIR KERE hesaplanir,
                    // itemBuilder icinde DEGIL (orada her satir icin
                    // yeniden cagrilirsa O(N^2) olur ve listede kasmaya
                    // yol acar). 'data' closure'i zaten her build'de bir
                    // kez calistigi icin ekstra Builder widget'ina gerek
                    // yok.
                    final sectioned = _buildSectionedItems(filtered);
                    return RefreshIndicator(
                      onRefresh: () =>
                          ref.read(productListProvider.notifier).refresh(),
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.only(top: 4, bottom: 100),
                        itemCount: sectioned.length + 2,
                        itemBuilder: (context, i) {
                          if (i == 0) return _buildStats(products);
                          if (i == 1) {
                            return _buildFilterBanner(activeFilter);
                          }
                          final item = sectioned[i - 2];
                          if (item is _SectionHeader) {
                            return _buildGroupHeader(
                                item.label, item.color);
                          }
                          final product = item as Product;
                          final card = ProductCard(
                            key: ValueKey(product.id),
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
                          // SOV ANIMASYONU: ekran acilirken kartlar
                          // sirayla (staggered) hafifce asagidan yukari
                          // belirir. Sadece ilk acilis penceresinde
                          // (_listEntryAnimDone false) uygulanir; sonra
                          // duz kart donulur (scroll'da tekrar oynamasin).
                          if (_listEntryAnimDone) return card;
                          return card
                              .animate(delay: (i * 35).ms)
                              .fadeIn(duration: 320.ms, curve: Curves.easeOut)
                              .slideY(
                                  begin: 0.08,
                                  end: 0,
                                  duration: 320.ms,
                                  curve: Curves.easeOutCubic);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
            // Speed-dial FAB (Stack icinde - tum ekrani kaplayabilir).
            SpeedDialFab(
              actions: [
                SpeedDialAction(
                  icon: Icons.print_rounded,
                  label: 'Etiket Bas',
                  color: AppTheme.primaryDark,
                  onTap: _openLabelPrint,
                ),
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
            // Sol altta: yukari cik FAB. Cok kaydirinca belirir, nav bar
            // gizlenince (asagi kaydirinca) o da senkron asagi iner.
            ScrollToTopFab(
              controller: _scrollCtrl,
              baseBottomPadding: 108,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner() {
    final topInset = MediaQuery.of(context).padding.top;
    return AuroraBackground(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 16 + topInset, 20, 20),
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
                              focusNode: _searchFocus,
                              textInputAction: TextInputAction.search,
                              // Disari dokununca klavye kapanir VE imlec
                              // kaybolur (focus birakilir). Boylece baska
                              // ekrandan geri donunce klavye kendiliginden
                              // acilmaz.
                              onTapOutside: (_) => _searchFocus.unfocus(),
                              onSubmitted: (_) => _searchFocus.unfocus(),
                              onChanged: (v) => ref
                                  .read(searchQueryProvider.notifier)
                                  .state = v,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Ürün veya barkod ara...',
                                hintStyle:
                                    TextStyle(color: Colors.white.withOpacity(0.7)),
                                prefixIcon: const Icon(Icons.search,
                                    color: Colors.white),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.16),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                      color:
                                          Colors.white.withOpacity(0.35)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                      color:
                                          Colors.white.withOpacity(0.35)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(
                                      color: Colors.white, width: 1.6),
                                ),
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
      ),
    );
  }

  Widget _buildStats(List<Product> products) {
    // PERFORMANS: tek geciste say (3 ayri .where() taramasi yerine).
    int expired = 0, critical = 0, warning = 0;
    for (final p in products) {
      final days = p.daysUntilExpiry;
      if (days < 0) {
        expired++;
      } else if (days <= AppConstants.criticalDays) {
        critical++;
      } else if (days <= AppConstants.warningDays) {
        warning++;
      }
    }

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
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? color.withOpacity(0.20)
              : AppTheme.glassTint.withOpacity(AppTheme.glassOpacity),
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          border: Border.all(
            color: active
                ? color
                : Colors.white.withOpacity(AppTheme.isLight ? 0.7 : 0.08),
            width: active ? 1.5 : 1.2,
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
            // Sayi degisince hafif scale+fade ile gecis yapar (yeni bir
            // urun eklenip/silinip sayac guncellendiginde fark edilir).
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: CurvedAnimation(
                    parent: anim, curve: Curves.easeOutBack),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Text('$count',
                  key: ValueKey(count),
                  style: TextStyle(
                      color: color,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1)),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
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
  /// PERFORMANS: tek geciste (O(N)) durumlara gore gruplar. Eskiden her
  /// durum icin ayri .where() taramasi yapiliyordu (O(4N)); buyuk
  /// listelerde (100+ urun) bu fark scroll/kasma uzerinde hissedilir.
  List<dynamic> _buildSectionedItems(List<Product> products) {
    final byStatus = <ExpiryStatus, List<Product>>{};
    for (final p in products) {
      (byStatus[p.status] ??= <Product>[]).add(p);
    }

    const sections = <_SectionDef>[
      _SectionDef(
          'Süresi Doldu', ExpiryStatus.expired, AppTheme.statusExpired),
      _SectionDef(
          'Kritik (≤3 gün)', ExpiryStatus.critical, AppTheme.statusCritical),
      _SectionDef(
          'Yaklaşan (≤7 gün)', ExpiryStatus.warning, AppTheme.statusWarning),
      _SectionDef('Güvenli', ExpiryStatus.safe, AppTheme.statusSafe),
    ];

    final result = <dynamic>[];
    for (final section in sections) {
      final items = byStatus[section.status];
      if (items == null || items.isEmpty) continue;
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
        decoration: BoxDecoration(
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
            Text(
              'Yedek alarak verilerinizi koruyun.',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await BackupService.instance.exportAll();
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
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final res =
                      await FilePicker.platform.pickFiles(type: FileType.any);
                  if (res != null && res.files.single.path != null) {
                    messenger.showSnackBar(const SnackBar(
                        duration: Duration(minutes: 5),
                        content: Text('Geri yükleniyor…')));
                    await BackupService.instance.restoreAll(
                      res.files.single.path!,
                      onProgress: (s) {
                        messenger.clearSnackBars();
                        messenger.showSnackBar(SnackBar(
                            duration: const Duration(minutes: 5),
                            content: Text(s)));
                      },
                    );
                    messenger.clearSnackBars();
                    if (mounted) {
                      messenger.showSnackBar(const SnackBar(
                          content: Text(
                              'Geri yüklendi. Uygulamayı yeniden başlatın.')));
                    }
                  }
                } catch (e) {
                  messenger.clearSnackBars();
                  if (mounted) {
                    messenger.showSnackBar(
                        SnackBar(content: Text('Geri yükleme hatası: $e')));
                  }
                }
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

  Future<void> _openLabelPrint() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LabelPrintScreen()),
    );
  }

  /// SKT Tara akisi: ÖNCE barkod taranir, SONRA SKT (son kullanma tarihi)
  /// tarama ekranina gecilir, form acilir ve KAYDEDILDIKTEN SONRA otomatik
  /// olarak tekrar barkod taramaya doner — bu sekilde art arda birden
  /// fazla urun, ana ekrana hic donmeden zincirleme taranabilir (dongu).
  /// Dongu, kullanici barkod ekraninda geri/kapat tusuna basip barkod
  /// taramadan cikinca (sonuc null donunce) sona erer.
  Future<void> _openScanner() async {
    while (true) {
      // Adim 1: Once barkod tara.
      if (!mounted) return;
      final barcode = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
      );
      if (!mounted) return;
      if (barcode == null) {
        // Kullanici barkod ekranindan geri/kapat ile cikti -> dongu biter.
        return;
      }

      // Adim 2: Sonra SKT (son kullanma tarihi) tarama ekranina gec.
      final outcome = await Navigator.of(context).push<ScanOutcome>(
        MaterialPageRoute(
          builder: (_) => ScannerScreen(prefillBarcode: barcode),
        ),
      );
      if (!mounted) return;
      if (outcome == null) {
        // SKT ekranindan da geri cikildi -> dongu biter (barkoda donmez).
        return;
      }
      final scanned = outcome.date.year == 1900 ? null : outcome.date;

      // Adim 3: Barkod + SKT tarihi + (varsa) etiket fotografi birlikte
      // forma gonderilir. Urun adi barkod aramasindan bulunamazsa, form
      // bu fotografi kullanarak OCR ile adi otomatik cikarmayi deneyebilir.
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ProductFormScreen(
            scannedExpiry: scanned,
            prefillBarcode: barcode,
            labelPhotoPath: outcome.labelPhotoPath,
          ),
        ),
      );
      if (!mounted) return;
      if (saved != true) {
        // Kullanici formu kaydetmeden kapatti (iptal) -> dongu biter.
        return;
      }
      // Kayit basarili: while donerek otomatik tekrar barkod taramaya
      // gec (form zaten kapandi, ekstra onay gosterilmiyor).
    }
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
      backgroundColor: Colors.black,
      // Kamera onizlemesi status bar arkasina kadar uzansin.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Barkod ile Ara'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
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
  const _SectionDef(this.label, this.status, this.color);
}
