enum NaturalDomain {
  commerce,
  grocery,
  freshFood,
  jobs,
  services,
  rides,
  parcel,
  insurance,
  loans,
  property,
  rentals,
  appointments,
  general,
}

class DomainBrainProfile {
  const DomainBrainProfile({
    required this.domain,
    required this.requiredSignals,
    required this.optionalSignals,
    required this.actions,
  });

  final NaturalDomain domain;
  final List<String> requiredSignals;
  final List<String> optionalSignals;
  final List<String> actions;
}

/// Domain-specific behaviour layer used above the universal deal state.
///
/// The universal state remains shared, but questions, matching and actions must
/// follow the natural behaviour of the detected domain. This prevents a
/// commerce demo (for example chicken) from leaking into jobs, insurance,
/// rides or other requests.
class DomainBrainRegistry {
  const DomainBrainRegistry();

  NaturalDomain detect(String rawText, {String? category}) {
    final text = '${category ?? ''} $rawText'.toLowerCase();
    bool any(List<String> words) => words.any(text.contains);

    if (any(['insurance', 'policy', 'premium', 'coverage', 'claim', 'ఇన్సూరెన్స్', 'పాలసీ'])) return NaturalDomain.insurance;
    if (any(['loan', 'emi', 'interest rate', 'credit', 'లోన్', 'ఈఎంఐ'])) return NaturalDomain.loans;
    if (any(['job', 'work', 'hiring', 'salary', 'resume', 'ఉద్యోగం', 'పని కావాలి'])) return NaturalDomain.jobs;
    if (any(['ride', 'cab', 'carpool', 'bike taxi', 'pickup', 'drop'])) return NaturalDomain.rides;
    if (any(['parcel', 'courier', 'package delivery'])) return NaturalDomain.parcel;
    if (any(['service', 'repair', 'electrician', 'plumber', 'technician', 'cleaning'])) return NaturalDomain.services;
    if (any(['house', 'flat', 'plot', 'property', 'bhk', 'apartment'])) return NaturalDomain.property;
    if (any(['rent', 'rental', 'అద్దె'])) return NaturalDomain.rentals;
    if (any(['appointment', 'doctor', 'clinic', 'salon slot'])) return NaturalDomain.appointments;
    if (any(['chicken', 'mutton', 'fish', 'meat', 'fresh food', 'చికెన్', 'మటన్'])) return NaturalDomain.freshFood;
    if (any(['grocery', 'vegetable', 'milk', 'rice', 'dal', 'కిరాణా'])) return NaturalDomain.grocery;
    if (any(['buy', 'sell', 'product', 'item', 'కొనాలి', 'అమ్మాలి'])) return NaturalDomain.commerce;
    return NaturalDomain.general;
  }

  DomainBrainProfile profile(NaturalDomain domain) => switch (domain) {
    NaturalDomain.jobs => const DomainBrainProfile(domain: NaturalDomain.jobs, requiredSignals: ['role_or_skill', 'location'], optionalSignals: ['experience', 'salary', 'shift', 'employment_type', 'availability'], actions: ['match_jobs', 'compare_fit', 'apply_or_connect']),
    NaturalDomain.insurance => const DomainBrainProfile(domain: NaturalDomain.insurance, requiredSignals: ['policy_need'], optionalSignals: ['age', 'coverage', 'premium_budget', 'tenure', 'family', 'existing_policy', 'claim_priority'], actions: ['compare_coverage', 'explain_exclusions', 'check_eligibility', 'connect_provider']),
    NaturalDomain.loans => const DomainBrainProfile(domain: NaturalDomain.loans, requiredSignals: ['loan_purpose', 'amount'], optionalSignals: ['income', 'tenure', 'emi_budget', 'credit_profile', 'employment'], actions: ['compare_eligibility', 'compare_total_cost', 'connect_lender']),
    NaturalDomain.rides => const DomainBrainProfile(domain: NaturalDomain.rides, requiredSignals: ['pickup', 'drop'], optionalSignals: ['time', 'passengers', 'vehicle_preference', 'luggage'], actions: ['match_route', 'compare_eta_fare', 'book_or_connect']),
    NaturalDomain.services => const DomainBrainProfile(domain: NaturalDomain.services, requiredSignals: ['problem_or_service', 'location'], optionalSignals: ['scope', 'date_time', 'budget', 'urgency'], actions: ['match_provider', 'compare_quote', 'book_or_connect']),
    NaturalDomain.property => const DomainBrainProfile(domain: NaturalDomain.property, requiredSignals: ['buy_rent_intent', 'location'], optionalSignals: ['budget', 'property_type', 'bhk', 'area', 'amenities', 'move_date'], actions: ['match_property', 'compare_options', 'schedule_visit']),
    NaturalDomain.freshFood => const DomainBrainProfile(domain: NaturalDomain.freshFood, requiredSignals: ['item', 'quantity'], optionalSignals: ['cut_or_variant', 'freshness', 'price', 'delivery_or_pickup', 'time'], actions: ['match_seller', 'compare_price_quality', 'order_or_connect']),
    NaturalDomain.grocery => const DomainBrainProfile(domain: NaturalDomain.grocery, requiredSignals: ['item'], optionalSignals: ['quantity', 'brand', 'budget', 'delivery_time'], actions: ['match_inventory', 'compare_price', 'order_or_connect']),
    NaturalDomain.commerce => const DomainBrainProfile(domain: NaturalDomain.commerce, requiredSignals: ['item'], optionalSignals: ['quantity', 'variant', 'budget', 'condition', 'delivery_or_pickup'], actions: ['match_seller', 'compare_options', 'negotiate', 'buy_or_connect']),
    NaturalDomain.parcel => const DomainBrainProfile(domain: NaturalDomain.parcel, requiredSignals: ['pickup', 'drop', 'parcel_type'], optionalSignals: ['weight', 'size', 'time', 'fragile'], actions: ['match_delivery', 'compare_eta_fare', 'book_delivery']),
    NaturalDomain.rentals => const DomainBrainProfile(domain: NaturalDomain.rentals, requiredSignals: ['rental_item', 'location'], optionalSignals: ['duration', 'budget', 'deposit', 'availability'], actions: ['match_rental', 'compare_terms', 'reserve_or_connect']),
    NaturalDomain.appointments => const DomainBrainProfile(domain: NaturalDomain.appointments, requiredSignals: ['professional_or_service'], optionalSignals: ['location', 'date_time', 'preference'], actions: ['find_slots', 'compare_options', 'book_slot']),
    NaturalDomain.general => const DomainBrainProfile(domain: NaturalDomain.general, requiredSignals: ['goal'], optionalSignals: ['location', 'budget', 'timing', 'preferences'], actions: ['understand_goal', 'ask_missing_only', 'solve_or_route']),
  };
}
