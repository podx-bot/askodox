import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/providers/backend_providers.dart';

/// Paid notifications (owner 2026-11-24): anyone sends one to their shop's followers and / or people nearby, a
/// few paise per person reached (AI Credits; free while charging is off). Server: `routes/notices.py`.
class AskodoxNoticeAnswer {
  const AskodoxNoticeAnswer({this.data = const {}, this.code = '', this.message = ''});

  final Map<String, Object?> data;

  /// '' = ok; otherwise the server's reason (not_owner, no_location, nobody, quiet_hours, daily_limit,
  /// AI_CREDITS_LOW, no_links, image, sign_in, network ...).
  final String code;
  final String message;

  bool get ok => code.isEmpty;
}

/// The server's `detail.code` (or a code from the HTTP status) of a failed call.
AskodoxNoticeAnswer askodoxNoticeAnswerOf(ApiResult<Map<String, Object?>> result) {
  if (result case ApiSuccess<Map<String, Object?>>(:final data)) return AskodoxNoticeAnswer(data: data);
  final failure = (result as ApiError<Map<String, Object?>>).failure;
  var code = '';
  var message = failure.message ?? '';
  final body = failure.cause;
  if (body is String && body.trim().startsWith('{')) {
    try {
      final detail = (jsonDecode(body) as Map)['detail'];
      if (detail is Map) {
        code = '${detail['code'] ?? ''}';
        message = '${detail['message'] ?? message}';
      }
    } on FormatException {
      // not JSON: fall back to the status
    }
  }
  if (code.isEmpty) {
    code = switch (failure.statusCode) {
      401 || 403 => 'sign_in',
      402 => 'AI_CREDITS_LOW',
      429 => 'busy',
      null => 'network',
      _ => 'failed',
    };
  }
  return AskodoxNoticeAnswer(code: code, message: message);
}

/// "₹1.25" from paise (always two places: these are small amounts).
String askodoxNoticeRupees(int paise) => '₹${(paise ~/ 100)}.${(paise % 100).toString().padLeft(2, '0')}';

/// One line a person understands for each reason the server gives.
String askodoxNoticeReason(String code, bool te) => switch (code) {
      'not_owner' => te ? 'ఫాలోవర్స్‌కి షాప్ ఓనర్ మాత్రమే పంపగలరు.' : 'Only the shop owner can notify its followers.',
      'no_location' => te ? 'దగ్గరలో వాళ్ళకి పంపాలంటే ముందు మీ లొకేషన్ పెట్టండి.' : 'Set your location first to reach people nearby.',
      'nobody' => te
          ? 'ఇప్పుడు ఎవరికీ చేరదు (ఫాలోవర్స్ లేరు / దగ్గరలో ASKODOX వాడేవాళ్ళు లేరు / ఈరోజు ఇప్పటికే పంపారు).'
          : 'Nobody can be reached now (no followers / nobody nearby / already sent today).',
      'quiet_hours' => te ? 'ఉదయం 8 నుంచి రాత్రి 9 లోపే పంపుతాం. ఉదయం పంపండి.' : 'Notifications go out 8 am – 9 pm. Send in the morning.',
      'daily_limit' => te ? 'ఈరోజు పంపాల్సినవి అయిపోయాయి. రేపు పంపండి.' : "You've sent today's notifications. Send more tomorrow.",
      'AI_CREDITS_LOW' => te ? 'AI Credits సరిపోవు. కొంచెం రీఛార్జ్ చేయండి లేదా తక్కువ మందిని ఎంచుకోండి.' : 'Not enough AI Credits. Recharge a little or choose fewer people.',
      'no_links' => te ? 'లింక్‌లు, ఫోన్ నంబర్లు వద్దు — నోటిఫికేషన్ మీ ASKODOX పేజీనే తెరుస్తుంది.' : 'No links or phone numbers — it opens your ASKODOX page.',
      'image' => te ? 'ఫోటో 3 MB లోపు PNG / JPEG ఉండాలి.' : 'The picture must be a PNG / JPEG up to 3 MB.',
      'sign_in' => te ? 'ముందు సైన్ ఇన్ అవ్వండి.' : 'Sign in first.',
      'network' => te ? 'ఇంటర్నెట్ చూసి మళ్ళీ నొక్కండి.' : 'Check the internet and try again.',
      _ => te ? 'ఇప్పుడు కుదరలేదు. మళ్ళీ ప్రయత్నించండి.' : 'Could not do it now. Please try again.',
    };

/// What the AI designer is asked for: the subject is the person's own words; the picture carries the heading and a
/// small ASKODOX mark, never a phone number or link (the server refuses those in the text anyway).
String askodoxNoticeDesignPrompt({required String subject, required String shop, required String heading}) {
  final from = shop.trim().isEmpty ? '' : ' for "${shop.trim()}"';
  return 'Design a bright, clean square promotional notification picture$from about: ${subject.trim()}. '
      'Show the heading "${heading.trim()}" in large clear letters, a festive or product scene that fits the '
      'subject, and a small "ASKODOX" mark at the bottom corner. No phone numbers, no website links, no QR codes, '
      'no real people\'s faces.';
}

/// A short heading from the subject when the person did not write one (first line, max 60 letters).
String askodoxNoticeHeading(String subject) {
  final line = subject.trim().split('\n').first.trim();
  return line.length <= 60 ? line : '${line.substring(0, 57).trimRight()}...';
}

class AskodoxNoticeRepository {
  AskodoxNoticeRepository(this._client, this._token);

  final ApiClient _client;
  final String? Function() _token;

  ApiRequestOptions get _auth => ApiRequestOptions(authToken: _token());

  Map<String, Object?> _audience(String audience, String shopId, double km, double? lat, double? lon) => {
        'audience': audience,
        'business_id': shopId,
        'radius_km': km,
        if (lat != null && lon != null) 'lat': lat,
        if (lat != null && lon != null) 'lon': lon,
      };

  Future<AskodoxNoticeAnswer> preview({
    required String audience,
    String shopId = '',
    double km = 3,
    double? lat,
    double? lon,
  }) async =>
      askodoxNoticeAnswerOf(await _client.post<Map<String, Object?>>('/api/notices/preview',
          body: _audience(audience, shopId, km, lat, lon), options: _auth));

  Future<AskodoxNoticeAnswer> send({
    required String title,
    required String body,
    required String audience,
    required String clientTxnId,
    String shopId = '',
    double km = 3,
    double? lat,
    double? lon,
    List<int>? image,
    String imageMime = '',
  }) async =>
      askodoxNoticeAnswerOf(await _client.post<Map<String, Object?>>('/api/notices',
          body: {
            ..._audience(audience, shopId, km, lat, lon),
            'title': title,
            'body': body,
            'client_txn_id': clientTxnId,
            if (image != null && image.isNotEmpty) 'image_base64': base64Encode(image),
            if (image != null && image.isNotEmpty) 'image_mime': imageMime,
          },
          options: ApiRequestOptions(authToken: _token(), timeout: const Duration(seconds: 60))));

  Future<AskodoxNoticeAnswer> open(String id) async =>
      askodoxNoticeAnswerOf(await _client.get<Map<String, Object?>>('/api/notices/$id', options: _auth));

  Future<List<Map<String, Object?>>> mine() async {
    final answer = askodoxNoticeAnswerOf(await _client.get<Map<String, Object?>>('/api/notices/mine', options: _auth));
    return [
      for (final row in (answer.data['notices'] as List? ?? const []))
        if (row is Map) Map<String, Object?>.from(row),
    ];
  }
}

final askodoxNoticeRepositoryProvider = Provider<AskodoxNoticeRepository>((ref) => AskodoxNoticeRepository(
    ref.watch(apiClientProvider), () => ref.read(authSessionProvider).tokenPlaceholder));
