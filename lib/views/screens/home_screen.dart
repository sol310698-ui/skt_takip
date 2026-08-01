import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants/app_constants.dart';
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
import 'label_print_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import 'web_search_screen.dart';

/// Liste siralamasi. Varsayilan SKT tarihi (en yakin once) — depodaki is
/// zaten bu sirayla yurur.
enum _SortMode { expiry, name, added }

extension _SortModeX on _SortMode {
  String get label {
    switch (this) {
      case _SortMode.expiry:
        return 'SKT tarihi';
      case _SortMode.name:
        return 'Ürün adı';
      case _SortMode.added:
        return 'Son eklenen';
    }
  }

  IconData get icon {
    switch (this) {
      case _SortMode.expiry:
        return Icons.event_rounded;
      case _SortMode.name:
        return Icons.sort_by_alpha_rounded;
      case _SortMode.added:
        return Icons.history_rounded;
    }
  }
}

/// ════════════════════════════════════════════════════════════════════
///  SKT LISTESI — ana ekran
/// ────────────────────────────────────────────────────────────────────
///  Ekranin tek isi su soruyu cevaplamak: "simdi neye dokunmam lazim?"
///
///  Yapi (tamami TEK CustomScrollView — eskiden Column + ic ListView'di):
///
///   ┌────────────────────────────────────────────┐ ← SliverAppBar (pinned)
///   │  SKT Takip                     [⚙] [+]     │   kaydirinca kuculur,
///   │  4 ürünün süresi doldu           128 ürün  │   baslik hep kalir
///   │  ▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │   ← RISK SERIDI
///   │  [🔍 Ürün veya barkod ara]            [▣]  │
///   └────────────────────────────────────────────┘
///   ┌────────────────────────────────────────────┐ ← SABIT filtre rayi
///   │ Tümü 128 │ Doldu 4 │ Kritik 9 │ …    │ ⇅   │   (hep erisilebilir)
///   └────────────────────────────────────────────┘
///     [ Akıllı Gün şeridi ]  (filtre/arama yokken)
///   ── SÜRESİ DOLDU · 4 ─────────────────────────  ← YAPISKAN baslik
///     [kart] [kart] …
///
///  RISK SERIDI ekranin imza ogesi: uc buyuk sayac karti (110 px) yerine
///  tek bir oransal serit (14 px). Hangi durumun listede ne kadar yer
///  kapladigi tek bakista gorunur; dokununca o duruma filtreler. Asil
///  dokunma hedefi ise asagidaki ray — eldivenle basilacak boyutta.
///
///  KOK COZUM: eski ekranda arama cubugu, scroll yonune bakan elle
///  yazilmis bir _searchVisible bayragiyla gizleniyordu; klavye acilip
///  kapaninca sahte scroll sinyali uretiliyor, cubuk kendiliginden
///  gizlenip geri geliyordu (uzerine bir de focus yamasi yazilmisti).
///  Artik bunu SliverAppBar yapiyor — bayrak da yama da kalkti.
/// ════════════════════════════════════════════════════════════════════
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// SKT <-> konum kalici bag etiketleri (urun id -> 'Palet X'/reyon adi).
  Map<int, String> _locLabels = {};

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _searchFocus = FocusNode();

  _SortMode _sort = _SortMode.expiry;

  /// Liste giris animasyonu: sadece ekran ACILIRKEN kartlar sirayla
  /// belirir. Sonrasinda tekrar oynatilmaz — yoksa her scroll'da kartlar
  /// yanip soner.
  bool _listEntryAnimDone = false;

  static const double _heroContentHeight = 152;

  @override
  void initState() {
    super.initState();
    _loadLocLabels();
    _scrollCtrl.addListener(_onScroll);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _listEntryAnimDone = true);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onScroll() => handleNavBarScroll(_scrollCtrl);

  Future<void> _loadLocLabels() async {
    try {
      final m =
          await ref.read(productRepositoryProvider).linkedLocationLabels();
      if (mounted) setState(() => _locLabels = m);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(productListProvider.notifier).refresh(),
      _loadLocLabels(),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final filtered = ref.watch(filteredProductsProvider);
    final activeFilter = ref.watch(statusFilterProvider);
    final query = ref.watch(searchQueryProvider).trim();
    final all = productsAsync.valueOrNull ?? const <Product>[];
    final counts = _countByStatus(all);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemBarForColor(AppTheme.primary),
      child: Scaffold(
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _refresh,
              edgeOffset: MediaQuery.of(context).padding.top + kToolbarHeight,
              child: CustomScrollView(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _heroBar(counts, all.length, activeFilter),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _FilterRailDelegate(
                      counts: counts,
                      total: all.length,
                      active: activeFilter,
                      sort: _sort,
                      onFilter: _applyFilter,
                      onSort: _pickSort,
                    ),
                  ),
                  ..._contentSlivers(
                    productsAsync: productsAsync,
                    all: all,
                    filtered: filtered,
                    activeFilter: activeFilter,
                    query: query,
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 110)),
                ],
              ),
            ),
            SpeedDialFab(
              actions: [
                SpeedDialAction(
                  icon: Icons.print_rounded,
                  label: 'Etiket Bas',
                  color: AppTheme.primaryDark,
                  onTap: _openLabelPrint,
                ),
                SpeedDialAction(
                  icon: Icons.event_available_rounded,
                  label: 'SKT Tara',
                  color: AppTheme.primary,
                  onTap: _openScanner,
                ),
              ],
            ),
            // NOT: "Etiket İncele" butonu TUM sayfalarda gorunen GLOBAL bir
            // buton (main.dart -> MaterialApp.builder); burada eklenmiyor.
            ScrollToTopFab(
              controller: _scrollCtrl,
              baseBottomPadding: 108,
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  HERO (AppBar)
  // ══════════════════════════════════════════════════════════════════
  Widget _heroBar(
      Map<ExpiryStatus, int> counts, int total, ExpiryStatus? active) {
    final topInset = MediaQuery.of(context).padding.top;
    final maxH = topInset + _heroContentHeight;
    final minH = topInset + kToolbarHeight;

    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      toolbarHeight: kToolbarHeight,
      expandedHeight: _heroContentHeight,
      systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.primary),
      flexibleSpace: LayoutBuilder(
        builder: (context, c) {
          // t = 0 tam acik, 1 tam kapali.
          final t = (maxH - minH) <= 0
              ? 0.0
              : ((maxH - c.maxHeight) / (maxH - minH)).clamp(0.0, 1.0);
          // Acik icerik hizli soner ki basligin altina girip karismasin.
          final openFade = (1 - t * 1.7).clamp(0.0, 1.0);
          final radius = lerpDouble(28, 0, t)!;
          final rounded =
              BorderRadius.vertical(bottom: Radius.circular(radius));

          return ClipRRect(
            borderRadius: rounded,
            child: AuroraBackground(
              borderRadius: rounded,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Acik durum: ozet + risk seridi + arama ──
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 14,
                    child: Opacity(
                      opacity: openFade,
                      child: IgnorePointer(
                        ignoring: openFade < 0.1,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _headline(counts, total),
                            const SizedBox(height: 8),
                            _RiskRibbon(
                              counts: counts,
                              active: active,
                              onTap: _applyFilter,
                            ),
                            const SizedBox(height: 12),
                            _searchRow(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // ── Her zaman gorunen ust satir ──
                  Positioned(
                    top: topInset,
                    left: 12,
                    right: 4,
                    height: kToolbarHeight,
                    child: Row(
                      children: [
                        const Text(
                          AppConstants.appName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Hero kapaninca sayaclar baslik yaninda ozetlenir.
                        Expanded(
                          child: Opacity(
                            opacity: t,
                            child: IgnorePointer(
                              ignoring: t < 0.5,
                              child: _CompactCounts(counts: counts),
                            ),
                          ),
                        ),
                        _HeroIconBtn(
                          icon: Icons.settings_rounded,
                          tooltip: 'Ayarlar',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const SettingsScreen()),
                          ),
                        ),
                        _HeroIconBtn(
                          icon: Icons.add_rounded,
                          tooltip: 'Yeni Ürün',
                          onTap: _openAddSheet,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Gunun tek cumlelik ozeti — okunmasi gereken TEK satir.
  Widget _headline(Map<ExpiryStatus, int> counts, int total) {
    final expired = counts[ExpiryStatus.expired] ?? 0;
    final critical = counts[ExpiryStatus.critical] ?? 0;
    final warning = counts[ExpiryStatus.warning] ?? 0;

    String text;
    if (total == 0) {
      text = 'Liste boş — ilk ürünü ekle';
    } else if (expired > 0) {
      text = '$expired ürünün süresi doldu';
    } else if (critical > 0) {
      text = '$critical ürün ${AppConstants.criticalDays} gün içinde doluyor';
    } else if (warning > 0) {
      text = '$warning ürün bu hafta doluyor';
    } else {
      text = 'Yakın tarihli ürün yok';
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ),
        if (total > 0)
          Text(
            '$total ürün',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _searchRow() {
    final hasText = _searchCtrl.text.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              // Disari dokununca klavye kapanir VE imlec birakilir; boylece
              // baska ekrandan donunce klavye kendiliginden acilmaz.
              onTapOutside: (_) => _searchFocus.unfocus(),
              onSubmitted: (_) => _searchFocus.unfocus(),
              onChanged: (v) {
                ref.read(searchQueryProvider.notifier).state = v;
                setState(() {}); // temizle (X) ikonu icin
              },
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: 'Ürün veya barkod ara',
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Colors.white, size: 21),
                suffixIcon: hasText
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 19),
                        onPressed: _clearSearch,
                        tooltip: 'Aramayı temizle',
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withOpacity(0.16),
                border: _searchBorder(0.35),
                enabledBorder: _searchBorder(0.35),
                focusedBorder: _searchBorder(1.0, width: 1.6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _scanBarcodeForSearch,
            child: const SizedBox(
              width: 46,
              height: 46,
              child: Icon(Icons.qr_code_scanner_rounded,
                  color: Colors.white, size: 23),
            ),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _searchBorder(double opacity, {double width = 1.0}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide:
          BorderSide(color: Colors.white.withOpacity(opacity), width: width),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  ICERIK
  // ══════════════════════════════════════════════════════════════════
  List<Widget> _contentSlivers({
    required AsyncValue<List<Product>> productsAsync,
    required List<Product> all,
    required List<Product> filtered,
    required ExpiryStatus? activeFilter,
    required String query,
  }) {
    if (productsAsync.isLoading && all.isEmpty) {
      return const [
        SliverFillRemaining(
            hasScrollBody: false, child: LoadingState(message: 'Yükleniyor')),
      ];
    }
    if (productsAsync.hasError && all.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorStateView(
            message: 'Ürünler yüklenemedi',
            onRetry: _refresh,
          ),
        ),
      ];
    }

    // Hic urun yok.
    if (all.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Henüz ürün yok',
            subtitle: 'Sağ alttaki "SKT Tara" ile barkodu ve son kullanma '
                'tarihini okut; ürün listeye düşsün.',
          ),
        ),
      ];
    }

    final slivers = <Widget>[];

    // Akilli Gun yalnizca "temiz" listede — filtre/arama varken kullanici
    // dar bir sonuca odaklanmistir, serit gurultu olur.
    if (activeFilter == null && query.isEmpty) {
      slivers.add(const SliverToBoxAdapter(child: SmartDayStrip()));
    }

    // Filtre/arama sonuc vermedi. (Eski ekranda burasi BOMBOS kaliyordu.)
    if (filtered.isEmpty) {
      slivers.add(SliverFillRemaining(
        hasScrollBody: false,
        child: query.isNotEmpty
            ? EmptyState(
                icon: Icons.search_off_rounded,
                iconColor: AppTheme.textSecondary,
                title: '"$query" bulunamadı',
                subtitle: 'Ürün adının bir kısmını ya da barkodu dene.',
                action: OutlinedButton.icon(
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Aramayı temizle'),
                ),
              )
            : EmptyState(
                icon: Icons.filter_alt_off_rounded,
                iconColor: activeFilter?.color,
                title: '${activeFilter?.label ?? 'Bu durumda'} ürün yok',
                subtitle: 'Bu durumda bekleyen ürün bulunmuyor.',
                action: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(statusFilterProvider.notifier).state = null,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Filtreyi kaldır'),
                ),
              ),
      ));
      return slivers;
    }

    final sorted = _sortProducts(filtered);

    // Gruplama yalnizca SKT sirasindayken ve durum filtresi YOKKEN
    // anlamli: filtre varken zaten tek grup kalir, ad/eklenme sirasinda
    // ise baslik listeyi bolmekten baska is yapmaz.
    final grouped = _sort == _SortMode.expiry && activeFilter == null;

    if (!grouped) {
      slivers.add(_productSliver(sorted, offset: 0));
      return slivers;
    }

    var offset = 0;
    for (final section in _sections) {
      final items = sorted
          .where((p) => p.status == section.status)
          .toList(growable: false);
      if (items.isEmpty) continue;
      slivers.add(SliverMainAxisGroup(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _SectionHeaderDelegate(
              label: section.label,
              count: items.length,
              color: section.status.color,
            ),
          ),
          _productSliver(items, offset: offset),
        ],
      ));
      offset += items.length;
    }
    return slivers;
  }

  Widget _productSliver(List<Product> items, {required int offset}) {
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final product = items[i];
        final card = ProductCard(
          key: ValueKey(product.id),
          product: product,
          locationLabel: product.id == null ? null : _locLabels[product.id],
          onDelete: () => _confirmDelete(product),
          onTap: () => _openEditSheet(product),
          onDispose: () => _openDisposalSheet(product),
          onSearch: product.barcode == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          WebSearchScreen(query: product.barcode!),
                    ),
                  ),
        );
        if (_listEntryAnimDone) return card;
        return card
            .animate(delay: ((offset + i) * 35).ms)
            .fadeIn(duration: 320.ms, curve: Curves.easeOut)
            .slideY(
                begin: 0.08,
                end: 0,
                duration: 320.ms,
                curve: Curves.easeOutCubic);
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  VERI YARDIMCILARI
  // ══════════════════════════════════════════════════════════════════
  /// Tek gecisli sayim (durum basina ayri .where() taramasi yapmaz).
  Map<ExpiryStatus, int> _countByStatus(List<Product> products) {
    final m = <ExpiryStatus, int>{
      ExpiryStatus.expired: 0,
      ExpiryStatus.critical: 0,
      ExpiryStatus.warning: 0,
      ExpiryStatus.safe: 0,
    };
    for (final p in products) {
      m[p.status] = (m[p.status] ?? 0) + 1;
    }
    return m;
  }

  List<Product> _sortProducts(List<Product> items) {
    final list = List<Product>.of(items);
    switch (_sort) {
      case _SortMode.expiry:
        list.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
        break;
      case _SortMode.name:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _SortMode.added:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
    return list;
  }

  static const List<_SectionDef> _sections = [
    _SectionDef('Süresi doldu', ExpiryStatus.expired),
    _SectionDef(
        'Kritik · ≤${AppConstants.criticalDays} gün', ExpiryStatus.critical),
    _SectionDef(
        'Yaklaşan · ≤${AppConstants.warningDays} gün', ExpiryStatus.warning),
    _SectionDef('Güvenli', ExpiryStatus.safe),
  ];

  // ══════════════════════════════════════════════════════════════════
  //  EYLEMLER
  // ══════════════════════════════════════════════════════════════════
  void _applyFilter(ExpiryStatus? status) {
    final notifier = ref.read(statusFilterProvider.notifier);
    // Ayni filtreye tekrar dokunmak kaldirir.
    notifier.state = notifier.state == status ? null : status;
    if (notifier.state != null) _clearSearch();
    _scrollToTop();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    if (mounted) setState(() {});
  }

  void _scrollToTop() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(0,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<_SortMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppTheme.rLg)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppTheme.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            for (final mode in _SortMode.values)
              ListTile(
                leading: Icon(mode.icon,
                    color: mode == _sort
                        ? AppTheme.primary
                        : AppTheme.textSecondary),
                title: Text(
                  mode.label,
                  style: TextStyle(
                    fontWeight:
                        mode == _sort ? FontWeight.w700 : FontWeight.w500,
                    color:
                        mode == _sort ? AppTheme.primary : AppTheme.textPrimary,
                  ),
                ),
                trailing: mode == _sort
                    ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, mode),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != _sort && mounted) {
      setState(() => _sort = picked);
      _scrollToTop();
    }
  }

  Future<void> _scanBarcodeForSearch() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _BarcodeSearchPage()),
    );
    if (code != null && mounted) {
      _searchCtrl.text = code;
      ref.read(searchQueryProvider.notifier).state = code;
      ref.read(statusFilterProvider.notifier).state = null;
      setState(() {});
    }
  }

  Future<void> _openAddSheet() async {
    // Arama kutusundaki degeri tasi: barkod formatindaysa barkod alanina,
    // degilse urun adi alanina (ad yazip ekle deyince barkod kirlenmez).
    final searchText = _searchCtrl.text.trim();
    String? prefillBarcode;
    String? prefillName;
    if (searchText.isNotEmpty) {
      if (ScanResult.looksLikeBarcode(searchText)) {
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
    await _loadLocLabels();
  }

  Future<void> _openEditSheet(Product product) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductFormScreen(existing: product)),
    );
    await _loadLocLabels();
  }

  Future<void> _openDisposalSheet(Product product) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DisposalSheet(product: product),
    );
  }

  Future<void> _openLabelPrint() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LabelPrintScreen()),
    );
  }

  /// SKT Tara akisi: ONCE barkod, SONRA SKT ekrani, sonra form; kayit
  /// bitince otomatik olarak tekrar barkod taramaya doner (zincir). Dongu,
  /// barkod ekranindan geri cikilinca biter.
  Future<void> _openScanner() async {
    while (true) {
      if (!mounted) return;
      final barcode = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
      );
      if (!mounted) return;
      if (barcode == null) return;

      final outcome = await Navigator.of(context).push<ScanOutcome>(
        MaterialPageRoute(
          builder: (_) => ScannerScreen(prefillBarcode: barcode),
        ),
      );
      if (!mounted) return;
      if (outcome == null) return;
      final scanned = outcome.date.year == 1900 ? null : outcome.date;

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
      if (saved != true) return;
      await _loadLocLabels();
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

// ════════════════════════════════════════════════════════════════════
//  RISK SERIDI — imza ogesi. Durumlarin listedeki ORANI tek bakista.
// ════════════════════════════════════════════════════════════════════
class _RiskRibbon extends StatelessWidget {
  final Map<ExpiryStatus, int> counts;
  final ExpiryStatus? active;
  final ValueChanged<ExpiryStatus> onTap;

  const _RiskRibbon({
    required this.counts,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const order = [
      ExpiryStatus.expired,
      ExpiryStatus.critical,
      ExpiryStatus.warning,
      ExpiryStatus.safe,
    ];
    final present =
        order.where((s) => (counts[s] ?? 0) > 0).toList(growable: false);

    if (present.isEmpty) {
      return Container(
        height: 11,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(AppTheme.rPill),
        ),
      );
    }

    return SizedBox(
      height: 14,
      child: Row(
        children: [
          for (final s in present)
            Expanded(
              flex: counts[s]!,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(s),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    height: (active == null || active == s) ? 11 : 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: s.color.withOpacity(
                          (active == null || active == s) ? 1 : 0.35),
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hero kapaninca baslik yaninda beliren mini sayaclar.
class _CompactCounts extends StatelessWidget {
  final Map<ExpiryStatus, int> counts;
  const _CompactCounts({required this.counts});

  @override
  Widget build(BuildContext context) {
    const order = [
      ExpiryStatus.expired,
      ExpiryStatus.critical,
      ExpiryStatus.warning,
    ];
    final shown =
        order.where((s) => (counts[s] ?? 0) > 0).toList(growable: false);
    if (shown.isEmpty) return const SizedBox.shrink();

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in shown)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(AppTheme.rPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: s.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${counts[s]}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  SABIT FILTRE RAYI — hero kapansa da filtre ve siralama hep elinin
//  altinda. (Eskiden filtre kartlari listenin ILK satirindaydi; filtre
//  degistirmek icin en basa kadar kaydirmak gerekiyordu.)
// ════════════════════════════════════════════════════════════════════
class _FilterRailDelegate extends SliverPersistentHeaderDelegate {
  final Map<ExpiryStatus, int> counts;
  final int total;
  final ExpiryStatus? active;
  final _SortMode sort;
  final ValueChanged<ExpiryStatus?> onFilter;
  final VoidCallback onSort;

  _FilterRailDelegate({
    required this.counts,
    required this.total,
    required this.active,
    required this.sort,
    required this.onFilter,
    required this.onSort,
  });

  static const double _height = 58;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  bool shouldRebuild(_FilterRailDelegate old) =>
      old.active != active ||
      old.total != total ||
      old.sort != sort ||
      !_sameCounts(old.counts, counts);

  static bool _sameCounts(Map<ExpiryStatus, int> a, Map<ExpiryStatus, int> b) {
    for (final s in ExpiryStatus.values) {
      if ((a[s] ?? 0) != (b[s] ?? 0)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      height: _height,
      color: AppTheme.background,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      _chip(
                        label: 'Tümü',
                        count: total,
                        color: AppTheme.primary,
                        selected: active == null,
                        onTap: () => onFilter(null),
                      ),
                      for (final s in const [
                        ExpiryStatus.expired,
                        ExpiryStatus.critical,
                        ExpiryStatus.warning,
                        ExpiryStatus.safe,
                      ])
                        _chip(
                          label: _shortLabel(s),
                          count: counts[s] ?? 0,
                          color: s.color,
                          selected: active == s,
                          onTap: () => onFilter(s),
                        ),
                    ],
                  ),
                ),
                Container(width: 1, height: 24, color: AppTheme.hairline),
                Tooltip(
                  message: 'Sırala: ${sort.label}',
                  child: InkWell(
                    onTap: onSort,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(sort.icon,
                              size: 18, color: AppTheme.textSecondary),
                          if (sort != _SortMode.expiry) ...[
                            const SizedBox(width: 5),
                            Text(
                              sort.label,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          Container(height: 1, color: AppTheme.hairline),
        ],
      ),
    );
  }

  static String _shortLabel(ExpiryStatus s) {
    switch (s) {
      case ExpiryStatus.expired:
        return 'Doldu';
      case ExpiryStatus.critical:
        return 'Kritik';
      case ExpiryStatus.warning:
        return 'Yaklaşan';
      case ExpiryStatus.safe:
        return 'Güvenli';
    }
  }

  Widget _chip({
    required String label,
    required int count,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final dim = count == 0 && !selected;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: Material(
          color: selected ? color.withOpacity(0.18) : AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.rPill),
                border: Border.all(
                  color: selected ? color : AppTheme.hairline,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color.withOpacity(dim ? 0.35 : 1),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? color
                          : (dim
                              ? AppTheme.textTertiary
                              : AppTheme.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? color
                          : (dim
                              ? AppTheme.textTertiary
                              : AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  YAPISKAN GRUP BASLIGI — hangi grubun icindesin, kaydirirken de belli.
// ════════════════════════════════════════════════════════════════════
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  final int count;
  final Color color;

  _SectionHeaderDelegate({
    required this.label,
    required this.count,
    required this.color,
  });

  static const double _height = 40;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  bool shouldRebuild(_SectionHeaderDelegate old) =>
      old.label != label || old.count != count || old.color != color;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      height: _height,
      color: AppTheme.background,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
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
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: color,
                ),
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hero ikon butonu.
class _HeroIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _HeroIconBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 23),
        onPressed: onTap,
        splashRadius: 22,
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
      // KOLI BARKODU: ITF-14 (depo/koli etiketleri). ScanParser bunu
      // otomatik olarak perakende EAN-13'e cevirir.
      BarcodeFormat.itf,
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
    final value =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
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
            width: 260,
            height: 140,
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

class _SectionDef {
  final String label;
  final ExpiryStatus status;
  const _SectionDef(this.label, this.status);
}
