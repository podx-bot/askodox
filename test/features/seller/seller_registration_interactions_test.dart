import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/seller/presentation/seller_registration_screen.dart';

void main() {
  testWidgets('seller registration works on phone size and opens dashboard', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/seller/register',
      routes: [
        GoRoute(
          path: '/seller/register',
          builder: (_, __) => const SellerRegistrationScreen(),
        ),
        GoRoute(
          path: '/seller/dashboard',
          builder: (_, __) => const Scaffold(body: Text('SELLER_DASHBOARD_DESTINATION')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sellerRegistrationScreen')), findsOneWidget);
    expect(find.byKey(const Key('sellerRegisterShopName')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('sellerRegisterShopName')), 'Demo Mart');
    await tester.enterText(find.byKey(const Key('sellerRegisterOwnerName')), 'Demo Seller');
    await tester.enterText(find.byKey(const Key('sellerRegisterMobile')), '9876543210');
    await tester.enterText(find.byKey(const Key('sellerRegisterAddress')), 'Main Road');

    final scroll = find.byKey(const Key('sellerRegistrationScroll'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerRegisterPhoto')),
      250,
      scrollable: scroll,
    );
    await tester.tap(find.byKey(const Key('sellerRegisterPhoto')));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerRegisterBusinessId')),
      250,
      scrollable: scroll,
    );
    await tester.tap(find.byKey(const Key('sellerRegisterBusinessId')));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerRegisterSubmit')),
      250,
      scrollable: scroll,
    );
    await tester.tap(find.byKey(const Key('sellerRegisterSubmit')));
    await tester.pumpAndSettle();

    expect(find.text('SELLER_DASHBOARD_DESTINATION'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
