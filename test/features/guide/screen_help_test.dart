import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/config/router/app_router.dart';
import 'package:podx/core/startup/startup_hint.dart';
import 'package:podx/features/guide/screen_help.dart';
import 'package:podx/features/guide/guide_watch.dart';
import 'package:podx/features/guide/screen_help_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every screen route (not a redirect) and its full path pattern.
List<String> _screenPaths(List<RouteBase> routes, [String parent = '']) {
  final out = <String>[];
  for (final r in routes) {
    if (r is GoRoute) {
      final full = r.path.startsWith('/') ? r.path : '${parent == '/' ? '' : parent}/${r.path}';
      final isScreen = r.builder != null || r.pageBuilder != null;
      if (isScreen) out.add(full);
      out.addAll(_screenPaths(r.routes, full));
    } else if (r is ShellRouteBase) {
      out.addAll(_screenPaths(r.routes, parent));
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('EVERY screen has a guide entry (en + te steps) or a stated reason', () {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    final paths = _screenPaths(router.configuration.routes).toSet();
    expect(paths.length, greaterThan(60), reason: 'the walk found the app routes');
    final missing = [
      for (final p in paths)
        if (askodoxScreenHelpFor(p) == null && !askodoxScreenHelpIsExempt(p)) p,
    ];
    expect(missing, isEmpty, reason: 'add these to askodoxScreenHelp (or askodoxScreenHelpExempt with a reason)');
    for (final entry in askodoxScreenHelp.entries) {
      final h = entry.value;
      expect(h.stepsEn, isNotEmpty, reason: entry.key);
      expect(h.stepsTe.length, h.stepsEn.length, reason: '${entry.key}: Telugu steps match English');
      expect(h.titleTe.trim(), isNotEmpty, reason: entry.key);
    }
    final stale = [for (final k in askodoxScreenHelp.keys) if (!paths.contains(k)) k];
    expect(stale, isEmpty, reason: 'help for routes that no longer exist');
  });

  testWidgets('one press of the guide button explains the screen; exempt screens show none', (tester) async {
    final router = GoRouter(initialLocation: '/pos/b1/items', routes: [
      GoRoute(path: '/pos/:id/items', builder: (_, __) => const Scaffold(body: Text('ITEMS'))),
      GoRoute(path: '/onboarding', builder: (_, __) => const Scaffold(body: Text('SIGN UP'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => AskodoxScreenHelpLayer(router: router, child: child!),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxScreenHelpButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxScreenHelpSheet')), findsOneWidget);
    expect(find.text('Items & stock'), findsOneWidget);
    expect(find.textContaining('POS / Online / Both'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    router.go('/onboarding');
    await tester.pumpAndSettle();
    expect(find.text('SIGN UP'), findsOneWidget);
    expect(find.byKey(const Key('askodoxScreenHelpButton')), findsNothing);
  });

  testWidgets('right after sign-up, Home opens the welcome guide once', (tester) async {
    AskodoxStartupHint.justOnboarded = true;
    addTearDown(() => AskodoxStartupHint.justOnboarded = false);
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME')))]);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => AskodoxScreenHelpLayer(router: router, child: child!),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxWelcomeGuide')), findsOneWidget);
    expect(find.textContaining('Examples:'), findsOneWidget);
    expect(AskodoxStartupHint.justOnboarded, isFalse);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxWelcomeGuide')), findsNothing);
  });

  group('the guide watches', () {
    tearDown(AskodoxGuideNudges.instance.clear);

    Future<GoRouter> pumpForm(WidgetTester tester) async {
      final router = GoRouter(initialLocation: '/pos/b1/items', routes: [
        GoRoute(
            path: '/pos/:id/items',
            builder: (_, __) => const Scaffold(
                  body: Column(children: [
                    AskodoxFieldGuideInfo(
                      titleEn: 'HSN code',
                      titleTe: 'HSN కోడ్',
                      en: 'The tax code printed on your purchase bill.',
                      te: 'కొనుగోలు బిల్లుపై ఉండే పన్ను కోడ్.',
                      exampleEn: '1006',
                      child: TextField(key: Key('hsn'), decoration: InputDecoration(labelText: 'HSN code')),
                    ),
                  ]),
                )),
      ]);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AskodoxScreenHelpLayer(router: router, child: child!),
        ),
      ));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('an empty box left for 5 s gets "need help?"; Yes explains the field, No stays quiet', (tester) async {
      await pumpForm(tester);
      await tester.tap(find.byKey(const Key('hsn')));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('askodoxGuideNudge')), findsNothing, reason: 'not before the pause');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byKey(const Key('askodoxGuideNudge')), findsOneWidget);
      expect(find.byKey(const Key('askodoxScreenHelpButton')), findsNothing, reason: 'the tab turns into the question');
      await tester.tap(find.byKey(const Key('askodoxGuideNudgeYes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('askodoxGuideNudgeSheet')), findsOneWidget);
      expect(find.text('The tax code printed on your purchase bill.'), findsOneWidget);
      expect(find.textContaining('1006'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('askodoxGuideNudge')), findsNothing);
    });

    testWidgets('typing in time means no question; No is remembered for that box', (tester) async {
      await pumpForm(tester);
      await tester.enterText(find.byKey(const Key('hsn')), '1006');
      await tester.pump(const Duration(seconds: 6));
      expect(find.byKey(const Key('askodoxGuideNudge')), findsNothing);
      await tester.enterText(find.byKey(const Key('hsn')), '');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byKey(const Key('hsn')));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(find.byKey(const Key('askodoxGuideNudge')), findsOneWidget);
      await tester.tap(find.byKey(const Key('askodoxGuideNudgeNo')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('askodoxGuideNudge')), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byKey(const Key('hsn')));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(find.byKey(const Key('askodoxGuideNudge')), findsNothing, reason: 'declined for this box on this page');
    });

    testWidgets('a refused action asks "need help?" with the reason', (tester) async {
      await pumpForm(tester);
      AskodoxGuideNudges.instance.reportError('GST rate must be 0, 5, 12, 18 or 28.');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('did not go through'), findsOneWidget);
      await tester.tap(find.byKey(const Key('askodoxGuideNudgeYes')));
      await tester.pumpAndSettle();
      expect(find.textContaining('GST rate must be'), findsOneWidget);
      expect(find.byKey(const Key('askodoxGuideNudgeExplain')), findsOneWidget, reason: 'the page has a guide entry');
      await tester.tap(find.byKey(const Key('askodoxGuideNudgeExplain')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('askodoxScreenHelpSheet')), findsOneWidget);
    });
  });
}
