import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/presentation/money_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-25: Coming up in 3 pieces (made-up data, phone storage only).
void main() {
  testWidgets('coming up: a saved due shows with this week total; delete asks once', (tester) async {
    final soon = DateTime.now().add(const Duration(days: 3));
    final day = '${soon.year}-${soon.month.toString().padLeft(2, '0')}-${soon.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({
      'askodox.mine.payalert.v1': jsonEncode({
        'dues': [
          {'id': 'd1', 'name': 'Test EMI', 'amount_paise': 150000, 'date': day, 'repeat': 'monthly'}
        ],
      }),
    });
    tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: AskodoxUpcomingStepsScreen())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxUpcomingSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxUpcomingStepsAdd')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxUpcomingStepsDue-d1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxUpcomingStepsDue-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxUpcomingStepsDelete-d1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxUpcomingStepsDue-d1')), findsOneWidget, reason: 'not deleted before the yes');
    await tester.tap(find.byKey(const Key('askodoxUpcomingStepsDeleteYes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxUpcomingStepsDue-d1')), findsNothing);
  });
}
