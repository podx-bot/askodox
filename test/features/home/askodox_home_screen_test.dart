import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/config/brand/brand_config.dart';
import 'package:podx/features/home/presentation/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ASKODOX brand is centralized', () {
    expect(BrandConfig.displayName, 'ASKODOX');
    expect(BrandConfig.assistantName, 'ASKODOX AI');
    expect(BrandConfig.askHint, 'Ask ASKODOX');
  });

  GoRouter buildRouter() => GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: '/search',
            builder: (_, __) => const Scaffold(body: Text('Search')),
          ),
          GoRoute(
            path: '/alerts',
            builder: (_, __) => const Scaffold(body: Text('Alerts')),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const Scaffold(body: Text('Profile')),
          ),
          GoRoute(
            path: '/discover/voice',
            builder: (_, __) => const Scaffold(body: Text('Voice')),
          ),
        ],
      );

  Widget buildApp(GoRouter router) => ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      );

  Future<void> finishRouteAnimation(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('AI-first home exposes every critical action', (tester) async {
    final router = buildRouter();

    await tester.pumpWidget(buildApp(router));
    await tester.pump();

    expect(find.byKey(const Key('askodoxOrb')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
    expect(find.byKey(const Key('askodoxHomeSendButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMicButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMenuButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSettingsButton')), findsOneWidget);
    expect(find.text('ASKODOX AI'), findsOneWidget);
    expect(find.text(BrandConfig.localPromise), findsOneWidget);
  });

  testWidgets('menu tap opens a real drawer and drawer navigation works',
      (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(buildApp(router));
    await tester.pump();

    await tester.tap(find.byKey(const Key('askodoxMenuButton')));
    await finishRouteAnimation(tester);

    expect(find.byKey(const Key('askodoxHomeDrawer')), findsOneWidget);
    expect(find.byKey(const Key('askodoxDrawerSearch')), findsOneWidget);

    await tester.tap(find.byKey(const Key('askodoxDrawerSearch')));
    await finishRouteAnimation(tester);
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets('voice tap routes to voice discovery', (tester) async {
    final router = buildRouter();

    await tester.pumpWidget(buildApp(router));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxMicButton')));
    await finishRouteAnimation(tester);

    expect(find.text('Voice'), findsOneWidget);
  });

  testWidgets('send tap opens conversation surface', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(buildApp(router));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('askodoxAskField')),
      'నాకు దగ్గరలో చికెన్ కావాలి',
    );
    await tester.tap(find.byKey(const Key('askodoxHomeSendButton')));
    await finishRouteAnimation(tester);

    expect(find.byKey(const Key('askodoxConversationList')), findsOneWidget);
    expect(find.byKey(const Key('askodoxConversationField')), findsOneWidget);
  });

  testWidgets('settings tap opens real developer settings on phone viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = buildRouter();
    await tester.pumpWidget(buildApp(router));
    await tester.pump();

    final settings = find.byKey(const Key('askodoxSettingsButton'));
    expect(settings, findsOneWidget);
    final rect = tester.getRect(settings);
    expect(rect.right, lessThanOrEqualTo(412));
    expect(rect.top, greaterThanOrEqualTo(0));

    await tester.tapAt(rect.center);
    await finishRouteAnimation(tester);

    expect(find.text('Developer settings'), findsOneWidget);
    expect(find.byKey(const Key('developerServerUrlField')), findsOneWidget);
    expect(find.byKey(const Key('demoRole-buyer')), findsOneWidget);
  });

  testWidgets('composer stays available when keyboard is shown', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = buildRouter();
    await tester.pumpWidget(buildApp(router));
    await tester.pump();

    final field = find.byKey(const Key('askodoxAskField'));
    await tester.tap(field);
    await tester.showKeyboard(field);
    await tester.pump();

    expect(find.byKey(const Key('askodoxComposerBar')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSettingsButton')), findsOneWidget);
    expect(find.byKey(const Key('askodoxHomeSendButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
