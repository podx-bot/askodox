import 'package:flutter_test/flutter_test.dart';
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
}
