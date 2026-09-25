import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/services/in_app_assistant_service.dart';

void main() {
  test('parses structured universal AI decision, entities and sends history', () async {
    late Map<String, dynamic> body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.path, '/api/in-app/assistant');
      return http.Response(
        jsonEncode({
          'reply': 'మీ షాప్‌కు delivery staff కావాలి.',
          'domain': 'STAFFING',
          'transactional': true,
          'action': 'find_staff',
          'confidence': 0.96,
          'source': 'universal_ai',
          'entities': {
            'role': 'delivery boy',
            'headcount': 10,
            'timing': 'tomorrow 11 AM',
            'salary': 800,
            'location': 'Vijayawada',
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = InAppAssistantService(client: client);
    final decision = await service.decide(
      message: 'naku delivery boys kavali na shop ki',
      locale: 'te',
      history: const [
        InAppAssistantTurn(role: 'user', text: 'naa shop undi'),
        InAppAssistantTurn(role: 'assistant', text: 'ఏం సహాయం కావాలి?'),
      ],
    );

    expect(decision, isNotNull);
    expect(decision!.domain, 'STAFFING');
    expect(decision.transactional, isTrue);
    expect(decision.usable, isTrue);
    expect(decision.entityText('role'), 'delivery boy');
    expect(decision.entityNumber('headcount'), 10);
    expect(decision.entityNumber('salary'), 800);
    expect(decision.entityText('location'), 'Vijayawada');
    expect(body['message'], 'naku delivery boys kavali na shop ki');
    expect((body['history'] as List).length, 2);
  });

  test('sends the known/default location so the backend does not re-ask for it', () async {
    late Map<String, dynamic> body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'reply': 'i want to buy 5 kg chicken in Vijayawada',
          'domain': 'FOOD',
          'transactional': true,
          'action': 'buy',
          'confidence': 0.95,
          'source': 'universal_ai',
          'entities': {'subject': 'chicken', 'quantity': 5, 'unit': 'kg', 'location': 'Vijayawada'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = InAppAssistantService(client: client);
    await service.decide(
      message: 'నాకు 5 కిలోల చికెన్ కావాలి',
      locale: 'te',
      history: const [],
      location: 'Vijayawada',
    );

    expect(body['location'], 'Vijayawada');
  });

  test('omits location from the request when none is known yet', () async {
    late Map<String, dynamic> body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'reply': 'Where should ASKODOX find the match?',
          'domain': 'FOOD',
          'transactional': true,
          'action': 'buy',
          'confidence': 0.9,
          'source': 'universal_ai',
          'entities': {'subject': 'chicken'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = InAppAssistantService(client: client);
    await service.decide(
      message: 'నాకు చికెన్ కావాలి',
      locale: 'te',
      history: const [],
    );

    expect(body.containsKey('location'), isFalse);
  });

  test('missing or malformed entities safely become an empty map', () {
    final decision = InAppAssistantDecision.fromJson({
      'reply': 'సరే',
      'domain': 'GENERAL',
      'transactional': false,
      'action': 'chat',
      'confidence': 0.8,
      'source': 'universal_ai',
      'entities': 'not-a-map',
    });

    expect(decision.entities, isEmpty);
    expect(decision.entityText('role'), isNull);
  });

  test('returns null on backend failure instead of inventing an action', () async {
    final client = MockClient((request) async => http.Response('temporary', 503));
    final service = InAppAssistantService(client: client);

    final decision = await service.decide(
      message: 'parcel pampali',
      locale: 'te',
      history: const [],
    );

    expect(decision, isNull);
  });

  // Added 2026-09-16 (round 9, roadmap Phase 1). See buyer_guide_gate.py on
  // the backend for when buying_guide is actually filled in -- this test
  // only covers that the Flutter side parses it correctly when present.
  test('parses a buying guide when the backend attaches one', () {
    final decision = InAppAssistantDecision.fromJson({
      'reply': 'ఏం రకం కారు కావాలి?',
      'domain': 'PRODUCT',
      'transactional': true,
      'action': 'buy_product',
      'confidence': 0.9,
      'source': 'universal_ai',
      'entities': {'subject': 'car'},
      'buying_guide': {
        'subject': 'car',
        'questions': ['ఎందుకు కొనాలి / main use ఏమిటి?', 'Budget range ఎంత?'],
        'decision_framework': ['WHAT_TO_BUY', 'FAIR_PRICE'],
        'context': {'location': 'Vijayawada'},
      },
    });

    expect(decision.buyingGuide, isNotNull);
    expect(decision.buyingGuide!.subject, 'car');
    expect(decision.buyingGuide!.questions, hasLength(2));
    expect(decision.buyingGuide!.decisionFramework, contains('FAIR_PRICE'));
  });

  // Active Role = the current message's request intent, computed by the
  // backend on every /assistant call (see in_app_assistant.py's
  // `_suggest_active_role`) -- never a permanent lock-in, so the app must
  // read it fresh on every decision rather than caching it.
  test('parses the active role and its confidence when present', () {
    final decision = InAppAssistantDecision.fromJson({
      'reply': 'సరే, మీ TV వివరాలు చెప్పండి.',
      'domain': 'PRODUCT',
      'transactional': true,
      'action': 'sell',
      'confidence': 0.9,
      'source': 'universal_ai',
      'entities': {'subject': 'TV'},
      'active_role': 'SELLER',
      'active_role_confidence': 0.93,
    });

    expect(decision.activeRole, 'SELLER');
    expect(decision.activeRoleConfidence, 0.93);
  });

  test('active role defaults to empty when the backend omits it', () {
    final decision = InAppAssistantDecision.fromJson({
      'reply': 'సరే',
      'domain': 'GENERAL',
      'transactional': false,
      'action': 'chat',
      'confidence': 0.8,
      'source': 'universal_ai',
      'entities': <String, Object?>{},
    });

    expect(decision.activeRole, '');
    expect(decision.activeRoleConfidence, 0.0);
  });

  test('buying guide is null when the backend does not attach one', () {
    final decision = InAppAssistantDecision.fromJson({
      'reply': 'సరే',
      'domain': 'GENERAL',
      'transactional': false,
      'action': 'chat',
      'confidence': 0.8,
      'source': 'universal_ai',
      'entities': <String, Object?>{},
    });

    expect(decision.buyingGuide, isNull);
  });
}
