import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart';
import 'barcode_list_screen.dart';
import 'home_screen.dart';
import 'label_inspect_screen.dart';
import 'morning_verify_screen.dart';
import 'price_change_screen.dart';
import 'shelf_check_screen.dart';
import 'shift_screen.dart';

/// Alt navigasyon barli ana kabuk.
/// "Kontrol" sekmesi sekme DEGISTIRMEZ: kamera otomatik baslamasin diye
/// bir secim sheet'i acar; secilen ekran tam sayfa (navbar'siz) push edilir.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
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
  }

  void _openControlSheet() {
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
              icon: Icons.document_scanner_rounded,
              color: AppTheme.accent,
              title: 'Etiket İnceleme',
              subtitle:
                  'Etiketi okut: fiyat, tarihler, ürün bilgisi, web arama',
              onTap: () => _push(const LabelInspectScreen()),
            ),
            const SizedBox(height: 10),
            _sheetOption(
              icon: Icons.wb_sunny_rounded,
              color: AppTheme.amber,
              title: 'Sabah Etiket Kaydı',
              subtitle:
                  'Teslim alınan etiketleri kaydet, sonra sorgula (30 gün)',
              onTap: () => _push(const MorningVerifyScreen()),
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
          ],
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
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _stackIndex,
        children: [
          const HomeScreen(),
          BarcodeListScreen(isActive: _navIndex == 1),
          const ShiftScreen(),
        ],
      ),
      bottomNavigationBar: Container(
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
        child: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: _onDestination,
          backgroundColor: AppTheme.surface,
          indicatorColor: AppTheme.primary.withOpacity(0.25),
          height: 68,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.event_note_outlined),
              selectedIcon:
                  Icon(Icons.event_note_rounded, color: AppTheme.primaryLight),
              label: 'SKT Takip',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_2_outlined),
              selectedIcon:
                  Icon(Icons.qr_code_2_rounded, color: AppTheme.primaryLight),
              label: 'Barkod Liste',
            ),
            NavigationDestination(
              icon: Icon(Icons.price_check_outlined),
              selectedIcon:
                  Icon(Icons.price_check_rounded, color: AppTheme.primaryLight),
              label: 'Kontrol',
            ),
            NavigationDestination(
              icon: Icon(Icons.access_time_outlined),
              selectedIcon: Icon(Icons.access_time_filled_rounded,
                  color: AppTheme.primaryLight),
              label: 'Mesai',
            ),
          ],
        ),
      ),
    );
  }
}
