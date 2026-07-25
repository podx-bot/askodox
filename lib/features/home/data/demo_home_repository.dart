import '../../../models/product.dart';
import '../domain/home_repository.dart';

class DemoHomeRepository implements HomeRepository {
  @override
  Future<List<Product>> featuredProducts() async => const [
        Product(name: 'Fresh produce', shop: 'Green Basket', price: 249, icon: '🥬'),
        Product(name: 'Handmade decor', shop: 'Craft Corner', price: 799, icon: '🏺'),
        Product(name: 'Daily essentials', shop: 'Neighborhood Mart', price: 349, icon: '🛍️'),
        Product(name: 'Artisan coffee', shop: 'Bean Local', price: 429, icon: '☕'),
      ];
}
