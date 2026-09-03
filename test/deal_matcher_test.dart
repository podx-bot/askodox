import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_brain.dart';
import 'package:podx/features/deal_brain/domain/deal_matcher.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

void main() {
  const brain = UniversalDealBrain();
  const matcher = DealMatcher();

  UniversalDeal ready(String text, DealIntent intent, String subject, String category) =>
      brain.capture(text).copyWith(intent: intent, subject: subject, category: category, quantity: 10, unit: 'kg', fulfilment: 'pickup', location: const DealLocation(label: 'Vijayawada'));

  UniversalDeal service({required DealIntent intent, required String subject, required double lat, required double lng, double radiusKm = 10}) =>
      brain.capture(subject).copyWith(intent: intent, subject: subject, category: 'service', fulfilment: 'onsite', location: DealLocation(label: 'Vijayawada', latitude: lat, longitude: lng, radiusKm: radiusKm));

  UniversalDeal job({required DealIntent intent, required String skill, required double lat, required double lng, double radiusKm = 15, String? jobType, double? minExperienceYears, double? experienceYears}) {
    final fields = <String, Object?>{'skill': skill};
    if (jobType != null) fields['jobType'] = jobType;
    if (minExperienceYears != null) fields['minExperienceYears'] = minExperienceYears;
    if (experienceYears != null) fields['experienceYears'] = experienceYears;
    return brain.capture(skill).copyWith(intent: intent, subject: skill, category: 'work', location: DealLocation(label: 'Vijayawada', latitude: lat, longitude: lng, radiusKm: radiusKm), dynamicFields: fields);
  }

  UniversalDeal routeDeal({required DealIntent intent, required String from, required String to, required String timing, double? seats, double? seatsAvailable, double? weightKg, double? maxWeightKg}) {
    final fields = <String, Object?>{'from': from, 'to': to};
    if (seats != null) fields['seats'] = seats;
    if (seatsAvailable != null) fields['seatsAvailable'] = seatsAvailable;
    if (weightKg != null) fields['weightKg'] = weightKg;
    if (maxWeightKg != null) fields['maxWeightKg'] = maxWeightKg;
    final category = intent == DealIntent.needRide || intent == DealIntent.offerRide ? 'ride' : 'parcel';
    return brain.capture('$from to $to $timing').copyWith(intent: intent, category: category, timing: timing, dynamicFields: fields);
  }

  UniversalDeal rental({required DealIntent intent, required String subject, required String timing, required String rentalType, required String startDate, double? durationDays, double? availableDays}) {
    final fields = <String, Object?>{'rentalType': rentalType, 'startDate': startDate};
    if (durationDays != null) fields['durationDays'] = durationDays;
    if (availableDays != null) fields['availableDays'] = availableDays;
    return brain.capture(subject).copyWith(intent: intent, subject: subject, category: 'rental', timing: timing, location: const DealLocation(label: 'Vijayawada'), dynamicFields: fields);
  }

  UniversalDeal appointment({required DealIntent intent, required String speciality, required String slot, String location = 'Vijayawada'}) =>
      brain.capture(speciality).copyWith(intent: intent, subject: speciality, category: 'appointment', timing: slot, location: DealLocation(label: location), dynamicFields: {'speciality': speciality, 'slot': slot});

  test('matches only opposite-side exact relevant local product', () {
    final request = ready('Need 10 kg rice in Vijayawada', DealIntent.buy, 'rice', 'product');
    final result = matcher.match(request, [
      DealMatchCandidate(id: 'rice-seller', deal: ready('Sell rice in Vijayawada', DealIntent.sell, 'rice', 'product'), trustScore: 90),
      DealMatchCandidate(id: 'tv-seller', deal: ready('Sell TV in Vijayawada', DealIntent.sell, 'TV', 'product'), trustScore: 99),
      DealMatchCandidate(id: 'rice-buyer', deal: ready('Need rice in Vijayawada', DealIntent.buy, 'rice', 'product'), trustScore: 100),
    ]);
    expect(result.matches.map((m) => m.candidate.id), ['rice-seller']);
  });

  test('returns explicit no-match recovery signal for irrelevant inventory', () {
    final result = matcher.match(ready('Need 10 kg rice in Vijayawada', DealIntent.buy, 'rice', 'product'), [DealMatchCandidate(id: 'chicken-seller', deal: ready('Sell chicken in Vijayawada', DealIntent.sell, 'chicken', 'product'))]);
    expect(result.needsNoMatchRecovery, isTrue);
  });

  test('ranks relevant sellers by trust when relevance is otherwise equal', () {
    final request = ready('Need rice in Vijayawada', DealIntent.buy, 'rice', 'product');
    final seller = ready('Sell rice in Vijayawada', DealIntent.sell, 'rice', 'product');
    final result = matcher.match(request, [DealMatchCandidate(id: 'seller-a', deal: seller, trustScore: 70), DealMatchCandidate(id: 'seller-b', deal: seller, trustScore: 95)]);
    expect(result.matches.first.candidate.id, 'seller-b');
  });

  test('matches correct service provider inside radius', () {
    final request = service(intent: DealIntent.needService, subject: 'electrician', lat: 16.5062, lng: 80.6480, radiusKm: 8);
    final result = matcher.match(request, [
      DealMatchCandidate(id: 'near', deal: service(intent: DealIntent.offerService, subject: 'electrician', lat: 16.5150, lng: 80.6550)),
      DealMatchCandidate(id: 'far', deal: service(intent: DealIntent.offerService, subject: 'electrician', lat: 16.6100, lng: 80.7200, radiusKm: 20)),
    ]);
    expect(result.matches.map((m) => m.candidate.id), ['near']);
  });

  test('job opening matches qualified worker', () {
    final opening = job(intent: DealIntent.needWorker, skill: 'electrician', lat: 16.5062, lng: 80.6480, jobType: 'full-time', minExperienceYears: 2);
    final result = matcher.match(opening, [
      DealMatchCandidate(id: 'qualified', deal: job(intent: DealIntent.seekWork, skill: 'electrician', lat: 16.5150, lng: 80.6550, jobType: 'full-time', experienceYears: 4)),
      DealMatchCandidate(id: 'novice', deal: job(intent: DealIntent.seekWork, skill: 'electrician', lat: 16.5100, lng: 80.6500, jobType: 'full-time', experienceYears: 1)),
    ]);
    expect(result.matches.map((m) => m.candidate.id), ['qualified']);
  });

  test('ride matches route timing and enough seats', () {
    final request = routeDeal(intent: DealIntent.needRide, from: 'Vijayawada', to: 'Bhimavaram', timing: 'tomorrow', seats: 2);
    final result = matcher.match(request, [
      DealMatchCandidate(id: 'exact', deal: routeDeal(intent: DealIntent.offerRide, from: 'Vijayawada', to: 'Bhimavaram', timing: 'tomorrow', seatsAvailable: 3)),
      DealMatchCandidate(id: 'wrong-route', deal: routeDeal(intent: DealIntent.offerRide, from: 'Vijayawada', to: 'Guntur', timing: 'tomorrow', seatsAvailable: 4)),
      DealMatchCandidate(id: 'wrong-day', deal: routeDeal(intent: DealIntent.offerRide, from: 'Vijayawada', to: 'Bhimavaram', timing: 'today', seatsAvailable: 4)),
      DealMatchCandidate(id: 'one-seat', deal: routeDeal(intent: DealIntent.offerRide, from: 'Vijayawada', to: 'Bhimavaram', timing: 'tomorrow', seatsAvailable: 1)),
    ]);
    expect(result.matches.map((m) => m.candidate.id), ['exact']);
  });

  test('ride no compatible driver triggers recovery', () {
    final request = routeDeal(intent: DealIntent.needRide, from: 'Vijayawada', to: 'Bhimavaram', timing: 'tomorrow', seats: 4);
    final result = matcher.match(request, [DealMatchCandidate(id: 'small-car', deal: routeDeal(intent: DealIntent.offerRide, from: 'Vijayawada', to: 'Bhimavaram', timing: 'tomorrow', seatsAvailable: 2))]);
    expect(result.hasLocalMatch, isFalse);
    expect(result.needsNoMatchRecovery, isTrue);
  });

  test('parcel matches route timing and weight capacity', () {
    final request = routeDeal(intent: DealIntent.sendParcel, from: 'Vijayawada', to: 'Guntur', timing: 'today', weightKg: 12);
    final result = matcher.match(request, [
      DealMatchCandidate(id: 'capable', deal: routeDeal(intent: DealIntent.deliverParcel, from: 'Vijayawada', to: 'Guntur', timing: 'today', maxWeightKg: 20)),
      DealMatchCandidate(id: 'under-capacity', deal: routeDeal(intent: DealIntent.deliverParcel, from: 'Vijayawada', to: 'Guntur', timing: 'today', maxWeightKg: 5)),
      DealMatchCandidate(id: 'reverse-route', deal: routeDeal(intent: DealIntent.deliverParcel, from: 'Guntur', to: 'Vijayawada', timing: 'today', maxWeightKg: 20)),
    ]);
    expect(result.matches.map((m) => m.candidate.id), ['capable']);
  });

  test('incomplete route request does not create false no-match recovery', () {
    final incomplete = brain.capture('Need a ride').copyWith(intent: DealIntent.needRide, dynamicFields: const {'from': 'Vijayawada'});
    final result = matcher.match(incomplete, const []);
    expect(result.hasLocalMatch, isFalse);
    expect(result.needsNoMatchRecovery, isFalse);
  });

  test('rental matches type start date and sufficient duration', () {
    final request = rental(intent: DealIntent.rent, subject: 'car', timing: '2026-09-10', rentalType: 'car', startDate: '2026-09-10', durationDays: 3);
    final result = matcher.match(request, [
      DealMatchCandidate(id: 'valid', deal: rental(intent: DealIntent.offerRental, subject: 'car', timing: '2026-09-10', rentalType: 'car', startDate: '2026-09-10', availableDays: 5)),
      DealMatchCandidate(id: 'wrong-type', deal: rental(intent: DealIntent.offerRental, subject: 'car', timing: '2026-09-10', rentalType: 'bike', startDate: '2026-09-10', availableDays: 5)),
      DealMatchCandidate(id: 'wrong-date', deal: rental(intent: DealIntent.offerRental, subject: 'car', timing: '2026-09-11', rentalType: 'car', startDate: '2026-09-11', availableDays: 5)),
      DealMatchCandidate(id: 'too-short', deal: rental(intent: DealIntent.offerRental, subject: 'car', timing: '2026-09-10', rentalType: 'car', startDate: '2026-09-10', availableDays: 2)),
    ]);
    expect(result.matches.map((m) => m.candidate.id), ['valid']);
  });

  test('appointment matches speciality location and exact slot', () {
    final request = appointment(intent: DealIntent.bookAppointment, speciality: 'dentist', slot: '2026-09-10 10:00');
    final result = matcher.match(request, [
      DealMatchCandidate(id: 'exact', deal: appointment(intent: DealIntent.offerAppointment, speciality: 'dentist', slot: '2026-09-10 10:00'), trustScore: 80),
      DealMatchCandidate(id: 'wrong-slot', deal: appointment(intent: DealIntent.offerAppointment, speciality: 'dentist', slot: '2026-09-10 11:00'), trustScore: 100),
      DealMatchCandidate(id: 'wrong-speciality', deal: appointment(intent: DealIntent.offerAppointment, speciality: 'cardiologist', slot: '2026-09-10 10:00'), trustScore: 100),
      DealMatchCandidate(id: 'wrong-location', deal: appointment(intent: DealIntent.offerAppointment, speciality: 'dentist', slot: '2026-09-10 10:00', location: 'Guntur'), trustScore: 100),
    ]);
    expect(result.matches.map((m) => m.candidate.id), ['exact']);
  });

  test('appointment no-match recovery stays local/admin only', () {
    final request = appointment(intent: DealIntent.bookAppointment, speciality: 'dentist', slot: '2026-09-10 10:00');
    final result = matcher.match(request, [DealMatchCandidate(id: 'wrong', deal: appointment(intent: DealIntent.offerAppointment, speciality: 'dentist', slot: '2026-09-10 12:00'))]);
    expect(result.hasLocalMatch, isFalse);
    expect(result.needsNoMatchRecovery, isTrue);
    expect(result.recovery!.onlineSuggestion, isNull);
    expect(result.recovery!.affiliateSuggestion, isNull);
  });
}
