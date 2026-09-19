import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/presentation/askodox_primary_home_screen.dart';

void main() {
  test('continuation reply advances to a concrete next action in English', () {
    final reply = askodoxContinuationReply(
      previousUserTurn: 'Plan my tasks for today',
      telugu: false,
    );

    expect(reply, contains('Plan my tasks for today'));
    expect(reply, contains('first unfinished item'));
    expect(reply, contains('Next step'));
  });

  test('continuation reply preserves Telugu context', () {
    final reply = askodoxContinuationReply(
      previousUserTurn: 'ఈ రోజు నా పనులు ప్లాన్ చేయి',
      telugu: true,
    );

    expect(reply, contains('ఈ రోజు నా పనులు ప్లాన్ చేయి'));
    expect(reply, contains('మొదటి పని'));
  });
}