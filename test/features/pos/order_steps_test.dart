import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/application/chat_shop_cart.dart';
import 'package:podx/features/pos/domain/order_steps.dart';

void main() {
  final placed = DateTime(2026, 11, 17, 19, 5).toUtc().toIso8601String();
  final accepted = DateTime(2026, 11, 17, 19, 7).toUtc().toIso8601String();

  test('times are said in plain words, never as a raw timestamp', () {
    final now = DateTime(2026, 11, 17, 21);
    expect(askodoxClockWords(placed, true, now: now), 'రాత్రి 7:05');
    expect(askodoxClockWords(DateTime(2026, 11, 17, 17, 30).toIso8601String(), true, now: now), 'సాయంత్రం 5:30');
    expect(askodoxClockWords(placed, false, now: now), '7:05 pm');
    expect(askodoxClockWords(DateTime(2026, 11, 16, 9, 5).toIso8601String(), true, now: now), '16/11 ఉదయం 9:05');
    expect(askodoxClockWords('', true), '');
  });

  test('waiting for the shop: no pay link yet, the accept step is the one being waited on', () {
    final order = {
      'stage': 'placed',
      'flow': ['placed', 'accepted', 'preparing', 'ready', 'packed', 'handed', 'done'],
      'timeline': [
        {'stage': 'placed', 'at': placed, 'kind': 'step'}
      ],
      'pay': [
        {'upi_link': 'upi://pay?a=1'}
      ],
    };
    expect(askodoxOrderAwaitsShop(order), isTrue);
    expect(askodoxOrderPayLink(order), isNull);
    final steps = askodoxOrderSteps(order);
    expect(steps.first.state, AskodoxStepState.done);
    expect(steps[1].stage, 'accepted');
    expect(steps[1].state, AskodoxStepState.now);
    expect(steps.any((s) => s.stage == 'done'), isFalse);
  });

  test('every step once (a billed note on the same stage is not a second step) and ONE pay link', () {
    final order = {
      'stage': 'accepted',
      'flow': ['placed', 'accepted', 'preparing', 'ready', 'packed', 'handed', 'done'],
      'timeline': [
        {'stage': 'placed', 'at': placed, 'kind': 'step'},
        {'stage': 'accepted', 'at': accepted, 'kind': 'step'},
        {'stage': 'accepted', 'at': accepted, 'kind': 'note', 'note': 'billed MM/1'},
      ],
      'pay': [
        {'upi_link': 'upi://pay?a=1'},
        {'upi_link': 'upi://pay?a=2'},
      ],
    };
    final steps = askodoxOrderSteps(order);
    expect(steps.where((s) => s.stage == 'accepted').length, 1);
    expect(steps.firstWhere((s) => s.stage == 'preparing').state, AskodoxStepState.now);
    expect(askodoxOrderPayLink(order), 'upi://pay?a=1');
  });

  test('a heard sentence adds to the chat cart, removes, clears; other talk is left to the chat', () {
    var cart = askodoxApplyHeard({'a': 1}, {
      'add': [
        {'product_id': 'a', 'qty': 1},
        {'product_id': 'b', 'qty': 2},
      ]
    });
    expect(cart, {'a': 2, 'b': 2});
    cart = askodoxApplyHeard(cart, {'remove': ['a']});
    expect(cart, {'b': 2});
    expect(askodoxApplyHeard(cart, {'clear': true}), isEmpty);
    expect(askodoxHeardIsAboutMenu({'intent': 'unknown', 'add': [], 'remove': []}), isFalse);
    expect(askodoxHeardIsAboutMenu({'add': [{'product_id': 'a'}]}), isTrue);
  });
}
