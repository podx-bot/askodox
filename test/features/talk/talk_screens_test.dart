import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/talk/data/talk_repository.dart';
import 'package:podx/features/talk/presentation/talk_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTalk implements TalkRepository {
  final known = <AskodoxTalkRoom>[const AskodoxTalkRoom(id: 'tr_1', topic: 'Cricket', messages: 3)];
  final sent = <String>[];

  @override
  String? get authToken => 'token';

  @override
  bool get signedIn => true;

  @override
  Future<List<AskodoxTalkRoom>> rooms(String query) async =>
      known.where((r) => r.topic.toLowerCase().contains(query.trim().toLowerCase())).toList();

  @override
  Future<(AskodoxTalkRoom?, String?)> open(String topic) async =>
      (AskodoxTalkRoom(id: 'tr_9', topic: topic, alias: 'నీలి చిలుక 42', aliasEn: 'Blue Parrot 42'), null);

  @override
  Future<AskodoxTalkPage> messages(String roomId, {int after = 0}) async => AskodoxTalkPage(messages: [
        if (after < 1)
          const AskodoxTalkMessage(id: 'tm_1', seq: 1, alias: 'పచ్చ పులి 17', aliasEn: 'Green Tiger 17',
              text: 'this is **** expensive', masked: true),
      ]);

  @override
  Future<AskodoxTalkSent> send(String roomId, String text, {String kind = 'text', String lang = 'te'}) async {
    sent.add(text);
    if (text.contains('end my life')) {
      return const AskodoxTalkSent(category: 'self_harm', support: 'Call Tele-MANAS 14416');
    }
    if (text.contains('kill')) return const AskodoxTalkSent(category: 'threat');
    return AskodoxTalkSent(posted: true, text: text);
  }

  @override
  Future<bool> report(String messageId, String reason) async => true;

  @override
  Future<bool> block(String messageId) async => true;

  @override
  Future<(Uint8List?, String, String?)> speak(String messageId, String lang) async => (null, 'this is beep', null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeTalk> _pump(WidgetTester tester, {bool accepted = false, String start = '/talk'}) async {
  SharedPreferences.setMockInitialValues({if (accepted) askodoxTalkRulesKey: true});
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fake = _FakeTalk();
  final router = GoRouter(initialLocation: start, routes: [
    GoRoute(path: '/talk', builder: (context, state) => const AskodoxTalkScreen()),
    GoRoute(
        path: '/talk/:id',
        builder: (context, state) => AskodoxTalkRoomScreen(
            roomId: state.pathParameters['id']!, topic: state.uri.queryParameters['topic'] ?? '')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [talkRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return fake;
}

void main() {
  testWidgets('first visit shows the rules (18+, anonymous, cost of listening) before any talk', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('askodoxTalkRules')), findsOneWidget);
    expect(find.textContaining('reading text is free'), findsOneWidget);
    expect(find.textContaining('18+'), findsWidgets);
    await tester.tap(find.byKey(const Key('askodoxTalkAccept')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxTalkSearch')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxTalkRoom-tr_1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxTalkCostNote')), findsOneWidget);
  });

  testWidgets('a new topic can be started and opens its room with a made-up name', (tester) async {
    await _pump(tester, accepted: true);
    await tester.enterText(find.byKey(const Key('askodoxTalkSearch')), 'Paddy prices');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('askodoxTalkStart')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('askodoxTalkRoomScreen')), findsOneWidget);
    expect(find.text('You are: Blue Parrot 42'), findsOneWidget);
    expect(find.text('this is **** expensive'), findsOneWidget);
    expect(find.text('Green Tiger 17'), findsOneWidget);
  });

  testWidgets('a held message is explained; self-harm gets support, not silence', (tester) async {
    final fake = await _pump(tester, accepted: true, start: '/talk/tr_9?topic=Cricket');
    await tester.enterText(find.byKey(const Key('askodoxTalkInput')), 'I will kill you');
    await tester.tap(find.byKey(const Key('askodoxTalkSend')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('was not posted'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.enterText(find.byKey(const Key('askodoxTalkInput')), 'I want to end my life');
    await tester.tap(find.byKey(const Key('askodoxTalkSend')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxTalkSupport')), findsOneWidget);
    expect(find.textContaining('14416'), findsOneWidget);
    expect(fake.sent, ['I will kill you', 'I want to end my life']);
  });
}
