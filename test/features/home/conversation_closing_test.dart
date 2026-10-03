import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/conversation_closing.dart';

void main() {
  test('closing messages in many languages are sign-offs', () {
    for (final t in ['bye', 'Good night!', 'thanks, bye', 'ok thank you', "that's all, thanks", 'శుభరాత్రి',
      'సరే బై', 'धन्यवाद', 'adiós', 'bonne nuit', 'спасибо', 'gute Nacht']) {
      expect(askodoxIsSignOff(t), isTrue, reason: t);
    }
  });

  test('requests that merely contain a thank-you are not sign-offs', () {
    for (final t in ['thanks, now show me fridges', 'bye one get one offer', 'good night lamp price',
      'I need chicken', '', 'ok']) {
      expect(askodoxIsSignOff(t), isFalse, reason: t);
    }
  });
}
