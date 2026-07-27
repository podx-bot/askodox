import 'package:flutter/foundation.dart';

enum OnlineSourceType { retailerApi, affiliateFeed, sellerSubmitted, adminVerified, licensedProvider, mock }
enum PackSizeMatch { exact, equivalentUnit, mismatch, unknown }
enum PriceInsightType { localCheaper, onlineCheaper, pricesSimilar, insufficientData, productMismatch, onlineUnavailable, localUnavailable, stale }
enum PriceConfidenceLevel { high, medium, low, insufficientData }
enum DataFreshness { updatedToday, withinThreeDays, withinSevenDays, stale, expired, unknown }
enum PriceObservationChannel { local, online }

@immutable
class OnlinePriceSource {
  const OnlinePriceSource({required this.id, required this.name, required this.type, this.enabled = true, this.reliabilityNote});
  final String id, name;
  final OnlineSourceType type;
  final bool enabled;
  final String? reliabilityNote;
}

@immutable
class OnlinePriceListing {
  const OnlinePriceListing({required this.id, required this.source, required this.productId, required this.listedPrice, required this.deliveryFee, required this.platformFee, required this.minimumOrderValue, required this.available, required this.quantity, required this.unit, required this.variant, required this.lastCheckedAt, this.offerPrice, this.otherCharges = 0, this.productUrl});
  final String id, productId, variant, unit;
  final OnlinePriceSource source;
  final String? productUrl;
  final double listedPrice, deliveryFee, platformFee, minimumOrderValue, quantity, otherCharges;
  final double? offerPrice;
  final bool available;
  final DateTime lastCheckedAt;
  String get packSize => '${quantity.toStringAsFixed(quantity.truncateToDouble() == quantity ? 0 : 1)} $unit';
}

@immutable
class EffectivePrice {
  const EffectivePrice({required this.basePrice, required this.total, this.deliveryFee = 0, this.platformFee = 0, this.otherCharges = 0, this.travelCost, this.pickupCost});
  final double basePrice, total, deliveryFee, platformFee, otherCharges;
  final double? travelCost, pickupCost;
}

@immutable
class ProductMatchResult {
  const ProductMatchResult({required this.matches, required this.confidence, required this.packSizeMatch, required this.reasons});
  final bool matches;
  final double confidence;
  final PackSizeMatch packSizeMatch;
  final List<String> reasons;
}

@immutable
class UnitPrice { const UnitPrice({required this.amount, required this.basis, required this.unit}); final double amount, basis; final String unit; }

@immutable
class FairPriceRange { const FairPriceRange(this.minimum, this.maximum); final double minimum, maximum; }

@immutable
class PriceBenchmark {
  const PriceBenchmark({required this.localLowest, required this.localAverage, required this.localHighest, required this.onlineLowest, required this.onlineAverage, required this.onlineHighest, required this.overallAverage, required this.median, required this.fairRange, required this.observations, required this.volatility, required this.freshness});
  final double localLowest, localAverage, localHighest, onlineLowest, onlineAverage, onlineHighest, overallAverage, median, volatility;
  final FairPriceRange fairRange;
  final int observations;
  final DataFreshness freshness;
  double get savingsAmount => onlineLowest - localLowest;
  double get savingsPercentage => onlineLowest <= 0 ? 0 : savingsAmount / onlineLowest * 100;
  double get differenceFromOnlineAverage => localLowest - onlineAverage;
  double get differenceFromLocalAverage => localLowest - localAverage;
}

@immutable
class PriceInsight { const PriceInsight({required this.type, required this.amount, required this.percentage, required this.strongClaimAllowed}); final PriceInsightType type; final double amount, percentage; final bool strongClaimAllowed; }

@immutable
class PriceConfidence {
  const PriceConfidence({required this.level, required this.score, required this.reasons});
  final PriceConfidenceLevel level;
  final double score;
  final List<String> reasons;
  bool get canShowComparisonLabel => level == PriceConfidenceLevel.high || level == PriceConfidenceLevel.medium;
}

@immutable
class PriceObservation { const PriceObservation({required this.id, required this.productId, required this.channel, required this.price, required this.observedAt, required this.sourceId, this.stale = false}); final String id, productId, sourceId; final PriceObservationChannel channel; final double price; final DateTime observedAt; final bool stale; }
@immutable
class PriceHistoryPoint { const PriceHistoryPoint({required this.date, required this.localLowest, required this.localAverage, required this.onlineLowest, required this.onlineAverage, this.isMock = true}); final DateTime date; final double localLowest, localAverage, onlineLowest, onlineAverage; final bool isMock; }
@immutable
class PriceComparisonDisclosure { const PriceComparisonDisclosure({required this.isMock, required this.requiresConfirmation}); final bool isMock, requiresConfirmation; }

