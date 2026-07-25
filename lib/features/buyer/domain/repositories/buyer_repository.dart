import '../entities/buyer_models.dart';

abstract interface class BuyerRepository {
  Future<List<BuyerLocation>> locations();
  Future<List<ProductPriceListing>> listings(String productId);
  Future<void> saveDefaultRadius(double kilometres);
  Future<void> saveRequest(BuyerProductRequest request);
  Future<void> reportWrongPrice(WrongPriceReport report);
}
