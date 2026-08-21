import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/seller/presentation/seller_login_screen.dart';

void main() {
  testWidgets('seller login works on phone size from mobile to dashboard', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/seller/login',
      routes: [
        GoRoute(path: '/seller/login', builder: (_, __) => const SellerLoginScreen()),
        GoRoute(path: '/seller/dashboard', builder: (_, __) => const Scaffold(body: Text('SELLER_DASHBOARD_DESTINATION'))),
        GoRoute(path: '/seller/register', builder: (_, __) => const Scaffold(body: Text('SELLER_REGISTER_DESTINATION'))),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sellerLoginMobileField')), findsOneWidget);
    expect(find.byKey(const Key('sellerLoginPrimaryAction')), findsOneWidget);
    expect(find.byKey(const Key('sellerLoginRegister')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('sellerLoginMobileField')), '9876543210');
    await tester.tap(find.byKey(const Key('sellerLoginPrimaryAction')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sellerLoginOtpField')), findsOneWidget);
    expect(find.text('Verify & continue'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('sellerLoginOtpField')), '123456');
    await tester.ensureVisible(find.byKey(const Key('sellerLoginPrimaryAction')));
    await tester.tap(find.byKey(const Key('sellerLoginPrimaryAction')));
    await tester.pumpAndSettle();

    expect(find.text('SELLER_DASHBOARD_DESTINATION'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
