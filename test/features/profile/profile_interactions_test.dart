import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

    return MaterialApp.router(
      routerConfig: router,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }

  testWidgets('profile settings opens real developer settings', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('askodoxProfileSettings')));
    await tester.tap(find.byKey(const Key('askodoxProfileSettings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Developer settings'), findsOneWidget);
    expect(find.byKey(const Key('developerServerUrlField')), findsOneWidget);
  });

  testWidgets('profile help opens feedback destination', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('askodoxProfileHelp')));
    await tester.tap(find.byKey(const Key('askodoxProfileHelp')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Feedback destination'), findsOneWidget);
  });
}
