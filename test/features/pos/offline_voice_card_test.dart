import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/presentation/offline_voice_card.dart';

void main() {
  test('offline voice line follows the phone engine answer, for any chosen language (owner 2026-11-17)', () {
    expect(askodoxOfflineVoiceLabel({'ready': true, 'offline': true}).$2, contains('నెట్ లేకపోయినా'));
    expect(askodoxOfflineVoiceLabel({'ready': true, 'supported': true, 'installed': false, 'offline': false}).$2,
        contains('డౌన్‌లోడ్'));
    expect(askodoxOfflineVoiceLabel({'ready': true, 'supported': false}).$1, contains('English'));
  });
}
