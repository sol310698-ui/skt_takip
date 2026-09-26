import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Warehouse management and selection screen.
class WarehouseListScreen extends ConsumerStatefulWidget {
  const WarehouseListScreen({super.key});

  @override
  ConsumerState<WarehouseListScreen> createState() => _WarehouseListScreenState();
}

class _WarehouseListScreenState extends ConsumerState<WarehouseListScreen> {
  int? _selectedWarehouse = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: const Text('Depolar'),
        backgroundColor: AppTheme.scaffold,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: GlassPanel(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hızlı İstatistikler',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatCard(
                          label: 'Depolar',
                          value: '8',
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        _StatCard(
                          label: 'Ürün',
                          value: '1.2K',
                          color: AppTheme.secondary,
                        ),
                        const SizedBox(width: 8),
                        _StatCard(
                          label: 'Uyarı',
                          value: '16',
                          color: AppTheme.warning,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Depolar', style: Theme.of(context).textTheme.titleLarge),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Tümü'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _demoWarehouses.length,
                itemBuilder: (context, index) {
                  final warehouse = _demoWarehouses[index];
                  final isSelected = _selectedWarehouse == index;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedWarehouse = index),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? AppTheme.primary : AppTheme.border,
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: AppTheme.primary.withOpacity(0.12), blurRadius: 12)]
                              : [],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: (warehouse['color'] as Color).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(14),
                                    border: isSelected
                                        ? Border.all(color: warehouse['color'] as Color, width: 2)
                                        : null,
                                  ),
                                  child: Icon(
                                    Icons.warehouse_outlined,
                                    color: warehouse['color'] as Color,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        warehouse['name'] as String,
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        warehouse['address'] as String,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: AppTheme.textMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: warehouse['color'] as Color,
                                    size: 24,
                                  )
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _WarehouseMetric(
                                    label: 'Ürün',
                                    value: warehouse['products'] as String,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _WarehouseMetric(
                                    label: 'Raflar',
                                    value: warehouse['shelves'] as String,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _WarehouseMetric(
                                    label: 'Uyarı',
                                    value: warehouse['alerts'] as String,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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

  static const List<Map<String, dynamic>> _demoWarehouses = [
    {
      'name': 'Ana Depo',
      'address': 'İstanbul, Pendik',
      'products': '542',
      'shelves': '24',
      'alerts': '8',
      'color': AppTheme.primary,
    },
    {
      'name': 'İzmir Şubesi',
      'address': 'İzmir, Alsancak',
      'products': '318',
      'shelves': '16',
      'alerts': '4',
      'color': AppTheme.secondary,
    },
    {
      'name': 'Ankara Merkezi',
      'address': 'Ankara, Çankaya',
      'products': '275',
      'shelves': '12',
      'alerts': '2',
      'color': AppTheme.success,
    },
    {
      'name': 'Antalya Depo',
      'address': 'Antalya, Muratpaşa',
      'products': '198',
      'shelves': '8',
      'alerts': '2',
      'color': AppTheme.info,
    },
  ];
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseMetric extends StatelessWidget {
  const _WarehouseMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.primary),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
