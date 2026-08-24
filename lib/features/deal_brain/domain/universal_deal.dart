enum DealIntent {
  buy,
  sell,
  needService,
  offerService,
  needWorker,
  seekWork,
  needRide,
  offerRide,
  sendParcel,
  deliverParcel,
  rent,
  offerRental,
  bookAppointment,
  offerAppointment,
  other,
}

enum DealSide { demand, supply }

enum DealStatus {
  collecting,
  readyToMatch,
  matching,
  matched,
  negotiating,
  closed,
  cancelled,
}

class DealLocation {
  const DealLocation({this.label, this.latitude, this.longitude, this.radiusKm});
  final String? label;
  final double? latitude;
  final double? longitude;
  final double? radiusKm;

  bool get isKnown =>
      (label != null && label!.trim().isNotEmpty) ||
      (latitude != null && longitude != null);
}

class DealPartyRequirement {
  const DealPartyRequirement({
    required this.side,
    required this.role,
    required this.action,
  });

  final DealSide side;
  final String role;
  final String action;
}

class UniversalDeal {
  const UniversalDeal({
    required this.rawText,
    required this.intent,
    required this.partyA,
    required this.partyB,
    this.subject,
    this.category,
    this.quantity,
    this.unit,
    this.price,
    this.priceBasis,
    this.quality,
    this.variant,
    this.size,
    this.weight,
    this.model,
    this.availability,
    this.fulfilment,
    this.location = const DealLocation(),
    this.timing,
    this.dynamicFields = const {},
    this.status = DealStatus.collecting,
  });

  final String rawText;
  final DealIntent intent;
  final DealPartyRequirement partyA;
  final DealPartyRequirement partyB;

  final String? subject;
  final String? category;
  final double? quantity;
  final String? unit;
  final double? price;
  final String? priceBasis;
  final String? quality;
  final String? variant;
  final String? size;
  final String? weight;
  final String? model;
  final String? availability;
  final String? fulfilment;
  final DealLocation location;
  final String? timing;

  /// Category-specific values live here so the core remains universal.
  /// Examples: job skill/experience, catering guest count/menu, ride seats/route,
  /// rental duration, appointment specialty, product storage/colour/warranty.
  final Map<String, Object?> dynamicFields;
  final DealStatus status;

  UniversalDeal copyWith({
    String? rawText,
    DealIntent? intent,
    DealPartyRequirement? partyA,
    DealPartyRequirement? partyB,
    String? subject,
    String? category,
    double? quantity,
    String? unit,
    double? price,
    String? priceBasis,
    String? quality,
    String? variant,
    String? size,
    String? weight,
    String? model,
    String? availability,
    String? fulfilment,
    DealLocation? location,
    String? timing,
    Map<String, Object?>? dynamicFields,
    DealStatus? status,
  }) {
    return UniversalDeal(
      rawText: rawText ?? this.rawText,
      intent: intent ?? this.intent,
      partyA: partyA ?? this.partyA,
      partyB: partyB ?? this.partyB,
      subject: subject ?? this.subject,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      priceBasis: priceBasis ?? this.priceBasis,
      quality: quality ?? this.quality,
      variant: variant ?? this.variant,
      size: size ?? this.size,
      weight: weight ?? this.weight,
      model: model ?? this.model,
      availability: availability ?? this.availability,
      fulfilment: fulfilment ?? this.fulfilment,
      location: location ?? this.location,
      timing: timing ?? this.timing,
      dynamicFields: dynamicFields ?? this.dynamicFields,
      status: status ?? this.status,
    );
  }

  /// ASKODOX should only ask what is actually required to make a useful match.
  List<String> get missingForMatch {
    final missing = <String>[];

    switch (intent) {
      case DealIntent.needRide:
      case DealIntent.offerRide:
        if (dynamicFields['from'] == null) missing.add('from');
        if (dynamicFields['to'] == null) missing.add('to');
        if (timing == null || timing!.trim().isEmpty) missing.add('timing');
        break;
      case DealIntent.needWorker:
      case DealIntent.seekWork:
        final skill = dynamicFields['skill']?.toString().trim();
        if (skill == null || skill.isEmpty) missing.add('skill');
        if (!location.isKnown) missing.add('location');
        break;
      case DealIntent.needService:
      case DealIntent.offerService:
        if (subject == null || subject!.trim().isEmpty) missing.add('subject');
        if (!location.isKnown) missing.add('location');
        break;
      case DealIntent.bookAppointment:
      case DealIntent.offerAppointment:
        if (subject == null || subject!.trim().isEmpty) missing.add('subject');
        if (!location.isKnown) missing.add('location');
        break;
      case DealIntent.buy:
      case DealIntent.sell:
      case DealIntent.rent:
      case DealIntent.offerRental:
        if (subject == null || subject!.trim().isEmpty) missing.add('subject');
        if (!location.isKnown && fulfilment != 'online') missing.add('location');
        break;
      case DealIntent.sendParcel:
      case DealIntent.deliverParcel:
        if (dynamicFields['from'] == null) missing.add('from');
        if (dynamicFields['to'] == null) missing.add('to');
        break;
      case DealIntent.other:
        if (subject == null || subject!.trim().isEmpty) missing.add('subject');
        break;
    }
    return missing;
  }

  bool get readyToMatch => missingForMatch.isEmpty;

  /// Opposite-side intent ASKODOX should search for.
  DealIntent get oppositeIntent => switch (intent) {
        DealIntent.buy => DealIntent.sell,
        DealIntent.sell => DealIntent.buy,
        DealIntent.needService => DealIntent.offerService,
        DealIntent.offerService => DealIntent.needService,
        DealIntent.needWorker => DealIntent.seekWork,
        DealIntent.seekWork => DealIntent.needWorker,
        DealIntent.needRide => DealIntent.offerRide,
        DealIntent.offerRide => DealIntent.needRide,
        DealIntent.sendParcel => DealIntent.deliverParcel,
        DealIntent.deliverParcel => DealIntent.sendParcel,
        DealIntent.rent => DealIntent.offerRental,
        DealIntent.offerRental => DealIntent.rent,
        DealIntent.bookAppointment => DealIntent.offerAppointment,
        DealIntent.offerAppointment => DealIntent.bookAppointment,
        DealIntent.other => DealIntent.other,
      };
}
