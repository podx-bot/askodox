import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/place_phrase.dart';
import 'package:podx/services/place_name_service.dart';

void main() {
  test('the real-phone duplicate "Vuyyuru, Andhra Pradeshలో in Vuyyuru, Andhra Pradesh" cannot be composed', () {
    const place = 'Vuyyuru, Andhra Pradesh';
    final te = askodoxWithPlace('grocery in Vuyyuru, Andhra Pradesh', place, 'te');
    expect(te, 'Vuyyuruలో grocery');
    expect(askodoxWithPlace('Vuyyuru, Andhra Pradeshలో grocery', place, 'te'), 'Vuyyuruలో grocery');
    expect(askodoxWithPlace('grocery', 'Vuyyuru, Andhra Pradeshలో', 'en'), 'grocery in Vuyyuru');
    expect(askodoxWithPlace('grocery', place, 'hi'), 'Vuyyuru में grocery');
    for (final text in [te, askodoxWithPlace('grocery in Vuyyuru', place, 'en')]) {
      expect(RegExp('Vuyyuru').allMatches(text).length, 1, reason: text);
      expect(text.contains('లో in') || text.contains('in Vuyyuru') && text.contains('లో'), isFalse, reason: text);
    }
  });

  test('clean / short place and label joins', () {
    expect(askodoxCleanPlace('in Vijayawada, Andhra Pradesh, India'), 'Vijayawada, Andhra Pradesh');
    expect(askodoxCleanPlace('Vijayawadaలో'), 'Vijayawada');
    expect(askodoxShortPlace('Vijayawada, Andhra Pradesh'), 'Vijayawada');
    expect(askodoxJoinPlace(['Vijayawada', 'Vijayawada, Andhra Pradesh 520001, India']), 'Vijayawada, Andhra Pradesh 520001');
    expect(askodoxJoinPlace(['Benz Circle', 'Vijayawada', 'Andhra Pradesh']), 'Benz Circle, Vijayawada, Andhra Pradesh');
    expect(askodoxWithoutPlace('toor dal', 'Vuyyuru'), 'toor dal');
  });
}
