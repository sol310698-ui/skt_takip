import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/services/database_service.dart';
import '../core/services/notification_service.dart';
import '../data/datasources/barcode_directory_datasource.dart';
import '../data/datasources/control_list_datasource.dart';
import '../data/datasources/count_datasource.dart';
import '../data/datasources/product_local_datasource.dart';
import '../data/datasources/shift_local_datasource.dart';
import '../data/models/product.dart';
import '../data/models/shift_entry.dart';
import '../data/repositories/barcode_directory_repository.dart';
import '../data/repositories/control_list_repository.dart';
import '../data/repositories/count_repository.dart';
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

final controlListDataSourceProvider =
    Provider<ControlListDataSource>((ref) {
  return ControlListDataSource(ref.watch(databaseServiceProvider));
});

final controlListRepositoryProvider =
    Provider<ControlListRepository>((ref) {
  return ControlListRepository(ref.watch(controlListDataSourceProvider));
});

final countDataSourceProvider = Provider<CountDataSource>((ref) {
  return CountDataSource(ref.watch(databaseServiceProvider));
});

final countRepositoryProvider = Provider<CountRepository>((ref) {
  return CountRepository(ref.watch(countDataSourceProvider));
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

/// Stat kartına tıklanınca aktif durum filtresi (null = hepsi).
final statusFilterProvider = StateProvider<ExpiryStatus?>((ref) => null);

// ─── Product List ─────────────────────────────────────────────────────────────

final productListProvider =
    AsyncNotifierProvider<ProductListNotifier, List<Product>>(
  ProductListNotifier.new,
);

class ProductListNotifier extends AsyncNotifier<List<Product>> {
  ProductRepository get _repo => ref.read(productRepositoryProvider);

  @override
  Future<List<Product>> build() async {
    try { await _repo.purgeOldDisposals(); } catch (_) {}
    final products = await _repo.getProducts();
    // Eski bildirim sema gocunu arka planda yap (bloke etmez).
    _migrateNotificationsIfNeeded(products);
    return products;
  }

  Future<void> _migrateNotificationsIfNeeded(List<Product> products) async {
    final ids = products.map((p) => p.id).whereType<int>().toList();
    try {
      await NotificationService.instance.migrateOldSchemaIfNeeded(ids);
      // Yetim alarm temizligi: ids bos olsa da (urun yoksa) calistir, ki
      // tum eski alarmlar bos liste ile temizlensin (hicbiri "valid" degil).
      await NotificationService.instance.purgeOrphanProductAlarms(ids);
    } catch (_) {}
  }

  /// PERFORMANS: refresh() ARTIK loading durumuna gecmiyor. Eskiden her
  /// ekleme/silme/guncellemede state=AsyncLoading() set ediliyordu; bu da
  /// listenin EKRANDAN TAMAMEN KAYBOLUP yeniden gelmesine (flicker) yol
  /// aciyordu — buyuk listelerde bu his "kasma" gibi algilanir. Simdi
  /// yeni veri DB'den gelene kadar ESKI LISTE EKRANDA KALIR, sadece veri
  /// hazir olunca tek seferde degisir (kullanici icin akici gecis).
  Future<void> refresh() async {
    final result = await AsyncValue.guard(_repo.getProducts);
    state = result;
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
    // Urun bu arada silinmis olabilir (baska ekrandan/asistandan): StateError
    // firlatip akisi kirmak yerine sessizce cik.
    final idx = products.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final product = products[idx];
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
  final statusFilter = ref.watch(statusFilterProvider);
  final products = ref.watch(productListProvider).valueOrNull ?? [];

  var filtered = products;

  // Durum filtresi (stat kartindan).
  if (statusFilter != null) {
    filtered = filtered.where((p) => p.status == statusFilter).toList();
  }

  // Metin arama.
  if (query.isNotEmpty) {
    filtered = filtered.where((p) {
      return p.name.toLowerCase().contains(query) ||
          (p.barcode?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  return filtered;
});

