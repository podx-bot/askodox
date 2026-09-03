import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/rfq_request.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

void main() {
  const demand = DealPartyRequirement(side: DealSide.demand, role: 'buyer', action: 'buy');
  const supply = DealPartyRequirement(side: DealSide.supply, role: 'seller', action: 'sell');

  test('wholesale RFQ snapshot preserves captured trade requirements', () {
    const deal = UniversalDeal(
      rawText: 'Need 10 bags masala near Guntur',
      intent: DealIntent.buy,
      partyA: demand,
      partyB: supply,
      subject: 'masala',
      category: 'product',
      quantity: 10,
      unit: 'bags',
      location: DealLocation(label: 'Guntur'),
      dynamicFields: <String, Object?>{
        'productProfile': 'wholesale_packaged_goods',
        'packSize': '25 kg',
      },
    );

    final rfq = RfqRequest.fromDeal(deal);
    expect(rfq.schemaId, 'wholesale');
    expect(rfq.subject, 'masala');
    expect(rfq.requirements['quantity'], 10);
    expect(rfq.requirements['unit'], 'bags');
    expect(rfq.requirements['packSize'], '25 kg');
    expect(rfq.requirements['location'], 'Guntur');
    expect(rfq.isReady, isTrue);
  });

  test('service RFQ snapshot keeps service-specific details', () {
    const deal = UniversalDeal(
      rawText: 'Need electrical repair near Vijayawada',
      intent: DealIntent.needService,
      partyA: demand,
      partyB: DealPartyRequirement(side: DealSide.supply, role: 'provider', action: 'offer service'),
      subject: 'electrical repair',
      category: 'service',
      location: DealLocation(label: 'Vijayawada'),
      timing: 'tomorrow',
      dynamicFields: <String, Object?>{'problem': 'switch board not working'},
    );

    final rfq = RfqRequest.fromDeal(deal);
    expect(rfq.schemaId, 'service');
    expect(rfq.requirements['problem'], 'switch board not working');
    expect(rfq.requirements['timing'], 'tomorrow');
    expect(rfq.requirements['location'], 'Vijayawada');
  });
}
