import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// One Travel Radio add-on plan. `available` is false until the Owner
/// activates billing -- the app never sells an inactive plan.
class AskodoxRadioPlan {
  const AskodoxRadioPlan({required this.code, required this.name, required this.price, required this.days,
      required this.available});
  final String code, name;
  final num price;
  final int days;
  final bool available;

  factory AskodoxRadioPlan.fromJson(Map<String, Object?> j) => AskodoxRadioPlan(
        code: '${j['code'] ?? ''}',
        name: '${j['name'] ?? ''}',
        price: (j['price'] as num?) ?? 0,
        days: (j['period_days'] as num?)?.toInt() ?? 1,
        available: j['available'] == true,
      );
}

class AskodoxRadioStatus {
  const AskodoxRadioStatus({required this.enabled, required this.access, required this.plans,
      this.passStatus, this.minutesToday = 0, this.dailyMinutes = 0, this.internalTesting = false});
  final bool enabled, access;

  /// Staff-chosen internal tester: Radio plays without a pass or price.
  final bool internalTesting;
  final List<AskodoxRadioPlan> plans;
  final String? passStatus;
  final num minutesToday, dailyMinutes;
}

/// What `/api/radio/next` answered. [problem] is a reason code
/// (RADIO_DISABLED / RADIO_ADDON_REQUIRED / RADIO_DAILY_LIMIT / nothing_new /
/// unavailable) -- never a made-up segment.
class AskodoxRadioSegment {
  const AskodoxRadioSegment({this.title = '', this.text = '', this.audio, this.problem});
  final String title, text;
  final Uint8List? audio;
  final String? problem;
}

String askodoxRadioProblemText(String code, bool te) => switch (code) {
      'RADIO_DISABLED' => te ? 'ట్రావెల్ రేడియో ఇంకా ప్రారంభం కాలేదు.' : 'Travel Radio is not switched on yet.',
      'RADIO_ADDON_REQUIRED' => te ? 'దీనికి ట్రావెల్ రేడియో పాస్ కావాలి.' : 'This needs a Travel Radio pass.',
      'RADIO_DAILY_LIMIT' => te ? 'ఈరోజు పరిమితి పూర్తయింది.' : "Today's listening limit is reached.",
      'nothing_new' => te ? 'ఇక్కడ కొత్త సమాచారం ఇంకా లేదు.' : 'Nothing new here yet.',
      'no_location' => te ? 'ముందు మీ లొకేషన్ ఎంచుకోండి.' : 'Choose your location first.',
      _ => te ? 'ఇప్పుడు అందుబాటులో లేదు.' : 'Not available right now.',
    };

class TravelRadioRepository {
  const TravelRadioRepository(this._client, {this.authToken});
  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions get _auth => ApiRequestOptions(authToken: authToken);

  Future<AskodoxRadioStatus?> status() async {
    if (authToken == null || authToken!.isEmpty) return null;
    final result = await _client.get<Map<String, Object?>>('/api/radio/status', options: _auth);
    if (result is! ApiSuccess<Map<String, Object?>>) throw StateError('radio unavailable');
    final d = result.data;
    final pass = d['pass'];
    return AskodoxRadioStatus(
      enabled: d['enabled'] == true,
      access: d['access'] == true,
      internalTesting: d['internal_testing'] == true,
      passStatus: pass is Map ? '${pass['status'] ?? ''}' : null,
      minutesToday: (d['minutes_today'] as num?) ?? 0,
      dailyMinutes: (d['daily_minutes'] as num?) ?? 0,
      plans: [
        for (final p in (d['plans'] as List?) ?? const [])
          if (p is Map) AskodoxRadioPlan.fromJson(Map<String, Object?>.from(p)),
      ],
    );
  }

  Future<AskodoxRadioSegment> next({required double latitude, required double longitude, required String lang,
      String voice = 'automatic'}) async {
    final result = await _client.post<Map<String, Object?>>('/api/radio/next',
        body: {'latitude': latitude, 'longitude': longitude, 'lang': lang, 'voice': voice}, options: _auth);
    if (result is ApiError<Map<String, Object?>>) {
      final code = switch (result.failure.statusCode) {
        503 => 'RADIO_DISABLED',
        402 => 'RADIO_ADDON_REQUIRED',
        429 => 'RADIO_DAILY_LIMIT',
        _ => 'unavailable',
      };
      return AskodoxRadioSegment(problem: code);
    }
    final d = (result as ApiSuccess<Map<String, Object?>>).data;
    final seg = d['segment'];
    if (seg is! Map) return const AskodoxRadioSegment(problem: 'nothing_new');
    final b64 = d['audio_b64'];
    return AskodoxRadioSegment(
      title: '${seg['title'] ?? ''}',
      text: '${seg['text'] ?? ''}',
      audio: b64 is String && b64.isNotEmpty ? base64Decode(b64) : null,
    );
  }
}

final travelRadioRepositoryProvider = Provider<TravelRadioRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return TravelRadioRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

final travelRadioStatusProvider =
    FutureProvider.autoDispose<AskodoxRadioStatus?>((ref) => ref.watch(travelRadioRepositoryProvider).status());
