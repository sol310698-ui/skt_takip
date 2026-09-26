import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Shelf and location verification screen.
class ShelfCheckScreen extends ConsumerStatefulWidget {
  const ShelfCheckScreen({super.key});

  @override
  ConsumerState<ShelfCheckScreen> createState() => _ShelfCheckScreenState();
}

class _ShelfCheckScreenState extends ConsumerState<ShelfCheckScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: const Text('Raf Kontrolü'),
        backgroundColor: AppTheme.scaffold,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppTheme.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Raf veya ürün ara...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _demoShelves.length,
                itemBuilder: (context, index) {
                  final shelf = _demoShelves[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: (shelf['color'] as Color).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.shelves_outlined, color: shelf['color'] as Color),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      shelf['name'] as String,
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${shelf['items']} ürün',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              StatusPill(
                                label: shelf['status'] as String,
                                color: shelf['color'] as Color,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Doğrula'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.success,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {},
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Düzenle'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.border),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const List<Map<String, dynamic>> _demoShelves = [
    {'name': 'A Rafı - 1. Bölüm', 'items': 24, 'status': 'Doğrulandi', 'color': AppTheme.success},
    {'name': 'A Rafı - 2. Bölüm', 'items': 18, 'status': 'Beklemede', 'color': AppTheme.warning},
    {'name': 'B Rafı - 1. Bölüm', 'items': 32, 'status': 'Hata', 'color': AppTheme.danger},
    {'name': 'B Rafı - 2. Bölüm', 'items': 15, 'status': 'Beklemede', 'color': AppTheme.warning},
  ];
}
