/// Clear, neat letters in every Indian language (owner 2026-11-27: "whatever the font that is clearest and neatest
/// for each language, put that; everything must be clear, in all languages").
///
/// One Noto Sans family per script is bundled (assets/fonts/noto, SIL OFL). They are only FALLBACKS: a letter the
/// phone's own font draws well stays as it is, a letter it lacks (or draws as a box, as on the web) comes from here.
/// Scripts: Telugu; Devanagari (Hindi, Marathi, Nepali, Sanskrit, Konkani, Maithili, Dogri, Bodo); Bengali (Bengali,
/// Assamese); Gujarati; Kannada; Malayalam; Odia; Gurmukhi (Punjabi); Tamil; Arabic (Urdu, Sindhi, Kashmiri);
/// Ol Chiki (Santali); Meetei Mayek (Manipuri). A new language with a new script = add its family here AND in
/// pubspec.yaml (test/config/askodox_fonts_test.dart checks they match).
const askodoxFontFallback = <String>[
  'NotoSansTelugu',
  'NotoSansDevanagari',
  'NotoSansBengali',
  'NotoSansGujarati',
  'NotoSansKannada',
  'NotoSansMalayalam',
  'NotoSansOriya',
  'NotoSansGurmukhi',
  'NotoSansTamil',
  'NotoSansArabic',
  'NotoSansOlChiki',
  'NotoSansMeeteiMayek',
];
