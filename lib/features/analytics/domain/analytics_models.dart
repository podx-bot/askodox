enum AnalyticsEventType { appOpened, screenViewed, productSearched, searchFailed, productViewed, priceComparisonOpened, shopViewed, watchlistItemAdded, watchlistItemRemoved, productRequested, sellerResponseSubmitted, shopFollowed, offerViewed, offerClicked, sellerProductAdded, sellerPriceUpdated, sellerStockUpdated, subscriptionPlanViewed, mockPaymentCompleted, notificationOpened }

enum AnalyticsTimeRange { today, last7Days, last30Days, last90Days, custom }
enum MetricTrend { increasing, decreasing, stable }
enum DemandLevel { veryHigh, high, medium, low, insufficientData }
enum CompetitivenessLabel { lowestPrice, competitive, aboveAverage, highPrice, insufficientData }

class AnalyticsEvent {
  const AnalyticsEvent({required this.type, required this.occurredAt, this.properties = const {}});
  final AnalyticsEventType type;
  final DateTime occurredAt;
  final Map<String, Object> properties;
}

class MetricValue {
  const MetricValue(this.label, this.current, this.previous, {this.unit = ''});
  final String label, unit;
  final double current, previous;
  double get percentageChange => previous == 0 ? (current == 0 ? 0 : 100) : ((current - previous) / previous) * 100;
  MetricTrend get trend => percentageChange.abs() < 1 ? MetricTrend.stable : percentageChange > 0 ? MetricTrend.increasing : MetricTrend.decreasing;
}

class BuyerInsight { const BuyerInsight(this.title, this.summary, this.value); final String title, summary, value; }
class SellerPerformanceMetric { const SellerPerformanceMetric(this.metric); final MetricValue metric; }

class ProductPerformance {
  const ProductPerformance({required this.id, required this.name, required this.views, required this.searchAppearances, required this.comparisonViews, required this.watchlistAdds, required this.requests, required this.offerClicks, required this.price, required this.pricePosition, required this.inStock, required this.updatedAt, required this.demand});
  final String id, name, pricePosition; final int views, searchAppearances, comparisonViews, watchlistAdds, requests, offerClicks; final double price; final bool inStock; final DateTime updatedAt; final DemandLevel demand;
  double get conversionProxy => views == 0 ? 0 : (requests + offerClicks) / views * 100;
  double get performanceScore => views + searchAppearances * .5 + watchlistAdds * 3 + requests * 4;
}

class PriceCompetitiveness {
  const PriceCompetitiveness({required this.product, required this.sellerPrice, required this.lowest, required this.highest, required this.average, required this.label, required this.suggestion});
  final String product, suggestion; final double sellerPrice, lowest, highest, average; final CompetitivenessLabel label;
  double get difference => sellerPrice - average;
  static CompetitivenessLabel calculate(double seller, List<double> nearby) {
    if (nearby.length < 2) return CompetitivenessLabel.insufficientData;
    final low = nearby.reduce((a, b) => a < b ? a : b), avg = nearby.reduce((a, b) => a + b) / nearby.length;
    if (seller <= low) return CompetitivenessLabel.lowestPrice;
    if (seller <= avg * 1.03) return CompetitivenessLabel.competitive;
    if (seller <= avg * 1.12) return CompetitivenessLabel.aboveAverage;
    return CompetitivenessLabel.highPrice;
  }
}

class DemandTrend { const DemandTrend(this.product, this.searches, this.watchlists, this.requests, this.buyerIntents, this.supply, this.level); final String product; final int searches, watchlists, requests, buyerIntents, supply; final DemandLevel level; double get ratio => supply == 0 ? buyerIntents.toDouble() : buyerIntents / supply; }
class AreaAnalytics { const AreaAnalytics(this.area, this.demand, this.activeSellers, this.availability, this.averagePrice, this.popularCategory, this.requests, this.supplyGaps); final String area, popularCategory; final int demand, activeSellers, availability, requests, supplyGaps; final double averagePrice; }
class CampaignAnalytics { const CampaignAnalytics(this.name, this.impressions, this.views, this.clicks, this.productOpens, this.shopOpens, this.followers, this.requests, this.status, this.start, this.end); final String name, status; final int impressions, views, clicks, productOpens, shopOpens, followers, requests; final DateTime start, end; double get clickThroughRate => impressions == 0 ? 0 : clicks / impressions * 100; double get engagementRate => impressions == 0 ? 0 : (clicks + productOpens + shopOpens) / impressions * 100; }
class FunnelStage { const FunnelStage(this.name, this.count, this.previousCount); final String name; final int count, previousCount; double conversionFrom(int first) => first == 0 ? 0 : count / first * 100; int dropOffTo(FunnelStage next) => count - next.count; }
class FunnelReport { const FunnelReport(this.name, this.stages); final String name; final List<FunnelStage> stages; }
class RetentionMetric { const RetentionMetric(this.name, this.value, this.summary); final String name, summary; final double value; }
enum SearchIntelligenceAction { addSynonym, linkProduct, markSpelling, createVerificationRequest, ignore }
class SearchIntelligenceItem { const SearchIntelligenceItem(this.term, this.category, this.count, {this.action}); final String term, category; final int count; final SearchIntelligenceAction? action; SearchIntelligenceItem copyWith({SearchIntelligenceAction? action}) => SearchIntelligenceItem(term, category, count, action: action); }
class ReportFilter { const ReportFilter(this.name, this.value); final String name, value; }
class ReportDefinition { const ReportDefinition(this.metric, this.range, this.filters, {this.chart = true}); final String metric; final AnalyticsTimeRange range; final List<ReportFilter> filters; final bool chart; }
class DataQualityIssue { const DataQualityIssue(this.title, this.count, this.severity, this.recordType); final String title, severity, recordType; final int count; }
class AnalyticsPrivacySettings { const AnalyticsPrivacySettings({this.basicUsage = true, this.recommendations = true, this.businessPerformance = true, this.marketComparisons = true}); final bool basicUsage, recommendations, businessPerformance, marketComparisons; AnalyticsPrivacySettings copyWith({bool? basicUsage, bool? recommendations, bool? businessPerformance, bool? marketComparisons}) => AnalyticsPrivacySettings(basicUsage: basicUsage ?? this.basicUsage, recommendations: recommendations ?? this.recommendations, businessPerformance: businessPerformance ?? this.businessPerformance, marketComparisons: marketComparisons ?? this.marketComparisons); }
