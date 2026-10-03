import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/conversation_language.dart';

void main() {
  test('short replies (yes / ok / all / ? / nearby / show me / this one) never reset te or hi to English', () {
    for (final current in ['te', 'hi']) {
      for (final reply in ['yes', 'ok', 'all', '?', 'nearby', 'show me', 'this one', 'no', 'All.', 'Tata']) {
        expect(askodoxNextConversationLanguage(current: current, message: reply), current, reason: '$current "$reply"');
      }
    }
    expect(askodoxNextConversationLanguage(current: 'te', message: 'అన్నీ'), 'te');
    expect(askodoxNextConversationLanguage(current: 'hi', message: 'सब'), 'hi');
    expect(askodoxNextConversationLanguage(current: 'te', message: 'I want to see all grocery items in my shop'), 'en',
        reason: 'a full English sentence is a real switch');
  });
}
