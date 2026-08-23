import '../domain/universal_deal.dart';

class UniversalDealBrain {
  const UniversalDealBrain();

  UniversalDeal capture(String rawText) {
    final text = rawText.trim();
    final lower = text.toLowerCase();
    final intent = _intent(lower);
    final parties = _parties(intent);

    return UniversalDeal(
      rawText: text,
      intent: intent,
      partyA: parties.$1,
      partyB: parties.$2,
      subject: _subject(text, intent),
      category: _category(lower, intent),
      quantity: _numberBeforeUnit(lower),
      unit: _unit(lower),
      price: _price(lower),
      fulfilment: _fulfilment(lower),
      timing: _timing(lower),
      dynamicFields: _dynamicFields(text, lower, intent),
    );
  }

  DealIntent _intent(String text) {
    bool hasAny(List<String> values) => values.any(text.contains);

    if (hasAny(['i want to buy', 'want to buy', 'need to buy', 'looking to buy', 'కొనాలి', 'కావాలి కొన'])) return DealIntent.buy;
    if (hasAny(['i want to sell', 'want to sell', 'for sale', 'అమ్మాలి', 'అమ్మకం'])) return DealIntent.sell;
    if (hasAny(['need a job', 'looking for job', 'find work', 'need work', 'ఉద్యోగం కావాలి', 'పని కావాలి'])) return DealIntent.seekWork;
    if (hasAny(['need worker', 'need staff', 'hiring', 'hire ', 'worker కావాలి', 'మనిషి కావాలి'])) return DealIntent.needWorker;
    if (hasAny(['need a ride', 'find a ride', 'ride కావాలి', 'cab కావాలి', 'car pool'])) return DealIntent.needRide;
    if (hasAny(['offer ride', 'seats available', 'ride available', 'carpool available'])) return DealIntent.offerRide;
    if (hasAny(['need service', 'book a service', 'service కావాలి', 'repair కావాలి', 'technician కావాలి'])) return DealIntent.needService;
    if (hasAny(['offer service', 'provide service', 'service provider', 'నేను service'])) return DealIntent.offerService;
    if (hasAny(['send parcel', 'parcel పంపాలి', 'courier కావాలి'])) return DealIntent.sendParcel;
    if (hasAny(['deliver parcel', 'delivery work', 'parcel delivery'])) return DealIntent.deliverParcel;
    if (hasAny(['want to rent', 'need rental', 'rent కావాలి', 'అద్దెకు కావాలి'])) return DealIntent.rent;
    if (hasAny(['for rent', 'rent out', 'అద్దెకు ఇస్తాను'])) return DealIntent.offerRental;
    if (hasAny(['book appointment', 'appointment కావాలి'])) return DealIntent.bookAppointment;
    if (hasAny(['appointments available', 'take appointments'])) return DealIntent.offerAppointment;

    // Default demand-side interpretation: the user is asking ASKODOX to get
    // something done. The brain can refine this with AI/backend classification.
    return DealIntent.buy;
  }

  (DealPartyRequirement, DealPartyRequirement) _parties(DealIntent intent) {
    return switch (intent) {
      DealIntent.buy => (_demand('buyer', 'needs an item'), _supply('seller', 'can supply the item')),
      DealIntent.sell => (_supply('seller', 'offers an item'), _demand('buyer', 'needs the item')),
      DealIntent.needService => (_demand('service seeker', 'needs a service'), _supply('service provider', 'can perform the service')),
      DealIntent.offerService => (_supply('service provider', 'offers a service'), _demand('service seeker', 'needs the service')),
      DealIntent.needWorker => (_demand('employer', 'needs a worker'), _supply('worker', 'can do the work')),
      DealIntent.seekWork => (_supply('worker', 'offers skill/time'), _demand('employer', 'needs that skill')),
      DealIntent.needRide => (_demand('passenger', 'needs transport'), _supply('driver', 'has a matching ride/seat')),
      DealIntent.offerRide => (_supply('driver', 'offers transport/seats'), _demand('passenger', 'needs the route')),
      DealIntent.sendParcel => (_demand('sender', 'needs parcel movement'), _supply('delivery partner', 'can deliver it')),
      DealIntent.deliverParcel => (_supply('delivery partner', 'offers delivery capacity'), _demand('sender', 'needs delivery')),
      DealIntent.rent => (_demand('renter', 'needs temporary use'), _supply('owner', 'offers rental')),
      DealIntent.offerRental => (_supply('owner', 'offers rental'), _demand('renter', 'needs it temporarily')),
      DealIntent.bookAppointment => (_demand('customer', 'needs an appointment'), _supply('professional', 'has an appointment slot')),
      DealIntent.offerAppointment => (_supply('professional', 'offers appointment slots'), _demand('customer', 'needs a slot')),
      DealIntent.other => (_demand('requester', 'needs an outcome'), _supply('provider', 'can fulfil it')),
    };
  }

  DealPartyRequirement _demand(String role, String action) => DealPartyRequirement(side: DealSide.demand, role: role, action: action);
  DealPartyRequirement _supply(String role, String action) => DealPartyRequirement(side: DealSide.supply, role: role, action: action);

  String? _subject(String text, DealIntent intent) {
    var value = text;
    final prefixes = <String>[
      'i want to buy ', 'want to buy ', 'need to buy ', 'i want to sell ', 'want to sell ',
      'i need ', 'need a ', 'need an ', 'looking for ', 'find ', 'book a ', 'book ',
    ];
    final lower = value.toLowerCase();
    for (final prefix in prefixes) {
      if (lower.startsWith(prefix)) {
        value = value.substring(prefix.length).trim();
        break;
      }
    }
    if (value.isEmpty) return null;
    return value;
  }

  String? _category(String text, DealIntent intent) {
    if (intent == DealIntent.seekWork || intent == DealIntent.needWorker) return 'work';
    if (intent == DealIntent.needRide || intent == DealIntent.offerRide) return 'ride';
    if (intent == DealIntent.needService || intent == DealIntent.offerService) return 'service';
    if (intent == DealIntent.sendParcel || intent == DealIntent.deliverParcel) return 'parcel';
    if (intent == DealIntent.rent || intent == DealIntent.offerRental) return 'rental';
    if (intent == DealIntent.bookAppointment || intent == DealIntent.offerAppointment) return 'appointment';
    return 'product';
  }

  double? _price(String text) {
    final match = RegExp(r'(?:₹|rs\.?|inr)\s*([0-9]+(?:\.[0-9]+)?)', caseSensitive: false).firstMatch(text);
    return double.tryParse(match?.group(1) ?? '');
  }

  double? _numberBeforeUnit(String text) {
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*(kg|kgs|g|gm|grams|litre|liter|l|ml|piece|pieces|pcs|seat|seats|hour|hours|day|days)\b').firstMatch(text);
    return double.tryParse(match?.group(1) ?? '');
  }

  String? _unit(String text) {
    final match = RegExp(r'[0-9]+(?:\.[0-9]+)?\s*(kg|kgs|g|gm|grams|litre|liter|l|ml|piece|pieces|pcs|seat|seats|hour|hours|day|days)\b').firstMatch(text);
    return match?.group(1);
  }

  String? _fulfilment(String text) {
    if (text.contains('delivery')) return 'delivery';
    if (text.contains('pickup') || text.contains('pick up')) return 'pickup';
    if (text.contains('online')) return 'online';
    return null;
  }

  String? _timing(String text) {
    for (final word in ['today', 'tomorrow', 'tonight', 'now', 'urgent', 'ఈరోజు', 'రేపు', 'ఇప్పుడు']) {
      if (text.contains(word)) return word;
    }
    return null;
  }

  Map<String, Object?> _dynamicFields(String raw, String lower, DealIntent intent) {
    final fields = <String, Object?>{};
    if (intent == DealIntent.needWorker || intent == DealIntent.seekWork) {
      fields['skill'] = _subject(raw, intent);
    }
    if (intent == DealIntent.needRide || intent == DealIntent.offerRide || intent == DealIntent.sendParcel || intent == DealIntent.deliverParcel) {
      final route = RegExp(r'(.+?)\s+(?:to|->|→)\s+(.+)', caseSensitive: false).firstMatch(raw);
      if (route != null) {
        fields['from'] = route.group(1)?.trim();
        fields['to'] = route.group(2)?.trim();
      }
    }
    return fields;
  }
}
