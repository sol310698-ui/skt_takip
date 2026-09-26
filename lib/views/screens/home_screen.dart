import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/product.dart';
import '../../viewmodels/providers.dart';
import '../widgets/product_card.dart';
import '../widgets/ui_kit.dart';

/// Inventory home. The UI is Material 3, but all values come from SQLite
/// through Riverpod; there are no placeholder products or counters here.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      ref.read(searchQueryProvider.notifier).state = _searchCtrl.text;
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final products = ref.watch(filteredProductsProvider);
    final all = productsAsync.valueOrNull ?? const <Product>[];
    final expired = all.where((p) => p.status == ExpiryStatus.expired).length;
    final approaching = all.where((p) => p.status == ExpiryStatus.warning ||
        p.status == ExpiryStatus.critical).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(productListProvider.notifier).refresh(),
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Merhaba', style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppTheme.textTertiary)),
                const SizedBox(height: 4),
                Text('SKT Takip', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 18),
                TextField(controller: _searchCtrl,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                        hintText: 'Ürün veya barkod ara...')),
                const SizedBox(height: 14),
                Row(children: [
                  StatTile(label: 'Toplam', value: '${all.length}', color: AppTheme.primary,
                      onTap: () => ref.read(statusFilterProvider.notifier).state = null),
                  const SizedBox(width: 8),
                  StatTile(label: 'Yakında', value: '$approaching', color: AppTheme.warning,
                      onTap: () => ref.read(statusFilterProvider.notifier).state = ExpiryStatus.warning),
                  const SizedBox(width: 8),
                  StatTile(label: 'Süre doldu', value: '$expired', color: AppTheme.danger,
                      onTap: () => ref.read(statusFilterProvider.notifier).state = ExpiryStatus.expired),
                ]),
              ]),
            )),
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('Ürünler', style: Theme.of(context).textTheme.titleLarge),
            )),
            productsAsync.when(
              loading: () => const SliverFillRemaining(hasScrollBody: false,
                  child: LoadingState()),
              error: (error, stack) => SliverFillRemaining(hasScrollBody: false,
                  child: ErrorStateView(error: error,
                      onRetry: () => ref.invalidate(productListProvider))),
              data: (_) => products.isEmpty
                  ? const SliverFillRemaining(hasScrollBody: false,
                      child: EmptyState(icon: Icons.inventory_2_outlined,
                          title: 'Ürün bulunamadı', subtitle: 'Ürün ekleyin veya arama filtresini temizleyin.'))
                  : SliverList(delegate: SliverChildBuilderDelegate(
                      (context, index) => ProductCard(product: products[index]),
                      childCount: products.length)),
            ),
          ]),
        ),
      ),
    );
  }
}
