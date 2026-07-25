import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_analytics_repositories.dart';
import '../domain/analytics_models.dart';
import '../domain/analytics_repositories.dart';

final analyticsServiceProvider = Provider<AnalyticsService>((_) => MockAnalyticsService());
final buyerAnalyticsRepositoryProvider = Provider<BuyerAnalyticsRepository>((_) => MockBuyerAnalyticsRepository());
final sellerAnalyticsRepositoryProvider = Provider<SellerAnalyticsRepository>((_) => MockSellerAnalyticsRepository());
final adminAnalyticsRepositoryProvider = Provider<AdminAnalyticsRepository>((_) => MockAdminAnalyticsRepository());
final funnelAnalyticsRepositoryProvider = Provider<FunnelAnalyticsRepository>((_) => MockFunnelAnalyticsRepository());
final searchIntelligenceRepositoryProvider = Provider<SearchIntelligenceRepository>((_) => MockSearchIntelligenceRepository());
final reportRepositoryProvider = Provider<ReportRepository>((_) => MockReportRepository());
final dataQualityRepositoryProvider = Provider<DataQualityRepository>((_) => MockDataQualityRepository());
final analyticsRangeProvider = StateProvider<AnalyticsTimeRange>((_) => AnalyticsTimeRange.last30Days);
final buyerInsightsProvider = FutureProvider((ref) => ref.watch(buyerAnalyticsRepositoryProvider).insights(ref.watch(analyticsRangeProvider)));
final sellerMetricsProvider = FutureProvider((ref) => ref.watch(sellerAnalyticsRepositoryProvider).metrics(ref.watch(analyticsRangeProvider)));
final productPerformanceProvider = FutureProvider((ref) => ref.watch(sellerAnalyticsRepositoryProvider).products());
final priceCompetitivenessProvider = FutureProvider((ref) => ref.watch(sellerAnalyticsRepositoryProvider).prices());
final demandAnalyticsProvider = FutureProvider((ref) => ref.watch(sellerAnalyticsRepositoryProvider).demand());
final areaAnalyticsProvider = FutureProvider((ref) => ref.watch(sellerAnalyticsRepositoryProvider).areas());
final campaignAnalyticsProvider = FutureProvider((ref) => ref.watch(sellerAnalyticsRepositoryProvider).campaigns());
final platformMetricsProvider = FutureProvider((ref) => ref.watch(adminAnalyticsRepositoryProvider).platformMetrics());
final retentionProvider = FutureProvider((ref) => ref.watch(adminAnalyticsRepositoryProvider).retention());
final funnelsProvider = FutureProvider((ref) => ref.watch(funnelAnalyticsRepositoryProvider).funnels());
final searchIntelligenceProvider = FutureProvider((ref) => ref.watch(searchIntelligenceRepositoryProvider).items());
final dataQualityProvider = FutureProvider((ref) => ref.watch(dataQualityRepositoryProvider).issues());

class PrivacyController extends StateNotifier<AnalyticsPrivacySettings> {
  PrivacyController(this.service):super(const AnalyticsPrivacySettings()); final AnalyticsService service;
  void setBasic(bool value)=>state=state.copyWith(basicUsage:value); void setRecommendations(bool value)=>state=state.copyWith(recommendations:value); void setBusiness(bool value)=>state=state.copyWith(businessPerformance:value); void setMarket(bool value)=>state=state.copyWith(marketComparisons:value); Future<void> clear()=>service.clear();
}
final analyticsPrivacyProvider = StateNotifierProvider<PrivacyController,AnalyticsPrivacySettings>((ref)=>PrivacyController(ref.watch(analyticsServiceProvider)));
