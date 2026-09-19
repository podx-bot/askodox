import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/deal_category_schema.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

UniversalDeal request(DealIntent intent, {String? category}) => UniversalDeal(
      rawText: 'request',
      intent: intent,
      category: category,
      partyA: const DealPartyRequirement(side: DealSide.demand, role: 'A', action: 'request'),
      partyB: const DealPartyRequirement(side: DealSide.supply, role: 'B', action: 'respond'),
    );

void main() {
  test('schemas cover unrelated categories with distinct result kinds', () {
    expect(DealCategorySchemas.forDeal(request(DealIntent.needService)).resultKind, 'service');
    expect(DealCategorySchemas.forDeal(request(DealIntent.seekWork)).resultKind, 'job');
    expect(DealCategorySchemas.forDeal(request(DealIntent.sendParcel)).resultKind, 'delivery');
    expect(DealCategorySchemas.forDeal(request(DealIntent.needRide)).resultKind, 'ride');
  });

  test('service readiness is schema-driven', () {
    final deal = request(DealIntent.needService);
    expect(deal.missingForMatch, ['subject', 'location']);
  });
}