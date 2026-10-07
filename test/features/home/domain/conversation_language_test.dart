import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/conversation_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('script detection works for every supported script, not only Telugu', () {
    expect(askodoxScriptLanguage('నాకు TV కావాలి'), 'te');
    expect(askodoxScriptLanguage('मुझे टीवी चाहिए'), 'hi');
    expect(askodoxScriptLanguage('எனக்கு டிவி வேண்டும்'), 'ta');
    expect(askodoxScriptLanguage('ನನಗೆ ಟಿವಿ ಬೇಕು'), 'kn');
    expect(askodoxScriptLanguage('എനിക്ക് ടിവി വേണം'), 'ml');
    expect(askodoxScriptLanguage('আমার টিভি চাই'), 'bn');
    expect(askodoxScriptLanguage('ମୋତେ ଟିଭି ଦରକାର'), 'or');
    expect(askodoxScriptLanguage('I want a TV'), isNull);
  });

  test('sticky: short Latin replies keep the language; a real English sentence or an explicit ask switches', () {
    String next(String current, String msg) => askodoxNextConversationLanguage(current: current, message: msg);
    expect(next('te', 'yes'), 'te');
    expect(next('te', 'show me'), 'te');
    expect(next('te', '43 inch Samsung'), 'te');
    expect(next('te', 'I would like to see cheaper options please'), 'en');
    expect(next('te', 'reply in English'), 'en');
    expect(next('en', 'telugu lo cheppu'), 'te');
    expect(next('en', 'हिंदी में बताओ'), 'hi');
  });

  test('labels exist for every app language and fall back to English for others', () {
    for (final lang in ['en', 'te', 'hi', 'or']) {
      for (final key in ['found', 'no_local', 'online', 'refer', 'join', 'send_request', 'details', 'open', 'compare']) {
        expect(askodoxChatLabel(key, lang), isNot(key), reason: '$lang/$key');
      }
    }
    expect(askodoxChatLabel('found', 'te', count: 3), contains('3'));
    expect(askodoxChatLabel('open', 'ta'), 'Open');
  });

  test('the conversation language survives an app restart', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    await c.read(askodoxConversationLanguageProvider.notifier).observe('నాకు TV కావాలి');
    expect(c.read(askodoxReplyLanguageProvider), 'te');
    c.dispose();
    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    restarted.read(askodoxConversationLanguageProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(restarted.read(askodoxReplyLanguageProvider), 'te');
  });

  test('Section 15: short replies never reset the language; romanized Indian languages are recognised', () {
    for (final short in ['yes', 'ok', 'go', '?', '? ', 'Sony', '43 inch', 'show me', 'order it']) {
      expect(askodoxNextConversationLanguage(current: 'te', message: short), 'te', reason: short);
      expect(askodoxNextConversationLanguage(current: 'hi', message: short), 'hi', reason: short);
    }
    expect(askodoxNextConversationLanguage(current: 'en', message: 'naku 43 inch TV kavali ekkada dorukutundi'), 'te');
    expect(askodoxNextConversationLanguage(current: 'en', message: 'mujhe AC service chahiye kahan milega'), 'hi');
    expect(askodoxNextConversationLanguage(current: 'te', message: '? telugu lo'), 'te');
    expect(askodoxNextConversationLanguage(current: 'te', message: 'Can you please show me the cheapest options nearby'), 'en',
        reason: 'a real English sentence still switches');
    expect(askodoxNextConversationLanguage(current: 'en', message: 'I need a good AC mechanic near me today'), 'en',
        reason: 'plain English is never mistaken for a romanized language');
    expect(askodoxRomanizedLanguage('kya'), isNull, reason: 'one marker is not enough');
  });
  test('explicit Telugu lock survives bad English STT until explicitly released', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(askodoxConversationLanguageProvider.notifier);

    await notifier.observe('telugu lo chapandi lock');
    expect(c.read(askodoxLanguageLockProvider), 'te');
    expect(c.read(askodoxReplyLanguageProvider), 'te');

    await notifier.observe('This is a long English speech recognition mistake from the microphone');
    expect(c.read(askodoxReplyLanguageProvider), 'te');

    await notifier.observe('reply in English');
    expect(c.read(askodoxLanguageLockProvider), 'en');
    expect(c.read(askodoxReplyLanguageProvider), 'en');

    await notifier.observe('back to automatic');
    expect(c.read(askodoxLanguageLockProvider), isNull);
  });

  test('Tenglish request is treated as explicit Telugu-family conversation preference', () {
    expect(askodoxExplicitLanguageSwitch('tenglish lo matladandi'), 'te');
    expect(askodoxExplicitLanguageSwitch('telugu english mix lo cheppu'), 'te');
  });
}
