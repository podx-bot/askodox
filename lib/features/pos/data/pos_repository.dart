import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../guide/guide_watch.dart';

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
    // A refused action (not a network blip): the guide on the left offers help with it.
    if (status == 400 || status == 409 || status == 422 || status == 403) {
      final reason = (error.failure.message ?? '').trim();
      AskodoxGuideNudges.instance.reportError(
          reason.isEmpty ? 'The server did not accept this.' : reason,
          reason.isEmpty ? 'సర్వర్ దీన్ని అంగీకరించలేదు.' : reason);
    }
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
  // restaurant
  Future<List<AskodoxJson>> tables(String id) async => askodoxPosList((await _send('GET', '${_b(id)}/tables'))['tables']);
  Future<AskodoxJson> addTable(String id, String name, {String area = '', int seats = 4}) =>
      _send('POST', '${_b(id)}/tables', body: {'name': name, 'area': area, 'seats': seats});
  Future<AskodoxJson> openOrder(String id, {String? tableId, String kind = 'dine_in', int guests = 0}) =>
      _send('POST', '${_b(id)}/orders', body: {'kind': kind, if (tableId != null) 'table_id': tableId, 'guests': guests});
  Future<List<AskodoxJson>> openOrders(String id) async => askodoxPosList((await _send('GET', '${_b(id)}/orders'))['orders']);
  Future<AskodoxJson> order(String id, String orderId) => _send('GET', '${_b(id)}/orders/$orderId');
  Future<AskodoxJson> addOrderItems(String id, String orderId, List<AskodoxJson> items) =>
      _send('POST', '${_b(id)}/orders/$orderId/items', body: {'items': items});
  Future<AskodoxJson> removeOrderItem(String id, String orderId, String itemId, {String reason = ''}) =>
      _send('POST', '${_b(id)}/orders/$orderId/items/$itemId/remove', body: {'reason': reason});
  Future<AskodoxJson> sendKot(String id, String orderId) => _send('POST', '${_b(id)}/orders/$orderId/kot');
  Future<AskodoxJson> moveOrder(String id, String orderId, String tableId) =>
      _send('POST', '${_b(id)}/orders/$orderId/move', body: {'table_id': tableId});
  Future<AskodoxJson> billOrder(String id, String orderId, AskodoxJson body) =>
      _send('POST', '${_b(id)}/orders/$orderId/bill', body: body);
  Future<AskodoxJson> voidOrder(String id, String orderId, String reason) =>
      _send('POST', '${_b(id)}/orders/$orderId/void', body: {'reason': reason});
  Future<List<AskodoxJson>> kitchen(String id) async => askodoxPosList((await _send('GET', '${_b(id)}/kitchen'))['kots']);
  Future<AskodoxJson> setKotStatus(String id, String kotId, String status) =>
      _send('POST', '${_b(id)}/kitchen/$kotId', body: {'status': status});
  // held bills / quotations (not financial records)
  Future<List<AskodoxJson>> drafts(String id, {String kind = ''}) async =>
      askodoxPosList((await _send('GET', '${_b(id)}/drafts', query: {if (kind.isNotEmpty) 'kind': kind}))['drafts']);
  Future<AskodoxJson> saveDraft(String id, AskodoxJson body) => _send('POST', '${_b(id)}/drafts', body: body);
  Future<AskodoxJson> deleteDraft(String id, String draftId) => _send('DELETE', '${_b(id)}/drafts/$draftId');

  // suppliers / purchases / batches
  Future<List<AskodoxJson>> suppliers(String id) async => askodoxPosList((await _send('GET', '${_b(id)}/suppliers'))['suppliers']);
  Future<AskodoxJson> addSupplier(String id, AskodoxJson body) => _send('POST', '${_b(id)}/suppliers', body: body);
  Future<AskodoxJson> supplier(String id, String supplierId) => _send('GET', '${_b(id)}/suppliers/$supplierId');
  Future<AskodoxJson> paySupplier(String id, String supplierId, AskodoxJson body) =>
      _send('POST', '${_b(id)}/suppliers/$supplierId/payments', body: body);
  Future<AskodoxJson> supplierStatement(String id, String supplierId, String month) =>
      _send('GET', '${_b(id)}/suppliers/$supplierId/statement', query: {'month': month});
  Future<List<AskodoxJson>> purchases(String id, {String supplierId = ''}) async =>
      askodoxPosList((await _send('GET', '${_b(id)}/purchases', query: {if (supplierId.isNotEmpty) 'supplier_id': supplierId}))['purchases']);
  Future<AskodoxJson> recordPurchase(String id, AskodoxJson body) => _send('POST', '${_b(id)}/purchases', body: body);
  Future<AskodoxJson> cancelPurchase(String id, String purchaseId, String reason) =>
      _send('POST', '${_b(id)}/purchases/$purchaseId/cancel', body: {'reason': reason});
  Future<List<AskodoxJson>> batches(String id, String productId) async =>
      askodoxPosList((await _send('GET', '${_b(id)}/stock/$productId/batches'))['batches']);
  Future<AskodoxJson> expiryReport(String id, {int days = 30}) => _send('GET', '${_b(id)}/reports/expiry', query: {'days': days});
  Future<AskodoxJson> valuation(String id) => _send('GET', '${_b(id)}/reports/valuation');
  Future<AskodoxJson> inputTax(String id, String from, String to) =>
      _send('GET', '${_b(id)}/reports/input-tax', query: {'date_from': from, 'date_to': to});

  // selling units / serials / purchase orders
  Future<AskodoxJson> setPack(String id, String productId, AskodoxJson body) =>
      _send('PUT', '${_b(id)}/products/$productId/packs', body: body);
  Future<List<String>> serialsInStock(String id, String productId) async =>
      [for (final s in ((await _send('GET', '${_b(id)}/products/$productId/serials'))['serials'] as List? ?? const [])) '$s'];
  Future<AskodoxJson> serialLookup(String id, String serial) => _send('GET', '${_b(id)}/serials/${Uri.encodeComponent(serial)}');
  Future<List<AskodoxJson>> purchaseOrders(String id) async => askodoxPosList((await _send('GET', '${_b(id)}/purchase-orders'))['orders']);
  Future<AskodoxJson> createPurchaseOrder(String id, AskodoxJson body) => _send('POST', '${_b(id)}/purchase-orders', body: body);
  Future<AskodoxJson> purchaseOrder(String id, String poId) => _send('GET', '${_b(id)}/purchase-orders/$poId');

  // Ready-made catalogue (shop's template), item details (attributes) and online price.
  Future<AskodoxJson> product(String id, String productId) => _send('GET', '${_b(id)}/products/$productId');
  Future<AskodoxJson> catalogue(String id) => _send('GET', '${_b(id)}/catalogue');
  Future<AskodoxJson> setCatalogueTemplate(String id, String? key) =>
      _send('PUT', '${_b(id)}/catalogue', body: {'template_key': key});
  Future<AskodoxJson> importCatalogue(String id, List<AskodoxJson> items) =>
      _send('POST', '${_b(id)}/catalogue/import', body: {'items': items});
  Future<AskodoxJson> setAttributes(String id, String productId, AskodoxJson values) =>
      _send('PUT', '${_b(id)}/products/$productId/attributes', body: {'values': values});
  Future<AskodoxJson> setOnlinePrice(String id, String productId, int? paise) =>
      _send('PUT', '${_b(id)}/products/$productId/online-price', body: {'online_price_paise': paise});

  /// Rates by quantity [{min_qty_milli, price_paise per base unit}] + the least quantity (null = none).
  Future<AskodoxJson> setPricing(String id, String productId, List<AskodoxJson> tiers, int? minQtyMilli) =>
      _send('PUT', '${_b(id)}/products/$productId/pricing', body: {'tiers': tiers, 'min_qty_milli': minQtyMilli});
  Future<AskodoxJson> setPhoto(String id, String productId, String base64Image) =>
      _send('PUT', '${_b(id)}/products/$productId/photo', body: {'image_base64': base64Image});
  Future<AskodoxJson> photo(String id, String productId) => _send('GET', '${_b(id)}/products/$productId/photo');

  // Where items are offered: pos / online / both (shop default + per item; null = follow the shop).
  Future<AskodoxJson> onlineStatus(String id) => _send('GET', '${_b(id)}/online');
  Future<AskodoxJson> setOnlineDefault(String id, String channel) =>
      _send('PUT', '${_b(id)}/online', body: {'channel': channel});
  Future<AskodoxJson> setOnlineChannel(String id, String productId, String? channel) =>
      _send('PUT', '${_b(id)}/products/$productId/online', body: {'channel': channel});

  // Shop advance (store credit): every change waits for the customer's approval in their own app.
  Future<AskodoxJson> advanceSettings(String id) => _send('GET', '${_b(id)}/advance/settings');
  Future<AskodoxJson> updateAdvanceSettings(String id, AskodoxJson body) =>
      _send('PUT', '${_b(id)}/advance/settings', body: body);
  Future<AskodoxJson> customerAdvance(String id, String customerId) =>
      _send('GET', '${_b(id)}/customers/$customerId/advance');

  /// kind = deposit | redeem | refund
  Future<AskodoxJson> requestAdvance(String id, String customerId, String kind, AskodoxJson body) =>
      _send('POST', '${_b(id)}/customers/$customerId/advance/$kind', body: body);
  Future<AskodoxJson> withdrawAdvance(String id, String entryId) => _send('POST', '${_b(id)}/advance/$entryId/withdraw');
  Future<AskodoxJson> myAdvances() => _send('GET', '/api/pos/me/advances');
  Future<AskodoxJson> decideAdvance(String entryId, {required bool approve, String? acceptTermsVersion}) =>
      _send('POST', '/api/pos/me/advances/$entryId/decision',
          body: {'approve': approve, if (acceptTermsVersion != null) 'accept_terms_version': acceptTermsVersion});
  Future<AskodoxJson> setPurchaseOrderStatus(String id, String poId, String status) =>
      _send('POST', '${_b(id)}/purchase-orders/$poId/status', body: {'status': status});
  Future<AskodoxJson> receivePurchaseOrder(String id, String poId, AskodoxJson body) =>
      _send('POST', '${_b(id)}/purchase-orders/$poId/receive', body: body);

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
