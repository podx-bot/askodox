import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/guide/guide_sheet.dart';

void main() {
  test('"not understood" is heard in Telugu, Hindi and English', () {
    for (final s in ['అర్థం కాలేదు', 'నాకు అర్ధం కాలేదు', 'samajh nahi aaya', 'समझ नहीं आया', "I didn't understand", 'not understand', 'confusing']) {
      expect(askodoxSaysNotUnderstood(s), isTrue, reason: s);
    }
    for (final s in ['పావు కిలో ధర ఎలా పెట్టాలి?', 'how do I add staff', 'అర్థమైంది']) {
      expect(askodoxSaysNotUnderstood(s), isFalse, reason: s);
    }
  });

  test('ladder: simpler words, then shown on the screen, then "say it, I do it"', () {
    expect(askodoxGuideNextRung(1, hasWalkthrough: true), 1);
    expect(askodoxGuideNextRung(2, hasWalkthrough: true), 2);
    expect(askodoxGuideNextRung(2, hasWalkthrough: false), 3, reason: 'no walkthrough for this page: go straight to "say it"');
    expect(askodoxGuideNextRung(3, hasWalkthrough: true), 3);
  });
}
