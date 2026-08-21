import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/profile/presentation/profile_screen.dart';
import 'package:podx/generated/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        GoRoute(
          path: '/beta-feedback',
          builder: (_, __) => const Scaffold(body: Text('Feedback destination')),
        ),
      ],
    );

    return ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }

  Future<Finder> revealProfileAction(
    WidgetTester tester,
    Key key,
  ) async {
    final list = find.byType(ListView);
    expect(list, findsOneWidget);

    final action = find.byKey(key);
    await tester.scrollUntilVisible(
      action,
      300,
      scrollable: find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.pump(const Duration(milliseconds: 150));
    return action;
  }

  testWidgets('profile settings opens real developer settings', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    final settings = await revealProfileAction(
      tester,
      const Key('askodoxProfileSettings'),
    );
    await tester.tap(settings);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Developer settings'), findsOneWidget);
    expect(find.byKey(const Key('developerServerUrlField')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile help opens feedback destination', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    final help = await revealProfileAction(
      tester,
      const Key('askodoxProfileHelp'),
    );
    await tester.tap(help);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Feedback destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
