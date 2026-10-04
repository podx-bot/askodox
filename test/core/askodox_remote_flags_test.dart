import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/flags/askodox_remote_flags.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers /api/flags like the backend: targeting by role / category / %.
class _FlagsApi implements ApiClient {
  _FlagsApi(this.answer);

  Map<String, bool> Function(Map<String, String> query) answer;
  final paths = <String>[];
  bool fail = false;

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    paths.add(path);
    if (fail) return ApiError(const ApiFailure(ApiFailureType.network, message: 'offline'));
    final query = Uri.parse('https://x$path').queryParameters;
    return ApiSuccess(<String, Object?>{'flags': answer(query)} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults keep everything on when nothing was ever fetched', () async {
    final api = _FlagsApi((_) => {})..fail = true;
    final flags = await AskodoxFlagsRepository(api).load(role: UserRole.buyer);
    expect(flags.fromServer, isFalse);
    expect(flags.enabled('advisor.enabled'), isTrue);
    expect(flags.enabled('voice.sarvam_tts'), isTrue);
    expect(flags.enabled('some.unknown.flag'), isTrue);
  });

  test('a server answer is cached and survives a later network failure', () async {
    final api = _FlagsApi((_) => {'voice.sarvam_tts': false});
    final repo = AskodoxFlagsRepository(api, ttl: Duration.zero);
    expect((await repo.load(role: UserRole.buyer)).enabled('voice.sarvam_tts'), isFalse);
    api.fail = true;
    final again = await AskodoxFlagsRepository(api).load(role: UserRole.buyer);
    expect(again.enabled('voice.sarvam_tts'), isFalse, reason: 'last good answer from the device cache');
    expect(again.enabled('advisor.enabled'), isTrue);
  });

  test('role and category are sent and decide the answer', () async {
    final api = _FlagsApi((q) => {'advisor.enabled': q['role'] == 'seller' || q['category'] == 'footwear'});
    final repo = AskodoxFlagsRepository(api);
    expect((await repo.load(role: UserRole.buyer)).enabled('advisor.enabled'), isFalse);
    expect((await repo.load(role: UserRole.buyer, category: 'Footwear')).enabled('advisor.enabled'), isTrue);
    final seller = AskodoxFlagsRepository(_FlagsApi((q) => {'advisor.enabled': q['role'] == 'seller'}));
    expect((await seller.load(role: UserRole.seller)).enabled('advisor.enabled'), isTrue);
    expect(api.paths.first, contains('platform=android'));
    expect(askodoxFlagRole(UserRole.guest), 'guest');
  });

  test('percentage rollout uses one stable anonymous id per install', () async {
    final seen = <String>{};
    final api = _FlagsApi((q) {
      seen.add(q['subject']!);
      return {'companion.enabled': (q['subject']!.codeUnits.fold<int>(0, (a, b) => a + b) % 100) < 30};
    });
    final repo = AskodoxFlagsRepository(api, random: Random(7), ttl: Duration.zero);
    final first = await repo.load(role: UserRole.guest);
    final second = await repo.load(role: UserRole.guest);
    expect(seen.length, 1, reason: 'same bucket every time');
    expect(first.enabled('companion.enabled'), second.enabled('companion.enabled'));
    // A signed-in user is bucketed by their own id instead.
    await repo.load(role: UserRole.buyer, subject: 'phone-919800000000');
    expect(seen, contains('phone-919800000000'));
  });

  test('a malformed answer never switches anything off', () {
    final flags = AskodoxRemoteFlags.parse({'flags': {'advisor.enabled': 'no', 'x': 1}});
    expect(flags.enabled('advisor.enabled'), isTrue);
  });
}
