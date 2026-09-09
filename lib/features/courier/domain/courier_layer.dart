enum CourierDeliveryMode {
  customerPickup,
  sellerOwnDelivery,
  askodoxLocalDelivery,
  courierShipping,
}

enum CourierShipmentStatus {
  draft,
  quoted,
  booked,
  pickupScheduled,
  pickedUp,
  inTransit,
  outForDelivery,
  delivered,
  cancelled,
  returnToOrigin,
}

class CourierAddress {
  const CourierAddress({
    required this.name,
    required this.phone,
    required this.line1,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.countryCode,
    this.line2,
  });

  final String name;
  final String phone;
  final String line1;
  final String? line2;
  final String city;
  final String state;
  final String postalCode;
  final String countryCode;
}

class CourierParcel {
  const CourierParcel({
    required this.weightKg,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    this.declaredValue,
    this.isCod = false,
    this.codAmount,
  });

  final double weightKg;
  final double lengthCm;
  final double widthCm;
  final double heightCm;
  final double? declaredValue;
  final bool isCod;
  final double? codAmount;
}

class CourierQuoteRequest {
  const CourierQuoteRequest({
    required this.pickup,
    required this.drop,
    required this.parcel,
  });

  final CourierAddress pickup;
  final CourierAddress drop;
  final CourierParcel parcel;
}

class CourierQuote {
  const CourierQuote({
    required this.providerId,
    required this.providerName,
    required this.serviceCode,
    required this.serviceName,
    required this.totalPrice,
    required this.estimatedDays,
    this.askodoxRevenue,
  });

  final String providerId;
  final String providerName;
  final String serviceCode;
  final String serviceName;
  final double totalPrice;
  final int estimatedDays;

  /// Revenue that belongs to ASKODOX only when a provider's commercial
  /// agreement explicitly enables commission/referral/margin sharing.
  final double? askodoxRevenue;
}

class CourierBooking {
  const CourierBooking({
    required this.bookingId,
    required this.providerId,
    required this.status,
    this.awb,
    this.labelUrl,
    this.trackingUrl,
  });

  final String bookingId;
  final String providerId;
  final CourierShipmentStatus status;
  final String? awb;
  final String? labelUrl;
  final String? trackingUrl;
}

abstract interface class CourierProvider {
  String get id;
  String get displayName;

  Future<bool> isServiceable(CourierQuoteRequest request);

  Future<List<CourierQuote>> getQuotes(CourierQuoteRequest request);

  Future<CourierBooking> book({
    required CourierQuote quote,
    required CourierQuoteRequest request,
    required String clientOrderId,
  });

  Future<CourierBooking> track(String bookingId);

  Future<void> cancel(String bookingId);
}

class CourierProviderRegistry {
  CourierProviderRegistry(Iterable<CourierProvider> providers)
      : _providers = {
          for (final provider in providers) provider.id: provider,
        };

  final Map<String, CourierProvider> _providers;

  Iterable<CourierProvider> get providers => _providers.values;

  CourierProvider? byId(String id) => _providers[id];

  Future<List<CourierQuote>> quotes(CourierQuoteRequest request) async {
    final quotes = <CourierQuote>[];
    for (final provider in _providers.values) {
      if (await provider.isServiceable(request)) {
        quotes.addAll(await provider.getQuotes(request));
      }
    }
    quotes.sort((a, b) => a.totalPrice.compareTo(b.totalPrice));
    return quotes;
  }
}

/// Deterministic provider used only for ASKODOX demo/testing flows.
/// Live courier adapters (Shiprocket/Delhivery/etc.) implement the same
/// [CourierProvider] contract and can be plugged in without changing UI flow.
class DemoCourierProvider implements CourierProvider {
  const DemoCourierProvider();

  @override
  String get id => 'askodox-demo-courier';

  @override
  String get displayName => 'ASKODOX Demo Courier';

  @override
  Future<bool> isServiceable(CourierQuoteRequest request) async =>
      request.pickup.postalCode.isNotEmpty && request.drop.postalCode.isNotEmpty;

  @override
  Future<List<CourierQuote>> getQuotes(CourierQuoteRequest request) async {
    final base = 55.0 + (request.parcel.weightKg * 18.0);
    return [
      CourierQuote(
        providerId: id,
        providerName: displayName,
        serviceCode: 'surface',
        serviceName: 'Surface',
        totalPrice: base,
        estimatedDays: 4,
      ),
      CourierQuote(
        providerId: id,
        providerName: displayName,
        serviceCode: 'express',
        serviceName: 'Express',
        totalPrice: base + 45.0,
        estimatedDays: 2,
      ),
    ];
  }

  @override
  Future<CourierBooking> book({
    required CourierQuote quote,
    required CourierQuoteRequest request,
    required String clientOrderId,
  }) async {
    final suffix = clientOrderId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return CourierBooking(
      bookingId: 'demo-$suffix',
      providerId: id,
      status: CourierShipmentStatus.booked,
      awb: 'ASKODOX$suffix',
    );
  }

  @override
  Future<CourierBooking> track(String bookingId) async => CourierBooking(
        bookingId: bookingId,
        providerId: id,
        status: CourierShipmentStatus.inTransit,
        awb: 'ASKODOX${bookingId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}',
      );

  @override
  Future<void> cancel(String bookingId) async {}
}
