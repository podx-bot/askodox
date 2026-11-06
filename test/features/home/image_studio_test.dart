import 'dart:convert';
import 'dart:typed_data';

import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/home/domain/image_studio.dart';
import 'package:podx/services/image_studio_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the photo analysis decides that words ask for a picture', () {
    expect(askodoxAnalysisWantsImage({'image_request': 'EDIT'}), isTrue);
    expect(askodoxAnalysisWantsImage({'image_request': 'create'}), isTrue);
    expect(askodoxAnalysisWantsImage({'image_request': 'NONE'}), isFalse);
    expect(askodoxAnalysisWantsImage({'subject': 'wig'}), isFalse);
    expect(askodoxAnalysisWantsImage(null), isFalse);
  });

  test('a picture is ok only when real bytes come back', () {
    final ok = askodoxImageStudioResultOf(ApiSuccess({'ok': true, 'image_base64': base64Encode([1, 2, 3])}));
    expect(ok.ok, isTrue);
    expect(ok.bytes, [1, 2, 3]);
    final empty = askodoxImageStudioResultOf(const ApiSuccess({'ok': true, 'image_base64': ''}));
    expect(empty.ok, isFalse);
    final capped = askodoxImageStudioResultOf(const ApiSuccess({'ok': false, 'code': 'daily_limit', 'daily_limit': 5}));
    expect((capped.ok, capped.code, capped.dailyLimit), (false, 'daily_limit', 5));
  });

  test('HTTP failures become honest reasons', () {
    ImageStudioResult of(int status) =>
        askodoxImageStudioResultOf(ApiError(ApiFailure(ApiFailureType.server, statusCode: status, message: 'x')));
    expect(of(401).code, 'sign_in');
    expect(of(402).code, 'credits_low');
    expect(of(429).code, 'busy');
    expect(of(500).code, 'failed');
  });

  test('every failure has a sentence in Telugu and English, and the limit is named', () {
    for (final code in ['sign_in', 'daily_limit', 'credits_low', 'not_configured', 'off', 'busy', 'provider_failed']) {
      expect(askodoxImageStudioFailureText(code, true), isNotEmpty);
      expect(askodoxImageStudioFailureText(code, false), isNotEmpty);
    }
    expect(askodoxImageStudioFailureText('daily_limit', false, dailyLimit: 5), contains('5'));
    expect(askodoxImageStudioDoneText(false), contains('AI'));
  });

  test('the sign-in token goes with the request; no token -> sign in, no call', () async {
    final client = _RecordingClient();
    final service = ApiImageStudioService(client);
    final none = await service.edit(prompt: 'wig', images: [Uint8List.fromList([1])], language: 'te');
    expect(none.code, 'sign_in');
    expect(client.tokens, isEmpty);
    final ok = await service.edit(prompt: 'wig', images: [Uint8List.fromList([1])], language: 'te', authToken: 'tok');
    expect(ok.ok, isTrue);
    expect(client.tokens, ['tok']);
  });
}

class _RecordingClient implements ApiClient {
  final tokens = <String?>[];

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    tokens.add(options.authToken);
    return ApiSuccess({'ok': true, 'image_base64': base64Encode([7])} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
