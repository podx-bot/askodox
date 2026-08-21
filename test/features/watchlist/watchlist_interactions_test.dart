import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/watchlist/application/watchlist_providers.dart';
import 'package:podx/features/watchlist/domain/watchlist_models.dart';
import 'package:podx/features/watchlist/domain/watchlist_repository.dart';
import 'package:podx/features/watchlist/presentation/watchlist_screen.dart';

class _FakeWatchlistRepository implements WatchlistRepository {
  _FakeWatchlistRepository(this._items);

  List<WatchlistItem> _items;
  List<ProductAlert> _alerts = const [];
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
}

void main() {
  testWidgets('alert settings opens, survives keyboard, and saves', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeWatchlistRepository([
      WatchlistItem(
        productId: 'demo-product',
        productName: 'Demo product',
        brand: 'ASKODOX',
        variant: 'Standard',
        image: '📦',
        createdAt: DateTime(2026, 8, 21),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [watchlistRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: WatchlistScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('watchlistAlertSettings-demo-product')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('watchlistAlertSettingsSheet')), findsOneWidget);
    expect(find.byKey(const Key('watchlistSavePreferences')), findsOneWidget);

    final target = find.byKey(const Key('watchlistTargetPriceField'));
    await tester.tap(target);
    await tester.enterText(target, '399');
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('watchlistSavePreferences')));
    await tester.tap(find.byKey(const Key('watchlistSavePreferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('watchlistAlertSettingsSheet')), findsNothing);
    expect(repo.items.single.targetPrice, 399);
    expect(tester.takeException(), isNull);
  });
}
