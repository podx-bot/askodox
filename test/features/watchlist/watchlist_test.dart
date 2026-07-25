import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/watchlist/application/watchlist_providers.dart';
import 'package:podx/features/watchlist/domain/watchlist_models.dart';

void main() {
  WatchlistItem item() => WatchlistItem(productId: 'p1', productName: 'Coffee', brand: 'PODX', variant: '500 ml', image: '☕', createdAt: DateTime(2026));
  test('adds, configures and removes watchlist item', () {
    final container = ProviderContainer(); addTearDown(container.dispose);
    container.read(watchlistProvider.notifier).add(item());
    expect(container.read(watchlistProvider), hasLength(1));
    container.read(watchlistProvider.notifier).update(item().copyWith(radiusKm: 2, targetPrice: 120));
    expect(container.read(watchlistProvider).single.targetPrice, 120);
    container.read(watchlistProvider.notifier).remove('p1');
    expect(container.read(watchlistProvider), isEmpty);
  });
  test('matches price and availability while enforcing radius and deduplication', () {
    final container = ProviderContainer(); addTearDown(container.dispose);
    container.read(watchlistProvider.notifier).add(item().copyWith(radiusKm: 2, targetPrice: 150));
    AlertEvent event({double distance=1,bool wasInStock=true}) => AlertEvent(productId:'p1',sellerName:'Shop',price:140,previousPrice:200,inStock:true,wasInStock:wasInStock,distanceKm:distance);
    expect(container.read(alertsProvider.notifier).match(event())?.type, AlertType.targetPriceMatched);
    expect(container.read(alertsProvider.notifier).match(event()), isNull);
    expect(container.read(alertsProvider.notifier).match(event(distance:3)), isNull);
    final later=DateTime.now().add(const Duration(days:2));
    expect(container.read(alertsProvider.notifier).match(event(wasInStock:false),now:later)?.type, AlertType.backInStock);
  });
  test('demand score is weighted and classified', () {
    final score=DemandScore.calculate(productId:'p',searches:100,watchlists:100,requests:100,targetIntents:100,nearbyBuyers:100,recentActivity:100);
    expect(score.score, 100); expect(score.level, 'High demand');
  });
  test('notification preferences persist in provider', () {
    final container=ProviderContainer();addTearDown(container.dispose);
    container.read(alertPreferenceProvider.notifier).set(const AlertPreference(priceDrops:false,quietHours:true));
    expect(container.read(alertPreferenceProvider).priceDrops,isFalse);
    expect(container.read(alertPreferenceProvider).quietHours,isTrue);
  });
  test('seller insights contain privacy-safe aggregate demand', () {
    final container=ProviderContainer();addTearDown(container.dispose);
    final insights=container.read(demandInsightsProvider);
    expect(insights,isNotEmpty);expect(insights.first.score.interestedBuyers,greaterThan(0));
  });
}
