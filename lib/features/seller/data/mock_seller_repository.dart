import '../domain/entities/seller_models.dart';
import '../domain/repositories/seller_repository.dart';

class MockSellerRepository implements SellerRepository {
  @override
  Future<void> sendOtp(String mobile) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  @override
  Future<bool> verifyOtp(String mobile, String otp) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return otp == '123456';
  }

  @override
  Future<ShopProfile> saveProfile(ShopProfile profile) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return profile;
  }
}
