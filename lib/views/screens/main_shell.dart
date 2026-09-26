import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart';
import '../../core/nav_bar_visibility.dart';
import 'barcode_list_screen.dart';
import 'control_list_screen.dart';
import 'count_screen.dart';
import 'home_screen.dart';
import 'checklist_screen.dart';
import 'shelf_restock_screen.dart';
import 'teshir_screen.dart';
import 'price_change_screen.dart';
import 'price_check_screen.dart';
import 'shelf_check_screen.dart';
import 'shelf_layout_list_screen.dart';
import 'shift_screen.dart';
import 'warehouse_chat_screen.dart';
import 'warehouse_list_screen.dart';

/// Alt nav barin govde uzerinde kapladigi yaklasik yukseklik.
const double kNavBarClearance = 92;

class MainShell extends StatefulWidget {
  final int initialNavIndex;
  const MainShell({super.key, this.initialNavIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _navIndex = 0;
  bool _warehouse = false;
  int _whTab = 0;

  @override
  void initState() {
    super.initState();
    _navIndex = widget.initialNavIndex;
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.location,
      Permission.notification,
      Permission.photos,
    ].request();
  }

  int get _stackIndex => _navIndex < 2 ? _navIndex : _navIndex - 1;

  void _onDestination(int i) {
    if (i == 2) {
      _openControlSheet();
      return;
    }
    setState(() {
      _navIndex = i;
      _warehouse = false;
    });
    navBarVisible.value = true;
  }

  void _openControlSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rXl)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          28 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Kontrol Araçları',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _sheetOption(
                icon: Icons.outbox_rounded,
                color: AppTheme.amber,
                title: 'Reyona Açılacaklar',
                subtitle:
                    'Barkod okut, listeye ekle; depodan FEFO ile çıkar ve reyona aç',
                onTap: () => _push(const ShelfRestockScreen()),
              ),
              const SizedBox(height: 10),
              _sheetOption(
                icon: Icons.price_check_rounded,
                color: AppTheme.primary,
                title: 'Reyon Kontrol',
                subtitle: 'Ürün + etiket eşleştirme, fiyat farkı kontrolü',
                onTap: () => _push(const ShelfCheckScreen()),
              ),
              const SizedBox(height: 10),
              _sheetOption(
                icon: Icons.receipt_long_rounded,
                color: AppTheme.coral,
                title: 'Fiyat Değişim',
                subtitle:
                    'A4 listeyi tara, etiketleri değiştir (fotolu), kalanı raporla',
                onTap: () => _push(const PriceChangeScreen()),
              ),
              const SizedBox(height: 10),
              _sheetOption(
                icon: Icons.checklist_rounded,
                color: AppTheme.accent,
                title: 'Kontrol Listeleri',
                subtitle:
                    'Yapılacaklar listeleri oluştur, maddeleri işaretle (açılış, kapanış, sabah...)',
                onTap: () => _push(const ChecklistScreen()),
              ),
              const SizedBox(height: 10),
              _sheetOption(
                icon: Icons.price_change_rounded,
                color: AppTheme.statusSafe,
                title: 'Fiyat Kontrol (Sesli)',
                subtitle:
                    'Etiket QR\'ı ile sistem fiyatını karşılaştır, uyuşmazlıkta sesli + titreşimli uyarı',
                onTap: () => _push(const PriceCheckScreen()),
              ),
              const SizedBox(height: 10),
              _sheetOption(
                icon: Icons.inventory_2_rounded,
                color: AppTheme.primary,
                title: 'Sayım',
                subtitle:
                    'Barkod okut, adet gir. Ürün adı dizinden bulunur; PDF/Excel rapor alınır',
                onTap: () => _push(const CountScreen()),
              ),
              _sheetOption(
                icon: Icons.fact_check_rounded,
                color: AppTheme.accent,
                title: 'Kontrol Listesi',
                subtitle:
                    'Yöneticinin attığı Excel veya fotoğrafı yükle, ürünleri tek tek internette kontrol et',
                onTap: () => _push(const ControlListScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Widget _sheetOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_warehouse,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (mounted) setState(() => _warehouse = false);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBarForColor(AppTheme.primary),
        child: Scaffold(
          extendBody: true,
          backgroundColor: AppTheme.background,
          body: IndexedStack(
            index: _warehouse ? 3 : _stackIndex,
            children: [
              const HomeScreen(),
              BarcodeListScreen(isActive: _navIndex == 1 && !_warehouse),
              const ShiftScreen(),
              _warehouseBody(),
            ],
          ),
          bottomNavigationBar: ValueListenableBuilder<bool>(
            valueListenable: navBarVisible,
            builder: (_, visible, child) => AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              offset: visible ? Offset.zero : const Offset(0, 1.4),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: visible ? 1 : 0,
                child: child,
              ),
            ),
            child: _buildCustomNavBar(),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomNavBar() {
    return SizedBox(
      height: 104,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: AppTheme.surface,
                  elevation: 0,
                  borderRadius: BorderRadius.circular(AppTheme.rXl),
                  child: Container(
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.rXl),
                      border: Border.all(color: AppTheme.hairline, width: 1),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _warehouse
                          ? Row(
                              key: const ValueKey('wh'),
                              children: [
                                _whNavItem(0, Icons.shelves_rounded,
                                    Icons.shelves_rounded, 'Reyon'),
                                _whNavItem(2, Icons.storefront_rounded,
                                    Icons.storefront_rounded, 'Teşhir'),
                                const Expanded(child: SizedBox()),
                                _whNavItem(1, Icons.warehouse_rounded,
                                    Icons.warehouse_rounded, 'Depo', flex: 2),
                              ],
                            )
                          : Row(
                              key: const ValueKey('main'),
                              children: [
                                _navItem(0, Icons.event_note_outlined,
                                    Icons.event_note_rounded, 'SKT'),
                                _navItem(1, Icons.qr_code_2_outlined,
                                    Icons.qr_code_2_rounded, 'Barkod'),
                                const Expanded(child: SizedBox()),
                                _navItem(2, Icons.price_check_outlined,
                                    Icons.price_check_rounded, 'Kontrol',
                                    isAction: true),
                                _navItem(3, Icons.access_time_outlined,
                                    Icons.access_time_filled_rounded, 'Mesai'),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                child: _buildWarpButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label,
      {bool isAction = false}) {
    final selected = !isAction && _navIndex == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        onTap: () => _onDestination(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? activeIcon : icon,
                color: selected ? AppTheme.primary : AppTheme.textTertiary,
                size: 24,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppTheme.primary : AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _whNavItem(
      int tab, IconData icon, IconData activeIcon, String label,
      {int flex = 1}) {
    final selected = _whTab == tab;
    return Expanded(
      flex: flex,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        onTap: () {
          setState(() => _whTab = tab);
          navBarVisible.value = true;
          HapticFeedback.selectionClick();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? activeIcon : icon,
                color: selected ? AppTheme.accent : AppTheme.textTertiary,
                size: 24,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? AppTheme.accent : AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _warehouseBody() {
    return Builder(
      builder: (context) {
        final mq = MediaQuery.of(context);
        final boosted = mq.copyWith(
          padding: mq.padding.copyWith(bottom: mq.padding.bottom + kNavBarClearance),
          viewPadding: mq.viewPadding.copyWith(bottom: mq.viewPadding.bottom + kNavBarClearance),
        );
        return MediaQuery(
          data: boosted,
          child: IndexedStack(
            index: _whTab,
            children: const [
              ShelfLayoutListScreen(isTabRoot: true),
              WarehouseListScreen(isTabRoot: true),
              TeshirScreen(isTabRoot: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWarpButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (_warehouse) {
            _warehouse = false;
          } else {
            _warehouse = true;
            _whTab = 0;
          }
        });
        navBarVisible.value = true;
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WarehouseChatScreen()),
        );
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppTheme.accent, AppTheme.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withOpacity(0.4),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
          border: Border.all(
            color: _warehouse ? Colors.white : AppTheme.background,
            width: 4,
          ),
        ),
        child: Icon(
          _warehouse ? Icons.close_rounded : Icons.warehouse_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }
}
