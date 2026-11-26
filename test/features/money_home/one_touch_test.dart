import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/money_home/one_touch.dart';

void main() {
  group('askodoxReorderOf (మళ్ళీ అదే)', () {
    test('latest finished order becomes the desk link with the same cart', () {
      final out = askodoxReorderOf([
        {'stage': 'placed', 'business_id': 'biz_running1', 'items': [{'product_id': 'p9', 'qty': 1, 'price_paise': 100}]},
        {
          'stage': 'done',
          'kind': 'dine_in',
          'business_id': 'biz_abc123',
          'business_name': 'Sri Biryani',
          'items': [
            {'product_id': 'p1', 'qty': 2.0, 'price_paise': 18000},
            {'product_id': 'p2', 'qty': 0.5, 'price_paise': 40000},
            {'product_id': 'p3', 'qty': 1, 'price_paise': 5000, 'status': 'unavailable'},
          ],
        },
      ]);
      expect(out, isNotNull);
      expect(out!.shop, 'Sri Biryani');
      expect(out.items, 2);
      expect(out.estimatePaise, 2 * 18000 + 20000);
      // dine-in comes back as takeaway; whole quantities without ".0"
      expect(out.route, '/order-desk?code=biz_abc123&kind=takeaway&cart=${Uri.encodeQueryComponent('p1:2,p2:0.5')}');
    });

    test('delivery stays delivery', () {
      final out = askodoxReorderOf([
        {'stage': 'delivered', 'kind': 'delivery', 'business_id': 'biz_x12345', 'items': [{'product_id': 'a', 'qty': 1}]},
      ]);
      expect(out!.route, contains('kind=delivery'));
    });

    test('nothing finished or nothing available = no chip', () {
      expect(askodoxReorderOf([]), isNull);
      expect(askodoxReorderOf([{'stage': 'cancelled', 'business_id': 'biz_x12345', 'items': [{'product_id': 'a', 'qty': 1}]}]), isNull);
      expect(
          askodoxReorderOf([
            {'stage': 'done', 'business_id': 'biz_x12345', 'items': [{'product_id': 'a', 'qty': 1, 'status': 'unavailable'}]},
          ]),
          isNull);
    });
  });

  test('habit card -> the same cart link; a card without anything to order gives no chip', () {
    final habit = askodoxHabitOf([
      {'kind': 'other'},
      {
        'kind': 'habit',
        'ref': 'biz_abc123',
        'times': 4,
        'order': {
          'stage': 'done',
          'kind': 'takeaway',
          'business_id': 'biz_abc123',
          'business_name': 'Murali Kirana',
          'items': [{'product_id': 'p1', 'qty': 2, 'price_paise': 3000}],
        },
      },
    ]);
    expect(habit, isNotNull);
    expect(habit!.shop, 'Murali Kirana');
    expect(habit.ref, 'biz_abc123');
    expect(habit.times, 4);
    expect(habit.route, '/order-desk?code=biz_abc123&kind=takeaway&cart=${Uri.encodeQueryComponent('p1:2')}');
    expect(askodoxHabitOf([]), isNull);
    expect(
        askodoxHabitOf([
          {'kind': 'habit', 'ref': 'b', 'order': {'stage': 'done', 'business_id': 'biz_x12345', 'items': []}},
        ]),
        isNull);
  });

  test('today spoken: numbers first, zero parts left out', () {
    final hub = {
      'sales': {'paise': 1250000},
      'dues': {'paise': 0},
      'orders': {'new': 3},
    };
    final te = askodoxTodaySpoken(hub, true);
    expect(te, contains('ఈ రోజు అమ్మకం'));
    expect(te, contains('కొత్త ఆర్డర్లు 3'));
    expect(te, isNot(contains('బాకీ')));
    expect(askodoxTodaySpoken(hub, false), startsWith("Today's sales"));
  });

  test('shop switch: open <-> break, closed opens', () {
    expect(askodoxNextShopStatus('open'), 'paused');
    expect(askodoxNextShopStatus(''), 'paused');
    expect(askodoxNextShopStatus('paused'), 'open');
    expect(askodoxNextShopStatus('closed'), 'open');
  });
}
