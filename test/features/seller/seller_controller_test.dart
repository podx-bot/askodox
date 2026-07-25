import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/catalog/domain/entities/brand.dart';
import 'package:podx/features/catalog/domain/entities/product.dart';
import 'package:podx/features/seller/application/seller_providers.dart';
import 'package:podx/features/seller/data/mock_seller_repository.dart';
import 'package:podx/features/seller/domain/entities/seller_models.dart';

void main() {
  late SellerController controller;
  setUp(() => controller = SellerController(MockSellerRepository()));

  test('mock OTP only accepts 123456', () async {
    await controller.sendOtp('9876543210');
    expect(await controller.verifyOtp('000000'), isFalse);
    expect(await controller.verifyOtp('123456'), isTrue);
    expect(controller.state.isAuthenticated, isTrue);
  });

  test('a master product cannot be added twice', () {
    const product = Product(id: 'unique', name: 'Test product', description: '', price: 100, originalPrice: 100, icon: '🛒', categoryId: 'cat', subcategoryId: 'sub', brand: Brand(id: 'brand', name: 'Brand', verified: true), rating: 0, reviewCount: 0, inStock: true, tags: []);
    expect(controller.addProduct(product, price: 90, stockStatus: StockStatus.inStock, quantity: 5), isTrue);
    expect(controller.addProduct(product, price: 90, stockStatus: StockStatus.inStock, quantity: 5), isFalse);
    expect(controller.state.products.where((item) => item.catalogId == 'unique'), hasLength(1));
  });

  test('new product request remains pending local data', () async {
    await controller.requestProduct(name: 'Missing item', category: 'Other');
    final request = controller.state.requests.last;
    expect(request.productName, 'Missing item');
    expect(request.isSellerSubmitted, isTrue);
  });
}
