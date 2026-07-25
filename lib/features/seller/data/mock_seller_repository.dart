import '../domain/entities/seller_models.dart';
import '../domain/repositories/seller_repository.dart';

class MockSellerRepository implements SellerRepository {
  final List<SellerProduct> _products = [];
  final List<ProductRequest> _sellerRequests = [];
  final List<SellerResponse> _responses = [];

  @override
  Future<void> sendOtp(String mobile) async => Future<void>.delayed(const Duration(milliseconds: 250));

  @override
  Future<bool> verifyOtp(String mobile, String otp) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return otp == '123456';
  }

  @override
  Future<Seller> saveSeller(Seller seller) async => seller;

  @override
  Future<List<SellerProduct>> loadProducts() async => List.unmodifiable(_products);

  @override
  Future<void> saveProducts(List<SellerProduct> products) async {
    _products..clear()..addAll(products);
  }

  @override
  Future<List<ProductRequest>> loadRequests() async => [
    ProductRequest(id: 'request-1', productName: 'Organic Toor Dal 1 kg', category: 'Groceries', interestedBuyers: 18, radiusKm: 3, expiresAt: DateTime.now().add(const Duration(days: 2)), icon: '🫘', targetPrice: 165),
    ProductRequest(id: 'request-2', productName: 'USB-C Fast Charger', category: 'Electronics', interestedBuyers: 11, radiusKm: 5, expiresAt: DateTime.now().add(const Duration(days: 4)), icon: '🔌'),
    ..._sellerRequests,
  ];

  @override
  Future<void> saveProductRequest(ProductRequest request) async => _sellerRequests.add(request);

  @override
  Future<void> saveResponse(SellerResponse response) async => _responses.add(response);

  @override
  Future<List<SellerInsight>> loadInsights() async => const [
    SellerInsight(title: 'Most searched nearby', productName: 'Sunflower Oil 1 L', score: 92, type: 'search'),
    SellerInsight(title: 'Most watchlisted nearby', productName: 'Wireless Earbuds', score: 86, type: 'watchlist'),
    SellerInsight(title: 'High demand, not listed', productName: 'Organic Toor Dal', score: 81, type: 'missing'),
    SellerInsight(title: 'Price refresh needed', productName: 'Classic Cold Brew', score: 68, type: 'refresh'),
  ];
}
