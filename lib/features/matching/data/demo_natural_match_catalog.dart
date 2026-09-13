import '../../deal_brain/domain/universal_deal.dart';
import 'universal_match_repository.dart';

class DemoNaturalMatchCatalog {
  const DemoNaturalMatchCatalog._();

  static List<UniversalMatch> forDeal(
    UniversalDeal deal, {
    bool enabled = false,
  }) {
    if (!enabled) return <UniversalMatch>[];

    final text = '${deal.rawText} ${deal.subject ?? ''} ${deal.category ?? ''}'.toLowerCase();
    final location = deal.location.label?.trim();

    if (_hasAny(text, const ['chicken', 'చికెన్', 'కోడి', 'meat', 'mutton', 'మటన్'])) {
      return [
        _match('demo-chicken-1', 'Fresh Chicken Center', location, 'Sandbox verified seller • fresh cut chicken • ready now • pickup/delivery', 96, 1.2, 220, 92, 96),
        _match('demo-chicken-2', 'Local Meat & Chicken Shop', location, 'Sandbox verified seller • chicken, boneless & wings • quick response', 91, 2.4, 215, 88, 90),
        _match('demo-chicken-3', 'Daily Fresh Poultry', location, 'Sandbox verified seller • fresh stock • same-day fulfilment', 86, 3.6, 225, 84, 88),
        _match('demo-chicken-4', 'Family Poultry Mart', location, 'Sandbox seller • live-cut and chilled options • evening availability', 82, 4.4, 218, 81, 84),
      ];
    }

    final isJob = _hasAny(text, const ['job', 'ఉద్యోగం', 'work', 'computer operator', 'driver job']);
    final isDelivery = _hasAny(text, const ['delivery', 'courier', 'డెలివరీ']);
    if (isJob && isDelivery) {
      return [
        _match('demo-delivery-job-1', 'Local Delivery Executive', location, 'Sandbox verified employer • delivery executive • immediate opening', 97, 1.6, null, 93, 96),
        _match('demo-delivery-job-2', 'Bike Delivery Rider Job', location, 'Sandbox verified employer • bike rider • local deliveries • hiring now', 93, 2.3, null, 91, 94),
        _match('demo-delivery-job-3', 'Courier Delivery Associate', location, 'Sandbox employer • courier delivery • local route opening', 88, 3.7, null, 87, 90),
      ];
    }

    if (isJob) {
      return [
        _match('demo-job-1', 'Local Office Hiring', location, 'Sandbox verified employer • computer operator • immediate opening', 95, 2.0, null, 90, 94),
        _match('demo-job-2', 'Retail Back Office Job', location, 'Sandbox verified employer • full-time • local candidates preferred', 88, 4.5, null, 86, 90),
        _match('demo-job-3', 'Local Driver Vacancy', location, 'Sandbox employer • driver opening • documents required', 84, 5.0, null, 83, 88),
      ];
    }

    if (_hasAny(text, const ['ac repair', 'plumber', 'electrician', 'service', 'repair', 'మెకానిక్', 'mechanic'])) {
      return [
        _match('demo-service-1', 'QuickFix Local Services', location, 'Sandbox verified service provider • technician available today', 96, 1.8, 350, 94, 95),
        _match('demo-service-2', 'Nearby Home Service Pro', location, 'Sandbox verified service provider • home visit • fast response', 90, 3.1, 300, 89, 91),
        _match('demo-service-3', 'Local Electrical & Plumbing', location, 'Sandbox service provider • electrical and plumbing visits', 85, 4.2, 280, 86, 87),
        _match('demo-service-4', 'AC Care Technician', location, 'Sandbox service provider • AC inspection and repair', 83, 4.8, 450, 84, 85),
      ];
    }

    if (_hasAny(text, const ['ride', 'carpool', 'driver', 'passenger', 'విజయవాడ', 'భీమవరం'])) {
      return [
        _match('demo-ride-1', 'Verified Carpool Driver', location, 'Sandbox verified driver • seats available • route matched', 94, 1.0, 750, 93, 92),
        _match('demo-ride-2', 'Intercity Ride Partner', location, 'Sandbox verified driver • pickup point can be adjusted', 87, 2.8, 700, 88, 87),
        _match('demo-ride-3', 'Local Bike Taxi Rider', location, 'Sandbox verified rider • short local trips • available now', 85, 2.1, 25, 86, 91),
      ];
    }

    if (_hasAny(text, const ['parcel', 'delivery', 'courier', 'పార్సెల్'])) {
      return [
        _match('demo-parcel-1', 'Nearby Delivery Rider', location, 'Sandbox verified rider • pickup in 15–20 min', 95, 1.4, 80, 91, 97),
        _match('demo-parcel-2', 'Local Parcel Partner', location, 'Sandbox verified rider • same-city delivery', 89, 2.7, 70, 87, 92),
        _match('demo-parcel-3', 'Quick Local Courier', location, 'Sandbox courier • document and small parcel delivery', 84, 3.9, 60, 84, 88),
      ];
    }

    if (_hasAny(text, const ['appointment', 'doctor', 'salon', 'clinic', 'booking', 'అపాయింట్మెంట్'])) {
      return [
        _match('demo-appointment-1', 'Nearby Appointment Provider', location, 'Sandbox verified provider • slots available today', 93, 2.1, null, 91, 94),
        _match('demo-appointment-2', 'Local Booking Partner', location, 'Sandbox verified provider • tomorrow morning slots available', 86, 3.8, null, 86, 89),
        _match('demo-appointment-3', 'Neighbourhood Salon Booking', location, 'Sandbox provider • same-day booking slots', 82, 4.6, 250, 83, 86),
      ];
    }

    if (_hasAny(text, const ['catering', 'function', 'guests', 'కేటరింగ్'])) {
      return [
        _match('demo-catering-1', 'Sri Local Caterers', location, 'Sandbox verified caterer • function package • custom menu quote', 95, 3.0, null, 93, 92),
        _match('demo-catering-2', 'Family Events Catering', location, 'Sandbox verified caterer • veg & non-veg packages', 89, 5.2, null, 88, 90),
        _match('demo-catering-3', 'Town Function Caterers', location, 'Sandbox caterer • small and medium functions • quote on request', 84, 6.0, null, 85, 86),
      ];
    }

    if (_hasAny(text, const ['tv', 'television', 'mobile', 'phone', 'furniture', 'sofa', 'appliance'])) {
      return [
        _match('demo-retail-1', 'Verified Local Retailer', location, 'Sandbox verified seller • product enquiry and local pickup', 92, 1.9, deal.price, 91, 93),
        _match('demo-retail-2', 'Nearby Multi Brand Store', location, 'Sandbox seller • price and availability confirmation in chat', 87, 3.3, deal.price, 86, 89),
        _match('demo-retail-3', 'Town Local Shop', location, 'Sandbox seller • local stock • pickup or seller delivery', 83, 4.7, deal.price, 84, 86),
      ];
    }

    return [
      _match('demo-local-1', 'Nearby Local Provider', location, 'Sandbox verified opposite-side profile • relevant local option • available now', 82, 2.5, deal.price, 84, 86),
      _match('demo-local-2', 'Local Business Partner', location, 'Sandbox opposite-side profile • chat before contact sharing', 78, 4.0, deal.price, 80, 82),
    ];
  }

  static bool _hasAny(String text, List<String> values) => values.any(text.contains);

  static UniversalMatch _match(String id, String title, String? location, String detail, double score, double distance, double? price, double trust, double availability) {
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
