import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/presentation/pos_counter_orders.dart';

void main() {
  test('counter cart becomes desk lines in pieces (max 50, empty ones dropped)', () {
    final lines = askodoxCounterDeskLines([
      (productId: 'p1', qtyMilli: 2000),
      (productId: 'p2', qtyMilli: 500),
      (productId: '', qtyMilli: 1000),
      (productId: 'p3', qtyMilli: 80000),
    ]);
    expect(lines, [
      {'product_id': 'p1', 'qty': 2.0},
      {'product_id': 'p2', 'qty': 0.5},
      {'product_id': 'p3', 'qty': 50.0},
    ]);
  });

  test('four ways at the counter: now, table, parcel, delivery', () {
    expect([for (final k in askodoxCounterOrderKinds) k.$1], ['now', 'dine_in', 'takeaway', 'delivery']);
  });
}
