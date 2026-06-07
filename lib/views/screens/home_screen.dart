import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/product.dart';
import '../../viewmodels/providers.dart';
import '../widgets/product_card.dart';
import 'add_product_screen.dart';
import 'scanner_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productListProvider);
    final filtered = ref.watch(filteredProductsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildBanner(context, ref),
            Expanded(
              child: productsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Hata: $e')),
                data: (_) {
                  if (filtered.isEmpty) return _buildEmpty();
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(productListProvider.notifier).refresh(),
                    child: ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 90),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final product = filtered[i];
                        return ProductCard(
                          product: product,
                          onDelete: () =>
                              _confirmDelete(context, ref, product),
                          onTap: () => _openEditSheet(context, product),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openScanner(context),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('SKT Tara'),
      ),
    );
  }

  Widget _buildBanner(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        gradient: AppTheme.bannerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
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
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                onPressed: () => _openAddSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) =>
                ref.read(searchQueryProvider.notifier).state = v,
            decoration: const InputDecoration(
              hintText: 'Ürün veya barkod ara...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 64, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text('Henüz ürün yok',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          SizedBox(height: 4),
          Text('SKT taramak için aşağıdaki butonu kullan',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  /// Yeni urun ekleme - kayan pencere (modal bottom sheet).
  Future<void> _openAddSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProductFormSheet(),
    );
  }

  /// Duzenleme - kayan pencere.
  Future<void> _openEditSheet(BuildContext context, Product product) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductFormSheet(existing: product),
    );
  }

  Future<void> _openScanner(BuildContext context) async {
    final result = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (result == null || !context.mounted) return;
    // 1900 = elle gir sentineli (tarih okunmadi)
    final scanned = result.year == 1900 ? null : result;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductFormSheet(scannedExpiry: scanned),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Product product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sil'),
        content: Text('"${product.name}" silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true && product.id != null) {
      await ref.read(productListProvider.notifier).remove(product.id!);
    }
  }
}
