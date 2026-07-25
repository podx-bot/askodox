import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/auth/route_guard.dart';
import 'package:podx/features/analytics/application/analytics_providers.dart';
import 'package:podx/features/analytics/data/mock_analytics_repositories.dart';
import 'package:podx/features/analytics/domain/analytics_models.dart';

void main() {
  group('privacy-safe event recording', () {
    test('records supported event and excludes sensitive fields', () async {
      final service = MockAnalyticsService();
      await service.record(AnalyticsEvent(type: AnalyticsEventType.productSearched, occurredAt: DateTime.now(), properties: const {'category':'Groceries','resultCount':4,'phoneNumber':'9999999999','address':'private','otp':'1234','accessToken':'secret','documentData':'bytes','latitude':17.4}));
      final events = await service.events();
      expect(events, hasLength(1));
      expect(events.single.properties, {'category':'Groceries','resultCount':4});
    });
    test('filters events by time range', () async {
      final service=MockAnalyticsService();
      await service.record(AnalyticsEvent(type:AnalyticsEventType.appOpened,occurredAt:DateTime.now().subtract(const Duration(days:40))));
      await service.record(AnalyticsEvent(type:AnalyticsEventType.appOpened,occurredAt:DateTime.now()));
      expect(await service.events(range:AnalyticsTimeRange.last30Days),hasLength(1));
    });
  });
  test('metric computes percentage and trend',(){expect(const MetricValue('Views',120,100).percentageChange,20);expect(const MetricValue('Views',90,100).trend,MetricTrend.decreasing);expect(const MetricValue('Views',0,0).percentageChange,0);});
  test('seller products rank by performance',() async {final products=await MockSellerAnalyticsRepository().products();products.sort((a,b)=>b.performanceScore.compareTo(a.performanceScore));expect(products.first.id,'p1');});
  test('price competitiveness calculation handles all bands',(){expect(PriceCompetitiveness.calculate(90,[100,110]),CompetitivenessLabel.lowestPrice);expect(PriceCompetitiveness.calculate(105,[100,110]),CompetitivenessLabel.competitive);expect(PriceCompetitiveness.calculate(130,[100,110]),CompetitivenessLabel.highPrice);expect(PriceCompetitiveness.calculate(100,[100]),CompetitivenessLabel.insufficientData);});
  test('demand-to-supply ratio is safe for zero supply',(){expect(const DemandTrend('x',1,2,3,12,4,DemandLevel.high).ratio,3);expect(const DemandTrend('x',1,2,3,12,0,DemandLevel.high).ratio,12);});
  test('funnel conversion and drop-off are calculated',(){const first=FunnelStage('Search',100,90),next=FunnelStage('Selected',60,50);expect(next.conversionFrom(first.count),60);expect(first.dropOffTo(next),40);});
  test('search intelligence action is local and explicit',() async {final repo=MockSearchIntelligenceRepository(),item=(await repo.items()).first,updated=await repo.apply(item,SearchIntelligenceAction.addSynonym);expect(updated.action,SearchIntelligenceAction.addSynonym);});
  test('privacy settings can be copied without changing unrelated consent',(){const settings=AnalyticsPrivacySettings();final changed=settings.copyWith(basicUsage:false);expect(changed.basicUsage,isFalse);expect(changed.marketComparisons,isTrue);});
  test('analytics routes enforce seller and admin roles',(){const guard=RouteGuard(),buyer=AuthSession(status:AuthStatus.loggedIn,user:AuthUser(id:'b',role:UserRole.buyer));expect(guard.redirect(buyer,'/seller/analytics'),'/forbidden');expect(guard.redirect(buyer,'/admin/analytics'),'/forbidden');});
  test('privacy controller clears local event history',() async {final service=MockAnalyticsService();final controller=PrivacyController(service);await service.record(AnalyticsEvent(type:AnalyticsEventType.appOpened,occurredAt:DateTime.now()));await controller.clear();expect(await service.events(),isEmpty);});
}
