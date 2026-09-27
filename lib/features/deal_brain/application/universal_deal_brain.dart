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
      size: screenSizeIn(lower),
      fulfilment: _fulfilment(lower),
      location: DealLocation(label: _location(text, intent)),
      timing: _timing(lower),
      dynamicFields: _dynamicFields(text, lower, intent),
    );
  }

  /// "43 inch", "55-inch", "43\"", "43 ఇంచ్" → "43 inch". A size stated
  /// in the request must not be asked for again.
  static String? screenSizeIn(String lower) {
    final match = RegExp(r'(\d{2,3})\s*-?\s*(inches|inch|"|ఇంచ్|అంగుళ)')
        .firstMatch(lower);
    return match == null ? null : '${match.group(1)} inch';
  }

  DealIntent _intent(String text) {
    bool hasAny(List<String> values) => values.any(text.contains);

    if (hasAny(['buy nearby', 'i want to buy', 'want to buy', 'need to buy', 'looking to buy', 'కొనాలి', 'కావాలి కొన'])) {
      return DealIntent.buy;
    }
    // Selling only when the user says THEY sell: "best selling TV", "I have
    // a budget of 25k" and "TV for sale near me" are buyers.
    final ownsForSale = RegExp(
      r'\b(i|we) (have|own|got) (a|an|some|my|our|one)\b.{0,50}\b(to sell|for sale)\b'
      r'|\b(my|our) .{1,50}\bfor sale\b'
      r"|\b(i am|i'm|we are|we're) selling\b|\bselling (my|our)\b|\bsell (my|our)\b",
    ).hasMatch(text);
    if (ownsForSale ||
        hasAny([
          'sell something',
          'i want to sell',
          'want to sell',
          'అమ్మాలి',
          'అమ్మకం',
          'అమ్ముతున్నాను',
        ])) {
      return DealIntent.sell;
    }
    // Sending something somewhere ("I need to send a parcel", "pickup at X,
    // drop at Y", "courier a document to Hyderabad") -- any wording.
    if (!hasAny(['deliver parcel', 'delivery work', 'parcel delivery job']) &&
        (RegExp(r'\b(send|deliver|courier|ship|drop)\b.{0,30}\b(parcel|package|courier|documents?|box|cover|luggage|item)\b'
                    r'|\bpick ?up\b.{0,80}\bdrop\b|\bparcel\b|\bcourier\b')
                .hasMatch(text) ||
            hasAny(['పార్సెల్', 'కొరియర్']))) {
      return DealIntent.sendParcel;
    }
    final hiring = hasAny(['need worker', 'need staff', 'hiring', 'hire ', 'worker కావాలి', 'మనిషి కావాలి']);
    if (hasAny(['need a job', 'looking for job', 'find work', 'need work', 'ఉద్యోగం కావాలి', 'పని కావాలి']) ||
        (text.contains('looking for ') && RegExp(r'\b(job|work|employment)\b').hasMatch(text)) ||
        (!hiring && (RegExp(r'\b(jobs?|vacancy|vacancies)\b').hasMatch(text) || hasAny(['ఉద్యోగం', 'జాబ్'])))) {
      return DealIntent.seekWork;
    }
    if (hasAny(['need worker', 'need staff', 'hiring', 'hire ', 'worker కావాలి', 'మనిషి కావాలి'])) {
      return DealIntent.needWorker;
    }
    if (hasAny(['need a ride', 'find a ride', 'ride కావాలి', 'cab కావాలి', 'car pool'])) {
      return DealIntent.needRide;
    }
    if (hasAny(['offer ride', 'seats available', 'ride available', 'carpool available'])) {
      return DealIntent.offerRide;
    }
    if (hasAny(['need service', 'book a service', 'service కావాలి', 'repair కావాలి', 'technician కావాలి'])) {
      return DealIntent.needService;
    }
    if (hasAny(['offer service', 'provide service', 'service provider', 'నేను service'])) {
      return DealIntent.offerService;
    }
    if (hasAny(['send parcel', 'parcel పంపాలి', 'courier కావాలి'])) return DealIntent.sendParcel;
    if (hasAny(['deliver parcel', 'delivery work', 'parcel delivery'])) return DealIntent.deliverParcel;
    if (hasAny(['want to rent', 'need rental', 'rent కావాలి', 'అద్దెకు కావాలి'])) return DealIntent.rent;
    if (hasAny(['for rent', 'rent out', 'అద్దెకు ఇస్తాను'])) return DealIntent.offerRental;
    if (hasAny(['book appointment', 'appointment కావాలి'])) return DealIntent.bookAppointment;
    if (hasAny(['appointments available', 'take appointments'])) return DealIntent.offerAppointment;
    // Someone who performs work for you (any trade) is a service need.
    if (RegExp(r'\b(plumber|electrician|carpenter|mechanic|technician|painter|mason|welder|tutor|repair|repairing|servicing|installation|cleaning)\b')
            .hasMatch(text) ||
        hasAny(['మెకానిక్', 'రిపేర్', 'సర్వీస్ కావాలి'])) {
      return DealIntent.needService;
    }
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

  static const _routeIntents = {
    DealIntent.sendParcel,
    DealIntent.deliverParcel,
    DealIntent.needRide,
    DealIntent.offerRide,
  };

  /// What is being sent ("a document", "2 boxes"), never the route.
  static String? parcelItem(String text) {
    final match = RegExp(
      r'\b(?:send|deliver|courier|ship)\s+(?:a|an|my|the|some|\d+)?\s*([a-z]+(?:\s[a-z]+)?)\s+(?:from|to|at|pickup|pick up)\b',
      caseSensitive: false,
    ).firstMatch(text);
    final item = match?.group(1)?.trim().toLowerCase();
    if (item == null || item.isEmpty || {'parcel', 'package', 'courier', 'it', 'something'}.contains(item)) {
      return null;
    }
    return item;
  }

  String? _subject(String text, DealIntent intent) {
    final lowerText = text.toLowerCase().trim();
    // A route need is about the service, not the places: "parcel to
    // Hyderabad" must never match a Hyderabad listing.
    if (_routeIntents.contains(intent)) {
      final isRide = intent == DealIntent.needRide || intent == DealIntent.offerRide;
      if (isRide) return null; // route + timing are the need; backend names it "ride"
      final item = parcelItem(text);
      return item == null ? 'parcel delivery' : '$item delivery';
    }
    if ({'buy nearby', 'sell something', 'find work', 'book a service', 'find a ride'}.contains(lowerText)) return null;

    var value = text;
    final prefixes = <String>[
      'i want to buy a ',
      'i want to buy an ',
      'want to buy a ',
      'want to buy an ',
      'need to buy a ',
      'need to buy an ',
      'i want to sell a ',
      'i want to sell an ',
      'want to sell a ',
      'want to sell an ',
      'i want to buy ',
      'want to buy ',
      'need to buy ',
      'i want to sell ',
      'want to sell ',
      'i need ',
      'need a ',
      'need an ',
      'looking for ',
      'find ',
      'book a ',
      'book ',
    ];
    final lower = value.toLowerCase();
    for (final prefix in prefixes) {
      if (lower.startsWith(prefix)) {
        value = value.substring(prefix.length).trim();
        break;
      }
    }

    if (intent == DealIntent.seekWork) {
      value = value.replaceFirst(RegExp(r'^(?:నాకు|నేను)\s*'), '').trim();
      value = value.replaceFirst(RegExp(r'\s*(?:ఉద్యోగం|జాబ్|పని)\s*కావాలి\s*$'), '').trim();
    }

    value = value.replaceFirst(
      RegExp(r'\s+(?:in|at|near|around)\s+.+?(?=\s+₹|\s+(?:today|tomorrow|tonight|now|urgent)\b|$)', caseSensitive: false),
      '',
    );
    value = value.replaceFirst(
      RegExp(r'\s+(?:today|tomorrow|tonight|now|urgent)\b.*$', caseSensitive: false),
      '',
    ).trim();
    value = value.replaceFirst(RegExp(r'\s*₹\s*[0-9]+(?:\.[0-9]+)?\s*$'), '').trim();

    final genericValues = <String>{
      'work', 'job', 'a job', 'any job', 'some work', 'a work', 'service', 'a service', 'ride', 'a ride',
      'something', 'nearby',
    };
    if (value.isEmpty || genericValues.contains(value.toLowerCase())) return null;
    return value;
  }

  String? _category(String text, DealIntent intent) {
    // What the person is DOING wins over nouns in the message: a parcel of
    // biryani is a parcel, not a food order.
    if (intent == DealIntent.sendParcel || intent == DealIntent.deliverParcel) return 'parcel';
    if (intent == DealIntent.needRide || intent == DealIntent.offerRide) return 'ride';
    if (intent == DealIntent.seekWork || intent == DealIntent.needWorker) return 'work';
    if (RegExp(r'\b(?:food|meal|biryani|restaurant|tiffin|lunch|dinner|chicken|rice)\b').hasMatch(text) ||
        text.contains('ఫుడ్') || text.contains('బిర్యానీ') || text.contains('చికెన్')) {
      return 'food';
    }
    if (RegExp(r'\b(?:house|flat|apartment|plot|property|furniture)\b').hasMatch(text) ||
        text.contains('ఇల్లు') || text.contains('ఫ్లాట్') || text.contains('ప్లాట్')) {
      return 'property';
    }
    if (intent == DealIntent.seekWork || intent == DealIntent.needWorker) return 'work';
    if (intent == DealIntent.needRide || intent == DealIntent.offerRide) return 'ride';
    if (intent == DealIntent.needService || intent == DealIntent.offerService) return 'service';
    if (intent == DealIntent.sendParcel || intent == DealIntent.deliverParcel) return 'parcel';
    if (intent == DealIntent.rent || intent == DealIntent.offerRental) return 'rental';
    if (intent == DealIntent.bookAppointment || intent == DealIntent.offerAppointment) return 'appointment';
    return 'product';
  }

  String? _location(String text, DealIntent intent) {
    if (intent == DealIntent.needRide ||
        intent == DealIntent.offerRide ||
        intent == DealIntent.sendParcel ||
        intent == DealIntent.deliverParcel) {
      return null;
    }
    final match = RegExp(
      r'\b(?:in|at|near|around)\s+(.+?)(?=\s+₹|\s+(?:today|tomorrow|tonight|now|urgent)\b|$)',
      caseSensitive: false,
    ).firstMatch(text);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
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
    if (text.contains('delivery') || text.contains('డెలివరీ')) return 'delivery';
    if (text.contains('pickup') || text.contains('pick up') || text.contains('పికప్')) return 'pickup';
    if (text.contains('online')) return 'online';
    return null;
  }

  String? _timing(String text) {
    for (final word in ['today', 'tomorrow', 'tonight', 'now', 'urgent', 'ఈరోజు', 'రేపు', 'ఇప్పుడు']) {
      if (text.contains(word)) return word;
    }
    return null;
  }

  (String, String)? _route(String raw, DealIntent intent) {
    var value = raw.trim();
    final prefixes = switch (intent) {
      DealIntent.sendParcel => ['send parcel from ', 'send parcel ', 'parcel పంపాలి '],
      DealIntent.deliverParcel => ['deliver parcel from ', 'deliver parcel ', 'parcel delivery from ', 'parcel delivery '],
      DealIntent.needRide => ['need a ride from ', 'need ride from ', 'find a ride from ', 'find ride from ', 'ride కావాలి '],
      DealIntent.offerRide => ['offer ride from ', 'ride available from ', 'carpool available from '],
      _ => const <String>[],
    };
    final lower = value.toLowerCase();
    for (final prefix in prefixes) {
      if (lower.startsWith(prefix)) {
        value = value.substring(prefix.length).trim();
        break;
      }
    }
    String tidy(String v) => v
        .replaceFirst(RegExp(r'^(?:at|from|the)\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'[\s,.;]+(?:and|then|&)?\s*$', caseSensitive: false), '')
        .trim();
    // "pickup at X, drop at Y" / "pick up from X and drop to Y" anywhere.
    final pickDrop = RegExp(
      r'pick\s?-?up\s*(?:is\s*|at\s*|from\s*)?(.+?)[\s,;]+(?:and\s+|then\s+)?drop(?:\s?-?off)?\s*(?:is\s*|at\s*|to\s*)?(.+)$',
      caseSensitive: false,
    ).firstMatch(raw);
    // "... from X to Y ..." anywhere; Telugu "X నుండి Y కి".
    final fromTo = RegExp(r'\bfrom\s+(.+?)\s+(?:to|->|→)\s+(.+)$', caseSensitive: false).firstMatch(raw);
    final telugu = RegExp(r'(\S+(?:\s\S+)?)\s*(?:నుండి|నుంచి)\s*(\S+?)(?:కి|కు)?(?:\s|$)').firstMatch(raw);
    value = value.replaceFirst(RegExp(r'^from\s+', caseSensitive: false), '');
    final match = pickDrop ?? fromTo ?? telugu ??
        RegExp(r'^(.+?)\s+(?:to|->|→)\s+(.+)$', caseSensitive: false).firstMatch(value);
    if (match == null) return null;
    var from = tidy(match.group(1) ?? '');
    var to = tidy(match.group(2) ?? '');
    // "I need to send a parcel": a verb phrase, not a route.
    if (RegExp(r'\b(need|want|have|like|going|able|has)$', caseSensitive: false).hasMatch(from) ||
        RegExp(r'^(send|buy|deliver|get|go|book|pick|ship|courier)\b', caseSensitive: false).hasMatch(to)) {
      return null;
    }
    // "parcel to Hyderabad": only the drop is known.
    if (RegExp(r'^(?:(?:a|my|the|send|send a)\s+)?(?:parcel|package|courier|document|box)s?$', caseSensitive: false)
        .hasMatch(from)) {
      from = '';
    }
    to = to.replaceFirst(
      RegExp(r'\s+(?:today|tomorrow|tonight|now|urgent)\b.*$', caseSensitive: false),
      '',
    ).trim();
    if (from.isEmpty && to.isEmpty) return null;
    return (from, to);
  }

  Map<String, Object?> _dynamicFields(String raw, String lower, DealIntent intent) {
    final fields = <String, Object?>{};
    if (intent == DealIntent.needWorker || intent == DealIntent.seekWork) {
      final skill = _subject(raw, intent);
      if (skill != null && skill.trim().isNotEmpty) fields['skill'] = skill;
    }
    if (intent == DealIntent.needRide || intent == DealIntent.offerRide || intent == DealIntent.sendParcel || intent == DealIntent.deliverParcel) {
      final route = _route(raw, intent);
      if (route != null) {
        if (route.$1.isNotEmpty) fields['from'] = route.$1;
        if (route.$2.isNotEmpty) fields['to'] = route.$2;
      }
    }

    final isChicken = lower.contains('chicken') || lower.contains('చికెన్');
    if (isChicken) {
      fields['productKind'] = 'chicken';
      if (lower.contains('fresh') || lower.contains('ఫ్రెష్') || lower.contains('live cut')) fields['freshness'] = 'fresh';
      if (lower.contains('chilled')) fields['freshness'] = 'chilled';
      if (lower.contains('curry cut') || lower.contains('కర్రీ')) fields['cut'] = 'curry cut';
      if (lower.contains('biryani cut') || lower.contains('బిర్యానీ')) fields['cut'] = 'biryani cut';
      if (lower.contains('whole') || lower.contains('హోల్')) fields['cut'] = 'whole';

      final preferences = <String>[];
      if (lower.contains('skinless') || lower.contains('స్కిన్‌లెస్') || lower.contains('స్కిన్లెస్')) preferences.add('skinless');
      if (lower.contains('with skin')) preferences.add('with skin');
      if (lower.contains('front')) preferences.add('front portion');
      if (lower.contains('back')) preferences.add('back portion');
      if (lower.contains('breast')) preferences.add('breast');
      if (lower.contains('leg')) preferences.add('leg');
      if (lower.contains('wing')) preferences.add('wings');
      if (lower.contains('liver') || lower.contains('లివర్')) preferences.add('liver');
      if (lower.contains('gizzard') || lower.contains('గిజార్డ్')) preferences.add('gizzard');
      if (preferences.isNotEmpty) fields['chickenPreference'] = preferences.join(', ');
    }
    return fields;
  }
}
