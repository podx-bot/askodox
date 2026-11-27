import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/business/presentation/biz_hub.dart';
import 'package:podx/features/memberships/memberships_logic.dart';
import 'package:podx/features/memberships/memberships_screens.dart';

void main() {
  test('the end day: the same day later, or the last day of a shorter month (as the server works it out)', () {
    expect(askodoxTermEnd(DateTime(2026, 11, 27), 1), DateTime(2026, 12, 27));
    expect(askodoxTermEnd(DateTime(2026, 11, 27), 3), DateTime(2027, 2, 27));
    expect(askodoxTermEnd(DateTime(2027, 1, 31), 1), DateTime(2027, 2, 28));
    expect(askodoxTermEnd(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
    expect(askodoxTermEnd(DateTime(2026, 12, 15), 12), DateTime(2027, 12, 15));
  });

  test('words and money', () {
    expect(askodoxDayText('2026-12-27'), '27-12-2026');
    expect(askodoxIsoDay(DateTime(2027, 2, 7)), '2027-02-07');
    expect(askodoxTermRupees(450000), '₹4500');
    expect(askodoxTermPaise('1,500'), 150000);
    expect(askodoxTermPaise('abc'), 0);
    expect(askodoxTermMonthsText(12, true), '1 సంవత్సరం');
    expect(askodoxTermStateText('ending', 0, true), 'ఈ రోజు ముగుస్తుంది');
    for (final state in ['ok', 'ending', 'ended', 'left', 'stopped']) {
      expect(askodoxTermStateText(state, 3, true).contains('లేదు'), isFalse);
    }
    expect(askodoxBizRoute('h1', 'money.members'), '/biz/h1/members');
  });

  testWidgets('the members page: counts, ending members with a reminder, everyone; attendance opens', (tester) async {
    final router = GoRouter(initialLocation: '/biz/b1/members', routes: [
      GoRoute(path: '/biz/:id/members', builder: (c, s) => AskodoxMembersScreen(businessId: s.pathParameters['id']!)),
      GoRoute(path: '/biz/:id/members/attendance', builder: (c, s) => const Scaffold(body: Text('attendance page'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        askodoxMembersProvider('b1').overrideWith((ref) async => {
              'terms': [1, 3, 6, 12],
              'counts': {'members': 2, 'ending_this_month': 1, 'fee_due': 0, 'came_today': 1},
              'ending': [
                {'id': 'm1', 'name': 'Member One', 'state': 'ending', 'days_left': 3, 'end_date': '2026-11-30',
                 'fee_paise': 150000, 'months': 1, 'whatsapp_url': 'https://wa.me/919300003050?text=x'},
              ],
              'members': [
                {'id': 'm1', 'name': 'Member One', 'state': 'ending', 'days_left': 3, 'end_date': '2026-11-30',
                 'fee_paise': 150000, 'months': 1},
                {'id': 'm2', 'name': 'Member Two', 'state': 'ok', 'days_left': 60, 'end_date': '2027-01-26',
                 'fee_paise': 450000, 'months': 3},
              ],
            }),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxMembers')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMemberEnding-m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMemberRemind-m1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMembersNew')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxMembersAttendance')));
    await tester.pumpAndSettle();
    expect(find.text('attendance page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
