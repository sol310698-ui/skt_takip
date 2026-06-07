import '../datasources/product_local_datasource.dart';
import '../models/product.dart';

/// Ürün verisi için repository katmanı.
/// ViewModel'ler yalnızca bu katmanla konuşur.
class ProductRepository {
  final ProductLocalDataSource _local;

  ProductRepository(this._local);

  Future<List<Product>> getProducts() => _local.getAll();

  Future<Product?> findByBarcode(String barcode) =>
      _local.getByBarcode(barcode);

  Future<int> addProduct(Product product) => _local.insert(product);

  Future<int> updateProduct(Product product) => _local.update(product);

  Future<int> deleteProduct(int id) => _local.delete(id);

  Future<void> importProducts(List<Product> products) =>
      _local.insertAll(products);
}
