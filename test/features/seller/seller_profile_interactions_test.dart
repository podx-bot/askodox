import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/seller/presentation/seller_profile_screen.dart';

void main() {
  testWidgets('seller profile actions navigate to working destinations',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/seller/profile',
      routes: [
        GoRoute(
          path: '/seller/profile',
          builder: (_, __) => const SellerProfileScreen(),
        ),
        GoRoute(
          path: '/seller/location',
          builder: (_, __) => const Scaffold(
            key: Key('sellerLocationDestination'),
            body: Text('Seller location destination'),
          ),
        ),
        GoRoute(
          path: '/seller/register',
          builder: (_, __) => const Scaffold(
            key: Key('sellerRegisterDestination'),
            body: Text('Seller register destination'),
          ),
        ),
        GoRoute(
          path: '/seller/login',
          builder: (_, __) => const Scaffold(
            key: Key('sellerLoginDestination'),
            body: Text('Seller login destination'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sellerProfileScreen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sellerProfileManageLocation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerLocationDestination')), findsOneWidget);

    router.go('/seller/profile');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerProfileEditDetails')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerRegisterDestination')), findsOneWidget);

    router.go('/seller/profile');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerProfileSignOut')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerLoginDestination')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
