import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// ASKODOX mobility (rides, parcels, local delivery, carpool) -- the ONE
/// backend system at `/api/delivery/*`. Nothing here is "confirmed" until
/// a partner accepts; phones arrive only after acceptance.
class MobilityResult<T> {
  const MobilityResult.ok(T this.data) : error = null, code = null;
  const MobilityResult.fail(this.error, {this.code}) : data = null;
  final T? data;
  final String? error;
  final int? code;
  bool get ok => data != null;
}

/// A ride / delivery request as the backend describes it.
class MobilityJob {
  const MobilityJob({
    required this.id,
    required this.kind,
    required this.status,
    required this.stage,
    required this.pickup,
    required this.drop,
    this.distanceKm,
    this.quote,
    this.confirmedByPartner = false,
    this.partnerName = '',
    this.partnerVehicle = '',
    this.partnerPhone = '',
    this.customerPhone = '',
    this.details = const {},
  });

  factory MobilityJob.fromJson(Map<String, Object?> j) {
    final partner = (j['partner'] as Map?) ?? const {};
    final quote = (j['quote'] as Map?) ?? const {};
    return MobilityJob(
      id: '${j['id'] ?? ''}',
      kind: '${j['kind'] ?? ''}',
      status: '${j['status'] ?? ''}',
      stage: '${j['stage'] ?? ''}',
      pickup: '${((j['pickup'] as Map?) ?? const {})['label'] ?? ''}',
      drop: '${((j['drop'] as Map?) ?? const {})['label'] ?? ''}',
      distanceKm: (j['distance_km'] as num?)?.toDouble(),
      quote: (quote['amount'] as num?)?.toDouble(),
      confirmedByPartner: j['confirmed_by_partner'] == true,
      partnerName: '${partner['name'] ?? ''}',
      partnerVehicle: [partner['vehicle'], partner['vehicle_number']]
          .where((v) => v != null && '$v'.isNotEmpty)
          .join(' · '),
      partnerPhone: '${partner['phone'] ?? ''}',
      customerPhone: '${j['customer_phone'] ?? ''}',
      details: Map<String, Object?>.from((j['details'] as Map?) ?? const {}),
    );
  }

  final String id, kind, status, stage, pickup, drop;
  final double? distanceKm, quote;
  final bool confirmedByPartner;
  final String partnerName, partnerVehicle, partnerPhone, customerPhone;
  final Map<String, Object?> details;

  bool get cancellable =>
      const {'REQUESTED', 'NEEDS_PARTNER', 'NEEDS_CONFIGURATION', 'PARTNER_SEARCH', 'PARTNER_ACCEPTED',
          'EN_ROUTE_PICKUP', 'ARRIVED_PICKUP'}.contains(status);
}

/// The partner's application / account.
class MobilityPartner {
  const MobilityPartner({
    required this.id,
    required this.status,
    required this.name,
    required this.services,
    required this.vehicle,
    this.available = false,
    this.reviewNote = '',
  });

  factory MobilityPartner.fromJson(Map<String, Object?> j) => MobilityPartner(
        id: '${j['id'] ?? ''}',
        status: '${j['status'] ?? ''}',
        name: '${j['name'] ?? ''}',
        services: [for (final s in (j['services'] as List? ?? const [])) '$s'],
        vehicle: '${j['vehicle'] ?? ''}',
        available: j['available'] == true,
        reviewNote: '${j['review_note'] ?? ''}',
      );

  final String id, status, name, vehicle, reviewNote;
  final List<String> services;
  final bool available;
}

/// The partner's next step on a trip: forward only (the backend refuses
/// anything else). Optional "arrived" steps are offered but may be skipped.
const askodoxTripPath = ['PARTNER_ACCEPTED', 'EN_ROUTE_PICKUP', 'ARRIVED_PICKUP', 'PICKED_UP', 'IN_TRANSIT',
  'ARRIVED_DROP', 'DELIVERED'];

String? askodoxNextTripStep(String status) {
  final i = askodoxTripPath.indexOf(status);
  return i < 0 || i == askodoxTripPath.length - 1 ? null : askodoxTripPath[i + 1];
}

abstract class MobilityRepository {
  Future<MobilityResult<MobilityJob>> request({
    required String kind,
    required Map<String, Object?> pickup,
    required Map<String, Object?> drop,
    Map<String, Object?> details = const {},
    String scheduleAt = '',
  });
  Future<List<MobilityJob>> myRequests();
  Future<MobilityResult<MobilityJob>> cancel(String id);
  Future<MobilityResult<MobilityJob>> confirm(String id);

  Future<MobilityResult<MobilityPartner?>> myPartner();
  Future<MobilityResult<MobilityPartner>> apply(Map<String, Object?> body, {bool update = false});
  Future<MobilityResult<MobilityPartner>> setAvailable(bool available, {double? latitude, double? longitude});
  Future<List<MobilityJob>> offers();
  Future<({List<MobilityJob> active, List<MobilityJob> history})> trips();
  Future<MobilityResult<MobilityJob>> accept(String id);
  Future<bool> decline(String id);
  Future<MobilityResult<MobilityJob>> step(String id, String status);

  Future<MobilityResult<Map<String, Object?>>> offerCarpool(Map<String, Object?> body);
  Future<List<Map<String, Object?>>> searchCarpool(
      {required double fromLat, required double fromLng, required double toLat, required double toLng,
      String date = ''});
  Future<MobilityResult<Map<String, Object?>>> requestSeat(String rideId, {int seats = 1});
  Future<Map<String, Object?>> myCarpool();
  Future<MobilityResult<Map<String, Object?>>> decideSeat(String requestId, bool accept);
  Future<bool> report(String subjectType, String subjectId, String reason);
}

final mobilityRepositoryProvider = Provider<MobilityRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return ApiMobilityRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

class ApiMobilityRepository implements MobilityRepository {
  ApiMobilityRepository(this._client, {this.authToken});

  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions get _auth => ApiRequestOptions(timeout: const Duration(seconds: 30), authToken: authToken);

  MobilityResult<T> _map<T>(ApiResult<Map<String, Object?>> r, T Function(Map<String, Object?>) parse) =>
      switch (r) {
        ApiSuccess(:final data) => MobilityResult.ok(parse(data)),
        ApiError(:final failure) => MobilityResult.fail(failure.message ?? 'Could not reach ASKODOX.',
            code: failure.statusCode),
      };

  Map<String, Object?> _json(ApiResult<Map<String, Object?>> r) =>
      r is ApiSuccess<Map<String, Object?>> ? r.data : const {};

  List<MobilityJob> _jobs(Object? list) => [
        for (final j in (list as List? ?? const []))
          if (j is Map) MobilityJob.fromJson(Map<String, Object?>.from(j)),
      ];

  static const _base = '/api/delivery';

  @override
  Future<MobilityResult<MobilityJob>> request(
          {required String kind,
          required Map<String, Object?> pickup,
          required Map<String, Object?> drop,
          Map<String, Object?> details = const {},
          String scheduleAt = ''}) async =>
      _map(
          await _client.post<Map<String, Object?>>('$_base/jobs',
              body: {
                'kind': kind,
                'pickup': pickup,
                'drop': drop,
                'details': details,
                if (scheduleAt.isNotEmpty) 'schedule_at': scheduleAt,
              },
              options: _auth),
          MobilityJob.fromJson);

  @override
  Future<List<MobilityJob>> myRequests() async =>
      _jobs(_json(await _client.get<Map<String, Object?>>('$_base/jobs/mine', options: _auth))['items']);

  @override
  Future<MobilityResult<MobilityJob>> cancel(String id) async => _map(
      await _client.post<Map<String, Object?>>('$_base/jobs/$id/cancel', body: const {}, options: _auth),
      MobilityJob.fromJson);

  @override
  Future<MobilityResult<MobilityJob>> confirm(String id) async =>
      _map(await _client.post<Map<String, Object?>>('$_base/jobs/$id/confirm', options: _auth), MobilityJob.fromJson);

  @override
  Future<MobilityResult<MobilityPartner?>> myPartner() async => _map(
      await _client.get<Map<String, Object?>>('$_base/partners/me', options: _auth),
      (d) => d['partner'] is Map ? MobilityPartner.fromJson(Map<String, Object?>.from(d['partner'] as Map)) : null);

  @override
  Future<MobilityResult<MobilityPartner>> apply(Map<String, Object?> body, {bool update = false}) async => _map(
      update
          ? await _client.patch<Map<String, Object?>>('$_base/partners/me', body: body, options: _auth)
          : await _client.post<Map<String, Object?>>('$_base/partners/apply', body: body, options: _auth),
      MobilityPartner.fromJson);

  @override
  Future<MobilityResult<MobilityPartner>> setAvailable(bool available, {double? latitude, double? longitude}) async =>
      _map(
          await _client.post<Map<String, Object?>>('$_base/partners/me/availability',
              body: {
                'available': available,
                if (latitude != null && longitude != null) 'latitude': latitude,
                if (latitude != null && longitude != null) 'longitude': longitude,
              },
              options: _auth),
          MobilityPartner.fromJson);

  @override
  Future<List<MobilityJob>> offers() async =>
      _jobs(_json(await _client.get<Map<String, Object?>>('$_base/offers', options: _auth))['items']);

  @override
  Future<({List<MobilityJob> active, List<MobilityJob> history})> trips() async {
    final d = _json(await _client.get<Map<String, Object?>>('$_base/jobs/assigned', options: _auth));
    return (active: _jobs(d['active']), history: _jobs(d['history']));
  }

  @override
  Future<MobilityResult<MobilityJob>> accept(String id) async =>
      _map(await _client.post<Map<String, Object?>>('$_base/jobs/$id/accept', options: _auth), MobilityJob.fromJson);

  @override
  Future<bool> decline(String id) async =>
      (await _client.post<Map<String, Object?>>('$_base/jobs/$id/decline', body: const {}, options: _auth))
          is ApiSuccess;

  @override
  Future<MobilityResult<MobilityJob>> step(String id, String status) async => _map(
      await _client.post<Map<String, Object?>>('$_base/jobs/$id/status', body: {'status': status}, options: _auth),
      MobilityJob.fromJson);

  @override
  Future<MobilityResult<Map<String, Object?>>> offerCarpool(Map<String, Object?> body) async =>
      _map(await _client.post<Map<String, Object?>>('$_base/carpool/rides', body: body, options: _auth), (d) => d);

  @override
  Future<List<Map<String, Object?>>> searchCarpool(
      {required double fromLat, required double fromLng, required double toLat, required double toLng,
      String date = ''}) async {
    final q = 'from_lat=$fromLat&from_lng=$fromLng&to_lat=$toLat&to_lng=$toLng'
        '${date.isEmpty ? '' : '&date=${Uri.encodeQueryComponent(date)}'}';
    return [
      for (final r in (_json(await _client.get<Map<String, Object?>>('$_base/carpool/search?$q', options: _auth))[
              'items'] as List? ??
          const [])) if (r is Map) Map<String, Object?>.from(r),
    ];
  }

  @override
  Future<MobilityResult<Map<String, Object?>>> requestSeat(String rideId, {int seats = 1}) async => _map(
      await _client.post<Map<String, Object?>>('$_base/carpool/rides/$rideId/request',
          body: {'seats': seats}, options: _auth),
      (d) => d);

  @override
  Future<Map<String, Object?>> myCarpool() async =>
      _json(await _client.get<Map<String, Object?>>('$_base/carpool/mine', options: _auth));

  @override
  Future<MobilityResult<Map<String, Object?>>> decideSeat(String requestId, bool accept) async => _map(
      await _client.post<Map<String, Object?>>('$_base/carpool/requests/$requestId/decide',
          body: {'accept': accept}, options: _auth),
      (d) => d);

  @override
  Future<bool> report(String subjectType, String subjectId, String reason) async =>
      (await _client.post<Map<String, Object?>>('$_base/reports',
          body: {'subject_type': subjectType, 'subject_id': subjectId, 'reason': reason}, options: _auth))
          is ApiSuccess;
}
