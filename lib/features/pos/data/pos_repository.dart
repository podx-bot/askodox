import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

typedef AskodoxJson = Map<String, Object?>;

AskodoxJson askodoxPosMap(Object? v) => v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
List<AskodoxJson> askodoxPosList(Object? v) => v is List ? [for (final e in v) askodoxPosMap(e)] : const [];
int askodoxPosInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

class AskodoxPosException implements Exception {
  const AskodoxPosException(this.kind, [this.detail = '', this.code = '']);

  /// sign_in | network | not_found | permission | rejected | conflict | failed
  final String kind;
  final String detail;
  final String code;

  /// Retrying later can succeed (keep the sale in the offline queue).
  bool get retryable => kind == 'network' || kind == 'failed';

  String message(bool te) => switch (kind) {
        'sign_in' => te ? 'సైన్ ఇన్ చేయండి.' : 'Sign in first.',
        'network' => te ? 'ఇంటర్నెట్ లేదు — బిల్లు ఫోన్‌లో దాచి తర్వాత పంపుతాం.' : 'No internet — the bill is kept on this phone and sent later.',
        'permission' => te ? 'మీ పాత్రకు ఈ అనుమతి లేదు.' : 'Your role cannot do this.',
        'not_found' => te ? 'కనబడలేదు.' : 'Not found.',
        _ => detail.isNotEmpty ? detail : (te ? 'కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'That did not work. Please try again.'),
      };
}

String askodoxNewTxnId() {
  final r = Random.secure();
  return 'pos-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join()}';
}

/// All POS calls; every one is token-proven, the server checks the role.
class AskodoxPosRepository {
  AskodoxPosRepository(this._client, {this.authToken});
  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions _opts([Map<String, Object?> query = const {}]) =>
      ApiRequestOptions(authToken: authToken, timeout: const Duration(seconds: 20), query: query);

  Never _fail(ApiError<Object?> error) {
    final status = error.failure.statusCode;
    var code = '';
    try {
      final body = jsonDecode('${error.failure.cause}');
      if (body is Map && body['detail'] is Map) code = '${(body['detail'] as Map)['code'] ?? ''}';
    } catch (_) {}
    throw AskodoxPosException(
        switch (status) {
          401 => 'sign_in',
          403 => 'permission',
          404 => 'not_found',
          409 => 'conflict',
          null => 'network',
          400 || 413 || 422 => 'rejected',
          _ => 'failed',
        },
        error.failure.message ?? '',
        code);
  }

  Future<AskodoxJson> _send(String method, String path, {Object? body, Map<String, Object?> query = const {}}) async {
    if (authToken == null) throw const AskodoxPosException('sign_in');
    final ApiResult<Object?> result = switch (method) {
      'GET' => await _client.get<Object?>(path, options: _opts(query)),
      'POST' => await _client.post<Object?>(path, body: body, options: _opts(query)),
      'PATCH' => await _client.patch<Object?>(path, body: body, options: _opts(query)),
      'PUT' => await _client.put<Object?>(path, body: body, options: _opts(query)),
      _ => await _client.delete<Object?>(path, options: _opts(query)),
    };
    if (result is ApiError<Object?>) _fail(result);
    return askodoxPosMap((result as ApiSuccess<Object?>).data);
  }

  String _b(String id) => '/api/pos/businesses/$id';

  Future<AskodoxJson> meta() => _send('GET', '/api/pos/meta');
  Future<List<AskodoxJson>> businesses() async => askodoxPosList((await _send('GET', '/api/pos/businesses'))['businesses']);
  Future<AskodoxJson> createBusiness(AskodoxJson body) => _send('POST', '/api/pos/businesses', body: body);
  Future<AskodoxJson> business(String id) => _send('GET', _b(id));
  Future<AskodoxJson> checkGstin(String gstin) => _send('GET', '/api/pos/gstin/${Uri.encodeComponent(gstin)}');
  Future<List<AskodoxJson>> products(String id, {String q = ''}) async =>
      askodoxPosList((await _send('GET', '${_b(id)}/products', query: {if (q.isNotEmpty) 'q': q}))['products']);
  Future<AskodoxJson> addProduct(String id, AskodoxJson body) => _send('POST', '${_b(id)}/products', body: body);
  Future<AskodoxJson> updateProduct(String id, String productId, AskodoxJson body) =>
      _send('PATCH', '${_b(id)}/products/$productId', body: body);
  Future<AskodoxJson> stock(String id, AskodoxJson body) => _send('POST', '${_b(id)}/stock', body: body);
  Future<List<AskodoxJson>> customers(String id, {String q = ''}) async =>
      askodoxPosList((await _send('GET', '${_b(id)}/customers', query: {if (q.isNotEmpty) 'q': q}))['customers']);
  Future<AskodoxJson> addCustomer(String id, AskodoxJson body) => _send('POST', '${_b(id)}/customers', body: body);
  Future<AskodoxJson> customer(String id, String customerId) => _send('GET', '${_b(id)}/customers/$customerId');
  Future<AskodoxJson> setCustomerPrice(String id, String customerId, String productId, int? paise) =>
      _send('PUT', '${_b(id)}/customers/$customerId/prices/$productId', body: {'price_paise': paise});
  Future<AskodoxJson> collect(String id, String customerId, AskodoxJson body) =>
      _send('POST', '${_b(id)}/customers/$customerId/payments', body: body);
  Future<AskodoxJson> statement(String id, String customerId, String month) =>
      _send('GET', '${_b(id)}/customers/$customerId/statement', query: {'month': month});
  Future<AskodoxJson> createInvoice(String id, AskodoxJson body) => _send('POST', '${_b(id)}/invoices', body: body);
  Future<List<AskodoxJson>> invoices(String id, {String dateFrom = '', String dateTo = ''}) async =>
      askodoxPosList((await _send('GET', '${_b(id)}/invoices', query: {
        if (dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo.isNotEmpty) 'date_to': dateTo,
      }))['invoices']);
  Future<AskodoxJson> invoice(String id, String invoiceId) => _send('GET', '${_b(id)}/invoices/$invoiceId');
  Future<AskodoxJson> creditNote(String id, String invoiceId, AskodoxJson body) =>
      _send('POST', '${_b(id)}/invoices/$invoiceId/credit-notes', body: body);
  Future<AskodoxJson> cancel(String id, String invoiceId, String reason) =>
      _send('POST', '${_b(id)}/invoices/$invoiceId/cancel', body: {'reason': reason});
  Future<AskodoxJson> day(String id, String date) => _send('GET', '${_b(id)}/day/$date');
  Future<AskodoxJson> closeDay(String id, AskodoxJson body) => _send('POST', '${_b(id)}/day-close', body: body);
  Future<AskodoxJson> gstReport(String id, String from, String to) =>
      _send('GET', '${_b(id)}/reports/gst', query: {'date_from': from, 'date_to': to});
  Future<List<AskodoxJson>> members(String id) async => askodoxPosList((await _send('GET', '${_b(id)}/members'))['members']);
  Future<AskodoxJson> setMember(String id, String phone, String role) =>
      _send('POST', '${_b(id)}/members', body: {'phone': phone, 'role': role});
  Future<AskodoxJson> deviceSeries(String id, String deviceId) =>
      _send('POST', '${_b(id)}/device-series', body: {'device_id': deviceId});
}

final askodoxPosRepositoryProvider = Provider<AskodoxPosRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return AskodoxPosRepository(ref.watch(apiClientProvider), authToken: session.user == null ? null : session.tokenPlaceholder);
});

const askodoxPosQueueKey = 'askodox.pos.queue.v1';
const askodoxPosSeriesKey = 'askodox.pos.series.v1';
const askodoxPosDeviceKey = 'askodox.pos.device.v1';

/// A sale made without internet: the bill number comes from THIS device's own
/// series (registered with the server while online), so numbers stay unique
/// and consecutive. The queue is plain app storage (not encrypted) and is
/// cleared on sign-out. Nothing is ever dropped silently: a rejected sale
/// stays in the queue marked with the server's reason.
class AskodoxPosOfflineQueue {
  AskodoxPosOfflineQueue(this._repo);
  final AskodoxPosRepository _repo;

  Future<List<AskodoxJson>> pending() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return askodoxPosList(jsonDecode(prefs.getString(askodoxPosQueueKey) ?? '[]'));
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<AskodoxJson> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(askodoxPosQueueKey, jsonEncode(items));
  }

  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(askodoxPosDeviceKey);
    if (id == null) {
      id = askodoxNewTxnId().replaceFirst('pos-', 'dev-');
      await prefs.setString(askodoxPosDeviceKey, id);
    }
    return id;
  }

  /// Reserve this device's series while online (safe to call often).
  Future<AskodoxJson> ensureSeries(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final all = askodoxPosMap(jsonDecode(prefs.getString(askodoxPosSeriesKey) ?? '{}'));
    final server = await _repo.deviceSeries(businessId, await deviceId());
    final local = askodoxPosMap(all[businessId]);
    final sameSeries = local['prefix'] == server['prefix'] && local['fy'] == server['fy'];
    final next = max(askodoxPosInt(server['next_number']), sameSeries ? askodoxPosInt(local['next']) : 0);
    all[businessId] = {'prefix': server['prefix'], 'fy': server['fy'], 'next': next};
    await prefs.setString(askodoxPosSeriesKey, jsonEncode(all));
    return askodoxPosMap(all[businessId]);
  }

  /// Next offline invoice number, or null when no series was reserved for this
  /// financial year (then the sale cannot be billed offline).
  Future<String?> takeNumber(String businessId, String fy) async {
    final prefs = await SharedPreferences.getInstance();
    final all = askodoxPosMap(jsonDecode(prefs.getString(askodoxPosSeriesKey) ?? '{}'));
    final local = askodoxPosMap(all[businessId]);
    if (local['prefix'] == null || local['fy'] != fy) return null;
    final n = askodoxPosInt(local['next']);
    all[businessId] = {...local, 'next': n + 1};
    await prefs.setString(askodoxPosSeriesKey, jsonEncode(all));
    return '${local['prefix']}/$fy/${n.toString().padLeft(6, '0')}';
  }

  Future<void> add(String businessId, AskodoxJson body) async {
    final items = await pending();
    items.add({'business_id': businessId, 'body': body, 'status': 'pending', 'error': ''});
    await _save(items);
  }

  /// Sends every pending sale; returns (sent, stillPending, rejected).
  Future<({int sent, int pending, int rejected})> sync() async {
    final items = await pending();
    var sent = 0;
    for (final item in items.toList()) {
      if (item['status'] == 'rejected') continue;
      try {
        await _repo.createInvoice('${item['business_id']}', askodoxPosMap(item['body']));
        items.remove(item);
        sent += 1;
      } on AskodoxPosException catch (e) {
        if (e.retryable || e.kind == 'sign_in') break;
        item['status'] = 'rejected';
        item['error'] = e.detail;
      }
    }
    await _save(items);
    return (
      sent: sent,
      pending: items.where((i) => i['status'] == 'pending').length,
      rejected: items.where((i) => i['status'] == 'rejected').length,
    );
  }
}

final askodoxPosQueueProvider = Provider<AskodoxPosOfflineQueue>((ref) => AskodoxPosOfflineQueue(ref.watch(askodoxPosRepositoryProvider)));

/// Indian financial year label for a local date: 2026-10-23 -> "2627".
String askodoxFinancialYear(DateTime local) {
  final start = local.month >= 4 ? local.year : local.year - 1;
  return '${(start % 100).toString().padLeft(2, '0')}${((start + 1) % 100).toString().padLeft(2, '0')}';
}
