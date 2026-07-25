import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/domain/entities/product.dart';
import '../data/mock_seller_repository.dart';
import '../domain/entities/seller_models.dart';
import '../domain/repositories/seller_repository.dart';

final sellerRepositoryProvider = Provider<SellerRepository>((ref) => MockSellerRepository());
final sellerProvider = StateNotifierProvider<SellerController, SellerState>((ref) {
  return SellerController(ref.read(sellerRepositoryProvider));
});

class SellerController extends StateNotifier<SellerState> {
  SellerController(this._repository)
      : super(SellerState(
          products: [
            SellerProduct(id: 'seller-1', catalogId: 'avocado-box', name: 'Farm Fresh Avocado Box', icon: '🥑', price: 339, stockStatus: StockStatus.inStock, quantity: 18, lastPriceUpdate: DateTime.now()),
            SellerProduct(id: 'seller-2', catalogId: 'wave-headphones', name: 'Wave Wireless Headphones', icon: '🎧', price: 2449, stockStatus: StockStatus.lowStock, quantity: 4, lastPriceUpdate: DateTime.now().subtract(const Duration(days: 38))),
            SellerProduct(id: 'seller-3', catalogId: 'cold-brew', name: 'Classic Cold Brew', icon: '🧋', price: 179, stockStatus: StockStatus.outOfStock, quantity: 0, lastPriceUpdate: DateTime.now().subtract(const Duration(days: 45))),
          ],
          requests: [
            ProductRequest(id: 'request-1', productName: 'Organic Toor Dal 1 kg', category: 'Groceries', interestedBuyers: 18, radiusKm: 3, expiresAt: DateTime.now().add(const Duration(days: 2)), icon: '🫘', targetPrice: 165),
            ProductRequest(id: 'request-2', productName: 'USB-C Fast Charger', category: 'Electronics', interestedBuyers: 11, radiusKm: 5, expiresAt: DateTime.now().add(const Duration(days: 4)), icon: '🔌'),
          ],
          insights: const [
            SellerInsight(title: 'Most searched nearby', productName: 'Sunflower Oil 1 L', score: 92, type: 'search'),
            SellerInsight(title: 'Most watchlisted nearby', productName: 'Wireless Earbuds', score: 86, type: 'watchlist'),
            SellerInsight(title: 'High demand, not listed', productName: 'Organic Toor Dal', score: 81, type: 'missing'),
            SellerInsight(title: 'Price refresh needed', productName: 'Classic Cold Brew', score: 68, type: 'refresh'),
          ],
        ));

  final SellerRepository _repository;

  Future<void> sendOtp(String mobile) async {
    await _repository.sendOtp(mobile);
    state = state.copyWith(mobile: mobile, isOtpSent: true);
  }

  Future<bool> verifyOtp(String otp) async {
    final valid = await _repository.verifyOtp(state.mobile, otp);
    if (valid) state = state.copyWith(isAuthenticated: true);
    return valid;
  }

  Future<void> register(Seller seller) async {
    final saved = await _repository.saveSeller(seller);
    state = state.copyWith(seller: saved, mobile: saved.mobile, isAuthenticated: true);
  }

  bool addProduct(Product product, {required double price, required StockStatus stockStatus, required int quantity, double? offerPrice, DateTime? offerStart, DateTime? offerExpiry}) {
    if (state.products.any((item) => item.catalogId == product.id)) return false;
    state = state.copyWith(products: [...state.products, SellerProduct(id: 'seller-${DateTime.now().microsecondsSinceEpoch}', catalogId: product.id, name: product.name, icon: product.icon, price: price, stockStatus: stockStatus, quantity: quantity, offerPrice: offerPrice, offerStart: offerStart, offerExpiry: offerExpiry, lastPriceUpdate: DateTime.now())]);
    _repository.saveProducts(state.products);
    return true;
  }

  void updateProduct(String id, {required double price, required StockStatus stockStatus, required int quantity, double? offerPrice}) {
    state = state.copyWith(products: [for (final item in state.products) if (item.id == id) item.copyWith(price: price, stockStatus: stockStatus, quantity: quantity, offerPrice: offerPrice, clearOffer: offerPrice == null) else item]);
    _repository.saveProducts(state.products);
  }

  void deleteProduct(String id) {
    state = state.copyWith(products: state.products.where((item) => item.id != id).toList());
    _repository.saveProducts(state.products);
  }

  Future<void> requestProduct({required String name, required String category, String? imagePath}) async {
    final request = ProductRequest(id: 'new-${DateTime.now().microsecondsSinceEpoch}', productName: name, category: category, interestedBuyers: 0, radiusKm: 0, expiresAt: DateTime.now().add(const Duration(days: 30)), imagePath: imagePath, isSellerSubmitted: true);
    await _repository.saveProductRequest(request);
    state = state.copyWith(requests: [...state.requests, request]);
  }

  Future<void> respond(SellerResponse response) async {
    await _repository.saveResponse(response);
    state = state.copyWith(responses: [...state.responses.where((item) => item.requestId != response.requestId), response]);
  }

  void signOut() => state = SellerState(products: state.products, requests: state.requests, insights: state.insights);
}
