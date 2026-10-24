import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// Round 2 intelligence APIs (`/api/intel/...`): tax / GST rules and
/// calculators, scam checklists, smart-trick calculators. The backend owns
/// every rule and its official source; this side only sends the user's
/// numbers and shows the answer as given.
class AskodoxIntelException implements Exception {
  const AskodoxIntelException(this.code, [this.detail = '']);

  /// invalid | unavailable | network
  final String code;
  final String detail;

  String message(bool te) => switch (code) {
        'invalid' => detail.isNotEmpty ? detail : (te ? 'విలువలు సరిచూడండి.' : 'Please check the values.'),
        'network' => te ? 'ఇంటర్నెట్ కనెక్షన్ చూడండి.' : 'Check your internet connection.',
        _ => te
            ? 'ఈ సమాచారం ఇప్పుడు అందుబాటులో లేదు. తర్వాత ప్రయత్నించండి.'
            : 'This information is not available right now. Please try again later.',
      };

  @override
  String toString() => 'AskodoxIntelException($code, $detail)';
}

class AskodoxIntelligenceRepository {
  AskodoxIntelligenceRepository(this._client);
  final ApiClient _client;

  Map<String, Object?> _unwrap(ApiResult<Map<String, Object?>> result) {
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) return data;
    final failure = (result as ApiError<Map<String, Object?>>).failure;
    throw switch (failure.statusCode) {
      400 || 422 => AskodoxIntelException('invalid', failure.message ?? ''),
      null => const AskodoxIntelException('network'),
      _ => const AskodoxIntelException('unavailable'),
    };
  }

  Future<Map<String, Object?>> _post(String path, Map<String, Object?> body) async =>
      _unwrap(await _client.post<Map<String, Object?>>(path, body: body));

  Future<Map<String, Object?>> _get(String path, String language) async => _unwrap(
      await _client.get<Map<String, Object?>>(path, options: ApiRequestOptions(query: {'language': language})));

  Future<Map<String, Object?>> taxOverview(String language) => _get('/api/intel/tax', language);

  Future<Map<String, Object?>> incomeTax({
    required String year,
    required String regime,
    required double salary,
    required double other,
    required double deductions,
    required String ageBand,
    required bool resident,
  }) =>
      _post('/api/intel/tax/income', {
        'year': year,
        'regime': regime,
        'salary_income': salary,
        'other_income': other,
        'deductions': deductions,
        'age_band': ageBand,
        'resident': resident,
      });

  Future<Map<String, Object?>> gstRegistration({required double turnover, required String supply, required String state}) =>
      _post('/api/intel/gst/registration', {'turnover': turnover, 'supply': supply, 'state': state});

  Future<Map<String, Object?>> gstComposition({
    required double turnover,
    required String business,
    required String state,
    required bool interstate,
    required bool ecommerce,
  }) =>
      _post('/api/intel/gst/composition', {
        'turnover': turnover,
        'business': business,
        'state': state,
        'interstate_outward': interstate,
        'ecommerce_tcs': ecommerce,
      });

  Future<Map<String, Object?>> gstAmount(
          {required double amount, required double rate, required bool inclusive, required bool interstate}) =>
      _post('/api/intel/gst/amount',
          {'amount': amount, 'rate_percent': rate, 'inclusive': inclusive, 'interstate': interstate});

  Future<Map<String, Object?>> fraudList(String language) => _get('/api/intel/fraud', language);

  Future<Map<String, Object?>> fraudScheme(String id, String language) =>
      _get('/api/intel/fraud/${Uri.encodeComponent(id)}', language);

  Future<Map<String, Object?>> trick(String calculator,
          {Map<String, Object?> values = const {}, List<Map<String, Object?>>? options}) =>
      _post('/api/intel/tricks/${Uri.encodeComponent(calculator)}',
          {'values': values, if (options != null) 'options': options});
}

final askodoxIntelligenceRepositoryProvider =
    Provider<AskodoxIntelligenceRepository>((ref) => AskodoxIntelligenceRepository(ref.watch(apiClientProvider)));

/// Small helpers for reading the backend's JSON maps.
Map<String, Object?> askodoxMap(Object? v) => v is Map ? Map<String, Object?>.from(v) : const {};
List<Object?> askodoxList(Object? v) => v is List ? v : const [];
String askodoxStr(Object? v) => v == null ? '' : '$v';
double askodoxNum(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// "1234567" -> "12,34,567" (Indian grouping), no decimals.
String askodoxRupees(Object? v) {
  final n = askodoxNum(v).round();
  final negative = n < 0;
  final digits = n.abs().toString();
  if (digits.length <= 3) return '₹${negative ? '-' : ''}$digits';
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${negative ? '-' : ''}${parts.join(',')},$last3';
}
