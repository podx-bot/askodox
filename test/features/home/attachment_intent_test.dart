import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/attachment_intent.dart';

void main() {
  test('attachments sent to be understood do not trigger a search', () {
    for (final text in ['', 'what is this?', 'ఇది ఏమిటి?', 'explain this', 'is this ok?']) {
      expect(askodoxAttachmentWantsAction(text), isFalse, reason: text);
    }
    for (final text in ['where can I buy this nearby', 'price of this', 'repair this', 'sell this', 'show me']) {
      expect(askodoxAttachmentWantsAction(text), isTrue, reason: text);
    }
  });

  test('guidance is honest about uncertainty and failures', () {
    final g = askodoxAttachmentGuidance(lowConfidence: true, failed: ['a.jpg']);
    expect(g, contains('Do not list sellers'));
    expect(g, contains('NOT confident'));
    expect(g, contains('a.jpg'));
    expect(askodoxAttachmentGuidance(), isNot(contains('NOT confident')));
  });

  test('referral / join prompts only when the customer talks about it', () {
    expect(askodoxAllowsGrowthPrompt('I want to buy a mixer grinder'), isFalse);
    expect(askodoxAllowsGrowthPrompt('I need a plumber'), isFalse);
    expect(askodoxAllowsGrowthPrompt('I can refer a plumber'), isTrue);
    expect(askodoxAllowsGrowthPrompt('I am a seller, how do I join'), isTrue);
  });
}
