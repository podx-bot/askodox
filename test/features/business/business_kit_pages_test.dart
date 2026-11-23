// Business Kit (owner 2026-11-24): a shop's pages follow EVERYTHING it picked (server `kit.page_family`), not only
// its kind -- a hotel that also sells sweets keeps tables + kitchen, a tailor gets orders & bookings, and a shop from
// an older server still falls back to its kind.
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/business/presentation/biz_hub.dart';
import 'package:podx/features/money_home/money_home_pages.dart';
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

  test('bookings, job cards and monthly pages come only with their way of working', () {
    Set<String> pages(List<String> flows) => {
          for (final p in askodoxSellerPages('h1', {
            'role': 'owner',
            'template': 'general',
            'kit': {'flows': flows, 'page_family': 'service'},
          }))
            p.id,
        };
    expect(pages(['3', '6']), containsAll(['s.bookings', 's.crm']));
    expect(pages(['3', '6']).contains('s.jobs'), isFalse);
    expect(pages(['4']), contains('s.jobs'));
    expect(pages(['1', '5']), contains('s.monthly'));
    expect(pages([]).intersection({'s.bookings', 's.jobs', 's.monthly'}), isEmpty);
    final orders = askodoxBizGroups(AskodoxBizKind.service, flows: {'3', '4'}).firstWhere((g) => g.id == 'orders');
    expect(orders.tiles.map((t) => t.page), containsAll(['orders.bookings', 'orders.jobs']));
    expect(askodoxBizRoute('h1', 'orders.bookings'), '/biz/h1/bookings');
    expect(askodoxBizRoute('h1', 'money.monthly'), '/biz/h1/monthly');
    expect(askodoxKitFlows({'kit': {'flows': ['1', '4']}}), {'1', '4'});
  });
}
