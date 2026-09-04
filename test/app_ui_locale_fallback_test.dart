import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/app.dart';

void main() {
  const generatedLocales = <Locale>[
    Locale('en'),
    Locale('te'),
    Locale('hi'),
    Locale('or'),
  ];

  test('supported generated ASKODOX UI locale is preserved', () {
    expect(
      askodoxUiLocale(const Locale('te'), generatedLocales).languageCode,
      'te',
    );
  });

  test('catalog-only ASKODOX language safely falls back to English UI', () {
    expect(
      askodoxUiLocale(const Locale('ta'), generatedLocales).languageCode,
      'en',
    );
  });

  test('unknown ASKODOX UI locale safely falls back to English', () {
    expect(
      askodoxUiLocale(const Locale('xx'), generatedLocales).languageCode,
      'en',
    );
  });
}
