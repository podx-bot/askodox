import '../../deal_brain/domain/universal_deal.dart';
import 'universal_match_repository.dart';

class DemoNaturalMatchCatalog {
  const DemoNaturalMatchCatalog._();

  static List<UniversalMatch> forDeal(
    UniversalDeal deal, {
    bool enabled = false,
  }) {
    // Never let a live error/no-match state silently turn into fake providers.
    // Demo data must be explicitly requested by a known demo/mock caller.
    if (!enabled) return <UniversalMatch>[];

    final text = '${deal.rawText} ${deal.subject ?? ''} ${deal.category ?? ''}'.toLowerCase();
    final location = deal.location.label?.trim();

    if (_hasAny(text, const ['chicken', 'చికెన్', 'కోడి', 'meat', 'mutton', 'మటన్'])) {
      return [
        _match('demo-chicken-1', 'Fresh Chicken Center', location,
            'Demo verified seller • fresh cut chicken • ready now • pickup/delivery', 96, 1.2, 220, 92, 96),
        _match('demo-chicken-2', 'Local Meat & Chicken Shop', location,
            'Demo verified seller • chicken, boneless & wings • quick response', 91, 2.4, 215, 88, 90),
        _match('demo-chicken-3', 'Daily Fresh Poultry', location,
            'Demo verified seller • fresh stock • same-day fulfilment', 86, 3.6, 225, 84, 88),
      ];
    }

    if (_hasAny(text, const ['job', 'ఉద్యోగం', 'work', 'computer operator', 'driver job'])) {
      return [
        _match('demo-job-1', 'Local Office Hiring', location,
            'Demo verified employer • computer operator • immediate opening', 95, 2.0, null, 90, 94),
        _match('demo-job-2', 'Retail Back Office Job', location,
            'Demo verified employer • full-time • local candidates preferred', 88, 4.5, null, 86, 90),
      ];
    }

    if (_hasAny(text, const ['ac repair', 'plumber', 'electrician', 'service', 'repair', 'మెకానిక్', 'mechanic'])) {
      return [
        _match('demo-service-1', 'QuickFix Local Services', location,
            'Demo verified service provider • technician available today', 96, 1.8, 350, 94, 95),
        _match('demo-service-2', 'Nearby Home Service Pro', location,
            'Demo verified service provider • home visit • fast response', 90, 3.1, 300, 89, 91),
      ];
    }

    if (_hasAny(text, const ['ride', 'carpool', 'driver', 'passenger', 'విజయవాడ', 'భీమవరం'])) {
      return [
        _match('demo-ride-1', 'Verified Carpool Driver', location,
            'Demo verified driver • seats available • route matched', 94, 1.0, 750, 93, 92),
        _match('demo-ride-2', 'Intercity Ride Partner', location,
            'Demo verified driver • pickup point can be adjusted', 87, 2.8, 700, 88, 87),
      ];
    }

    if (_hasAny(text, const ['parcel', 'delivery', 'courier', 'పార్సెల్'])) {
      return [
        _match('demo-parcel-1', 'Nearby Delivery Rider', location,
            'Demo verified rider • pickup in 15–20 min', 95, 1.4, 80, 91, 97),
        _match('demo-parcel-2', 'Local Parcel Partner', location,
            'Demo verified rider • same-city delivery', 89, 2.7, 70, 87, 92),
      ];
    }

    if (_hasAny(text, const ['appointment', 'doctor', 'salon', 'clinic', 'booking', 'అపాయింట్మెంట్'])) {
      return [
        _match('demo-appointment-1', 'Nearby Appointment Provider', location,
            'Demo verified provider • slots available today', 93, 2.1, null, 91, 94),
        _match('demo-appointment-2', 'Local Booking Partner', location,
            'Demo verified provider • tomorrow morning slots available', 86, 3.8, null, 86, 89),
      ];
    }

    if (_hasAny(text, const ['catering', 'function', 'guests', 'కేటరింగ్'])) {
      return [
        _match('demo-catering-1', 'Sri Local Caterers', location,
            'Demo verified caterer • function package • custom menu quote', 95, 3.0, null, 93, 92),
        _match('demo-catering-2', 'Family Events Catering', location,
            'Demo verified caterer • veg & non-veg packages', 89, 5.2, null, 88, 90),
      ];
    }

    return [
      _match('demo-local-1', 'Nearby Local Provider', location,
          'Demo verified opposite-side profile • relevant local option • available now', 82, 2.5, deal.price, 84, 86),
    ];
  }

  static bool _hasAny(String text, List<String> values) => values.any(text.contains);

  static UniversalMatch _match(
    String id,
    String title,
    String? location,
    String detail,
    double score,
    double distance,
    double? price,
    double trust,
    double availability,
  ) {
    final area = (location == null || location.isEmpty) ? 'nearby' : location;
    return UniversalMatch(
      id: id,
      title: title,
      subtitle: '$detail • $area',
      score: score,
      distanceKm: distance,
      price: price,
      providerId: 'demo-provider-$id',
      trustScore: trust,
      availabilityScore: availability,
    );
  }
}
