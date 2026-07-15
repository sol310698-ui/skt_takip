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
import 'price_change_screen.dart';
import 'price_check_screen.dart';
import 'shelf_check_screen.dart';
import 'shift_screen.dart';
import 'warehouse_chat_screen.dart';
import 'warehouse_list_screen.dart';

/// Alt navigasyon barli ana kabuk.
/// "Kontrol" sekmesi sekme DEGISTIRMEZ: kamera otomatik baslamasin diye
/// bir secim sheet'i acar; secilen ekran tam sayfa (navbar'siz) push edilir.
class MainShell extends StatefulWidget {
  /// Acilista gosterilecek sekme (0=Anasayfa, 1=Barkod, 3=Mesai).
  /// Kilit ekraninda kullanici is yerindeyse 3 (Mesai) ile acilir.
  final int initialNavIndex;
  const MainShell({super.key, this.initialNavIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _navIndex = 0;

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

  /// Nav index -> IndexedStack index (2=Kontrol sheet, stack'te yok).
  int get _stackIndex => _navIndex < 2 ? _navIndex : _navIndex - 1;

  void _onDestination(int i) {
    if (i == 2) {
      // Kontrol: sekme degistirme, secim sheet'i ac.
      _openControlSheet();
      return;
    }
    setState(() => _navIndex = i);
    // Sekme degisince nav bar'i her zaman geri goster.
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
            const Text('Kontrol Araçları',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
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
                  'Etiket QR\'ı ile sistem fiyatını karşılaştır, uyuşmazlıkta sesli + titreşimli uyarı (görme dostu)',
              onTap: () => _push(const PriceCheckScreen()),
            ),
            _sheetOption(
              icon: Icons.inventory_2_rounded,
              color: AppTheme.primary,
              title: 'Sayım',
              subtitle:
                  'Barkod okut, adet gir. Ürün adı dizinden bulunur; '
                  'PDF/Excel rapor alınır',
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
    Navigator.of(context).pop(); // sheet'i kapat
    // Push: navbar gorunmez (MainShell disinda tam sayfa).
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
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // KRITIK: MainShell'in KENDI bir AnnotatedRegion'i olmasi gerekir.
    // Eskiden bu yoktu; sadece IndexedStack icindeki HER ekran (HomeScreen,
    // BarcodeListScreen, ShiftScreen) kendi AnnotatedRegion'ini ayri ayri
    // set ediyordu. LockScreen'den (AppTheme.background bazli, koyu/duz
    // renk) MainShell'e gecis bir Navigator push/pop DEGIL, dogrudan
    // MaterialApp.home icindeki widget'in degismesi seklinde oluyor
    // (main.dart: _locked ? LockScreen(...) : MainShell()). Bu anlik
    // kok-widget degisiminde, ic ekranlarin AnnotatedRegion'lari bazi
    // cihazlarda/karelerde GEC devreye giriyor, bu da status bar'in
    // LockScreen'in koyu/duz renginde "yapisik" kalmasina (banner'in
    // gradyaninin status bar arkasinda hic gorunmemesine) sebep
    // olabiliyordu. MainShell'in kendi AnnotatedRegion'i, IndexedStack
    // render olmadan ONCE devreye girip dogru rengi hemen garanti eder.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemBarForColor(AppTheme.primary),
      child: Scaffold(
      extendBody: true,
      backgroundColor: AppTheme.background,
      body: IndexedStack(
        index: _stackIndex,
        children: [
          const HomeScreen(),
          BarcodeListScreen(isActive: _navIndex == 1),
          const ShiftScreen(),
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
    );
  }

  Widget _buildCustomNavBar() {
    return SizedBox(
      height: 112,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          // Alt bar — floating: yanlardan ve alttan bosluklu, tum koseler
          // yuvarlak (pill/rXl), Soft Glass frosted-glass (BackdropFilter).
          Positioned(
            bottom: 12,
            left: 16,
            right: 16,
            child: SafeArea(
              top: false,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.all(Radius.circular(AppTheme.rXl)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    height: 66,
                    decoration: BoxDecoration(
                      color: AppTheme.glassTint
                          .withOpacity(AppTheme.glassOpacity + 0.1),
                      borderRadius: const BorderRadius.all(
                          Radius.circular(AppTheme.rXl)),
                      border: Border.all(
                        color: Colors.white
                            .withOpacity(AppTheme.isLight ? 0.8 : 0.1),
                        width: 1.2,
                      ),
                      boxShadow: AppTheme.shadowMd,
                    ),
                    child: Row(
                      children: [
                        _navItem(0, Icons.event_note_outlined,
                            Icons.event_note_rounded, 'SKT'),
                        _navItem(1, Icons.qr_code_2_outlined,
                            Icons.qr_code_2_rounded, 'Barkod'),
                        const Expanded(child: SizedBox()), // orta bosluk
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
          ),
          // Ortadaki "evren gecisi" butonu
          Positioned(
            top: 0,
            child: _buildWarpButton(),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label,
      {bool isAction = false}) {
    final selected = !isAction && _navIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onDestination(index),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          scale: selected ? 1.0 : 0.96,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  selected ? activeIcon : icon,
                  key: ValueKey(selected),
                  color: selected
                      ? AppTheme.primaryDark
                      : AppTheme.textTertiary,
                  size: 24,
                ),
              ),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppTheme.primaryDark
                          : AppTheme.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }

  /// Ortadaki buyuk depo gecis butonu — basinca evrenler arasi gecis.
  Widget _buildWarpButton() {
    return GestureDetector(
      onTap: _enterWarehouse,
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
              color: AppTheme.accent.withOpacity(0.5),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
          border: Border.all(color: AppTheme.background, width: 4),
        ),
        child: const Icon(Icons.warehouse_rounded,
            color: Colors.white, size: 30),
      ),
    );
  }

  /// Depo düğmesine basınca iki seçenek sun: Depo ya da Asistan (chat).
  void _enterWarehouse() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _sheetOption(
                  sheetCtx,
                  icon: Icons.warehouse_rounded,
                  title: 'Depo',
                  subtitle: 'Reyon, palet ve raf yönetimi',
                  color: AppTheme.primary,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const WarehouseListScreen()));
                  },
                ),
                const SizedBox(height: 10),
                _sheetOption(
                  sheetCtx,
                  icon: Icons.assistant_rounded,
                  title: 'Depo Asistanı',
                  subtitle: 'Ürün nerede? Sor, yerini bulayım',
                  color: AppTheme.accent,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const WarehouseChatScreen()));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sheetOption(
    BuildContext ctx, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textTertiary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}
