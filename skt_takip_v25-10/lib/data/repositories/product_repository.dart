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
  Future<int> addProduct(Product product) => _local.insert(product);
  Future<int> updateProduct(Product product) => _local.update(product);
  Future<int> deleteProduct(int id) => _local.delete(id);
  Future<void> importProducts(List<Product> products) => _local.insertAll(products);
  Future<void> purgeOldDisposals() => _local.purgeOldDisposals();
}
