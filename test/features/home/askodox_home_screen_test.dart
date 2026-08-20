import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/config/brand/brand_config.dart';
import 'package:podx/features/home/presentation/home_screen.dart';

void main() {
  test('ASKODOX brand is centralized', () {
    expect(BrandConfig.displayName, 'ASKODOX');
    expect(BrandConfig.assistantName, 'ASKODOX AI');
    expect(BrandConfig.askHint, 'Ask ASKODOX');
  });

  testWidgets('AI-first home exposes orb, ask field and voice action', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/search', builder: (_, __) => const Scaffold(body: Text('Search'))),
        GoRoute(path: '/discover/voice', builder: (_, __) => const Scaffold(body: Text('Voice'))),
        GoRoute(path: '/profile', builder: (_, __) => const Scaffold(body: Text('Profile'))),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    expect(find.byKey(const Key('askodoxOrb')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAskField')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMicButton')), findsOneWidget);
    expect(find.text('ASKODOX AI'), findsOneWidget);
    expect(find.text('Ask anything local. Buy, sell, work, services or rides.'), findsOneWidget);
  });

  testWidgets('voice action routes to voice discovery', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/search', builder: (_, __) => const Scaffold(body: Text('Search'))),
        GoRoute(path: '/discover/voice', builder: (_, __) => const Scaffold(body: Text('Voice'))),
        GoRoute(path: '/profile', builder: (_, __) => const Scaffold(body: Text('Profile'))),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxMicButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Voice'), findsOneWidget);
  });
}
