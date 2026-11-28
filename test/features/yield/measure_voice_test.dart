import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/yield/yield_extras.dart';

void main() {
  test('spoken measure to grams', () {
    expect(askodoxMeasureGrams('250 grams'), 250);
    expect(askodoxMeasureGrams('250'), 250);
    expect(askodoxMeasureGrams('0.25 kg'), 250);
    expect(askodoxMeasureGrams('1.5 కేజీ'), 1500);
    expect(askodoxMeasureGrams('అర కేజీ'), 500);
    expect(askodoxMeasureGrams('half kilo'), 500);
    expect(askodoxMeasureGrams('hello'), 0);
  });
}
