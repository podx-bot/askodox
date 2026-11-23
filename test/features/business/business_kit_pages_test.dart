// Business Kit (owner 2026-11-24): a shop's pages follow EVERYTHING it picked (server `kit.page_family`), not only
// its kind -- a hotel that also sells sweets keeps tables + kitchen, a tailor gets orders & bookings, and a shop from
// an older server still falls back to its kind.
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/business/presentation/biz_hub.dart';
import 'package:podx/features/pos/presentation/pos_home_screen.dart';

void main() {
  test('the kit decides the page family, the kind is only a fallback', () {
    expect(askodoxBizKindOf({'template': 'kirana', 'kit': {'page_family': 'food'}}), AskodoxBizKind.food);
    expect(askodoxBizKindOf({'template': 'clothing', 'kit': {'page_family': 'service'}}), AskodoxBizKind.service);
    expect(askodoxBizKindOf({'template': 'restaurant', 'kit': {'page_family': 'retail'}}), AskodoxBizKind.retail);
    expect(askodoxBizKindOf({'template': 'restaurant'}), AskodoxBizKind.food);
    expect(askodoxBizKindOf({'template': 'salon', 'kit': {}}), AskodoxBizKind.service);
    expect(askodoxBizKindOf(null), AskodoxBizKind.retail);
  });

  test('tables and kitchen come with a food shop, whatever its kind', () {
    expect(askodoxPosHasTables({'template': 'general', 'kit': {'page_family': 'food'}}), isTrue);
    expect(askodoxPosHasTables({'template': 'restaurant', 'kit': {'page_family': 'retail'}}), isFalse);
    expect(askodoxPosHasTables({'template': 'bakery'}), isTrue);
    expect(askodoxPosHasTables({'template': 'kirana'}), isFalse);
  });
}
