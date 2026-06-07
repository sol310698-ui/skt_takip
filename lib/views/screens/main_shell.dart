import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'barcode_list_screen.dart';
import 'home_screen.dart';
import 'shelf_check_screen.dart';

/// Alt navigasyon barli ana kabuk.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final List<Widget> _pages = const [
    HomeScreen(),
    BarcodeListScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          ..._pages,
          // Reyon kontrol sadece secili oldugunda kamerayi calistirir.
          ShelfCheckScreen(isActive: _index == 2),
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
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: AppTheme.surface,
          indicatorColor: AppTheme.primary.withOpacity(0.2),
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.event_note_outlined),
              selectedIcon: Icon(Icons.event_note, color: AppTheme.primary),
              label: 'SKT Takip',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_2_outlined),
              selectedIcon: Icon(Icons.qr_code_2, color: AppTheme.primary),
              label: 'Barkod Liste',
            ),
            NavigationDestination(
              icon: Icon(Icons.price_check_outlined),
              selectedIcon: Icon(Icons.price_check, color: AppTheme.primary),
              label: 'Reyon Kontrol',
            ),
          ],
        ),
      ),
    );
  }
}
