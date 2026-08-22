import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/catalog/presentation/widgets/product_request_actions.dart';
import 'package:podx/features/watchlist/application/watchlist_providers.dart';

void main() {
  testWidgets('product request actions mutate watchlist and notification state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: ProductRequestActions()),
        ),
        GoRoute(
          path: '/discover/image',
          builder: (_, __) => const Scaffold(body: Text('Image discovery')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    final scopeContext = tester.element(find.byType(ProductRequestActions));
    final container = ProviderScope.containerOf(scopeContext);

    expect(container.read(watchlistProvider), isEmpty);

    await tester.tap(find.byKey(const Key('productRequestWatchlist')));
    await tester.pumpAndSettle();
    expect(container.read(watchlistProvider), hasLength(1));
    expect(find.text('In Watchlist'), findsOneWidget);

    await tester.tap(find.byKey(const Key('productRequestNotify')));
    await tester.pumpAndSettle();
    expect(container.read(watchlistProvider).single.alertsEnabled, isTrue);
    expect(find.text('Notifications On'), findsOneWidget);

    await tester.tap(find.byKey(const Key('productRequestImage')));
    await tester.pumpAndSettle();
    expect(find.text('Image discovery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
