import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/radio/data/travel_radio_repository.dart';
import 'package:podx/features/radio/presentation/travel_radio_screen.dart';

/// Answers /api/radio/next with a fixed status code / body.
class _FakeClient implements ApiClient {
  _FakeClient(this.status, [this.body = const {}]);
  final int status;
  final Map<String, Object?> body;
  Object? lastBody;

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    lastBody = body;
    if (status != 200) return ApiError<T>(ApiFailure(ApiFailureType.unknown, statusCode: status));
    return ApiSuccess<T>(this.body as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
}

void main() {
  group('Travel Radio repository: reason codes, never a made-up segment', () {
    Future<AskodoxRadioSegment> next(_FakeClient c) =>
        TravelRadioRepository(c, authToken: 't').next(latitude: 16.3, longitude: 80.8, lang: 'te');

    test('locked / disabled / capped map to their reasons', () async {
      expect((await next(_FakeClient(402))).problem, 'AI_CREDITS_LOW');
      expect((await next(_FakeClient(503))).problem, 'RADIO_DISABLED');
      expect((await next(_FakeClient(429))).problem, 'RADIO_DAILY_LIMIT');
      expect((await next(_FakeClient(500))).problem, 'unavailable');
    });

    test('nothing new is honest; a real segment carries its audio', () async {
      expect((await next(_FakeClient(200, {'status': 'nothing_new', 'segment': null}))).problem, 'nothing_new');
      final client = _FakeClient(200, {
        'status': 'ok',
        'segment': {'title': 'Uyyuru', 'text': 'మీరు ఇప్పుడు Uyyuru దగ్గర ఉన్నారు.'},
        'audio_b64': base64Encode([1, 2, 3]),
      });
      final seg = await next(client);
      expect(seg.problem, isNull);
      expect(seg.text, contains('Uyyuru'));
      expect(seg.audio, [1, 2, 3]);
      expect((client.lastBody as Map)['lang'], 'te');
    });
  });

  testWidgets('no separate radio package: no pass list, runs on AI Credits; off = locked', (tester) async {
    const status = AskodoxRadioStatus(enabled: false, access: false, plans: [
      AskodoxRadioPlan(code: 'radio_1d', name: 'Travel Radio · 1 day', price: 29, days: 1, available: false),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [travelRadioStatusProvider.overrideWith((ref) async => status)],
      child: const MaterialApp(home: TravelRadioScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxRadioPlan-radio_1d')), findsNothing);
    expect(find.text('₹29'), findsNothing);
    expect(find.textContaining('Radio pass'), findsNothing);
    expect(find.textContaining('free right now'), findsOneWidget);
    final play = tester.widget<ButtonStyleButton>(find.byKey(const Key('askodoxRadioPlay')));
    expect(play.onPressed, isNull, reason: 'switched off: nothing plays');
    expect(find.byKey(const Key('askodoxRadioLocked')), findsOneWidget);
  });

  testWidgets('switched on: plays; credit rate shown when charging is on', (tester) async {
    const status = AskodoxRadioStatus(enabled: true, access: true, plans: [], creditsCharging: true, creditRatePaise: 50);
    await tester.pumpWidget(ProviderScope(
      overrides: [travelRadioStatusProvider.overrideWith((ref) async => status)],
      child: const MaterialApp(home: TravelRadioScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxRadioLocked')), findsNothing);
    expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('askodoxRadioPlay'))).onPressed, isNotNull);
    expect(find.textContaining('₹0.50 of your AI Credits'), findsOneWidget);
  });

  testWidgets('internal testers see the testing label', (tester) async {
    const status = AskodoxRadioStatus(enabled: true, access: true, internalTesting: true, plans: [
      AskodoxRadioPlan(code: 'radio_1d', name: 'Travel Radio · 1 day', price: 29, days: 1, available: false),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [travelRadioStatusProvider.overrideWith((ref) async => status)],
      child: const MaterialApp(home: TravelRadioScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxRadioInternalTesting')), findsOneWidget);
    expect(find.byKey(const Key('askodoxRadioLocked')), findsNothing);
    expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('askodoxRadioPlay'))).onPressed, isNotNull);
  });
}
