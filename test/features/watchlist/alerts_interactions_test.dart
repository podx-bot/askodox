import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/watchlist/application/watchlist_providers.dart';
import 'package:podx/features/watchlist/domain/watchlist_models.dart';
import 'package:podx/features/watchlist/domain/watchlist_repository.dart';
import 'package:podx/features/watchlist/presentation/alerts_screen.dart';

class _FakeWatchlistRepository implements WatchlistRepository {
  _FakeWatchlistRepository(this._items, this._alerts);

  List<WatchlistItem> _items;
  List<ProductAlert> _alerts;
  AlertPreference _preferences = const AlertPreference();

  @override
  List<WatchlistItem> get items => List.unmodifiable(_items);

  @override
  List<ProductAlert> get alerts => List.unmodifiable(_alerts);

  @override
  AlertPreference get preferences => _preferences;

  @override
  void saveItem(WatchlistItem item) {
    _items = [
      for (final current in _items)
        if (current.productId == item.productId) item else current,
    ];
  }

  @override
  void removeItem(String productId) {
    _items = _items.where((item) => item.productId != productId).toList();
  }

  @override
  void saveAlerts(List<ProductAlert> alerts) {
    _alerts = List.of(alerts);
  }

  @override
  void savePreferences(AlertPreference value) {
    _preferences = value;
  }

  @override
  void saveRequest(dynamic request) {}
}

void main() {
  testWidgets('alerts expose stable actions and menu mutations work', (tester) async {
    final repo = _FakeWatchlistRepository(
      [
        WatchlistItem(
          productId: 'demo-product',
          productName: 'Demo product',
          brand: 'ASKODOX',
          variant: 'Standard',
          image: '📦',
          createdAt: DateTime(2026, 8, 21),
        ),
      ],
      [
        ProductAlert(
          id: 'alert-1',
          type: AlertType.priceDropped,
          productId: 'demo-product',
          productName: 'Demo product',
          image: '📦',
          sellerName: 'Demo seller',
          price: 399,
          distanceKm: 1.2,
          createdAt: DateTime(2026, 8, 21),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [watchlistRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: AlertsScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('alertsNotificationPreferences')), findsOneWidget);
    expect(find.byKey(const Key('alertsDemoAutomation')), findsOneWidget);
    expect(find.byKey(const Key('alertRow-alert-1')), findsOneWidget);

    final menuFinder = find.byKey(const Key('alertMenu-alert-1'));
    expect(menuFinder, findsOneWidget);
    var menu = tester.widget<PopupMenuButton<String>>(menuFinder);

    menu.onSelected?.call('read');
    await tester.pump();
    expect(repo.alerts.single.isRead, isTrue);

    menu = tester.widget<PopupMenuButton<String>>(menuFinder);
    menu.onSelected?.call('mute');
    await tester.pump();
    expect(repo.items.single.alertsEnabled, isFalse);

    menu = tester.widget<PopupMenuButton<String>>(menuFinder);
    menu.onSelected?.call('delete');
    await tester.pump();
    expect(repo.alerts, isEmpty);
    expect(find.byKey(const Key('alertRow-alert-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
