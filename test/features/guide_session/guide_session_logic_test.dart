import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/guide_session/guide_session_logic.dart';

void main() {
  test('time-up only after the minutes given', () {
    final t = DateTime(2026, 11, 26, 10);
    expect(askodoxGuideTimeUp(t, 10, t.add(const Duration(minutes: 9))), isFalse);
    expect(askodoxGuideTimeUp(t, 10, t.add(const Duration(minutes: 10))), isTrue);
  });
  test('labels and keys', () {
    expect(askodoxGuideMinutesLabel(60, te: false), '1 hour');
    expect(askodoxGuideMinutesLabel(10, te: true), '10 నిమిషాలు');
    expect(askodoxGuideKeys(['who', {'key': 'work'}, 3]), ['who', 'work']);
    expect(askodoxGuideTopicName('menu', te: false), 'Items and prices');
  });
  test('reminder needs a ref and an app route', () {
    expect(AskodoxGuideReminder.from({'ref': 'a', 'route': '/guide-session', 'text': 'x'}), isNotNull);
    expect(AskodoxGuideReminder.from({'ref': 'a', 'route': 'https://x'}), isNull);
  });
  test('why points promise deletion and no selling', () {
    expect(askodoxGuideWhyPoints(te: false).join(' '), contains('deleted'));
    expect(askodoxGuideWhyPoints(te: false).join(' '), contains('never given or sold'));
  });
}
