import '../domain/entities/buyer_models.dart';
import '../domain/repositories/buyer_repository.dart';

class MockBuyerRepository implements BuyerRepository {
  final requests = <BuyerProductRequest>[];
  final reports = <WrongPriceReport>[];
  double defaultRadius = 5;
  @override Future<List<BuyerLocation>> locations() async => const [
    BuyerLocation(id: 'current', label: 'Current location', address: 'Banjara Hills, Hyderabad', latitude: 17.4156, longitude: 78.4347),
    BuyerLocation(id: 'home', label: 'Home', address: 'Jubilee Hills, Hyderabad', latitude: 17.4326, longitude: 78.4071),
    BuyerLocation(id: 'work', label: 'Work', address: 'Somajiguda, Hyderabad', latitude: 17.4239, longitude: 78.4738),
  ];
  @override Future<List<ProductPriceListing>> listings(String productId) async {
    final now = DateTime.now();
    final seeds = [
      ('s1','ASKODOX Fresh Mart','Supermarket',17.4170,78.4370,349.0,329.0,true,true,4.8,true,2),
      ('s2','Sri Local Stores','Kirana',17.4260,78.4430,315.0,null,true,false,4.1,true,25),
      ('s3','Metro Daily','Supermarket',17.4380,78.4510,365.0,319.0,true,true,4.9,false,74),
      ('s4','Neighbour Basket','Kirana',17.4810,78.4850,305.0,null,false,true,4.5,true,10),
      ('s5','Value Hyper','Hypermarket',17.4050,78.4200,359.0,299.0,true,true,4.6,true,180),
    ];
    return [for (final s in seeds) ProductPriceListing(id: '${productId}_${s.$1}', productId: productId, shopId: s.$1, shopName: s.$2, shopCategory: s.$3, latitude: s.$4, longitude: s.$5, price: s.$6, offerPrice: s.$7, inStock: s.$8, verified: s.$9, trustScore: s.$10, isOpen: s.$11, updatedAt: now.subtract(Duration(hours: s.$12)))];
  }
  @override Future<void> saveDefaultRadius(double kilometres) async { defaultRadius = kilometres; }
  @override Future<void> saveRequest(BuyerProductRequest request) async { requests.add(request); }
  @override Future<void> reportWrongPrice(WrongPriceReport report) async { reports.add(report); }
}
