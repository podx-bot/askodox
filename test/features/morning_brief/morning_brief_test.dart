import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/morning_brief/morning_brief_logic.dart';
import 'package:podx/features/morning_brief/morning_brief_screen.dart';
import 'package:podx/shared/widgets/estimate_note.dart';

void main() {
  test('rows: known kinds with a page only; words carry the real counts', () {
    final tasks = askodoxBriefTasks([
      {'key': 'dues', 'action': 'send', 'count': 3, 'route': '/pos/b1/dues'},
      {'key': 'low_stock', 'action': 'approve', 'count': 2, 'name': 'Toor dal', 'route': '/pos/b1/automations'},
      {'key': 'something_new', 'action': 'view', 'route': '/x'},
      {'key': 'winback', 'action': 'send', 'count': 5, 'days': 15, 'route': 'no-slash'},
      'junk',
    ]);
    expect([for (final t in tasks) t.key], ['dues', 'low_stock']);
    expect(askodoxBriefTitle(tasks[0], true), '3 బాకీలు గుర్తు చేయాలి');
    expect(askodoxBriefButton(tasks[0], true), 'పంపు');
    expect(askodoxBriefTitle(tasks[1], false), 'Toor dal +1 running low');
    expect(askodoxBriefButton(tasks[1], true), 'ఆమోదించు');
    expect(askodoxBriefShowsMoney(tasks), isFalse);
  });

  test('money, greeting, headline and yesterday counts', () {
    expect(askodoxBriefRupees(96200), '₹962');
    expect(askodoxBriefRupees(96250), '₹962.50');
    expect(askodoxBriefGreeting(4, 7, true), 'శుభోదయం · శుక్రవారం');
    expect(askodoxBriefGreeting(6, 18, false), 'Hello · Sunday');
    expect(askodoxBriefHeadline(3, true), 'ఈ రోజు మీ దగ్గర 3 పనులు');
    expect(askodoxBriefHeadline(0, true), 'ఈ రోజు పనులన్నీ అయిపోయాయి');
    final bill = AskodoxBriefTask.from({'key': 'my_bills', 'count': 1, 'amount_paise': 10000, 'route': '/me/bills'})!;
    expect(askodoxBriefTitle(bill, true), '1 బిల్లులు కట్టాలి · ₹100');
    expect(askodoxBriefShowsMoney([bill]), isTrue);
    // A count the server left out is not shown as 0.
    expect(askodoxBriefHandled({'day': '2026-11-26', 'bills': 12, 'payments': 4}, true),
        [('బిల్స్ సేవ్', 12), ('పేమెంట్లు విన్నది', 4)]);
    expect(askodoxBriefHandled(null, true), isEmpty);
  });

  test('the owner word rule: no screen text of the brief says "లేదు"', () {
    final all = <String>[askodoxEstimateNoteTe, askodoxBriefHeadline(0, true), askodoxBriefHeadline(2, true)];
    for (final key in askodoxBriefKinds) {
      final task = AskodoxBriefTask(key: key, action: 'view', route: '/x', count: 2, name: 'X', days: 15, amountPaise: 100);
      all.addAll([askodoxBriefTitle(task, true), askodoxBriefSub(task, true), askodoxBriefButton(task, true)]);
    }
    expect(all.where((text) => text.contains('లేదు')), isEmpty);
  });

  testWidgets('the screen: three rows with one button each, the button opens that page, money shows the note',
      (tester) async {
    final router = GoRouter(initialLocation: '/pos/b1/brief', routes: [
      GoRoute(path: '/pos/:id/brief', builder: (c, s) => AskodoxMorningBriefScreen(businessId: s.pathParameters['id']!)),
      GoRoute(path: '/pos/:id/dues', builder: (c, s) => const Scaffold(body: Text('dues page'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        askodoxMorningBriefProvider('b1').overrideWith((ref) async => {
              'weekday': 4,
              'tasks': [
                {'key': 'dues', 'action': 'send', 'count': 2, 'route': '/pos/b1/dues'},
                {'key': 'low_stock', 'action': 'approve', 'count': 1, 'name': 'Toor dal', 'route': '/pos/b1/automations'},
                {'key': 'yesterday', 'action': 'view', 'count': 12, 'amount_paise': 480000, 'route': '/biz/b1/reports/day'},
              ],
              'handled': {'bills': 12, 'reminders': 4},
            }),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBriefHeadline')), findsOneWidget);
    for (final key in ['dues', 'low_stock', 'yesterday']) {
      expect(find.byKey(ValueKey('askodoxBriefTask-$key')), findsOneWidget);
      expect(find.byKey(ValueKey('askodoxBriefGo-$key')), findsOneWidget);
    }
    expect(find.byKey(const Key('askodoxBriefApproveNote')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('askodoxEstimateNote')), 120);
    expect(find.byKey(const Key('askodoxEstimateNote')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('askodoxBriefGo-dues')), -120);
    await tester.tap(find.byKey(const ValueKey('askodoxBriefGo-dues')));
    await tester.pumpAndSettle();
    expect(find.text('dues page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
