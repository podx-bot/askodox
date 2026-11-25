import 'package:podx/features/steps/domain/one_touch_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// Owner 2026-11-25 "ఒక్క టచ్" leftovers: the same numbers / splits as the server (pos_bulk_price.new_price,
// tests/test_family_lists_and_bulk_price.py).
void main() {
  test('bulk price = the server rule (rounding, never below ₹1)', () {
    expect(askodoxBulkNewPrice(4000, 'up_percent', 10, 100), 4400);
    expect(askodoxBulkNewPrice(1200, 'up_percent', 10, 500), 1500);
    expect(askodoxBulkNewPrice(1200, 'down_rupees', 50, 100), 100);
    expect(askodoxBulkNewPrice(4000, 'up_rupees', 5, 100), 4500);
    expect(askodoxBulkNewPrice(999, 'set', 15, 0), 1500);
    expect(askodoxBulkNewPrice(1250, 'down_percent', 10, 0), 1125);
    expect(askodoxBulkValueOk('down_percent', 95), isFalse);
    expect(askodoxBulkValueOk('up_rupees', 0), isFalse);
    expect(askodoxBulkValueOk('up_percent', 20), isTrue);
  });

  test('family list: one spoken / typed line -> items', () {
    expect(askodoxFamilyItemsFrom('sugar, milk and 2 kg rice'), ['sugar', 'milk', '2 kg rice']);
    expect(askodoxFamilyItemsFrom('చక్కెర, పాలు మరియు సబ్బు'), ['చక్కెర', 'పాలు', 'సబ్బు']);
    expect(askodoxFamilyItemsFrom(' , \n '), isEmpty);
    expect(askodoxFamilyNearbyAsk(['milk'], false), contains('milk'));
  });
}
