import 'analytics_models.dart';

abstract interface class AnalyticsService { Future<void> record(AnalyticsEvent event); Future<List<AnalyticsEvent>> events({AnalyticsTimeRange? range}); Future<void> clear(); }
abstract interface class BuyerAnalyticsRepository { Future<List<BuyerInsight>> insights(AnalyticsTimeRange range); }
abstract interface class SellerAnalyticsRepository { Future<List<SellerPerformanceMetric>> metrics(AnalyticsTimeRange range); Future<List<ProductPerformance>> products(); Future<List<PriceCompetitiveness>> prices(); Future<List<DemandTrend>> demand(); Future<List<AreaAnalytics>> areas(); Future<List<CampaignAnalytics>> campaigns(); }
abstract interface class AdminAnalyticsRepository { Future<List<MetricValue>> platformMetrics(); Future<List<RetentionMetric>> retention(); }
abstract interface class FunnelAnalyticsRepository { Future<List<FunnelReport>> funnels(); }
abstract interface class SearchIntelligenceRepository { Future<List<SearchIntelligenceItem>> items(); Future<SearchIntelligenceItem> apply(SearchIntelligenceItem item, SearchIntelligenceAction action); }
abstract interface class ReportRepository { Future<List<Map<String, Object>>> generate(ReportDefinition definition); }
abstract interface class DataQualityRepository { Future<List<DataQualityIssue>> issues(); }
