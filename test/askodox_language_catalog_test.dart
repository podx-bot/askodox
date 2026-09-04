import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/localization/askodox_language_catalog.dart';

void main() {
  test('ASKODOX exposes all 22 scheduled Indian languages plus English', () {
    expect(AskodoxLanguageCatalog.indianLanguages, hasLength(22));
    expect(AskodoxLanguageCatalog.all, hasLength(23));
  });

  test('ASKODOX language codes are unique', () {
    final codes = AskodoxLanguageCatalog.all.map((language) => language.code);
    expect(codes.toSet(), hasLength(AskodoxLanguageCatalog.all.length));
  });

  test('major ASKODOX India languages are available', () {
    for (final code in <String>['te', 'hi', 'ta', 'kn', 'ml', 'mr', 'bn', 'gu', 'pa', 'or', 'ur']) {
      expect(AskodoxLanguageCatalog.supports(code), isTrue, reason: code);
    }
  });

  test('unsupported language safely falls back to English', () {
    expect(AskodoxLanguageCatalog.normalize('xx'), 'en');
    expect(AskodoxLanguageCatalog.byCode('xx').name, 'English');
  });
}
