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
      expect((await next(_FakeClient(402))).problem, 'RADIO_ADDON_REQUIRED');
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

  testWidgets('plans show the proposed prices but are NOT sold until billing is activated', (tester) async {
    const status = AskodoxRadioStatus(enabled: false, access: false, plans: [
      AskodoxRadioPlan(code: 'radio_1d', name: 'Travel Radio · 1 day', price: 29, days: 1, available: false),
      AskodoxRadioPlan(code: 'radio_7d', name: 'Travel Radio · 7 days', price: 149, days: 7, available: false),
      AskodoxRadioPlan(code: 'radio_30d', name: 'Travel Radio · 30 days', price: 399, days: 30, available: false),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [travelRadioStatusProvider.overrideWith((ref) async => status)],
      child: const MaterialApp(home: TravelRadioScreen()),
    ));
    await tester.pumpAndSettle();
    for (final code in ['radio_1d', 'radio_7d', 'radio_30d']) {
      expect(find.byKey(ValueKey('askodoxRadioPlan-$code')), findsOneWidget);
    }
    expect(find.text('₹29'), findsOneWidget);
    expect(find.text('₹399'), findsOneWidget);
    expect(find.text('Not available yet'), findsNWidgets(3));
    final play = tester.widget<ButtonStyleButton>(find.byKey(const Key('askodoxRadioPlay')));
    expect(play.onPressed, isNull, reason: 'switched off / no pass: nothing plays');
    expect(find.byKey(const Key('askodoxRadioLocked')), findsOneWidget);
  });

  testWidgets('internal testers see the testing label; plans stay unavailable', (tester) async {
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
    expect(find.text('Not available yet'), findsOneWidget);
  });
}
