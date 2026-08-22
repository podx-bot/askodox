import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'price_benchmark_models.dart';

class EffectivePriceCalculator {
  const EffectivePriceCalculator();

  EffectivePrice online(OnlinePriceListing listing) {
    final double base = listing.offerPrice ?? listing.listedPrice;
    final double total = base +
        listing.deliveryFee +
        listing.platformFee +
        listing.otherCharges;
    return EffectivePrice(
      basePrice: base,
      deliveryFee: listing.deliveryFee,
      platformFee: listing.platformFee,
      otherCharges: listing.otherCharges,
      total: total,
    );
  }

  EffectivePrice local({
    required double sellingPrice,
    double? offerPrice,
    double? travelCost,
    double? pickupCost,
    bool includeOptionalCosts = false,
  }) {
    final double base = offerPrice ?? sellingPrice;
    final double optional = includeOptionalCosts
        ? (travelCost ?? 0.0) + (pickupCost ?? 0.0)
        : 0.0;
    return EffectivePrice(
      basePrice: base,
      travelCost: travelCost,
      pickupCost: pickupCost,
      total: base + optional,
    );
  }
}

class UnitPriceCalculator {
  const UnitPriceCalculator();

  UnitPrice? calculate({
    required double price,
    required double quantity,
    required String unit,
  }) {
    if (price < 0 || quantity <= 0) return null;
    final u = unit.toLowerCase();
    if (u == 'g' || u == 'gram' || u == 'grams') {
      return UnitPrice(amount: price / quantity * 100.0, basis: 100.0, unit: 'g');
    }
    if (u == 'kg') return UnitPrice(amount: price / quantity, basis: 1.0, unit: 'kg');
    if (u == 'ml') return UnitPrice(amount: price / quantity * 1000.0, basis: 1.0, unit: 'L');
    if (u == 'l' || u == 'litre' || u == 'liter') {
      return UnitPrice(amount: price / quantity, basis: 1.0, unit: 'L');
    }
    if (u == 'piece' || u == 'pieces' || u == 'unit') {
      return UnitPrice(amount: price / quantity, basis: 1.0, unit: 'piece');
    }
    return null;
  }
}

class ProductMatchingService {
  const ProductMatchingService();

  ProductMatchResult match({
    required String localBrand,
    required String onlineBrand,
    required String localProduct,
    required String onlineProduct,
    required double localQuantity,
    required double onlineQuantity,
    required String localUnit,
    required String onlineUnit,
    required String localVariant,
    required String onlineVariant,
  }) {
    bool same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();
    final identity = same(localBrand, onlineBrand) &&
        same(localProduct, onlineProduct) &&
        same(localVariant, onlineVariant);
    final pack = same(localUnit, onlineUnit) && localQuantity == onlineQuantity
        ? PackSizeMatch.exact
        : same(localUnit, onlineUnit)
            ? PackSizeMatch.equivalentUnit
            : PackSizeMatch.mismatch;
    final double confidence = (identity ? 0.75 : 0.0) +
        (pack == PackSizeMatch.exact
            ? 0.25
            : pack == PackSizeMatch.equivalentUnit
                ? 0.1
                : 0.0);
    return ProductMatchResult(
      matches: identity && pack == PackSizeMatch.exact,
      confidence: confidence,
      packSizeMatch: pack,
      reasons: [
        if (!identity) 'Brand, product or variant differs',
        if (pack != PackSizeMatch.exact) 'Pack sizes are different',
      ],
    );
  }
}

class PriceInsightService {
  const PriceInsightService({this.similarThresholdPercent = 3.0});
  final double similarThresholdPercent;

  PriceInsight create({
    double? localLowest,
    double? onlineLowest,
    required DataFreshness freshness,
    bool productMatches = true,
  }) {
    if (localLowest == null) {
      return const PriceInsight(type: PriceInsightType.localUnavailable, amount: 0.0, percentage: 0.0, strongClaimAllowed: false);
    }
    if (onlineLowest == null) {
      return const PriceInsight(type: PriceInsightType.onlineUnavailable, amount: 0.0, percentage: 0.0, strongClaimAllowed: false);
    }
    if (!productMatches) {
      return const PriceInsight(type: PriceInsightType.productMismatch, amount: 0.0, percentage: 0.0, strongClaimAllowed: false);
    }
    if (freshness == DataFreshness.stale || freshness == DataFreshness.expired || freshness == DataFreshness.unknown) {
      return const PriceInsight(type: PriceInsightType.stale, amount: 0.0, percentage: 0.0, strongClaimAllowed: false);
    }
    final double difference = onlineLowest - localLowest;
    final double percentage = onlineLowest <= 0.0 ? 0.0 : difference.abs() / onlineLowest * 100.0;
    final type = percentage <= similarThresholdPercent
        ? PriceInsightType.pricesSimilar
        : difference > 0.0
            ? PriceInsightType.localCheaper
            : PriceInsightType.onlineCheaper;
    return PriceInsight(type: type, amount: difference.abs(), percentage: percentage, strongClaimAllowed: true);
  }
}

class PriceConfidenceService {
  const PriceConfidenceService();

  PriceConfidence calculate({
    required int localListings,
    required int onlineObservations,
    required double matchConfidence,
    required PackSizeMatch packSizeMatch,
    required DataFreshness freshness,
    required double consistency,
    required double sourceReliability,
  }) {
    if (localListings == 0 || onlineObservations == 0) {
      return const PriceConfidence(level: PriceConfidenceLevel.insufficientData, score: 0.0, reasons: ['Local and online observations are required']);
    }
    final double freshnessScore = switch (freshness) {
      DataFreshness.updatedToday => 1.0,
      DataFreshness.withinThreeDays => 0.85,
      DataFreshness.withinSevenDays => 0.65,
      DataFreshness.stale => 0.3,
      DataFreshness.expired => 0.0,
      DataFreshness.unknown => 0.2,
    };
    final double packScore = packSizeMatch == PackSizeMatch.exact
        ? 1.0
        : packSizeMatch == PackSizeMatch.equivalentUnit
            ? 0.55
            : 0.0;
    final double volume = math.min<double>(1.0, (localListings + onlineObservations) / 6.0);
    final double score = (volume * 0.2 +
            matchConfidence * 0.25 +
            packScore * 0.2 +
            freshnessScore * 0.15 +
            consistency.clamp(0.0, 1.0).toDouble() * 0.1 +
            sourceReliability.clamp(0.0, 1.0).toDouble() * 0.1) *
        100.0;
    final reasons = <String>[
      if (packScore < 1.0) 'Pack-size match is not exact',
      if (freshnessScore < 0.65) 'Some price data is old',
      if (volume < 0.7) 'Few matching observations',
      if (sourceReliability < 0.6) 'Source reliability needs review',
    ];
    return PriceConfidence(
      level: score >= 80.0
          ? PriceConfidenceLevel.high
          : score >= 55.0
              ? PriceConfidenceLevel.medium
              : PriceConfidenceLevel.low,
      score: score,
      reasons: reasons,
    );
  }
}

DataFreshness priceFreshness(DateTime? observedAt, DateTime now) {
  if (observedAt == null) return DataFreshness.unknown;
  final age = now.difference(observedAt);
  if (age.isNegative || age.inDays < 1) return DataFreshness.updatedToday;
  if (age.inDays <= 3) return DataFreshness.withinThreeDays;
  if (age.inDays <= 7) return DataFreshness.withinSevenDays;
  if (age.inDays <= 14) return DataFreshness.stale;
  return DataFreshness.expired;
}

enum SellerPricePosition { lowestNearby, belowAverage, nearAverage, aboveAverage, insufficientData }

SellerPricePosition sellerPricePosition({
  required double sellerPrice,
  double? localLowest,
  double? localAverage,
}) {
  if (localLowest == null || localAverage == null || localAverage == 0.0) {
    return SellerPricePosition.insufficientData;
  }
  if (sellerPrice <= localLowest) return SellerPricePosition.lowestNearby;
  final double difference = (sellerPrice - localAverage) / localAverage * 100.0;
  if (difference < -3.0) return SellerPricePosition.belowAverage;
  if (difference.abs() <= 3.0) return SellerPricePosition.nearAverage;
  return SellerPricePosition.aboveAverage;
}

@immutable
class ComparisonAlertCandidate {
  const ComparisonAlertCandidate({required this.dedupeKey, required this.savings, required this.savingsPercent});
  final String dedupeKey;
  final double savings, savingsPercent;
}

class PriceComparisonAlertService {
  final Set<String> _sent = <String>{};

  ComparisonAlertCandidate? evaluate({
    required String productId,
    required double localPrice,
    required double onlineEffectivePrice,
    double? minimumSaving,
    double? minimumPercent,
  }) {
    final double saving = onlineEffectivePrice - localPrice;
    final double percent = onlineEffectivePrice <= 0.0 ? 0.0 : saving / onlineEffectivePrice * 100.0;
    if (saving <= 0.0 ||
        (minimumSaving != null && saving < minimumSaving) ||
        (minimumPercent != null && percent < minimumPercent)) {
      return null;
    }
    final key = '$productId:${localPrice.toStringAsFixed(2)}:${onlineEffectivePrice.toStringAsFixed(2)}';
    if (!_sent.add(key)) return null;
    return ComparisonAlertCandidate(dedupeKey: key, savings: saving, savingsPercent: percent);
  }
}
