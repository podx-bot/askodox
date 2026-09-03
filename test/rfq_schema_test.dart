import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_brain.dart';
import 'package:podx/features/deal_brain/domain/rfq_schema.dart';

void main() {
  test('chicken RFQ uses bulk trade fields', () {
    final schema = RfqSchemas.resolve(category: 'product', productProfile: 'chicken', subject: 'chicken');
    expect(schema.id, 'chicken_bulk');
    expect(schema.fields, containsAll(<String>['pricePerKg', 'quantity', 'cut', 'deliveryLeadTime', 'validity']));
  });

  test('furniture RFQ captures dimensions transport and installation', () {
    final schema = RfqSchemas.resolve(category: 'product', productProfile: 'furniture', subject: 'bed');
    expect(schema.id, 'furniture');
    expect(schema.fields, containsAll(<String>['material', 'dimensions', 'transport', 'installation', 'totalPrice']));
  });

  test('service RFQ separates labour and material', () {
    final schema = RfqSchemas.resolve(category: 'service', subject: 'electrical repair');
    expect(schema.id, 'service');
    expect(schema.fields, containsAll(<String>['labourPrice', 'materialPrice', 'timeline', 'warranty']));
  });

  test('wholesale RFQ includes MOQ freight and payment terms', () {
    final schema = RfqSchemas.resolve(category: 'product', productProfile: 'wholesale_packaged_goods', subject: 'masala');
    expect(schema.id, 'wholesale');
    expect(schema.fields, containsAll(<String>['moq', 'unitPrice', 'taxes', 'freight', 'paymentTerms']));
  });

  test('captured wholesale deal exposes wholesale RFQ schema', () {
    final deal = const UniversalDealBrain().capture('I want to buy masala wholesale near Guntur');
    expect(deal.productProfile, 'wholesale_packaged_goods');
    expect(deal.rfqSchema.id, 'wholesale');
    expect(deal.rfqSchema.fields, containsAll(<String>['moq', 'unitPrice', 'freight', 'paymentTerms']));
  });

  test('captured service deal exposes service RFQ schema', () {
    final deal = const UniversalDealBrain().capture('I need electrical repair near Vijayawada');
    expect(deal.rfqSchema.id, 'service');
    expect(deal.rfqSchema.fields, containsAll(<String>['labourPrice', 'materialPrice', 'timeline', 'warranty']));
  });
}
