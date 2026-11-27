import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/askodox_fonts.dart';

void main() {
  test('every fallback family is declared in pubspec with both weights and the files exist', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final family in askodoxFontFallback) {
      expect(pubspec, contains('- family: $family'), reason: family);
      for (final w in ['Regular', 'Bold']) {
        expect(pubspec, contains('assets/fonts/noto/$family-$w.ttf'), reason: '$family $w');
        expect(File('assets/fonts/noto/$family-$w.ttf').existsSync(), isTrue, reason: '$family $w file');
      }
    }
  });
}
