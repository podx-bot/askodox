import 'package:flutter/material.dart';

@immutable
class AskodoxLanguage {
  const AskodoxLanguage({required this.code, required this.name});

  final String code;
  final String name;

  Locale get locale => Locale(code);
}

/// Central ASKODOX language catalog.
///
/// The India list follows the 22 languages in the Eighth Schedule of the
/// Constitution of India. English is kept as the global/default fallback.
class AskodoxLanguageCatalog {
  const AskodoxLanguageCatalog._();

  static const english = AskodoxLanguage(code: 'en', name: 'English');

  static const indianLanguages = <AskodoxLanguage>[
    AskodoxLanguage(code: 'as', name: 'Assamese'),
    AskodoxLanguage(code: 'bn', name: 'Bengali'),
    AskodoxLanguage(code: 'brx', name: 'Bodo'),
    AskodoxLanguage(code: 'doi', name: 'Dogri'),
    AskodoxLanguage(code: 'gu', name: 'Gujarati'),
    AskodoxLanguage(code: 'hi', name: 'Hindi'),
    AskodoxLanguage(code: 'kn', name: 'Kannada'),
    AskodoxLanguage(code: 'ks', name: 'Kashmiri'),
    AskodoxLanguage(code: 'kok', name: 'Konkani'),
    AskodoxLanguage(code: 'mai', name: 'Maithili'),
    AskodoxLanguage(code: 'ml', name: 'Malayalam'),
    AskodoxLanguage(code: 'mni', name: 'Manipuri'),
    AskodoxLanguage(code: 'mr', name: 'Marathi'),
    AskodoxLanguage(code: 'ne', name: 'Nepali'),
    AskodoxLanguage(code: 'or', name: 'Odia'),
    AskodoxLanguage(code: 'pa', name: 'Punjabi'),
    AskodoxLanguage(code: 'sa', name: 'Sanskrit'),
    AskodoxLanguage(code: 'sat', name: 'Santali'),
    AskodoxLanguage(code: 'sd', name: 'Sindhi'),
    AskodoxLanguage(code: 'ta', name: 'Tamil'),
    AskodoxLanguage(code: 'te', name: 'Telugu'),
    AskodoxLanguage(code: 'ur', name: 'Urdu'),
  ];

  static const all = <AskodoxLanguage>[
    english,
    ...indianLanguages,
  ];

  static final Set<String> supportedCodes =
      all.map((language) => language.code).toSet();

  static bool supports(String? code) =>
      code != null && supportedCodes.contains(code.trim().toLowerCase());

  static String normalize(String? code) {
    final normalized = code?.trim().toLowerCase();
    return supports(normalized) ? normalized! : english.code;
  }

  static AskodoxLanguage byCode(String? code) {
    final normalized = normalize(code);
    return all.firstWhere((language) => language.code == normalized);
  }
}
