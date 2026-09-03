import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/rfq_quote_pipeline.dart';
import 'package:podx/features/deal_brain/domain/rfq_request.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

void main() {
  const demand = DealPartyRequirement(side: DealSide.demand, role: 'buyer', action: 'buy');
  const supply = DealPartyRequirement(side: DealSide.supply, role: 'seller', action: 'sell');

  test('natural seller quotes attach to RFQ and compare automatically', () {
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

    var pipeline = RfqQuotePipeline(request: RfqRequest.fromDeal(deal));
    pipeline = pipeline.ingestText(
      sellerId: 'seller-a',
      text: 'Total ₹12000, delivery ₹300, delivery in 2 days',
      trustScore: 75,
    );
    pipeline = pipeline.ingestText(
      sellerId: 'seller-b',
      text: 'Total ₹12500, delivery free, delivery in 4 hours',
      trustScore: 90,
    );

    expect(pipeline.hasQuotes, isTrue);
    expect(pipeline.collection.quotes, hasLength(2));
    expect(pipeline.result.cheapest?.sellerId, 'seller-a');
    expect(pipeline.result.fastest?.sellerId, 'seller-b');
  });

  test('seller revision replaces previous normalized quote', () {
    const deal = UniversalDeal(
      rawText: 'Need electrical repair near Vijayawada',
      intent: DealIntent.needService,
      partyA: demand,
      partyB: DealPartyRequirement(side: DealSide.supply, role: 'provider', action: 'offer service'),
      subject: 'electrical repair',
      category: 'service',
      location: DealLocation(label: 'Vijayawada'),
    );

    var pipeline = RfqQuotePipeline(request: RfqRequest.fromDeal(deal));
    pipeline = pipeline.ingestText(sellerId: 'provider-a', text: 'Total ₹2000, 1 day');
    pipeline = pipeline.ingestText(sellerId: 'provider-a', text: 'Total ₹1800, 4 hours');

    expect(pipeline.collection.quotes, hasLength(1));
    expect(pipeline.result.cheapest?.amount, 1800);
    expect(pipeline.result.fastest?.leadTimeHours, 4);
  });
}
