import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_context_resolver.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

UniversalDeal deal({
  required String subject,
  DealIntent intent = DealIntent.buy,
  double? quantity,
  String? unit,
  String? variant,
  String? location,
  Map<String, Object?> dynamicFields = const {},
}) {
  return UniversalDeal(
    rawText: subject,
    intent: intent,
    partyA: const DealPartyRequirement(
      side: DealSide.demand,
      role: 'buyer',
      action: 'buy',
    ),
    partyB: const DealPartyRequirement(
      side: DealSide.supply,
      role: 'seller',
      action: 'sell',
    ),
    subject: subject,
    quantity: quantity,
    unit: unit,
    variant: variant,
    location: DealLocation(label: location),
    dynamicFields: dynamicFields,
  );
}

void main() {
  const resolver = UniversalDealContextResolver();

  test('same subject and intent are treated as one active context', () {
    final active = deal(subject: 'Chicken Boneless', quantity: 10, unit: 'kg');
    final incoming = deal(subject: ' chicken boneless! ', quantity: 12, unit: 'kg');

    expect(resolver.sameContext(active, incoming), isTrue);
  });

  test('different subject or intent is a new context', () {
    final active = deal(subject: 'chicken');

    expect(resolver.sameContext(active, deal(subject: 'mutton')), isFalse);
    expect(
      resolver.sameContext(active, deal(subject: 'chicken', intent: DealIntent.sell)),
      isFalse,
    );
  });

  test('merge updates supplied fields and preserves known active facts', () {
    final active = deal(
      subject: 'chicken',
      quantity: 10,
      unit: 'kg',
      variant: 'with bone',
      location: 'Vijayawada',
      dynamicFields: const {'quality': 'fresh', 'cut': 'medium'},
    );
    final incoming = deal(
      subject: 'chicken',
      quantity: 12,
      unit: 'kg',
      variant: 'boneless',
      dynamicFields: const {'cut': 'small'},
    );

    final merged = resolver.merge(active, incoming);

    expect(merged.quantity, 12);
    expect(merged.unit, 'kg');
    expect(merged.variant, 'boneless');
    expect(merged.location.label, 'Vijayawada');
    expect(merged.dynamicFields['quality'], 'fresh');
    expect(merged.dynamicFields['cut'], 'small');
  });
}
