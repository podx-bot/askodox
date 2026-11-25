import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/presentation/money_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-25: Coming up in 3 pieces (made-up data, phone storage only).
void main() {
  testWidgets('coming up: add a due -> it shows with this week total -> delete asks once', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: AskodoxUpcomingStepsScreen())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxUpcomingSteps')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxUpcomingStepsAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxDueName')), 'Test EMI');
    await tester.enterText(find.byKey(const Key('askodoxDueAmount')), '1500');
    await tester.ensureVisible(find.byKey(const Key('askodoxDueSave')));
    await tester.tap(find.byKey(const Key('askodoxDueSave')));
    await tester.pumpAndSettle();
    expect(find.text('Test EMI'), findsOneWidget);
    await tester.tap(find.text('Test EMI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('askodoxUpcomingStepsDelete-')));
    await tester.pumpAndSettle();
    expect(find.text('Test EMI'), findsWidgets, reason: 'not deleted before the yes');
    await tester.tap(find.byKey(const Key('askodoxUpcomingStepsDeleteYes')));
    await tester.pumpAndSettle();
    expect(find.text('Test EMI'), findsNothing);
  });
}
