import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/domain/voice_language.dart';

void main() {
  test('owner 2026-11-23: the region of the place picks the voice language', () {
    expect(askodoxRegionLanguage('Vuyyuru, Andhra Pradesh'), 'te');
    expect(askodoxRegionLanguage('Hyderabad, Telangana'), 'te');
    expect(askodoxRegionLanguage('విజయవాడ, ఆంధ్రప్రదేశ్'), 'te', reason: 'a Telugu phone names places in Telugu');
    expect(askodoxRegionLanguage('Chennai, Tamil Nadu'), 'ta');
    expect(askodoxRegionLanguage('Bengaluru, Karnataka'), 'kn');
    expect(askodoxRegionLanguage('Kochi, Kerala'), 'ml');
    expect(askodoxRegionLanguage('Kolkata, West Bengal'), 'bn');
    expect(askodoxRegionLanguage('Pune, Maharashtra'), 'mr');
    expect(askodoxRegionLanguage('Surat, Gujarat'), 'gu');
    expect(askodoxRegionLanguage('Ludhiana, Punjab'), 'pa');
    expect(askodoxRegionLanguage('Bhubaneswar, Odisha'), 'or');
    expect(askodoxRegionLanguage('Lucknow, Uttar Pradesh'), 'hi');
    expect(askodoxRegionLanguage('New Delhi, Delhi'), 'hi');
    expect(askodoxRegionLanguage('Current location'), isNull);
    expect(askodoxRegionLanguage(null), isNull);
  });

  test('the person\'s own choice always wins; then the region; then the phone; then English', () {
    expect(askodoxSuggestedVoiceLanguage(chosen: 'hi', place: 'Vuyyuru, Andhra Pradesh', device: 'en'), 'hi');
    expect(askodoxSuggestedVoiceLanguage(place: 'Vuyyuru, Andhra Pradesh', device: 'en'), 'te');
    expect(askodoxSuggestedVoiceLanguage(place: 'Current location', device: 'ta'), 'ta');
    expect(askodoxSuggestedVoiceLanguage(device: 'fr'), 'en');
  });

  test('a shop counter speaks te / hi / en only', () {
    expect(askodoxSuggestedVoiceLanguage(place: 'Chennai, Tamil Nadu', device: 'en', allowed: askodoxShopVoiceLanguages), 'en');
    expect(askodoxSuggestedVoiceLanguage(place: 'Guntur, Andhra Pradesh', allowed: askodoxShopVoiceLanguages), 'te');
  });
}
