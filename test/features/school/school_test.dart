import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/business/presentation/biz_hub.dart';
import 'package:podx/features/school/school_logic.dart';
import 'package:podx/features/school/school_screens.dart';

void main() {
  test('every problem the server sends has words in Telugu and English, and the hub opens the page', () {
    for (final key in ['unlisted_pickup', 'health_follow_up', 'absent_streak', 'unmarked', 'absent_today']) {
      expect(askodoxSchoolProblemTitle(key, true), isNot(key));
      expect(askodoxSchoolProblemTitle(key, false), isNot(key));
    }
    expect(askodoxSchoolProblemTitle('something_new', true), 'something_new');
    expect(askodoxSchoolItemText('absent_streak', {'name': 'Child One', 'days': 3}, false), 'Child One · 3 days');
    expect(askodoxSchoolItemText('unmarked', {'name': '5-A', 'teacher': 'Teacher One'}, false), '5-A · Teacher One');
    expect(askodoxSchoolSavedText(28, 2, false), 'Saved: 28 present, 2 absent');
    expect(askodoxBizRoute('h1', 'money.school'), '/biz/h1/school');
  });

  testWidgets('the school page shows only problems, a class with its children, and the register opens', (tester) async {
    final router = GoRouter(initialLocation: '/biz/b1/school', routes: [
      GoRoute(path: '/biz/:id/school', builder: (c, s) => AskodoxSchoolScreen(businessId: s.pathParameters['id']!)),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        askodoxSchoolTodayProvider('b1').overrideWith((ref) async => {
              'problems': [
                {
                  'key': 'absent_streak',
                  'count': 1,
                  'items': [
                    {'student_id': 's1', 'name': 'Child One', 'days': 3, 'whatsapp_url': 'https://wa.me/919300004011?text=x'}
                  ]
                },
              ],
            }),
        askodoxSchoolClassesProvider('b1').overrideWith((ref) async => {
              'classes': [
                {
                  'id': 'c1',
                  'name': '5-A',
                  'teacher': 'Teacher One',
                  'marked_today': false,
                  'students': [
                    {'id': 's1', 'name': 'Child One', 'parent_name': 'Parent One', 'hostel': false},
                    {'id': 's2', 'name': 'Child Two', 'parent_name': 'Parent Two', 'hostel': true},
                  ],
                },
              ],
            }),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxSchool')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxSchoolProblem-absent_streak')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSchoolAllClear')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('askodoxSchoolClass-c1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxSchoolStudent-s2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxSchoolMark-c1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxSchoolAbsent-s1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxSchoolAbsent-s1')));
    await tester.pump();
    expect(find.text('Absent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
