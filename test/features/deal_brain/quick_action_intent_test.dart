import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_brain.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

void main() {
  const brain = UniversalDealBrain();

  group('ASKODOX quick actions', () {
    test('Buy nearby asks for the actual item before location', () {
      final deal = brain.capture('Buy nearby');

      expect(deal.intent, DealIntent.buy);
      expect(deal.subject, isNull);
      expect(deal.missingForMatch, ['subject', 'location']);
    });

    test('Sell something is seller intent and asks for actual item', () {
      final deal = brain.capture('Sell something');

      expect(deal.intent, DealIntent.sell);
      expect(deal.subject, isNull);
      expect(deal.partyA.role, 'seller');
      expect(deal.missingForMatch, ['subject', 'location']);
    });

    test('Find work asks for real skill before location', () {
      final deal = brain.capture('Find work');

      expect(deal.intent, DealIntent.seekWork);
      expect(deal.subject, isNull);
      expect(deal.dynamicFields['skill'], isNull);
      expect(deal.missingForMatch, ['skill', 'location']);
    });

    test('specific work phrase keeps the actual skill', () {
      final deal = brain.capture('Looking for computer operator job');

      expect(deal.intent, DealIntent.seekWork);
      expect(deal.dynamicFields['skill'], isNotNull);
      expect(deal.missingForMatch, isNot(contains('skill')));
      expect(deal.missingForMatch, contains('location'));
    });

    test('Book a service asks for the actual service before location', () {
      final deal = brain.capture('Book a service');

      expect(deal.intent, DealIntent.needService);
      expect(deal.subject, isNull);
      expect(deal.missingForMatch, ['subject', 'location']);
    });

    test('Find a ride asks for route and timing rather than generic subject', () {
      final deal = brain.capture('Find a ride');

      expect(deal.intent, DealIntent.needRide);
      expect(deal.subject, isNull);
      expect(deal.missingForMatch, ['from', 'to', 'timing']);
    });

    test('buy request reuses stated location and keeps it out of subject', () {
      final deal = brain.capture('I want to buy a laptop in Vijayawada');

      expect(deal.intent, DealIntent.buy);
      expect(deal.subject, 'laptop');
      expect(deal.location.label, 'Vijayawada');
      expect(deal.missingForMatch, isEmpty);
    });

    test('appointment reuses stated location but still asks only for timing', () {
      final deal = brain.capture('Book appointment doctor near Guntur');

      expect(deal.intent, DealIntent.bookAppointment);
      expect(deal.subject, 'appointment doctor');
      expect(deal.location.label, 'Guntur');
      expect(deal.missingForMatch, ['timing']);
    });

    test('job location is separated from skill instead of being asked twice', () {
      final deal = brain.capture('Looking for computer operator job in Vijayawada');

      expect(deal.intent, DealIntent.seekWork);
      expect(deal.dynamicFields['skill'], 'computer operator job');
      expect(deal.location.label, 'Vijayawada');
      expect(deal.missingForMatch, isEmpty);
    });
  });
}
