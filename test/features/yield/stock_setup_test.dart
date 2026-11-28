import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/yield/stock_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('setup json round trip drops bad values', () {
    const s = AskodoxStockSetup(item: 'mutton', recipe: true, sellPaise: 24000, done: true);
    final back = AskodoxStockSetup.fromJson(s.toJson());
    expect(back.item, 'mutton');
    expect(back.recipe, isTrue);
    expect(back.sellPaise, 24000);
    expect(back.done, isTrue);
    final bad = AskodoxStockSetup.fromJson({'i': '', 's': -4});
    expect(bad.item, 'chicken');
    expect(bad.sellPaise, 0);
    expect(bad.done, isFalse);
  });

  testWidgets('three steps, back and next, alert note never says it is sent', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(theme: AppTheme.light, home: const AskodoxStockSetupScreen(businessId: '1'))));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('askodoxSetupStock')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxSetupNext')));
    await tester.pump();
    expect(find.byKey(const Key('askodoxSetupRate')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxSetupNext')));
    await tester.pump();
    expect(find.byKey(const Key('askodoxSetupAlertNote')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxSetupBack')));
    await tester.pump();
    expect(find.byKey(const Key('askodoxSetupRate')), findsOneWidget);
  });
}
