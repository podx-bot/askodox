import 'brand.dart';
import 'category.dart';
import 'product.dart';

class Catalog {
  const Catalog({required this.categories, required this.brands, required this.products});

  final List<ProductCategory> categories;
  final List<Brand> brands;
  final List<Product> products;
}
