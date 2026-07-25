import 'package:flutter/foundation.dart';

enum SearchRadius {
  metres100(.1, '100 m'), metres200(.2, '200 m'), metres500(.5, '500 m'),
  kilometre1(1, '1 km'), kilometres2(2, '2 km'), kilometres5(5, '5 km'),
  kilometres10(10, '10 km'), kilometres25(25, '25 km'), kilometres50(50, '50 km'), custom(-1, 'Custom');
  const SearchRadius(this.kilometres, this.label);
  final double kilometres;
  final String label;
}

@immutable
class BuyerLocation {
  const BuyerLocation({required this.id, required this.label, required this.address, required this.latitude, required this.longitude});
  final String id, label, address;
  final double latitude, longitude;
}

enum PriceFreshness { today, withinThreeDays, withinSevenDays, old }
enum SearchSortOption { lowestPrice, nearestShop, highestTrust, bestOffer, recentlyUpdated }

@immutable
class SearchFilter {
  const SearchFilter({this.inStockOnly = true, this.offersOnly = false, this.verifiedOnly = false, this.maximumDistanceKm, this.minimumPrice, this.maximumPrice, this.shopCategory});
  final bool inStockOnly, offersOnly, verifiedOnly;
  final double? maximumDistanceKm, minimumPrice, maximumPrice;
  final String? shopCategory;
  SearchFilter copyWith({bool? inStockOnly, bool? offersOnly, bool? verifiedOnly, double? maximumDistanceKm, double? minimumPrice, double? maximumPrice, String? shopCategory}) => SearchFilter(inStockOnly: inStockOnly ?? this.inStockOnly, offersOnly: offersOnly ?? this.offersOnly, verifiedOnly: verifiedOnly ?? this.verifiedOnly, maximumDistanceKm: maximumDistanceKm ?? this.maximumDistanceKm, minimumPrice: minimumPrice ?? this.minimumPrice, maximumPrice: maximumPrice ?? this.maximumPrice, shopCategory: shopCategory ?? this.shopCategory);
}

@immutable
class ProductPriceListing {
  const ProductPriceListing({required this.id, required this.productId, required this.shopId, required this.shopName, required this.shopCategory, required this.latitude, required this.longitude, required this.price, required this.inStock, required this.updatedAt, required this.verified, required this.trustScore, required this.isOpen, this.offerPrice});
  final String id, productId, shopId, shopName, shopCategory;
  final double latitude, longitude, price, trustScore;
  final double? offerPrice;
  final bool inStock, verified, isOpen;
  final DateTime updatedAt;
  double get effectivePrice => offerPrice ?? price;
  PriceFreshness freshness(DateTime now) { final days = now.difference(updatedAt).inDays; return days < 1 ? PriceFreshness.today : days <= 3 ? PriceFreshness.withinThreeDays : days <= 7 ? PriceFreshness.withinSevenDays : PriceFreshness.old; }
}

@immutable
class NearbySellerResult {
  const NearbySellerResult({required this.listing, required this.distanceKm});
  final ProductPriceListing listing;
  final double distanceKm;
}

@immutable
class WrongPriceReport {
  const WrongPriceReport({required this.id, required this.listingId, required this.reason, required this.createdAt});
  final String id, listingId, reason;
  final DateTime createdAt;
}

@immutable
class BuyerProductRequest {
  const BuyerProductRequest({required this.id, required this.productName, required this.createdAt, this.imagePath, this.watchlisted = false, this.notify = false});
  final String id, productName;
  final DateTime createdAt;
  final String? imagePath;
  final bool watchlisted, notify;
}
