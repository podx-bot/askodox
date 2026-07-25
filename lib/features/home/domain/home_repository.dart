import '../../../models/product.dart';

abstract interface class HomeRepository {
  Future<List<Product>> featuredProducts();
}
