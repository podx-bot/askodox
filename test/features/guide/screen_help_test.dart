import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/config/router/app_router.dart';
import 'package:podx/core/startup/startup_hint.dart';
import 'package:podx/features/guide/screen_help.dart';
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
}
