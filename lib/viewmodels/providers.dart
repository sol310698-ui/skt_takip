import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/database_service.dart';
import '../data/datasources/product_local_datasource.dart';
import '../data/models/product.dart';
import '../data/repositories/product_repository.dart';

/// Bağımlılık sağlayıcıları (DI).

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService.instance;
});

final productLocalDataSourceProvider =
    Provider<ProductLocalDataSource>((ref) {
  return ProductLocalDataSource(ref.watch(databaseServiceProvider));
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(ref.watch(productLocalDataSourceProvider));
});

/// Arama metni durumu.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Ürün listesini yöneten AsyncNotifier.
final productListProvider =
    AsyncNotifierProvider<ProductListNotifier, List<Product>>(
  ProductListNotifier.new,
);

class ProductListNotifier extends AsyncNotifier<List<Product>> {
  ProductRepository get _repo => ref.read(productRepositoryProvider);

  @override
  Future<List<Product>> build() async {
    return _repo.getProducts();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.getProducts);
  }

  Future<int> add(Product product) async {
    final id = await _repo.addProduct(product);
    await refresh();
    return id;
  }

  Future<void> updateProduct(Product product) async {
    await _repo.updateProduct(product);
    await refresh();
  }

  Future<void> remove(int id) async {
    await _repo.deleteProduct(id);
    await refresh();
  }
}

/// Aramaya göre filtrelenmiş ürün listesi (türetilmiş).
final filteredProductsProvider = Provider<List<Product>>((ref) {
  final query = ref.watch(searchQueryProvider).toLowerCase().trim();
  final products = ref.watch(productListProvider).valueOrNull ?? [];
  if (query.isEmpty) return products;
  return products.where((p) {
    return p.name.toLowerCase().contains(query) ||
        (p.barcode?.toLowerCase().contains(query) ?? false);
  }).toList();
});
