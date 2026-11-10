import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/services/in_app_assistant_service.dart';

/// Owner 2026-11-10: a long answer shows word by word while it is written; the final JSON
/// is still the real answer, and an older backend without the stream route keeps working.
void main() {
  String ndjson(List<Map<String, Object?>> events) => '${events.map(jsonEncode).join('\n')}\n';

  const finalDecision = {
    'reply': '1. Open udyamregistration.gov.in\n2. Login with OTP',
    'domain': 'GENERAL',
    'transactional': false,
    'action': 'explain_steps',
    'mode': 'advice',
    'source': 'universal_ai',
  };

  test('pieces grow the text so far, then the final decision is returned', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return http.Response(
        ndjson([
          {'type': 'delta', 'text': '1. Open '},
          {'type': 'delta', 'text': 'udyamregistration.gov.in'},
          {'type': 'final', 'decision': finalDecision},
        ]),
        200,
        headers: {'content-type': 'application/x-ndjson; charset=utf-8'},
      );
    });
    final shown = <String>[];
    final decision = await InAppAssistantService(client: client).decideStreaming(
      message: 'Udyam registration ela cheyali?',
      locale: 'te',
      history: const [],
      onText: shown.add,
    );
    expect(paths, ['/api/in-app/assistant/stream']);
    expect(shown, ['1. Open ', '1. Open udyamregistration.gov.in']);
    expect(decision, isNotNull);
    expect(decision!.action, 'explain_steps');
    expect(decision.reply, finalDecision['reply']);
  });

  test('a withdrawn answer clears the text before the fallback answer', () async {
    final client = MockClient((request) async => http.Response(
          ndjson([
            {'type': 'delta', 'text': 'half'},
            {'type': 'reset'},
            {'type': 'delta', 'text': 'GEMINI GUIDE'},
            {'type': 'final', 'decision': {...finalDecision, 'reply': 'GEMINI GUIDE'}},
          ]),
          200,
        ));
    final shown = <String>[];
    final decision = await InAppAssistantService(client: client)
        .decideStreaming(message: 'how to', locale: 'en', history: const [], onText: shown.add);
    expect(shown, ['half', '', 'GEMINI GUIDE']);
    expect(decision!.reply, 'GEMINI GUIDE');
  });

  test('an older backend without the stream route is asked the plain way', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/stream')) return http.Response('Not Found', 404);
      return http.Response(jsonEncode(finalDecision), 200, headers: {'content-type': 'application/json'});
    });
    final shown = <String>[];
    final decision = await InAppAssistantService(client: client)
        .decideStreaming(message: 'how to', locale: 'en', history: const [], onText: shown.add);
    expect(paths, ['/api/in-app/assistant/stream', '/api/in-app/assistant']);
    expect(shown, isEmpty);
    expect(decision!.action, 'explain_steps');
  });

  test('a plain JSON answer on the stream route is still read', () async {
    final client = MockClient((request) async =>
        http.Response(jsonEncode(finalDecision), 200, headers: {'content-type': 'application/json'}));
    final decision = await InAppAssistantService(client: client)
        .decideStreaming(message: 'how to', locale: 'en', history: const [], onText: (_) {});
    expect(decision!.reply, finalDecision['reply']);
  });

  test('the stream route gets the same request body as the plain route', () async {
    late Map<String, dynamic> body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(ndjson([
        {'type': 'final', 'decision': finalDecision},
      ]), 200);
    });
    await InAppAssistantService(client: client).decideStreaming(
      message: 'how to',
      locale: 'te',
      history: const [InAppAssistantTurn(role: 'user', text: 'hi')],
      location: 'Vuyyuru',
      onText: (_) {},
    );
    expect(body['message'], 'how to');
    expect(body['location'], 'Vuyyuru');
    expect((body['history'] as List).length, 1);
    expect(body['capabilities'], contains('meaning_tags'));
  });

  test('a server error gives no decision (the app keeps its own flow)', () async {
    final client = MockClient((request) async => http.Response('oops', 500));
    final decision = await InAppAssistantService(client: client)
        .decideStreaming(message: 'how to', locale: 'en', history: const [], onText: (_) {});
    expect(decision, isNull);
  });
}
