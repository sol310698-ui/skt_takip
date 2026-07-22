import '../datasources/product_local_datasource.dart';
import '../models/product.dart';

/// Urun verisi icin repository katmani.
class ProductRepository {
  final ProductLocalDataSource _local;
  ProductRepository(this._local);

  Future<List<Product>> getProducts() => _local.getActive();
  Future<List<Product>> getDisposalHistory() => _local.getDisposalHistory();
  Future<List<Product>> getAllActiveByBarcode(String barcode) =>
      _local.getAllActiveByBarcode(barcode);
  Future<Product?> findByBarcode(String barcode) => _local.getByBarcode(barcode);
  /// Bu barkodla kayitli TUM aktif SKT urunleri (yakin tarih once).
  Future<List<Product>> findActiveListByBarcode(String barcode) =>
      _local.getActiveListByBarcode(barcode);
  Future<int> addProduct(Product product) => _local.insert(product);
  Future<int> updateProduct(Product product) => _local.update(product);
  Future<int> deleteProduct(int id) => _local.delete(id);
  Future<void> importProducts(List<Product> products) => _local.insertAll(products);
  Future<void> purgeOldDisposals() => _local.purgeOldDisposals();

  /// MUKERRER TEMIZLEME.
  /// Ayni BARKOD + ayni SKT TARIHI olan aktif kayitlardan SADECE BIR tane
  /// birakir (en eski kayit = en kucuk id korunur), digerlerini siler.
  /// Farkli tarihli ayni barkod (gercek farkli partiler) KORUNUR.
  /// Barkodu olmayan kayitlara dokunulmaz (yanlislikla silmemek icin).
  /// Silinen kayit sayisini doner.
  Future<int> removeDuplicates() async {
    final active = await _local.getActive();

    // Anahtar: barkod + SKT tarihi (gun bazinda). Grupla.
    final groups = <String, List<Product>>{};
    for (final p in active) {
      final bc = (p.barcode ?? '').trim();
      if (bc.isEmpty) continue; // barkodsuz kayda dokunma
      final d = p.expiryDate;
      final key = '$bc|${d.year}-${d.month}-${d.day}';
      (groups[key] ??= []).add(p);
    }

    int removed = 0;
    for (final list in groups.values) {
      if (list.length < 2) continue; // mukerrer degil
      // En eski kaydi (en kucuk id) koru, gerisini sil.
      list.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
      for (int i = 1; i < list.length; i++) {
        final id = list[i].id;
        if (id != null) {
          await _local.delete(id);
          removed++;
        }
      }
    }
    return removed;
  }
}
