import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/presentation/chat_bill_card.dart';

void main() {
  test('number bills are sent to the shop bill check; ordinary chat is not (owner 2026-11-19)', () {
    for (final text in ['bill 1 2, 3 1', 'బిల్ 1 రెండు', '#4 x3', '1x2, 3x1', '1 2, 3 1', 'బిల్లు 5']) {
      expect(askodoxLooksLikeNumberBill(text), isTrue, reason: text);
    }
    for (final text in ['5', 'I need 2 kg rice', 'price of iphone 17', 'hello', '', 'call me at 5 pm']) {
      expect(askodoxLooksLikeNumberBill(text), isFalse, reason: text);
    }
  });
}
