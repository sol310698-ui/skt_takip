import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'add_product_screen.dart';
import 'barcode_list_screen.dart';
import 'count_screen.dart';
import 'home_screen.dart';
import 'shelf_check_screen.dart';
import 'warehouse_list_screen.dart';

/// Modern shell that anchors the main bottom navigation and warehouse mode.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialNavIndex = 0});

  final int initialNavIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    _navIndex = widget.initialNavIndex;
  }

  final List<Widget> _screens = const [
    HomeScreen(),
    BarcodeListScreen(),
    CountScreen(),
    ShelfCheckScreen(),
    WarehouseListScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _navIndex,
          children: _screens,
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Material(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(28),
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.border, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: NavigationBar(
              height: 74,
              backgroundColor: AppTheme.surface,
              surfaceTintColor: Colors.transparent,
              indicatorColor: AppTheme.primary.withOpacity(0.12),
              selectedIndex: _navIndex,
              onDestinationSelected: (index) => setState(() => _navIndex = index),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Ana Sayfa'),
                NavigationDestination(icon: Icon(Icons.qr_code_2_outlined), selectedIcon: Icon(Icons.qr_code_2), label: 'Barkod'),
                NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Sayım'),
                NavigationDestination(icon: Icon(Icons.checklist_rtl_outlined), selectedIcon: Icon(Icons.checklist_rtl), label: 'Kontrol'),
                NavigationDestination(icon: Icon(Icons.warehouse_outlined), selectedIcon: Icon(Icons.warehouse), label: 'Depo'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
