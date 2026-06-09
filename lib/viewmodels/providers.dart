import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/database_service.dart';
import '../core/services/notification_service.dart';
import '../data/datasources/barcode_directory_datasource.dart';
import '../data/datasources/product_local_datasource.dart';
import '../data/datasources/shift_local_datasource.dart';
import '../data/models/product.dart';
import '../data/models/shift_entry.dart';
import '../data/repositories/barcode_directory_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/shift_repository.dart';

// ─── DI Providers ────────────────────────────────────────────────────────────

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

final barcodeDirectoryDataSourceProvider =
    Provider<BarcodeDirectoryDataSource>((ref) {
  return BarcodeDirectoryDataSource(ref.watch(databaseServiceProvider));
});

final barcodeDirectoryRepositoryProvider =
    Provider<BarcodeDirectoryRepository>((ref) {
  return BarcodeDirectoryRepository(
      ref.watch(barcodeDirectoryDataSourceProvider));
});

final shiftLocalDataSourceProvider = Provider<ShiftLocalDataSource>((ref) {
  return ShiftLocalDataSource(ref.watch(databaseServiceProvider));
});

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  return ShiftRepository(ref.watch(shiftLocalDataSourceProvider));
});

/// Mesai listesi + acik vardiya durumu.
final shiftListProvider =
    AsyncNotifierProvider<ShiftListNotifier, List<ShiftEntry>>(
  ShiftListNotifier.new,
);

class ShiftListNotifier extends AsyncNotifier<List<ShiftEntry>> {
  ShiftRepository get _repo => ref.read(shiftRepositoryProvider);

  @override
  Future<List<ShiftEntry>> build() async {
    return _repo.getShifts();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.getShifts);
  }

  Future<int> add(ShiftEntry s) async {
    final id = await _repo.addShift(s);
    await refresh();
    return id;
  }

  Future<void> updateShift(ShiftEntry s) async {
    await _repo.updateShift(s);
    await refresh();
  }

  Future<void> remove(int id) async {
    await _repo.deleteShift(id);
    await refresh();
  }
}

/// Acik (devam eden) vardiya - null ise mesaide degil.
final openShiftProvider = FutureProvider<ShiftEntry?>((ref) {
  // shiftList degisince bu da yenilensin
  ref.watch(shiftListProvider);
  return ref.read(shiftRepositoryProvider).getOpenShift();
});

// ─── UI State Providers ───────────────────────────────────────────────────────

final searchQueryProvider = StateProvider<String>((ref) => '');

// ─── Product List ─────────────────────────────────────────────────────────────

final productListProvider =
    AsyncNotifierProvider<ProductListNotifier, List<Product>>(
  ProductListNotifier.new,
);

class ProductListNotifier extends AsyncNotifier<List<Product>> {
  ProductRepository get _repo => ref.read(productRepositoryProvider);

  @override
  Future<List<Product>> build() async {
    // Acilista 90 gunden eski imha/iade kayitlarini temizle (DB sismesini onler).
    // Hata olursa listelemeyi engellemesin.
    try {
      await _repo.purgeOldDisposals();
    } catch (_) {}
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
    await NotificationService.instance.cancelForProduct(id);
    await refresh();
  }

  /// Urunu imha veya iade olarak isaretle (silmez, gunceller).
  Future<void> dispose_(int id, DisposalStatus status, String? note) async {
    final products = state.valueOrNull ?? [];
    final product = products.firstWhere((p) => p.id == id);
    final updated = product.copyWith(
      disposalStatus: status,
      disposalDate: DateTime.now(),
      disposalNote: note,
    );
    await _repo.updateProduct(updated);
    // Artik rafta degil: planlanmis SKT bildirimlerini iptal et.
    await NotificationService.instance.cancelForProduct(id);
    await refresh();
  }
}

// ─── Disposal History ─────────────────────────────────────────────────────────

final disposalHistoryProvider =
    AsyncNotifierProvider<DisposalHistoryNotifier, List<Product>>(
  DisposalHistoryNotifier.new,
);

class DisposalHistoryNotifier extends AsyncNotifier<List<Product>> {
  ProductRepository get _repo => ref.read(productRepositoryProvider);

  @override
  Future<List<Product>> build() async {
    return _repo.getDisposalHistory();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.getDisposalHistory);
  }
}

// ─── Filtered Products ────────────────────────────────────────────────────────

final filteredProductsProvider = Provider<List<Product>>((ref) {
  final query = ref.watch(searchQueryProvider).toLowerCase().trim();
  final products = ref.watch(productListProvider).valueOrNull ?? [];
  if (query.isEmpty) return products;
  return products.where((p) {
    return p.name.toLowerCase().contains(query) ||
        (p.barcode?.toLowerCase().contains(query) ?? false);
  }).toList();
});

