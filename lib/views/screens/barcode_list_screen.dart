import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Barcode scanning and list management screen.
class BarcodeListScreen extends ConsumerStatefulWidget {
  const BarcodeListScreen({super.key});

  @override
  ConsumerState<BarcodeListScreen> createState() => _BarcodeListScreenState();
}

class _BarcodeListScreenState extends ConsumerState<BarcodeListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: const Text('Barkod Okut'),
        backgroundColor: AppTheme.scaffold,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_outlined),
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
                      'Kamera ile Barkodu Okut',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Kamerayı Aç'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Son Okutmalar', style: Theme.of(context).textTheme.titleMedium),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Temizle'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _demoBarcodes.length,
                itemBuilder: (context, index) {
                  final item = _demoBarcodes[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border, width: 1),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: (item['color'] as Color).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.qr_code_2, color: item['color'] as Color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['code'] as String,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontFamily: 'monospace'),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item['time'] as String,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_outlined, color: AppTheme.primary),
                            onPressed: () {},
                            constraints: const BoxConstraints(minWidth: 36),
                            padding: EdgeInsets.zero,
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

  static const List<Map<String, dynamic>> _demoBarcodes = [
    {'code': '8696321400032', 'time': 'Şimdi', 'color': AppTheme.success},
    {'code': '8696321400035', 'time': '2 dakika önce', 'color': AppTheme.primary},
    {'code': '8696321400038', 'time': '15 dakika önce', 'color': AppTheme.warning},
    {'code': '8696321400041', 'time': '1 saat önce', 'color': AppTheme.primary},
  ];
}
