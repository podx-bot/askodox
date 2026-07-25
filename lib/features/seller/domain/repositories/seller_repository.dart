import '../entities/seller_models.dart';

abstract interface class SellerRepository {
  Future<void> sendOtp(String mobile);
  Future<bool> verifyOtp(String mobile, String otp);
  Future<ShopProfile> saveProfile(ShopProfile profile);
}
