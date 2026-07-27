import 'package:flutter/foundation.dart';

enum AlertType { availableNearby, priceDropped, targetPriceMatched, newSellerStock, newOffer, backInStock, requestedProductFound, localLowerThanOnline, savingAmountReached, savingPercentageReached, onlinePriceChanged, comparisonStale }
enum AlertFrequency { instant, daily, weekly }
enum ProductRequestStatus { pending, sentToSellers, sellerResponded, productFound, addedToCatalog, closed }

@immutable
class WatchlistItem {
  const WatchlistItem({required this.productId, required this.productName, required this.brand, required this.variant, required this.image, required this.createdAt, this.radiusKm = 5, this.targetPrice, this.alertsEnabled = true, this.frequency = AlertFrequency.instant, this.requestStatus});
  final String productId, productName, brand, variant, image;
  final DateTime createdAt;
  final double radiusKm;
  final double? targetPrice;
  final bool alertsEnabled;
  final AlertFrequency frequency;
  final ProductRequestStatus? requestStatus;
  WatchlistItem copyWith({double? radiusKm, double? targetPrice, bool clearTarget = false, bool? alertsEnabled, AlertFrequency? frequency, ProductRequestStatus? requestStatus}) => WatchlistItem(productId: productId, productName: productName, brand: brand, variant: variant, image: image, createdAt: createdAt, radiusKm: radiusKm ?? this.radiusKm, targetPrice: clearTarget ? null : targetPrice ?? this.targetPrice, alertsEnabled: alertsEnabled ?? this.alertsEnabled, frequency: frequency ?? this.frequency, requestStatus: requestStatus ?? this.requestStatus);
}

@immutable
class ProductAlert {
  const ProductAlert({required this.id, required this.type, required this.productId, required this.productName, required this.image, required this.sellerName, required this.price, required this.distanceKm, required this.createdAt, this.isRead = false});
  final String id, productId, productName, image, sellerName;
  final AlertType type;
  final double price, distanceKm;
  final DateTime createdAt;
  final bool isRead;
  ProductAlert copyWith({bool? isRead}) => ProductAlert(id:id,type:type,productId:productId,productName:productName,image:image,sellerName:sellerName,price:price,distanceKm:distanceKm,createdAt:createdAt,isRead:isRead??this.isRead);
}

@immutable
class AlertPreference {
  const AlertPreference({this.priceDrops=true,this.availability=true,this.offers=true,this.nearbySellers=true,this.requestedProducts=true,this.instant=true,this.daily=true,this.weekly=true,this.quietHours=false});
  final bool priceDrops, availability, offers, nearbySellers, requestedProducts, instant, daily, weekly, quietHours;
  AlertPreference copyWith({bool? priceDrops,bool? availability,bool? offers,bool? nearbySellers,bool? requestedProducts,bool? instant,bool? daily,bool? weekly,bool? quietHours}) => AlertPreference(priceDrops:priceDrops??this.priceDrops,availability:availability??this.availability,offers:offers??this.offers,nearbySellers:nearbySellers??this.nearbySellers,requestedProducts:requestedProducts??this.requestedProducts,instant:instant??this.instant,daily:daily??this.daily,weekly:weekly??this.weekly,quietHours:quietHours??this.quietHours);
}

class DemandScore {
  const DemandScore({required this.productId,required this.score,required this.interestedBuyers,required this.watchlists,required this.requests});
  final String productId; final double score; final int interestedBuyers,watchlists,requests;
  String get level => score>=70?'High demand':score>=40?'Medium demand':'Low demand';
  static DemandScore calculate({required String productId,required int searches,required int watchlists,required int requests,required int targetIntents,required int nearbyBuyers,required int recentActivity}) { final value=(searches*.25+watchlists*.25+requests*.2+targetIntents*.1+nearbyBuyers*.1+recentActivity*.1).clamp(0,100).toDouble(); return DemandScore(productId:productId,score:value,interestedBuyers:nearbyBuyers,watchlists:watchlists,requests:requests); }
}
class AreaDemandInsight { const AreaDemandInsight({required this.productId,required this.productName,required this.score}); final String productId,productName; final DemandScore score; }
class SellerStockSuggestion { const SellerStockSuggestion({required this.productId,required this.productName,required this.reason,required this.priority}); final String productId,productName,reason,priority; }

class AlertEvent { const AlertEvent({required this.productId,required this.sellerName,required this.price,required this.previousPrice,required this.inStock,required this.wasInStock,required this.distanceKm,this.hasOffer=false}); final String productId,sellerName; final double price,previousPrice,distanceKm; final bool inStock,wasInStock,hasOffer; }
