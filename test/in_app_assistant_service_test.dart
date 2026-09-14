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
}
