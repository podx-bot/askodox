import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/automations/shop_automations_screen.dart';

void main() {
  test('quantities read like a person writes them', () {
    expect(askodoxQtyText(6000), '6');
    expect(askodoxQtyText(2500), '2.5');
    expect(askodoxQtyText(1250), '1.25');
    expect(askodoxQtyText(null), '0');
  });

  test('a win-back message is only ever a WhatsApp link the owner opens', () {
    expect(askodoxWinbackLink('+91 93000-02001', 'నమస్తే!').toString(),
        'https://wa.me/919300002001?text=${Uri.encodeComponent('నమస్తే!')}');
    expect(askodoxWinbackLink('12345', 'x'), isNull);
  });
}
