import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/api_models.dart';
import '../core/providers/backend_providers.dart';

/// What came back from a photo edit / create request.
class ImageStudioResult {
  const ImageStudioResult({required this.ok, this.bytes, this.code = '', this.dailyLimit});

  final bool ok;
  final Uint8List? bytes;

  /// Why there is no picture: sign_in, daily_limit, credits_low, not_configured,
  /// off, busy, provider_failed, failed.
  final String code;
  final int? dailyLimit;
}

abstract interface class ImageStudioService {
  /// [images] in the order the customer attached them; the words say which
  /// photo changes. No images -> a new picture from the words.
  Future<ImageStudioResult> edit({required String prompt, required List<Uint8List> images, required String language});
}

class ApiImageStudioService implements ImageStudioService {
  ApiImageStudioService(this._client);

  final ApiClient _client;

  @override
  Future<ImageStudioResult> edit({
    required String prompt,
    required List<Uint8List> images,
    required String language,
  }) async {
    final result = await _client.post<Map<String, Object?>>(
      '/api/images/edit',
      body: {
        'prompt': prompt,
        'images': [
          for (final image in images.take(4)) {'data_base64': base64Encode(image)},
        ],
        'language': language,
      },
      options: const ApiRequestOptions(timeout: Duration(seconds: 150)),
    );
    return askodoxImageStudioResultOf(result);
  }
}

/// Maps the server's answer (or HTTP failure) to one result. A picture is
/// only "ok" when real image bytes came back.
ImageStudioResult askodoxImageStudioResultOf(ApiResult<Map<String, Object?>> result) {
  if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
    final limit = data['daily_limit'] is num ? (data['daily_limit'] as num).toInt() : null;
    if (data['ok'] == true) {
      try {
        final bytes = base64Decode('${data['image_base64'] ?? ''}');
        if (bytes.isNotEmpty) return ImageStudioResult(ok: true, bytes: bytes, dailyLimit: limit);
      } on FormatException {
        // fall through: no usable picture
      }
      return const ImageStudioResult(ok: false, code: 'failed');
    }
    final code = '${data['code'] ?? ''}';
    return ImageStudioResult(ok: false, code: code.isEmpty ? 'failed' : code, dailyLimit: limit);
  }
  final status = (result as ApiError<Map<String, Object?>>).failure.statusCode;
  return ImageStudioResult(
    ok: false,
    code: switch (status) { 401 || 403 => 'sign_in', 402 => 'credits_low', 429 => 'busy', _ => 'failed' },
  );
}

final imageStudioServiceProvider = Provider<ImageStudioService>(
  (ref) => ApiImageStudioService(ref.watch(apiClientProvider)),
);
