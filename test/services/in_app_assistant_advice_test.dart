import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/services/in_app_assistant_service.dart';

/// One-time advice memory: the app sends the ledger it got last turn and
/// keeps the one the brain returns, so a warning is never repeated without
/// new information, an explicit ask or a critical risk.
void main() {
  test('advice ledger round-trips between the app and the brain', () async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'reply': 'Okay, go ahead with the used one.',
            'domain': 'GENERAL',
            'transactional': false,
            'action': 'chat',
            'confidence': 0.9,
            'source': 'universal_ai',
            'advice': {'key': 'battery_health', 'repeated': true, 'allowed': false},
            'advice_ledger': [
              {'key': 'battery_health', 'summary': 'check battery', 'severity': 'caution', 'times': 2},
            ],
          }),
          200);
    });
    final ledger = [
      {'key': 'battery_health', 'summary': 'check battery', 'severity': 'caution', 'times': 1},
    ];
    final decision = await InAppAssistantService(client: client).decide(
        message: "I've decided, I'll buy it", locale: 'en', history: const [], adviceGiven: ledger);
    expect(sent!['advice_given'], ledger);
    expect(sent!['capabilities'], ['meaning_tags'], reason: 'this build renders the meaning tags');
    expect(decision!.advice!['repeated'], isTrue);
    expect(decision.adviceLedger!.single['times'], 2);
  });

  test('no ledger is sent when there is none, and an older backend keeps it null', () async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({'reply': 'Hi!', 'domain': 'GENERAL', 'transactional': false, 'action': 'chat',
              'confidence': 0.9, 'source': 'universal_ai'}),
          200);
    });
    final decision =
        await InAppAssistantService(client: client).decide(message: 'hi', locale: 'en', history: const []);
    expect(sent!.containsKey('advice_given'), isFalse);
    expect(decision!.advice, isNull);
    expect(decision.adviceLedger, isNull, reason: 'the app keeps the ledger it already has');
  });
}
