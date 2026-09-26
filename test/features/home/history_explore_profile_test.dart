import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/features/home/application/conversation_archive.dart';
import 'package:podx/features/home/presentation/explore_screen.dart';
import 'package:podx/features/profile/presentation/profile_screen.dart';
import 'package:podx/features/watchlist/presentation/watchlist_screen.dart';
import 'package:podx/services/explore_service.dart';
import 'package:podx/services/support_escalation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _snapshot(String id, String title, String status) => {
      'id': id,
      'title': title,
      'updatedAt': DateTime.now().toIso8601String(),
      'status': status,
      'data': {'turns': []},
    };

Future<ProviderContainer> _pumpRouted(
  WidgetTester tester, {
  required String initial,
  required Map<String, Widget> screens,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1440, 3200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: initial, routes: [
    for (final entry in screens.entries)
      GoRoute(path: entry.key, builder: (_, __) => entry.value),
  ]);
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

void main() {
  testWidgets('History lists real conversations, filters work, open restores and New ask starts clean',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'askodox.conversation_archive.v1': jsonEncode([
        _snapshot('c-3', 'AC service', 'completed'),
        _snapshot('c-2', 'Chicken nearby', 'matched'),
        _snapshot('c-1', 'Computer operator job', 'active'),
      ]),
    });
    final container = await _pumpRouted(tester, initial: '/history', screens: {
      '/history': const WatchlistScreen(),
      '/': const Text('MAIN CHAT'),
    });

    expect(find.text('Chicken nearby'), findsOneWidget);
    expect(find.text('AC service'), findsOneWidget);
    expect(find.text('Computer operator job'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('historyFilter-matched')));
    await tester.pump();
    expect(find.text('Chicken nearby'), findsOneWidget);
    expect(find.text('AC service'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('historyFilter-completed')));
    await tester.pump();
    expect(find.text('AC service'), findsOneWidget);
    expect(find.text('Chicken nearby'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('historyFilter-active')));
    await tester.pump();
    expect(find.text('Computer operator job'), findsOneWidget);
    expect(find.text('AC service'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('historyFilter-all')));
    await tester.pump();
    await tester.tap(find.text('Chicken nearby'));
    await tester.pumpAndSettle();
    expect(container.read(askodoxChatRequestProvider)?.conversationId, 'c-2');
    expect(find.text('MAIN CHAT'), findsOneWidget);
  });

  testWidgets('History New ask requests a clean conversation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = await _pumpRouted(tester, initial: '/history', screens: {
      '/history': const WatchlistScreen(),
      '/': const Text('MAIN CHAT'),
    });
    expect(find.textContaining('No conversations yet'), findsOneWidget);
    expect(find.text('Chicken nearby'), findsNothing, reason: 'no hardcoded demo history');
    await tester.tap(find.byKey(const Key('historyNewAsk')));
    await tester.pumpAndSettle();
    expect(container.read(askodoxChatRequestProvider)?.newConversation, isTrue);
    expect(find.text('MAIN CHAT'), findsOneWidget);
  });

  testWidgets('Explore shows real listings and every selection continues in the same chat',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final explore = ExploreService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/discover/explore');
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'items': [
              {'id': '9', 'title': 'Samsung 43 inch TV — open box', 'segment': 'surplus', 'source': 'local',
               'prompt': 'I want to buy Samsung 43 inch TV — open box'},
            ],
          })),
          200,
        );
      }),
    );
    final container = await _pumpRouted(tester, initial: '/explore', screens: {
      '/explore': const ExploreScreen(),
      '/': const Text('MAIN CHAT'),
    }, overrides: [exploreServiceProvider.overrideWithValue(explore)]);

    expect(find.textContaining('Mock Nearby'), findsNothing);
    expect(find.text('Samsung 43 inch TV — open box'), findsOneWidget);
    expect(find.textContaining('Open-box / clearance'), findsOneWidget);
    for (final tile in ['Products', 'Services', 'Jobs', 'Rides & delivery', 'Deals & offers',
        'Used / second-hand', 'Individual sellers', 'Surplus / open-box', 'Videos & reviews']) {
      expect(find.byKey(ValueKey('exploreTile-$tile')), findsOneWidget, reason: tile);
    }

    await tester.tap(find.byKey(const ValueKey('exploreItem-9')));
    await tester.pumpAndSettle();
    expect(container.read(askodoxChatRequestProvider)?.prompt, 'I want to buy Samsung 43 inch TV — open box');
    expect(find.text('MAIN CHAT'), findsOneWidget);
  });

  testWidgets('Explore category tile asks ASKODOX in chat', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = await _pumpRouted(tester, initial: '/explore', screens: {
      '/explore': const ExploreScreen(),
      '/': const Text('MAIN CHAT'),
    }, overrides: [
      exploreServiceProvider.overrideWithValue(
          ExploreService(client: MockClient((_) async => http.Response('{"items":[]}', 200)))),
    ]);
    await tester.tap(find.byKey(const ValueKey('exploreTile-Used / second-hand')));
    await tester.pumpAndSettle();
    expect(container.read(askodoxChatRequestProvider)?.prompt, contains('used and second-hand'));
  });

  testWidgets('Profile highlights the active role without changing stored roles', (tester) async {
    SharedPreferences.setMockInitialValues({
      'askodox.roles.v1': jsonEncode({'owned': ['buyer', 'serviceProvider'], 'active': 'seller'}),
    });
    await _pumpRouted(tester, initial: '/profile', screens: {'/profile': const ProfileScreen()});

    expect(find.text('Seller · Active now'), findsOneWidget);
    final seller = tester.widget<FilterChip>(find.byKey(const ValueKey('profileRole-seller')));
    expect(seller.selected, isFalse, reason: 'active role is highlighted, not added to stored roles');
    final provider = tester.widget<FilterChip>(find.byKey(const ValueKey('profileRole-serviceProvider')));
    expect(provider.selected, isTrue);
    expect(find.text('Buyer'), findsOneWidget);
  });

  test('support escalation client sends full context and reads configured channels', () async {
    late Map<String, dynamic> body;
    final service = SupportEscalationService(client: MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.path, '/api/in-app/support/escalate');
      expect(request.headers['Authorization'], 'Bearer tok');
      return http.Response(jsonEncode({
        'case_id': 7,
        'channels': {'chat': true, 'whatsapp_url': null, 'call_uri': 'tel:+911234'},
      }), 200);
    }));
    final supportCase = await service.escalate(
      issue: 'refund not received',
      category: 'PAYMENT',
      critical: true,
      conversation: const [{'role': 'user', 'text': 'refund not received'}],
      dealId: '42',
      authToken: 'tok',
    );
    expect(supportCase!.caseId, '7');
    expect(supportCase.whatsappUrl, isNull);
    expect(supportCase.callUri, 'tel:+911234');
    expect(body['deal_id'], '42');
    expect(body['critical'], isTrue);

    final failing = SupportEscalationService(client: MockClient((_) async => http.Response('', 500)));
    expect(await failing.escalate(issue: 'x', category: 'GENERAL', critical: false, conversation: const []), isNull);
  });
}
