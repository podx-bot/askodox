import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/intelligence/presentation/personal_finance_screen.dart';

void main() {
  testWidgets('Personal Finance opens the existing tax / GST / money screens (no new engine)', (tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget page(String name) => Scaffold(body: Text('PAGE $name'));
    final router = GoRouter(initialLocation: '/me/finance', routes: [
      GoRoute(path: '/me/finance', builder: (_, __) => const AskodoxPersonalFinanceScreen()),
      for (final r in ['/intel/tax', '/intel/gst', '/intel/tricks', '/intel/fraud', '/me/shop-advances',
        '/me/payment-methods', '/me/ai-credits'])
        GoRoute(path: r, builder: (_, __) => page(r)),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Personal Tax Assistant'), findsOneWidget);
    for (final (id, route) in [
      ('income_tax', '/intel/tax'),
      ('gst', '/intel/gst'),
      ('fraud_check', '/intel/fraud'),
      ('ai_credits', '/me/ai-credits'),
    ]) {
      await tester.tap(find.byKey(ValueKey('askodoxFinance-$id')));
      await tester.pumpAndSettle();
      expect(find.text('PAGE $route'), findsOneWidget, reason: id);
      router.pop();
      await tester.pumpAndSettle();
    }
  });
}
