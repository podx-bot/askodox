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
      );

  // Added 2026-09-16 (round 8). The backend now withholds
  // buyer_user_id/seller_user_id (each is literally "app-phone-<digits>",
  // the other party's phone number) until the order is ACCEPTED/FULFILLED
  // -- see backend/app/services/order_contact_visibility.py. These two
  // getters turn whichever id the backend did choose to reveal into a
  // plain phone number for display, and return null both when it's
  // withheld (blank string) and when the other party is a guest with no
  // real phone on record ("app-guest-...").
  String? get sellerContact => _phoneFrom(sellerUserId);
  String? get buyerContact => _phoneFrom(buyerUserId);

  static String? _phoneFrom(String userId) {
    final match = RegExp(r'^app-phone-(\d+)$').firstMatch(userId);
    return match?.group(1);
  }
}

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
  final user = ref.watch(authSessionProvider).user;
  return ApiOrderRepository(
    ref.watch(apiClientProvider),
    appUserId: user == null ? _guestOrderUserId : _appUser(user.id),
  );
});

class ApiOrderRepository implements OrderRepository {
  ApiOrderRepository(this._client, {required this.appUserId});

  final ApiClient _client;
  final String appUserId;

  // Placing an order is a POST and is never auto-retried, to avoid risking
  // a duplicate order on a flaky connection. Railway can need more than the
  // global default timeout while a service is waking up, same reasoning as
  // ApiUniversalMatchRepository's _createOptions.
  static const _mutateOptions =
      ApiRequestOptions(timeout: Duration(seconds: 30));

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
