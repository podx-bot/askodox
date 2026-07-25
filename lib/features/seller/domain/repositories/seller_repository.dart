import '../entities/seller_models.dart';

abstract interface class SellerRepository {
  Future<void> sendOtp(String mobile);
  Future<bool> verifyOtp(String mobile, String otp);
  Future<Seller> saveSeller(Seller seller);
  Future<List<SellerProduct>> loadProducts();
  Future<void> saveProducts(List<SellerProduct> products);
  Future<List<ProductRequest>> loadRequests();
  Future<void> saveProductRequest(ProductRequest request);
  Future<void> saveResponse(SellerResponse response);
  Future<List<SellerInsight>> loadInsights();
}
