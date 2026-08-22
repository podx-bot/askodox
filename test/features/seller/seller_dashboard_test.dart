import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/seller/presentation/seller_dashboard_screen.dart';

void main() {
  testWidgets('dashboard presents seller inventory and request metrics', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SellerDashboardScreen()),
      ),
    );
    expect(find.text('Seller dashboard'), findsOneWidget);
    expect(find.text('Total products'), findsOneWidget);
    expect(find.text('Price updates'), findsOneWidget);
    expect(find.text('New requests'), findsOneWidget);
  });

  testWidgets('dashboard primary actions expose stable keys and profile opens profile route', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/seller/dashboard',
      routes: [
        GoRoute(
          path: '/seller/dashboard',
          builder: (_, __) => const SellerDashboardScreen(),
        ),
        GoRoute(
          path: '/seller/profile',
          builder: (_, __) => const Scaffold(body: Text('PROFILE_DESTINATION')),
        ),
        GoRoute(
          path: '/seller/login',
          builder: (_, __) => const Scaffold(body: Text('LOGIN_DESTINATION')),
        ),
        GoRoute(
          path: '/seller/analytics',
          builder: (_, __) => const Scaffold(body: Text('ANALYTICS_DESTINATION')),
        ),
        GoRoute(
          path: '/seller/analytics/products',
          builder: (_, __) => const Scaffold(body: Text('PRODUCT_ANALYTICS_DESTINATION')),
        ),
        GoRoute(
          path: '/seller/analytics/market',
          builder: (_, __) => const Scaffold(body: Text('MARKET_DESTINATION')),
        ),
        GoRoute(
          path: '/seller/analytics/privacy',
          builder: (_, __) => const Scaffold(body: Text('PRIVACY_DESTINATION')),
        ),
        GoRoute(
          path: '/seller/products/add',
          builder: (_, __) => const Scaffold(body: Text('ADD_PRODUCT_DESTINATION')),
        ),
        GoRoute(
          path: '/seller/products',
          builder: (_, __) => const Scaffold(body: Text('PRODUCTS_DESTINATION')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    // App-bar actions are always available on the phone viewport.
    expect(find.byKey(const Key('sellerDashboardShopProfile')), findsOneWidget);
    expect(find.byKey(const Key('sellerDashboardMenu')), findsOneWidget);

    // The body is a lazy ListView, so verify each lower action only after
    // scrolling it into the built/visible region of the phone viewport.
    final scrollable = find.byType(Scrollable).first;
    for (final key in <String>[
      'sellerDashboardAnalytics',
      'sellerDashboardProductPerformance',
      'sellerDashboardMarketIntelligence',
      'sellerDashboardPrivacy',
      'sellerDashboardAddProduct',
      'sellerDashboardManageProducts',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        260,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(Key(key)), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('sellerDashboardShopProfile')));
    await tester.pumpAndSettle();
    expect(find.text('PROFILE_DESTINATION'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
