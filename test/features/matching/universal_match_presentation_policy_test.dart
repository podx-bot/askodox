import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';
import 'package:podx/features/matching/domain/universal_match_presentation_policy.dart';

UniversalDeal deal(DealIntent intent, {String category = 'product'}) => UniversalDeal(
      rawText: 'request',
      intent: intent,
      category: category,
      partyA: const DealPartyRequirement(
        side: DealSide.demand,
        role: 'Party A',
        action: 'request',
      ),
      partyB: const DealPartyRequirement(
        side: DealSide.supply,
        role: 'Party B',
        action: 'respond',
      ),
    );

void main() {
  test('commerce buyer preserves payment and invoice behavior', () {
    final presentation = UniversalMatchPresentationPolicy.forDeal(deal(DealIntent.buy));

    expect(presentation.resultKind, 'product');
    expect(presentation.partyLabel, 'seller');
    expect(presentation.supportsPayment, isTrue);
    expect(presentation.supportsInvoice, isTrue);
    expect(presentation.questionChips, contains('Price'));
  });

  test('service provider uses provider language without commerce payment', () {
    final presentation = UniversalMatchPresentationPolicy.forDeal(deal(DealIntent.needService, category: 'service'));

    expect(presentation.resultKind, 'service');
    expect(presentation.partyLabel, 'provider');
    expect(presentation.confirmLabel, 'Confirm provider');
    expect(presentation.supportsPayment, isFalse);
    expect(presentation.supportsInvoice, isFalse);
    expect(presentation.questionChips, contains('Availability'));
  });

  test('job delivery appointment and mobility use non-commerce result capabilities', () {
    for (final intent in [
      DealIntent.seekWork,
      DealIntent.sendParcel,
      DealIntent.bookAppointment,
      DealIntent.needRide,
    ]) {
      final presentation = UniversalMatchPresentationPolicy.forDeal(deal(intent));
      expect(presentation.supportsPayment, isFalse);
      expect(presentation.supportsInvoice, isFalse);
      expect(presentation.questionChips, isNotEmpty);
    }
  });

  test('cross-category result matrix keeps non-commerce flows out of payment UI', () {
    final cases = <DealIntent>[
      DealIntent.needService,
      DealIntent.seekWork,
      DealIntent.sendParcel,
      DealIntent.bookAppointment,
      DealIntent.rent,
      DealIntent.needRide,
      DealIntent.buy,
    ];

    final presentations = cases
        .map((intent) => UniversalMatchPresentationPolicy.forDeal(deal(intent)))
        .toList();

    expect(presentations.take(6).every((item) => !item.supportsPayment), isTrue);
    expect(presentations.last.supportsPayment, isTrue);
    expect(presentations.map((item) => item.resultKind).toSet().length, greaterThan(3));
  });
}
