import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/generated/l10n/app_localizations.dart';
import 'package:podx/shared/widgets/app_shell.dart';

void main() {
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => AppShell(shell: shell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/',
                    builder: (_, __) => const _Marker('HOME_SCREEN'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/search',
                    builder: (_, __) => const _Marker('SEARCH_SCREEN'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/watchlist',
                    builder: (_, __) => const _Marker('WATCHLIST_SCREEN'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/alerts',
                    builder: (_, __) => const _Marker('ALERTS_SCREEN'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/profile',
                    builder: (_, __) => const _Marker('PROFILE_SCREEN'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

  Widget buildApp(GoRouter router) => MaterialApp.router(
        routerConfig: router,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      );

  testWidgets('mobile primary navigation opens every destination by tap',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = buildRouter();
    await tester.pumpWidget(buildApp(router));
    await tester.pump();

    expect(find.byKey(const Key('askodoxPrimaryNavigation')), findsOneWidget);
    expect(find.text('HOME_SCREEN'), findsOneWidget);

    Future<void> tapDestination(Key key, String marker) async {
      final destination = find.byKey(key);
      expect(destination, findsOneWidget);
      await tester.tap(destination);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text(marker), findsOneWidget);
    }

    await tapDestination(const Key('askodoxNavSearch'), 'SEARCH_SCREEN');
    await tapDestination(const Key('askodoxNavWatchlist'), 'WATCHLIST_SCREEN');
    await tapDestination(const Key('askodoxNavAlerts'), 'ALERTS_SCREEN');
    await tapDestination(const Key('askodoxNavProfile'), 'PROFILE_SCREEN');
    await tapDestination(const Key('askodoxNavHome'), 'HOME_SCREEN');
  });
}

class _Marker extends StatelessWidget {
  const _Marker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: Text(label)),
      );
}
