import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/ui/mode_names.dart';

void main() {
  test('the two sides are My and My Biz', () {
    expect(askodoxSideName(seller: false), 'My');
    expect(askodoxSideName(seller: true), 'My Biz');
  });
  test('state line and screen-reader label follow the side and language', () {
    expect(askodoxSideStateName(seller: true, te: false), 'Business');
    expect(askodoxSideStateName(seller: false, te: true), 'వ్యక్తిగతం');
    expect(askodoxSwitchSemantics(seller: true, te: false), contains('My Biz'));
    expect(askodoxSwitchSemantics(seller: false, te: true), contains('My'));
  });
}
