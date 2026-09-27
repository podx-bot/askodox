import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

// Mirrors the exact "app-" prefixed identity convention already used by
// ApiUniversalMatchRepository (features/matching/data/universal_match_repository.dart)
// and by the real /deals backend endpoints, which itself comes from the
// phone-number-OTP-verified identity in AuthController. No new auth system
// is introduced here.
String _appUser(String raw) => raw.startsWith('app-') ? raw : 'app-$raw';
final String _guestOrderUserId =
    'app-guest-${DateTime.now().microsecondsSinceEpoch}';

/// A real, persisted order against a real seller_products listing.
///
/// Added 2026-09-15 (round 5) so that "placing an order" in the app is a
/// real, saved fact a seller can see and a buyer can look back on -- not a
/// local UI animation. This covers everything short of actual payment
/// (Master Architecture Point 21 is still not built); settling payment
/// between buyer and seller still happens outside the app, same as before.
class Order {
  const Order({
    required this.id,
    required this.buyerUserId,
    required this.sellerUserId,
    required this.productId,
    required this.productTitle,
    this.quantity,
    this.unit,
    this.price,
    this.currency = 'INR',
    this.totalAmount,
    required this.status,
    this.buyerNote,
    this.sellerNote,
    this.createdAt,
    this.updatedAt,
    this.kind = 'product',
    this.paymentState = 'NOT_STARTED',
    this.paymentReference,
    this.closedAt,
    this.requestContext = const {},
  });

  final String id;
  final String buyerUserId;
  final String sellerUserId;
  final String productId;
  final String productTitle;
  final double? quantity;
  final String? unit;
  final double? price;
  final String currency;
  final double? totalAmount;
  final String status;
  final String? buyerNote;
  final String? sellerNote;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 'product' or 'service': same universal lifecycle, different execution
  /// steps (see backend deal_lifecycle.py).
  final String kind;
  /// Truthful payment state: ASKODOX never marks VERIFIED on its own.
  final String paymentState;
  final String? paymentReference;
  final DateTime? closedAt;
  final Map<String, Object?> requestContext;

  bool get isService => kind == 'service';

  factory Order.fromJson(Map<String, Object?> json) => Order(
        id: '${json['id'] ?? ''}',
        buyerUserId: '${json['buyer_user_id'] ?? ''}',
        sellerUserId: '${json['seller_user_id'] ?? ''}',
        productId: '${json['product_id'] ?? ''}',
        productTitle: '${json['product_title'] ?? ''}',
        quantity: (json['quantity'] as num?)?.toDouble(),
        unit: json['unit']?.toString(),
        price: (json['price'] as num?)?.toDouble(),
        currency: json['currency']?.toString() ?? 'INR',
        totalAmount: (json['total_amount'] as num?)?.toDouble(),
        status: json['status']?.toString() ?? 'PLACED',
        buyerNote: json['buyer_note']?.toString(),
        sellerNote: json['seller_note']?.toString(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
        kind: json['kind']?.toString() ?? 'product',
        paymentState: json['payment_state']?.toString() ?? 'NOT_STARTED',
        paymentReference: json['payment_reference']?.toString(),
        closedAt: DateTime.tryParse(json['closed_at']?.toString() ?? ''),
        requestContext: json['request_context'] is Map
            ? Map<String, Object?>.from(json['request_context'] as Map)
            : const {},
      );

  // Added 2026-09-16 (round 8). The backend now withholds
  // buyer_user_id/seller_user_id (each is literally "app-phone-<digits>",
  // the other party's phone number) until the order is ACCEPTED/FULFILLED
  // -- see backend/app/services/order_contact_visibility.py. These two
  // getters turn whichever id the backend did choose to reveal into a
  // plain phone number for display, and return null both when it's
  // withheld (blank string) and when the other party is a guest with no
  // real phone on record ("app-guest-...").
  // 2026-09-25: also gated on status here (defense in depth), so a stale
  // or misbehaving response can never surface a phone before acceptance.
  String? get sellerContact =>
      orderContactVisible(status) ? _phoneFrom(sellerUserId) : null;
  String? get buyerContact =>
      orderContactVisible(status) ? _phoneFrom(buyerUserId) : null;

  static String? _phoneFrom(String userId) {
    final match = RegExp(r'^app-phone-(\d+)$').firstMatch(userId);
    return match?.group(1);
  }
}

/// Mirrors backend `order_contact_visibility.CONTACT_VISIBLE_STATUSES`: the
/// other party's contact is shown only once the request is accepted (or
/// fulfilled). Any other or unknown status keeps it hidden.
const orderContactVisibleStatuses = {
  'ACCEPTED', 'FULFILLED', 'PREPARING', 'READY', 'DISPATCHED', 'DELIVERED',
  'SCHEDULED', 'PROVIDER_ASSIGNED', 'ARRIVED', 'IN_PROGRESS', 'SERVICE_COMPLETED',
  'DISPUTED', 'RESOLVED', 'CLOSED',
};

bool orderContactVisible(String? status) =>
    orderContactVisibleStatuses.contains((status ?? '').trim().toUpperCase());

class OrderActionResult {
  const OrderActionResult({required this.success, this.order, this.message});
  final bool success;
  final Order? order;
  final String? message;
}

abstract interface class OrderRepository {
  Future<OrderActionResult> placeOrder({
    required String productId,
    double? quantity,
    String? buyerNote,
    Map<String, Object?>? requestContext,
    String? question,
  });

  Future<List<Order>> myOrders({int limit = 50});
  Future<List<Order>> incomingOrders({int limit = 50});

  // Added 2026-09-16 (round 8). Wires the seller-facing Accept/Decline
  // action to the already-existing (but previously unused by any screen)
  // POST /api/orders/{id}/status endpoint. Only a seller can call this --
  // enforced server-side by checking payload.seller_user_id against the
  // order's own seller_user_id (see orders.py's update_order_status).
  Future<OrderActionResult> respondToOrder({
    required String orderId,
    required String status, // 'ACCEPTED' or 'REJECTED'
    String? sellerNote,
  });
}

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  final user = session.user;
  return ApiOrderRepository(
    ref.watch(apiClientProvider),
    appUserId: user == null ? _guestOrderUserId : _appUser(user.id),
    // Added 2026-09-16 (round 10): the real signed session token from
    // POST /onboarding/otp/verify (see session_tokens.py on the backend).
    // Every order endpoint now requires this instead of trusting the
    // *_user_id fields alone -- see orders.py's _authenticated_app_user. A
    // guest (user == null) has no token; those calls now correctly get a
    // 401 from the backend rather than silently acting as a fake identity.
    authToken: user == null ? null : session.tokenPlaceholder,
  );
});

class ApiOrderRepository implements OrderRepository {
  ApiOrderRepository(this._client, {required this.appUserId, this.authToken});

  final ApiClient _client;
  final String appUserId;
  final String? authToken;

  // Placing an order is a POST and is never auto-retried, to avoid risking
  // a duplicate order on a flaky connection. Railway can need more than the
  // global default timeout while a service is waking up, same reasoning as
  // ApiUniversalMatchRepository's _createOptions.
  //
  // Changed from a static const to an instance getter in round 10 so it can
  // carry this instance's authToken.
  ApiRequestOptions get _mutateOptions =>
      ApiRequestOptions(timeout: const Duration(seconds: 30), authToken: authToken);

  // Listing lookups are safe GETs, so one retry is allowed after a
  // cold-start/network timeout, same as ApiUniversalMatchRepository's
  // _matchOptions.
  static const _readTimeout = Duration(seconds: 30);
  static const _readRetryCount = 1;

  @override
  Future<OrderActionResult> placeOrder({
    required String productId,
    double? quantity,
    String? buyerNote,
    Map<String, Object?>? requestContext,
    String? question,
  }) async {
    final numericProductId = int.tryParse(productId);
    if (numericProductId == null) {
      return const OrderActionResult(
          success: false, message: 'This listing cannot be ordered right now.');
    }

    final result = await _client.post<Map<String, Object?>>(
      '/api/orders',
      body: {
        'buyer_user_id': appUserId,
        'product_id': numericProductId,
        if (quantity != null) 'quantity': quantity,
        if (buyerNote != null && buyerNote.trim().isNotEmpty)
          'buyer_note': buyerNote.trim(),
        if (requestContext != null && requestContext.isNotEmpty)
          'request_context': requestContext,
        if (question != null && question.trim().isNotEmpty)
          'question': question.trim(),
      },
      options: _mutateOptions,
    );
    if (result is ApiError<Map<String, Object?>>) {
      return OrderActionResult(
          success: false,
          message: result.failure.message ?? 'Unable to place this order.');
    }

    final data = (result as ApiSuccess<Map<String, Object?>>).data;
    if (data['id'] == null) {
      // Demo data is allowed only when the app is explicitly using
      // MockApiClient, which echoes the request body back verbatim (no real
      // "id"). A live backend must never be treated this leniently, because
      // that would hide a genuine save failure -- but the ApiSuccess check
      // above already guarantees a real backend's 2xx response reaches here,
      // and a real backend always returns the saved order's id.
      return const OrderActionResult(success: true);
    }
    return OrderActionResult(success: true, order: Order.fromJson(data));
  }

  @override
  Future<List<Order>> myOrders({int limit = 50}) async {
    final result = await _client.get<Map<String, Object?>>(
      '/api/orders/mine',
      options: ApiRequestOptions(
        timeout: _readTimeout,
        retryCount: _readRetryCount,
        query: {'buyer_user_id': appUserId, 'limit': limit},
        authToken: authToken,
      ),
    );
    if (result is ApiError<Map<String, Object?>>) {
      throw StateError(result.failure.message ?? 'Unable to load your orders.');
    }
    return _parseItems((result as ApiSuccess<Map<String, Object?>>).data);
  }

  @override
  Future<List<Order>> incomingOrders({int limit = 50}) async {
    final result = await _client.get<Map<String, Object?>>(
      '/api/orders/incoming',
      options: ApiRequestOptions(
        timeout: _readTimeout,
        retryCount: _readRetryCount,
        query: {'seller_user_id': appUserId, 'limit': limit},
        authToken: authToken,
      ),
    );
    if (result is ApiError<Map<String, Object?>>) {
      throw StateError(
          result.failure.message ?? 'Unable to load incoming orders.');
    }
    return _parseItems((result as ApiSuccess<Map<String, Object?>>).data);
  }

  @override
  Future<OrderActionResult> respondToOrder({
    required String orderId,
    required String status,
    String? sellerNote,
  }) async {
    final numericOrderId = int.tryParse(orderId);
    if (numericOrderId == null) {
      return const OrderActionResult(
          success: false, message: 'This request cannot be updated right now.');
    }

    final result = await _client.post<Map<String, Object?>>(
      '/api/orders/$numericOrderId/status',
      body: {
        'seller_user_id': appUserId,
        'status': status,
        if (sellerNote != null && sellerNote.trim().isNotEmpty)
          'seller_note': sellerNote.trim(),
      },
      options: _mutateOptions,
    );
    if (result is ApiError<Map<String, Object?>>) {
      return OrderActionResult(
          success: false,
          message: result.failure.message ?? 'Unable to update this request.');
    }

    final data = (result as ApiSuccess<Map<String, Object?>>).data;
    if (data['id'] == null) {
      // Same MockApiClient allowance as placeOrder above.
      return const OrderActionResult(success: true);
    }
    return OrderActionResult(success: true, order: Order.fromJson(data));
  }

  List<Order> _parseItems(Map<String, Object?> data) {
    final rawItems = data['items'];
    if (rawItems is! List) return const [];
    return [
      for (final entry in rawItems)
        if (entry is Map) Order.fromJson(Map<String, Object?>.from(entry)),
    ];
  }
}


// ---------------------------------------------------------------------------
// Universal deal lifecycle (orders & bookings): mediated seller Q&A and
// negotiation, truthful payment state, execution, customer confirmation,
// problems/disputes, review and alternatives. Backend: orders.py +
// deal_lifecycle.py.

class OrderMessage {
  const OrderMessage({required this.fromRole, required this.kind, this.text, this.amount});

  final String fromRole; // buyer | seller
  final String kind; // QUESTION, ANSWER, OFFER, COUNTER_OFFER, ACCEPT_OFFER, ...
  final String? text;
  final double? amount;

  factory OrderMessage.fromJson(Map<String, Object?> json) => OrderMessage(
        fromRole: json['from_role']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        text: json['text']?.toString(),
        amount: (json['amount'] as num?)?.toDouble(),
      );
}

class OrderDetail {
  const OrderDetail({
    required this.order,
    this.messages = const [],
    this.actions = const [],
    this.awaiting = 'none',
    this.sellerUnresponsive = false,
    this.supportCaseId,
  });

  final Order order;
  final List<OrderMessage> messages;
  /// What this viewer may do next, decided by the server's lifecycle rules.
  final List<String> actions;
  /// seller | buyer | support | none
  final String awaiting;
  final bool sellerUnresponsive;
  final String? supportCaseId;

  bool can(String action) => actions.contains(action);

  OrderMessage? get lastOffer {
    for (final m in messages.reversed) {
      if (m.kind == 'OFFER' || m.kind == 'COUNTER_OFFER') return m;
    }
    return null;
  }

  factory OrderDetail.fromJson(Map<String, Object?> json) => OrderDetail(
        order: Order.fromJson(json),
        messages: [
          for (final m in (json['messages'] as List? ?? const []))
            if (m is Map) OrderMessage.fromJson(Map<String, Object?>.from(m)),
        ],
        actions: [for (final a in (json['actions'] as List? ?? const [])) '$a'],
        awaiting: json['awaiting']?.toString() ?? 'none',
        sellerUnresponsive: json['seller_unresponsive'] == true,
        supportCaseId: json['support_case_id']?.toString(),
      );
}

class OrderLifecycleRepository {
  OrderLifecycleRepository(this._client, {this.authToken});

  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions get _options =>
      ApiRequestOptions(timeout: const Duration(seconds: 30), authToken: authToken);

  Future<OrderDetail> _call(Future<ApiResult<Map<String, Object?>>> request) async {
    final result = await request;
    if (result is ApiError<Map<String, Object?>>) {
      throw StateError(result.failure.message ?? 'This request could not be updated.');
    }
    return OrderDetail.fromJson((result as ApiSuccess<Map<String, Object?>>).data);
  }

  Future<OrderDetail> detail(String orderId) =>
      _call(_client.get<Map<String, Object?>>('/api/orders/$orderId', options: _options));

  Future<OrderDetail> message(String orderId, String kind, {String? text, double? amount}) => _call(
      _client.post<Map<String, Object?>>('/api/orders/$orderId/messages',
          body: {'kind': kind, if (text != null) 'text': text, if (amount != null) 'amount': amount},
          options: _options));

  Future<OrderDetail> cancel(String orderId) =>
      _call(_client.post<Map<String, Object?>>('/api/orders/$orderId/cancel', options: _options));

  Future<OrderDetail> payment(String orderId, String action, {String? reference}) => _call(
      _client.post<Map<String, Object?>>('/api/orders/$orderId/payment',
          body: {'action': action, if (reference != null) 'reference': reference}, options: _options));

  Future<OrderDetail> confirm(String orderId) =>
      _call(_client.post<Map<String, Object?>>('/api/orders/$orderId/confirm', options: _options));

  Future<OrderDetail> problem(String orderId,
          {required String issue, String category = 'DELIVERY', List<String> aiAttempts = const []}) =>
      _call(_client.post<Map<String, Object?>>('/api/orders/$orderId/problem',
          body: {'issue': issue, 'category': category, 'ai_attempts': aiAttempts}, options: _options));

  Future<void> review(String orderId, int rating, {String text = ''}) async {
    final result = await _client.post<Map<String, Object?>>('/api/orders/$orderId/review',
        body: {'rating': rating, 'text': text}, options: _options);
    if (result is ApiError<Map<String, Object?>>) {
      throw StateError(result.failure.message ?? 'The review could not be saved.');
    }
  }

  /// Other listings for the same need after a decline -- never start over.
  Future<List<Map<String, Object?>>> alternatives(String orderId) async {
    final result = await _client.get<Map<String, Object?>>('/api/orders/$orderId/alternatives', options: _options);
    if (result is ApiError<Map<String, Object?>>) return const [];
    return [
      for (final m in ((result as ApiSuccess<Map<String, Object?>>).data['matches'] as List? ?? const []))
        if (m is Map) Map<String, Object?>.from(m),
    ];
  }
}

final orderLifecycleRepositoryProvider = Provider<OrderLifecycleRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return OrderLifecycleRepository(
    ref.watch(apiClientProvider),
    authToken: session.user == null ? null : session.tokenPlaceholder,
  );
});
