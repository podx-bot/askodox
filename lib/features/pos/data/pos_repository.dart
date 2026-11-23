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
        // Owner 2026-11-20: this text shows on EVERY page (items, settings, quick bill), so it never claims a bill was
        // kept -- only the sale screen's own offline queue says that, after it really queued the bill.
        'network' => te
            ? 'ASKODOX సర్వర్ అందలేదు (ఇంటర్నెట్ లేదు లేదా నెమ్మదిగా ఉంది). మళ్ళీ నొక్కండి.'
            : 'Could not reach ASKODOX (no or slow internet). Please tap again.',
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

  ApiRequestOptions _opts([Map<String, Object?> query = const {}, Duration timeout = const Duration(seconds: 20)]) =>
      ApiRequestOptions(authToken: authToken, timeout: timeout, query: query);

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

  Future<AskodoxJson> _send(String method, String path,
      {Object? body, Map<String, Object?> query = const {}, Duration timeout = const Duration(seconds: 20)}) async {
    if (authToken == null) throw const AskodoxPosException('sign_in');
    final opts = _opts(query, timeout);
    Future<ApiResult<Object?>> once() async => switch (method) {
          'GET' => await _client.get<Object?>(path, options: opts),
          'POST' => await _client.post<Object?>(path, body: body, options: opts),
          'PATCH' => await _client.patch<Object?>(path, body: body, options: opts),
          'PUT' => await _client.put<Object?>(path, body: body, options: opts),
          _ => await _client.delete<Object?>(path, options: opts),
        };
    var result = await once();
    // A network blip on a read or a repeat-safe save (GET / PUT) is tried once more by itself before the person is told.
    if (result is ApiError<Object?> && result.failure.statusCode == null && (method == 'GET' || method == 'PUT')) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      result = await once();
    }
    if (result is ApiError<Object?>) _fail(result);
    return askodoxPosMap((result as ApiSuccess<Object?>).data);
  }

  String _b(String id) => '/api/pos/businesses/$id';

  Future<AskodoxJson> meta() => _send('GET', '/api/pos/meta');
  Future<List<AskodoxJson>> businesses() async => askodoxPosList((await _send('GET', '/api/pos/businesses'))['businesses']);
  Future<AskodoxJson> createBusiness(AskodoxJson body) => _send('POST', '/api/pos/businesses', body: body);
  Future<AskodoxJson> business(String id) => _send('GET', _b(id));
  /// Shop name only (owner 2026-11-14: a typo at creation must be fixable). Backend: PATCH /businesses/{id}.
  /// Owner only: open | paused | closed (listings hide, self-shopping / table QR refuse; nothing is deleted).
  Future<AskodoxJson> setBusinessStatus(String id, String status, {String note = ''}) =>
      _send('POST', '${_b(id)}/status', body: {'status': status, 'note': note});
  // ---- Front desk (pos_frontdesk.py): QR menu -> customer order -> kitchen -> bill. Customer calls need only sign-in.
  Future<AskodoxJson> deskResolve(String code) => _send('GET', '/api/pos/order-desk/resolve', query: {'code': code});
  Future<AskodoxJson> deskAssist(String code, String text, List<AskodoxJson> cart, {bool te = true}) =>
      _send('POST', '/api/pos/order-desk/assist', body: {'code': code, 'text': text, 'cart': cart, 'te': te});
  /// Shops with a menu whose name contains [q] (the search box beside the QR photo).
  /// ASKODOX Shopping: shops on ASKODOX (name / menu) + the affiliate items for what was searched.
  /// [lat] / [lng] = the person's place: the nearest ASKODOX shops come first (owner 2026-11-19).
  Future<AskodoxJson> shopping(String q, {double? lat, double? lng}) => _send('GET', '/api/pos/shopping',
      query: {'q': q, if (lat != null && lng != null) 'lat': '$lat', if (lat != null && lng != null) 'lng': '$lng'});
  Future<List<AskodoxJson>> deskShops(String q) async =>
      askodoxPosList((await _send('GET', '/api/pos/order-desk/shops', query: {'q': q}))['shops']);
  Future<AskodoxJson> deskPlace(AskodoxJson body) => _send('POST', '/api/pos/order-desk/orders', body: body);
  // Table reservation ahead of time (owner 2026-11-19).
  Future<AskodoxJson> freeTables(String biz, String atIso, int people) =>
      _send('GET', '/api/pos/order-desk/$biz/tables/free', query: {'at': atIso, 'people': '$people'});
  Future<AskodoxJson> reserveTable(String biz, AskodoxJson body) => _send('POST', '/api/pos/order-desk/$biz/reservations', body: body);
  Future<List<AskodoxJson>> myReservations() async =>
      askodoxPosList((await _send('GET', '/api/pos/me/reservations'))['reservations']);
  Future<AskodoxJson> cancelMyReservation(String id) => _send('POST', '/api/pos/me/reservations/$id/cancel');
  Future<List<AskodoxJson>> shopReservations(String biz) async =>
      askodoxPosList((await _send('GET', '${_b(biz)}/reservations'))['reservations']);
  Future<AskodoxJson> shopReservationStatus(String biz, String id, String status) =>
      _send('POST', '${_b(biz)}/reservations/$id/status', body: {'status': status});
  Future<List<AskodoxJson>> deskMine() async => askodoxPosList((await _send('GET', '/api/pos/order-desk/mine'))['orders']);
  Future<AskodoxJson> deskMineOne(String id) => _send('GET', '/api/pos/order-desk/mine/$id');
  /// The customer's choice: 'cash' (pay at the counter / table) or 'online' (the shop's own UPI).
  Future<AskodoxJson> deskPayChoice(String id, String choice) =>
      _send('POST', '/api/pos/order-desk/mine/$id/pay-choice', body: {'choice': choice});
  Future<AskodoxJson> deskMyRequests(String orderId) => _send('GET', '/api/pos/order-desk/mine/$orderId/requests');
  Future<AskodoxJson> deskAsk(String orderId, {List<String> kinds = const [], String text = ''}) =>
      _send('POST', '/api/pos/order-desk/mine/$orderId/requests', body: {'kinds': kinds, 'text': text});
  Future<AskodoxJson> deskRequests(String biz) => _send('GET', '${_b(biz)}/desk/requests');
  Future<AskodoxJson> deskRequestDone(String biz, String id) => _send('POST', '${_b(biz)}/desk/requests/$id/done');
  Future<AskodoxJson> deskRequestSettings(String biz) => _send('GET', '${_b(biz)}/desk/request-settings');
  Future<AskodoxJson> deskRequestSettingsSave(String biz, {List<String>? off, List<AskodoxJson>? custom}) =>
      _send('PUT', '${_b(biz)}/desk/request-settings', body: {if (off != null) 'off': off, if (custom != null) 'custom': custom});
  Future<AskodoxJson> deskCancelMine(String id) => _send('POST', '/api/pos/order-desk/mine/$id/cancel');
  Future<AskodoxJson> deskOrders(String biz, {String lane = 'active'}) =>
      _send('GET', '${_b(biz)}/desk/orders', query: {'lane': lane});
  Future<AskodoxJson> deskStaffPlace(String biz, AskodoxJson body) => _send('POST', '${_b(biz)}/desk/orders', body: body);
  Future<AskodoxJson> deskConfirm(String biz, String id, Map<String, bool> decisions) =>
      _send('POST', '${_b(biz)}/desk/orders/$id/confirm', body: {'decisions': decisions});
  Future<AskodoxJson> deskReject(String biz, String id, String reason) =>
      _send('POST', '${_b(biz)}/desk/orders/$id/reject', body: {'reason': reason});
  Future<AskodoxJson> deskAdvance(String biz, String id, String stage, {String assignee = '', String assigneeUser = ''}) =>
      _send('POST', '${_b(biz)}/desk/orders/$id/advance', body: {'stage': stage, 'assignee': assignee, 'assignee_user': assigneeUser});
  Future<AskodoxJson> deskBill(String biz, String id, List<AskodoxJson> payments, {String? customerId}) =>
      _send('POST', '${_b(biz)}/desk/orders/$id/bill',
          body: {'payments': payments, 'client_txn_id': askodoxNewTxnId(), 'customer_id': customerId});
  Future<AskodoxJson> deskAssign(String biz, String id, String who, {String userId = ''}) =>
      _send('POST', '${_b(biz)}/desk/orders/$id/assign', body: {'assignee': who, 'assignee_user': userId});
  /// The staff an order can be assigned to ({id, label, role, you}).
  Future<List<AskodoxJson>> deskPeople(String biz) async => askodoxPosList((await _send('GET', '${_b(biz)}/desk/people'))['people']);
  /// Who is told about each step + auto-confirm (owner only).
  Future<AskodoxJson> deskSettings(String biz) => _send('GET', '${_b(biz)}/desk/settings');
  Future<AskodoxJson> deskSettingsSave(String biz, {Map<String, List<String>>? routing, bool? autoConfirm}) =>
      _send('PUT', '${_b(biz)}/desk/settings', body: {if (routing != null) 'routing': routing, if (autoConfirm != null) 'auto_confirm': autoConfirm});
  /// Today / week / month sales from the shop's own bills.
  Future<AskodoxJson> shopSales(String biz, {String period = 'day', String date = ''}) =>
      _send('GET', '${_b(biz)}/sales', query: {'period': period, if (date.isNotEmpty) 'date': date});
  Future<AskodoxJson> deskCounterAssist(String biz, String text, List<AskodoxJson> cart, {bool te = true}) =>
      _send('POST', '${_b(biz)}/desk/assist', body: {'text': text, 'cart': cart, 'te': te});
  Future<AskodoxJson> deskMenu(String biz) => _send('GET', '${_b(biz)}/desk/menu');
  Future<AskodoxJson> deskMenuParse(String biz, String text) => _send('POST', '${_b(biz)}/desk/menu/parse', body: {'text': text});
  /// Menu photo(s) -> a PREVIEW (items + printed prices, nothing saved). [images]: {data: base64, mime}.
  /// Reading takes the AI 10-40 s, so this call waits 90 s (owner 2026-11-16: at 20 s the phone gave up while the
  /// server had read the menu, and showed "No internet").
  Future<AskodoxJson> deskMenuPhoto(String biz, List<AskodoxJson> images) =>
      _send('POST', '${_b(biz)}/desk/menu/photo', body: {'images': images}, timeout: const Duration(seconds: 90));
  Future<AskodoxJson> deskMenuImport(String biz, List<AskodoxJson> items, {int rateBp = 0}) =>
      _send('POST', '${_b(biz)}/desk/menu/import', body: {'items': items, 'rate_bp': rateBp});
  Future<AskodoxJson> deskAvailability(String biz, String product, bool available) =>
      _send('POST', '${_b(biz)}/desk/menu/$product/availability', body: {'available': available});
  Future<AskodoxJson> deskTodayOnly(String biz, String product, bool todayOnly) =>
      _send('POST', '${_b(biz)}/desk/menu/$product/today-only', body: {'today_only': todayOnly});
  Future<AskodoxJson> deskQr(String biz) => _send('GET', '${_b(biz)}/desk/qr');
  /// Speak-to-fill: the words said + the page's boxes -> {values: {key: value}} (nothing invented; server checks types).
  Future<AskodoxJson> formFill(List<AskodoxJson> fields, String text, {String locale = 'te'}) =>
      _send('POST', '/api/pos/form-fill', body: {'fields': fields, 'text': text, 'locale': locale});
  /// The calculator bill as a REAL bill (items, GST only for a registered shop, advance, pending on the customer).
  Future<AskodoxJson> quickBill(String biz, AskodoxJson body) => _send('POST', '${_b(biz)}/quick-bill', body: body);
  // ---- Bills after the counter (pos_bills.py): send to the customer's number, settle later, history, customer inbox.
  /// -> {channel: askodox | whatsapp, text, url, whatsapp_to}. ASKODOX users get it in "My bills"; others on WhatsApp.
  Future<AskodoxJson> billSend(String biz, String invoiceId, String phone) =>
      _send('POST', '${_b(biz)}/bills/$invoiceId/send', body: {'phone': phone});
  /// [amountPaise] 0 = the whole balance of this bill; more than 0 = part of it (the dues steps split one payment
  /// over a person's bills, oldest first).
  Future<AskodoxJson> billSettle(String biz, String invoiceId, String pay, String txn, {int amountPaise = 0}) =>
      _send('POST', '${_b(biz)}/bills/$invoiceId/settle',
          body: {'pay': pay, 'client_txn_id': txn, if (amountPaise > 0) 'amount_paise': amountPaise});
  /// Main chat bill by item numbers (owner 2026-11-19): {card, reply}; card null = not a number bill / not a seller.
  Future<AskodoxJson> chatBill(String text, {required bool te}) =>
      _send('POST', '/api/pos/chat-bill', body: {'text': text, 'te': te});
  /// The phone printed this bill (owner 2026-11-19: history flags bills never printed).
  Future<AskodoxJson> billPrinted(String biz, String invoiceId) => _send('POST', '${_b(biz)}/bills/$invoiceId/printed');
  Future<AskodoxJson> billHistory(String biz, {String from = '', String to = '', bool due = false, String q = ''}) =>
      _send('GET', '${_b(biz)}/bills', query: {'date_from': from, 'date_to': to, 'due': due ? 'true' : 'false', 'q': q});
  Future<List<AskodoxJson>> myBills() async => askodoxPosList((await _send('GET', '/api/pos/me/bills'))['bills']);
  Future<AskodoxJson> myBillPaid(String token, String app) =>
      _send('POST', '/api/pos/me/bills/$token/paid', body: {'app': app});
  /// "I will pay on (date)" for a pending bill: the shop is told, reminders wait until then.
  // ---- Baaki reminders (pos_dues_followup.py): 3 days before the pay date .. the date, WhatsApp text ready.
  Future<AskodoxJson> dueReminders(String id) => _send('GET', '${_b(id)}/dues/reminders');
  Future<AskodoxJson> setDueDate(String id, String invoiceId, String date) =>
      _send('PUT', '${_b(id)}/dues/$invoiceId/date', body: {'date': date});
  Future<AskodoxJson> markDueReminded(String id, String invoiceId) => _send('POST', '${_b(id)}/dues/$invoiceId/sent');
  Future<AskodoxJson> myBillPromise(String token, String date) =>
      _send('POST', '/api/pos/me/bills/$token/promise', body: {'date': date});
  Future<AskodoxJson> renameBusiness(String id, String name) => _send('PATCH', _b(id), body: {'name': name});
  // Shop follows: any signed-in person, shop owners included (backend: routes/shop_follows.py).
  Future<AskodoxJson> shopState(String id) => _send('GET', '/api/shops/$id');
  // ratings, reviews, shop page, welcome (owner 2026-11-17)
  Future<AskodoxJson> shopPage(String id) => _send('GET', '/api/pos/shops/$id/page');
  Future<AskodoxJson> writeReview(String id, int stars, String text, List<AskodoxJson> photos) =>
      _send('POST', '/api/pos/shops/$id/review', body: {'stars': stars, 'text': text, 'photos': photos});
  Future<AskodoxJson> deleteReview(String id) => _send('DELETE', '/api/pos/shops/$id/review');
  Future<AskodoxJson> replyReview(String id, String reviewId, String text) =>
      _send('POST', '/api/pos/shops/$id/reviews/$reviewId/reply', body: {'text': text});
  Future<AskodoxJson> reportReview(String reviewId) => _send('POST', '/api/pos/shops/reviews/$reviewId/report');
  Future<AskodoxJson> rateAsk(String orderId) => _send('GET', '/api/pos/order-desk/mine/$orderId/rate');
  Future<AskodoxJson> rate(String orderId, {int? shop, Map<String, int> items = const {}, bool later = false}) =>
      _send('POST', '/api/pos/order-desk/mine/$orderId/rate',
          body: {if (shop != null) 'shop': shop, 'items': items, 'later': later});
  Future<AskodoxJson> welcomeSettings(String biz) => _send('GET', '${_b(biz)}/welcome');
  Future<AskodoxJson> saveWelcome(String biz, AskodoxJson body) => _send('PUT', '${_b(biz)}/welcome', body: body);
  // 193 items took longer than the old 20 s (owner 2026-11-18 "no internet"): the server now reads parts at once.
  Future<AskodoxJson> menuSort(String biz) =>
      _send('POST', '${_b(biz)}/desk/menu/sort', timeout: const Duration(seconds: 150));
  /// Owner 2026-11-23: the reading runs on the server in the background ([menuSortState] polls it; a notification
  /// says when it is ready), so the owner may leave the page.
  Future<AskodoxJson> menuSortStart(String biz, {String lang = 'te'}) =>
      _send('POST', '${_b(biz)}/desk/menu/sort', query: {'background': 1, 'lang': lang});
  Future<AskodoxJson> menuSortState(String biz) => _send('GET', '${_b(biz)}/desk/menu/sort');
  /// Today's numbers for the business hub and its 6 group pages.
  Future<AskodoxJson> hub(String biz) => _send('GET', '${_b(biz)}/hub');
  /// The ASK bar: one sentence -> {reply, open?, confirm?}. A change runs only through [askConfirm].
  Future<AskodoxJson> ask(String biz, String text, {String page = 'hub', String lang = 'te'}) =>
      _send('POST', '${_b(biz)}/ask', body: {'text': text, 'page': page, 'lang': lang}, timeout: const Duration(seconds: 40));
  Future<AskodoxJson> askConfirm(String biz, AskodoxJson change) => _send('POST', '${_b(biz)}/ask/confirm', body: change);
  // Cashbook (money in from bills is read, not typed) + dues grouped by person.
  Future<AskodoxJson> cashbook(String biz, {String month = ''}) =>
      _send('GET', '${_b(biz)}/cashbook', query: {'month': month});
  Future<AskodoxJson> cashbookAdd(String biz, AskodoxJson entry) => _send('POST', '${_b(biz)}/cashbook', body: entry);
  Future<AskodoxJson> cashbookRemove(String biz, String entryId, {bool undo = false}) =>
      _send('DELETE', '${_b(biz)}/cashbook/$entryId', query: {'undo': undo ? 'true' : 'false'});
  Future<AskodoxJson> dues(String biz) => _send('GET', '${_b(biz)}/dues');
  // Staff attendance, salary, tasks (pos_attendance.py). A staff ref = the last 4 digits of their number.
  Future<AskodoxJson> attendanceToday(String biz) => _send('GET', '${_b(biz)}/attendance/today');
  Future<AskodoxJson> attendanceCheck(String biz, AskodoxJson body) =>
      _send('POST', '${_b(biz)}/attendance/check', body: body, timeout: const Duration(seconds: 40));
  Future<AskodoxJson> attendanceMark(String biz, String ref, String date, String status, {int otMin = 0}) =>
      _send('POST', '${_b(biz)}/attendance/mark', body: {'ref': ref, 'date': date, 'status': status, 'ot_min': otMin});
  Future<AskodoxJson> attendanceSettings(String biz) => _send('GET', '${_b(biz)}/attendance/settings');
  Future<AskodoxJson> saveAttendanceSettings(String biz, AskodoxJson body) =>
      _send('PUT', '${_b(biz)}/attendance/settings', body: body);
  Future<AskodoxJson> attendanceMonth(String biz, {String ref = '', String month = ''}) =>
      _send('GET', '${_b(biz)}/attendance/month', query: {'ref': ref, 'month': month});
  Future<AskodoxJson> attendancePhoto(String biz, String attendanceId) =>
      _send('GET', '${_b(biz)}/attendance/photo/$attendanceId');
  Future<AskodoxJson> staffPay(String biz, String ref, AskodoxJson body) => _send('PUT', '${_b(biz)}/staff/$ref/pay', body: body);
  Future<AskodoxJson> staffAdvance(String biz, String ref, int paise, {String note = ''}) =>
      _send('POST', '${_b(biz)}/staff/$ref/advance', body: {'amount_paise': paise, 'note': note});
  /// Extra money for this month (festival bonus ...): added to the salary worked out for the month.
  Future<AskodoxJson> staffBonus(String biz, String ref, int paise, {String note = ''}) =>
      _send('POST', '${_b(biz)}/staff/$ref/bonus', body: {'amount_paise': paise, 'note': note});
  Future<List<AskodoxJson>> shopHolidays(String biz) async =>
      askodoxPosList((await _send('GET', '${_b(biz)}/attendance/holidays'))['holidays']);
  Future<List<AskodoxJson>> setShopHoliday(String biz, String date, {String name = '', bool remove = false}) async =>
      askodoxPosList((await _send('POST', '${_b(biz)}/attendance/holidays', body: {'date': date, 'name': name, 'remove': remove}))['holidays']);
  Future<AskodoxJson> reportDay(String biz, {String date = ''}) =>
      _send('GET', '${_b(biz)}/reports/day', query: {'date': date});
  Future<AskodoxJson> reportRange(String biz, {int days = 7}) =>
      _send('GET', '${_b(biz)}/reports/range', query: {'days': '$days'});
  Future<AskodoxJson> reportSettings(String biz) => _send('GET', '${_b(biz)}/reports/settings');
  Future<AskodoxJson> saveReportSettings(String biz, AskodoxJson body) =>
      _send('PUT', '${_b(biz)}/reports/settings', body: body);
  Future<AskodoxJson> teamSalary(String biz, {String month = ''}) => _send('GET', '${_b(biz)}/salary', query: {'month': month});
  Future<AskodoxJson> salaryPaid(String biz, String ref, String month) =>
      _send('POST', '${_b(biz)}/staff/$ref/salary/$month/paid');
  Future<AskodoxJson> tasks(String biz) => _send('GET', '${_b(biz)}/tasks');
  Future<AskodoxJson> taskAdd(String biz, String title, String ref, {String dueAt = ''}) =>
      _send('POST', '${_b(biz)}/tasks', body: {'title': title, 'ref': ref, 'due_at': dueAt});
  Future<AskodoxJson> taskDone(String biz, String taskId, {bool undo = false}) =>
      _send('POST', '${_b(biz)}/tasks/$taskId/done', query: {'undo': undo ? 'true' : 'false'});
  Future<AskodoxJson> menuSortApply(String biz, List<AskodoxJson> items) =>
      _send('POST', '${_b(biz)}/desk/menu/sort/apply', body: {'items': items});
  Future<AskodoxJson> billPaper(String biz, String invoiceId) => _send('GET', '${_b(biz)}/bills/$invoiceId/paper');
  Future<AskodoxJson> followShop(String id) => _send('POST', '/api/shops/$id/follow');
  Future<AskodoxJson> unfollowShop(String id) => _send('DELETE', '/api/shops/$id/follow');
  Future<List<AskodoxJson>> myFollows() async => askodoxPosList((await _send('GET', '/api/me/follows'))['follows']);
  /// The owner's one picture a day (the phone draws the brand into it). [imageBase64] is a PNG.
  Future<AskodoxJson> createShopPost(String id, String caption, String imageBase64) =>
      _send('POST', '/api/shops/$id/posts', body: {'caption': caption, 'image_base64': imageBase64});
  /// The shop's own details (owner only). The answer is the shop state with its `profile`.
  /// Ready-to-pick shop categories with sub-categories (en + te labels).
  Future<List<AskodoxJson>> shopCategories() async =>
      askodoxPosList((await _send('GET', '/api/shops/categories'))['categories']);
  Future<AskodoxJson> saveShopProfile(String id, AskodoxJson body) => _send('PUT', '/api/shops/$id/profile', body: body);
  Future<List<AskodoxJson>> myFeed() async => askodoxPosList((await _send('GET', '/api/me/feed'))['posts']);
  Future<AskodoxJson> checkGstin(String gstin) => _send('GET', '/api/pos/gstin/${Uri.encodeComponent(gstin)}');
  Future<List<AskodoxJson>> products(String id, {String q = ''}) async =>
      askodoxPosList((await _send('GET', '${_b(id)}/products', query: {if (q.isNotEmpty) 'q': q}))['products']);
  Future<AskodoxJson> addProduct(String id, AskodoxJson body) => _send('POST', '${_b(id)}/products', body: body);
  /// Combo offers of the shop (2-6 items for one price).
  Future<List<AskodoxJson>> combos(String id) async => askodoxPosList((await _send('GET', '${_b(id)}/combos'))['combos']);
  Future<List<AskodoxJson>> saveCombos(String id, List<AskodoxJson> combos) async =>
      askodoxPosList((await _send('PUT', '${_b(id)}/combos', body: {'combos': combos}))['combos']);
  /// One packet photo -> name, MRP, expiry, barcode for the new-item form (owner 2026-11-19). Nothing is saved.
  Future<AskodoxJson> productPhoto(String id, List<AskodoxJson> images) =>
      _send('POST', '${_b(id)}/products/photo', body: {'images': images}, timeout: const Duration(seconds: 60));
  Future<AskodoxJson> updateProduct(String id, String productId, AskodoxJson body) =>
      _send('PATCH', '${_b(id)}/products/$productId', body: body);
  Future<AskodoxJson> stock(String id, AskodoxJson body) => _send('POST', '${_b(id)}/stock', body: body);
  Future<List<AskodoxJson>> customers(String id, {String q = ''}) async =>
      askodoxPosList((await _send('GET', '${_b(id)}/customers', query: {if (q.isNotEmpty) 'q': q}))['customers']);
  Future<AskodoxJson> addCustomer(String id, AskodoxJson body) => _send('POST', '${_b(id)}/customers', body: body);
  /// People who ordered / got a bill but are not in the list (owner 2026-11-24); saved only on a tap.
  Future<List<AskodoxJson>> customerSuggestions(String id) async =>
      askodoxPosList((await _send('GET', '${_b(id)}/customers/suggestions'))['suggestions']);
  Future<AskodoxJson> skipCustomerSuggestion(String id, String phone) =>
      _send('POST', '${_b(id)}/customers/suggestions/skip', body: {'phone': phone});
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
  // ---- Shop link (shop_links.py): askodox.com/s/<slug>; only the owner saves, managers read it + its counts.
  Future<AskodoxJson> shopLink(String id) => _send('GET', '${_b(id)}/link');
  Future<AskodoxJson> checkShopLink(String id, String slug) => _send('GET', '${_b(id)}/link/check', query: {'slug': slug});
  Future<AskodoxJson> saveShopLink(String id, AskodoxJson body) => _send('PUT', '${_b(id)}/link', body: body);
  Future<AskodoxJson> gstReport(String id, String from, String to) =>
      _send('GET', '${_b(id)}/reports/gst', query: {'date_from': from, 'date_to': to});
  Future<List<AskodoxJson>> members(String id) async => askodoxPosList((await _send('GET', '${_b(id)}/members'))['members']);
  Future<AskodoxJson> setMember(String id, String phone, String role, {String? label, bool? acceptsOrders, List<String>? tools}) =>
      _send('POST', '${_b(id)}/members', body: {
        'phone': phone,
        'role': role,
        if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
        if (acceptsOrders != null) 'accepts_orders': acceptsOrders,
        if (tools != null) 'tools': tools,
      });
  /// Edit a staff member's role / spoken name / "may accept orders" / pause, or bring a removed one back (send their
  /// role), by the last 4 digits in the list.
  Future<AskodoxJson> editMember(String id, String ref, {String? role, String? label, bool? acceptsOrders, bool? paused, List<String>? tools}) =>
      _send('PATCH', '${_b(id)}/members/$ref', body: {
        if (role != null) 'role': role,
        if (label != null) 'label': label,
        if (acceptsOrders != null) 'accepts_orders': acceptsOrders,
        if (paused != null) 'paused': paused,
        if (tools != null) 'tools': tools,
      });
  Future<AskodoxJson> removeMember(String id, String ref) => _send('DELETE', '${_b(id)}/members/$ref');
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

  // Business CRM (pos_crm.py): leads, enquiries, quotations, follow-ups, complaints, customer history, reports.
  String _c(String id) => '${_b(id)}/crm';
  Future<AskodoxJson> crmPipeline(String id, {bool mine = false}) =>
      _send('GET', '${_c(id)}/pipeline', query: {if (mine) 'mine': 'true'});
  Future<List<AskodoxJson>> crmStaff(String id) async => askodoxPosList((await _send('GET', '${_c(id)}/staff'))['staff']);
  Future<List<AskodoxJson>> crmLeads(String id,
          {String stage = '', String kind = '', String q = '', bool mine = false, String customerId = ''}) async =>
      askodoxPosList((await _send('GET', '${_c(id)}/leads', query: {
        if (stage.isNotEmpty) 'stage': stage,
        if (kind.isNotEmpty) 'kind': kind,
        if (q.isNotEmpty) 'q': q,
        if (mine) 'mine': 'true',
        if (customerId.isNotEmpty) 'customer_id': customerId,
      }))['leads']);
  Future<AskodoxJson> crmAddLead(String id, AskodoxJson body) => _send('POST', '${_c(id)}/leads', body: body);
  Future<AskodoxJson> crmLead(String id, String leadId) => _send('GET', '${_c(id)}/leads/$leadId');
  Future<AskodoxJson> crmUpdateLead(String id, String leadId, AskodoxJson body) =>
      _send('PATCH', '${_c(id)}/leads/$leadId', body: body);
  Future<AskodoxJson> crmLeadToCustomer(String id, String leadId, AskodoxJson body) =>
      _send('POST', '${_c(id)}/leads/$leadId/customer', body: body);
  Future<AskodoxJson> crmActivity(String id, AskodoxJson body) => _send('POST', '${_c(id)}/activity', body: body);
  Future<List<AskodoxJson>> crmFollowups(String id, {String when = 'due', bool mine = false}) async =>
      askodoxPosList((await _send('GET', '${_c(id)}/followups', query: {'when': when, if (mine) 'mine': 'true'}))['followups']);
  Future<AskodoxJson> crmAddFollowup(String id, AskodoxJson body) => _send('POST', '${_c(id)}/followups', body: body);
  Future<AskodoxJson> crmCloseFollowup(String id, String followupId, AskodoxJson body) =>
      _send('POST', '${_c(id)}/followups/$followupId/close', body: body);
  Future<List<AskodoxJson>> crmQuotations(String id) async =>
      askodoxPosList((await _send('GET', '${_c(id)}/quotations'))['quotations']);
  Future<AskodoxJson> crmSetQuote(String id, String draftId, AskodoxJson body) =>
      _send('PUT', '${_c(id)}/quotations/$draftId', body: body);
  Future<List<AskodoxJson>> crmComplaints(String id, {String status = '', String customerId = ''}) async =>
      askodoxPosList((await _send('GET', '${_c(id)}/complaints', query: {
        if (status.isNotEmpty) 'status': status,
        if (customerId.isNotEmpty) 'customer_id': customerId,
      }))['complaints']);
  Future<AskodoxJson> crmAddComplaint(String id, AskodoxJson body) => _send('POST', '${_c(id)}/complaints', body: body);
  Future<AskodoxJson> crmComplaint(String id, String complaintId) => _send('GET', '${_c(id)}/complaints/$complaintId');
  Future<AskodoxJson> crmUpdateComplaint(String id, String complaintId, AskodoxJson body) =>
      _send('PATCH', '${_c(id)}/complaints/$complaintId', body: body);
  Future<AskodoxJson> crmCustomerHistory(String id, String customerId) =>
      _send('GET', '${_c(id)}/customers/$customerId/history');
  Future<AskodoxJson> crmReport(String id, String from, String to) =>
      _send('GET', '${_c(id)}/report', query: {'date_from': from, 'date_to': to});

  // Role-based AI agents (pos_agents.py): facts from the shop's records; sensitive actions wait for approval.
  Future<List<AskodoxJson>> agents(String id) async => askodoxPosList((await _send('GET', '${_b(id)}/agents'))['agents']);
  Future<AskodoxJson> agentAsk(String id, String agent, String question, String locale) =>
      _send('POST', '${_b(id)}/agents/$agent/ask', body: {'question': question, 'locale': locale});
  Future<AskodoxJson> agentPropose(String id, String agent, String action, AskodoxJson params) =>
      _send('POST', '${_b(id)}/agents/$agent/actions', body: {'action': action, 'params': params});
  Future<List<AskodoxJson>> agentActions(String id, {String status = ''}) async => askodoxPosList(
      (await _send('GET', '${_b(id)}/agent-actions', query: {if (status.isNotEmpty) 'status': status}))['actions']);
  Future<AskodoxJson> agentDecide(String id, String actionId, bool approve, {String note = ''}) =>
      _send('POST', '${_b(id)}/agent-actions/$actionId/decision', body: {'approve': approve, 'note': note});
  Future<AskodoxJson> buyerAgentAsk(String question, String locale) =>
      _send('POST', '/api/pos/me/agents/buyer/ask', body: {'question': question, 'locale': locale});

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
  /// Supplier bill PHOTO -> preview (nothing saved); the confirmed bill is saved in one call (owner 2026-11-19).
  Future<AskodoxJson> purchaseBillPhoto(String id, List<AskodoxJson> images) =>
      _send('POST', '${_b(id)}/purchases/photo', body: {'images': images}, timeout: const Duration(seconds: 90));
  Future<AskodoxJson> purchaseFromPhoto(String id, AskodoxJson body) => _send('POST', '${_b(id)}/purchases/from-photo', body: body);
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

  // Self-shopping (scan & go). Staff side:
  Future<AskodoxJson> selfShopSettings(String id) => _send('GET', '${_b(id)}/selfshop');
  Future<AskodoxJson> setSelfShop(String id, {required bool enabled, int minutes = 90}) =>
      _send('PUT', '${_b(id)}/selfshop', body: {'enabled': enabled, 'minutes': minutes});
  Future<AskodoxJson> selfShopByExitCode(String id, String code) => _send('GET', '${_b(id)}/selfshop/exit/$code');
  Future<AskodoxJson> selfShopSession(String id, String sessionId) => _send('GET', '${_b(id)}/selfshop/sessions/$sessionId');
  Future<AskodoxJson> selfShopStaffQty(String id, String sessionId, String productId, String pack, int qtyMilli) =>
      _send('PUT', '${_b(id)}/selfshop/sessions/$sessionId/items',
          body: {'product_id': productId, 'pack': pack, 'qty_milli': qtyMilli});
  Future<AskodoxJson> selfShopVerify(String id, String sessionId, List<String> barcodes) =>
      _send('POST', '${_b(id)}/selfshop/sessions/$sessionId/verify', body: {'barcodes': barcodes});
  Future<AskodoxJson> selfShopBill(String id, String sessionId, List<AskodoxJson> payments) =>
      _send('POST', '${_b(id)}/selfshop/sessions/$sessionId/bill', body: {'payments': payments});
  Future<AskodoxJson> selfShopStaffCancel(String id, String sessionId) =>
      _send('POST', '${_b(id)}/selfshop/sessions/$sessionId/cancel');

  // Customer side (the shopper's own phone):
  Future<AskodoxJson> selfShopJoin(String code) => _send('POST', '/api/pos/selfshop/join', body: {'code': code});
  Future<AskodoxJson> selfShopMine() => _send('GET', '/api/pos/selfshop/mine');
  Future<AskodoxJson> selfShopView(String sessionId) => _send('GET', '/api/pos/selfshop/$sessionId');
  Future<AskodoxJson> selfShopScan(String sessionId, String barcode) =>
      _send('POST', '/api/pos/selfshop/$sessionId/scan', body: {'barcode': barcode});
  Future<AskodoxJson> selfShopQty(String sessionId, String productId, String pack, int qtyMilli) =>
      _send('PUT', '/api/pos/selfshop/$sessionId/items', body: {'product_id': productId, 'pack': pack, 'qty_milli': qtyMilli});
  Future<AskodoxJson> selfShopCheckout(String sessionId) => _send('POST', '/api/pos/selfshop/$sessionId/checkout');
  Future<AskodoxJson> selfShopReopen(String sessionId) => _send('POST', '/api/pos/selfshop/$sessionId/reopen');
  Future<AskodoxJson> selfShopCancel(String sessionId) => _send('POST', '/api/pos/selfshop/$sessionId/cancel');

  // Payment voice alerts: notification events only (never bank-verified, never revenue).
  String _pa(String id) => '${_b(id)}/payment-alerts';
  Future<AskodoxJson> paymentAlertSettings(String id) => _send('GET', '${_pa(id)}/settings');
  Future<AskodoxJson> updatePaymentAlertSettings(String id, AskodoxJson body) => _send('PUT', '${_pa(id)}/settings', body: body);
  Future<AskodoxJson> registerAlertDevice(String id, AskodoxJson body) => _send('POST', '${_pa(id)}/devices', body: body);
  /// Owner 2026-11-18: each phone's payment sound (working / permission off / not answering).
  Future<AskodoxJson> paymentAlertPhones(String id) => _send('GET', '${_pa(id)}/phones');
  /// This phone says how its payment sound is (every shop row of this install).
  Future<AskodoxJson> paymentAlertHeartbeat(String deviceKey, String health) =>
      _send('POST', '/api/pos/me/payment-alerts/heartbeat', body: {'device_key': deviceKey, 'health': health});
  /// Who hears MY payments: mode all / none / some (+ chosen people refs). Returns the settings.
  Future<AskodoxJson> setAlertShare(String id, String mode, {List<String> listeners = const []}) =>
      _send('PUT', '${_pa(id)}/share', body: {'mode': mode, 'listeners': listeners});
  /// What I hear from one person (ref) or everyone ('*'): mute, or pause for N minutes (0 = resume).
  Future<AskodoxJson> setAlertListening(String id, String source, {bool? muted, int? pauseMinutes}) =>
      _send('PUT', '${_pa(id)}/listening',
          body: {'source': source, if (muted != null) 'muted': muted, if (pauseMinutes != null) 'pause_minutes': pauseMinutes});
  Future<List<AskodoxJson>> alertDevices(String id) async => askodoxPosList((await _send('GET', '${_pa(id)}/devices'))['devices']);
  Future<List<AskodoxJson>> revokeAlertDevice(String id, String deviceId) async =>
      askodoxPosList((await _send('POST', '${_pa(id)}/devices/$deviceId/revoke'))['devices']);
  Future<AskodoxJson> reportPaymentEvent(String id, AskodoxJson body) => _send('POST', '${_pa(id)}/events', body: body);
  Future<AskodoxJson> paymentEvents(String id, {String status = '', String q = '', String since = '', int limit = 100}) =>
      _send('GET', '${_pa(id)}/events', query: {
        if (status.isNotEmpty) 'status': status,
        if (q.isNotEmpty) 'q': q,
        if (since.isNotEmpty) 'since': since,
        'limit': '$limit',
      });
  // The person's OWN ways to be paid (UPI from any app's QR, bank). ASKODOX never holds money.
  Future<List<AskodoxJson>> myPaymentMethods() async =>
      askodoxPosList((await _send('GET', '/api/me/payment-methods'))['methods']);
  Future<List<AskodoxJson>> addPaymentMethod(AskodoxJson body) async =>
      askodoxPosList((await _send('POST', '/api/me/payment-methods', body: body))['methods']);
  Future<AskodoxJson> readUpiQr(String text) => _send('POST', '/api/me/payment-methods/read-qr', body: {'qr_text': text});
  Future<List<AskodoxJson>> defaultPaymentMethod(String methodId) async =>
      askodoxPosList((await _send('POST', '/api/me/payment-methods/$methodId/default'))['methods']);
  Future<List<AskodoxJson>> removePaymentMethod(String methodId) async =>
      askodoxPosList((await _send('DELETE', '/api/me/payment-methods/$methodId'))['methods']);
  // Collect to the shop's OWN UPI (amount QR) + notification matching.
  Future<AskodoxJson> collectSettings(String id) => _send('GET', '${_b(id)}/collect');
  Future<AskodoxJson> setCollectMethod(String id, String methodId) =>
      _send('PUT', '${_b(id)}/collect', body: {'method_id': methodId});
  Future<AskodoxJson> createCollectRequest(String id, int amountPaise, String label) =>
      _send('POST', '${_b(id)}/collect/requests', body: {'amount_paise': amountPaise, 'label': label});
  Future<List<AskodoxJson>> collectRequests(String id) async =>
      askodoxPosList((await _send('GET', '${_b(id)}/collect/requests'))['requests']);
  Future<AskodoxJson> decideCollectRequest(String id, String requestId, String action, {bool checkedBank = false}) =>
      _send('POST', '${_b(id)}/collect/requests/$requestId', body: {'action': action, 'checked_bank': checkedBank});
  Future<AskodoxJson> paymentProvider(String id) => _send('GET', '${_pa(id)}/provider');
  Future<AskodoxJson> connectPaymentProvider(String id, AskodoxJson body) => _send('PUT', '${_pa(id)}/provider', body: body);
  Future<AskodoxJson> disconnectPaymentProvider(String id) => _send('DELETE', '${_pa(id)}/provider');
  Future<AskodoxJson> createProviderQr(String id) => _send('POST', '${_pa(id)}/provider/qr');
  Future<AskodoxJson> ackPaymentEvent(String id, String eventId, String deviceId, String state) =>
      _send('POST', '${_pa(id)}/events/$eventId/ack', body: {'device_id': deviceId, 'state': state});
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
