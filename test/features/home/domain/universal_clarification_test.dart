import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/need_clarification.dart';

void main() {
  test('AI clarification works for any category and resolves by number, label or distinctive word', () {
    final c = askodoxDynamicClarification(
      question: 'Do you mean a guitar amplifier or a car audio amplifier?',
      options: ['guitar amplifier', 'car audio amplifier'],
    )!;
    expect(c.question, contains('guitar'));
    expect(askodoxResolveClarification(c, '2')?.subject, 'car audio amplifier');
    expect(askodoxResolveClarification(c, 'the guitar one')?.subject, 'guitar amplifier');
    expect(askodoxResolveClarification(c, 'car audio amplifier')?.subject, 'car audio amplifier');
    // Restored after an app restart from its key alone.
    expect(askodoxClarificationByKey(c.key)?.options.map((o) => o.subject), ['guitar amplifier', 'car audio amplifier']);
  });

  test('no question without at least two real options', () {
    expect(askodoxDynamicClarification(options: const []), isNull);
    expect(askodoxDynamicClarification(options: const ['only one']), isNull);
  });

  test('offline fallback rules still clarify when the AI is unavailable', () {
    expect(askodoxClarificationFor('I need tablets'), isNotNull);
    expect(askodoxClarificationFor('I need a samsung tablet'), isNull);
  });
}
