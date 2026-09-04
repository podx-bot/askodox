import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/presentation/home_screen.dart';

void main() {
  group('ASKODOX localized home greeting', () {
    test('uses the correct daypart boundaries', () {
      expect(askodoxGreetingForHour(4, 'en'), 'Good night 👋');
      expect(askodoxGreetingForHour(5, 'en'), 'Good morning 👋');
      expect(askodoxGreetingForHour(11, 'en'), 'Good morning 👋');
      expect(askodoxGreetingForHour(12, 'en'), 'Good afternoon 👋');
      expect(askodoxGreetingForHour(16, 'en'), 'Good afternoon 👋');
      expect(askodoxGreetingForHour(17, 'en'), 'Good evening 👋');
      expect(askodoxGreetingForHour(20, 'en'), 'Good evening 👋');
      expect(askodoxGreetingForHour(21, 'en'), 'Good night 👋');
    });

    test('keeps Telugu, Hindi and Odia greetings localized', () {
      expect(askodoxGreetingForHour(8, 'te'), 'శుభోదయం 👋');
      expect(askodoxGreetingForHour(14, 'hi'), 'शुभ दोपहर 👋');
      expect(askodoxGreetingForHour(18, 'or'), 'ଶୁଭ ସନ୍ଧ୍ୟା 👋');
    });

    test('falls back safely to English for unsupported languages', () {
      expect(askodoxGreetingForHour(8, 'fr'), 'Good morning 👋');
    });

    test('clamps invalid hour values safely', () {
      expect(askodoxGreetingForHour(-5, 'en'), 'Good night 👋');
      expect(askodoxGreetingForHour(30, 'en'), 'Good night 👋');
    });
  });
}
