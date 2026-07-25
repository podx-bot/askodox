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
      : super(const SellerState(products: [
          SellerProduct(id: 'seller-1', catalogId: 'avocado-box', name: 'Farm Fresh Avocado Box', icon: '🥑', price: 339, stock: 18),
          SellerProduct(id: 'seller-2', catalogId: 'wave-headphones', name: 'Wave Wireless Headphones', icon: '🎧', price: 2449, stock: 7),
          SellerProduct(id: 'seller-3', catalogId: 'cold-brew', name: 'Classic Cold Brew', icon: '🧋', price: 179, stock: 0),
        ]));

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

  Future<void> register(ShopProfile profile) async {
    final saved = await _repository.saveProfile(profile);
    state = state.copyWith(profile: saved, mobile: saved.mobile, isAuthenticated: true);
  }

  void addProduct(Product product, double price, int stock) {
    if (state.products.any((item) => item.catalogId == product.id)) return;
    state = state.copyWith(products: [
      ...state.products,
      SellerProduct(id: 'seller-${DateTime.now().microsecondsSinceEpoch}', catalogId: product.id, name: product.name, icon: product.icon, price: price, stock: stock),
    ]);
  }

  void updateProduct(String id, double price, int stock) => state = state.copyWith(
        products: [for (final item in state.products) if (item.id == id) item.copyWith(price: price, stock: stock) else item],
      );

  void deleteProduct(String id) => state = state.copyWith(products: state.products.where((item) => item.id != id).toList());

  void signOut() => state = SellerState(products: state.products);
}
