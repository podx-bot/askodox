/// ONE language for the whole ASKODOX conversation (replies, result
/// headings, card actions, warnings) -- universal for every supported
/// language, never a Telugu-only rule.
///
/// * Preferred Language chosen in Settings -> always that language.
/// * Automatic -> the language the customer is actually using, detected
///   from the script of their messages, and kept (sticky) through results,
///   follow-ups, role changes, navigation and restarts. Short Latin replies
///   ("yes", "show me", "43 inch", brand names) never flip it to English;
///   only a real English sentence or an explicit request does.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/app_settings_provider.dart';

/// Unicode block -> language (the catalog's languages; a shared script maps
/// to its most common language unless the user picks another explicitly).
const _scripts = <(int, int, String)>[
  (0x0C00, 0x0C7F, 'te'),
  (0x0900, 0x097F, 'hi'),
  (0x0980, 0x09FF, 'bn'),
  (0x0A00, 0x0A7F, 'pa'),
  (0x0A80, 0x0AFF, 'gu'),
  (0x0B00, 0x0B7F, 'or'),
  (0x0B80, 0x0BFF, 'ta'),
  (0x0C80, 0x0CFF, 'kn'),
  (0x0D00, 0x0D7F, 'ml'),
  (0x0600, 0x06FF, 'ur'),
  (0xABC0, 0xABFF, 'mni'),
  (0x1C50, 0x1C7F, 'sat'),
];

/// The language a message is written in by script, or null for
/// Latin/digits-only text (English OR transliterated Indian languages).
String? askodoxScriptLanguage(String text) {
  final counts = <String, int>{};
  for (final rune in text.runes) {
    for (final (from, to, code) in _scripts) {
      if (rune >= from && rune <= to) {
        counts[code] = (counts[code] ?? 0) + 1;
        break;
      }
    }
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

final _explicitSwitch = <RegExp, String>{
  RegExp(r'\b(in|reply in|speak in|talk in|switch to)\s+english\b|\benglish\s*(lo|me|mein)\b', caseSensitive: false): 'en',
  RegExp(r'\b(in|reply in|speak in|switch to)\s+telugu\b|\btelugu\s*lo\b|తెలుగులో', caseSensitive: false): 'te',
  RegExp(r'\b(in|reply in|speak in|switch to)\s+hindi\b|\bhindi\s*(me|mein)\b|हिंदी में', caseSensitive: false): 'hi',
  RegExp(r'\b(in|reply in|speak in|switch to)\s+tamil\b|தமிழில்', caseSensitive: false): 'ta',
  RegExp(r'\b(in|reply in|speak in|switch to)\s+kannada\b|ಕನ್ನಡದಲ್ಲಿ', caseSensitive: false): 'kn',
  RegExp(r'\b(in|reply in|speak in|switch to)\s+odia\b|ଓଡ଼ିଆରେ', caseSensitive: false): 'or',
};

/// The conversation language after [message], given the [current] one.
String askodoxNextConversationLanguage({required String current, required String message}) {
  for (final entry in _explicitSwitch.entries) {
    if (entry.key.hasMatch(message)) return entry.value;
  }
  final script = askodoxScriptLanguage(message);
  if (script != null) return script;
  // Latin-only: a short answer, number, brand or command keeps the language;
  // a real English sentence (5+ words) means the customer switched.
  final words = message.trim().split(RegExp(r'\s+')).where((w) => RegExp(r'[A-Za-z]{2,}').hasMatch(w)).length;
  return words >= 5 ? 'en' : current;
}

class AskodoxConversationLanguage extends StateNotifier<String> {
  AskodoxConversationLanguage() : super('en') {
    _restore();
  }

  static const _key = 'askodox.conversation.language.v1';

  Future<void> _restore() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      if (saved != null && saved.isNotEmpty && mounted) state = saved;
    } catch (_) {}
  }

  /// Update from what the customer just said (Automatic mode only).
  Future<void> observe(String message) async {
    final next = askodoxNextConversationLanguage(current: state, message: message);
    if (next == state) return;
    state = next;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, next);
    } catch (_) {}
  }
}

final askodoxConversationLanguageProvider =
    StateNotifierProvider<AskodoxConversationLanguage, String>((ref) => AskodoxConversationLanguage());

/// The language ASKODOX answers in: an explicitly chosen Preferred Language
/// wins; otherwise (Automatic) the detected conversation language.
final askodoxReplyLanguageProvider = Provider<String>((ref) {
  final preferred = ref.watch(appSettingsProvider).locale?.languageCode;
  if (preferred != null && preferred.isNotEmpty) return preferred;
  return ref.watch(askodoxConversationLanguageProvider);
});

/// Dynamic chat labels in every language the app ships translations for
/// (en, te, hi, or -- the same set as the app's l10n). Other catalog
/// languages get these labels in English while ASKODOX's replies still
/// follow the customer's language.
String askodoxChatLabel(String key, String lang, {int count = 0}) {
  final table = _labels[lang] ?? _labels['en']!;
  final value = table[key] ?? _labels['en']![key] ?? key;
  return value.replaceAll('{n}', '$count');
}

const _labels = <String, Map<String, String>>{
  'en': {
    'found': 'Found {n} options',
    'found_pick': 'Found {n} options — pick one to continue',
    'no_local': 'No local match yet',
    'online': 'Online options',
    'refer': 'Know someone? Refer',
    'join': 'Seller or provider? Join ASKODOX',
    'send_request': 'Send request',
    'details': 'Details',
    'open': 'Open',
    'compare': 'Compare',
    'price_unverified': 'Price not verified',
  },
  'te': {
    'found': '{n} ఎంపికలు దొరికాయి',
    'found_pick': '{n} ఎంపికలు దొరికాయి — ఒకటి ఎంచుకోండి',
    'no_local': 'ఇంకా స్థానిక ఫలితం లేదు',
    'online': 'ఆన్‌లైన్ ఎంపికలు',
    'refer': 'ఎవరైనా తెలుసా? సూచించండి',
    'join': 'మీరు విక్రేత/ప్రొవైడరా? ASKODOXలో చేరండి',
    'send_request': 'అభ్యర్థన పంపండి',
    'details': 'వివరాలు',
    'open': 'తెరవండి',
    'compare': 'పోల్చండి',
    'price_unverified': 'ధర ధృవీకరించలేదు',
  },
  'hi': {
    'found': '{n} विकल्प मिले',
    'found_pick': '{n} विकल्प मिले — एक चुनें',
    'no_local': 'अभी कोई स्थानीय विकल्प नहीं',
    'online': 'ऑनलाइन विकल्प',
    'refer': 'किसी को जानते हैं? रेफ़र करें',
    'join': 'विक्रेता/सेवा प्रदाता हैं? ASKODOX से जुड़ें',
    'send_request': 'अनुरोध भेजें',
    'details': 'विवरण',
    'open': 'खोलें',
    'compare': 'तुलना करें',
    'price_unverified': 'कीमत सत्यापित नहीं',
  },
  'or': {
    'found': '{n}ଟି ବିକଳ୍ପ ମିଳିଲା',
    'found_pick': '{n}ଟି ବିକଳ୍ପ ମିଳିଲା — ଗୋଟିଏ ବାଛନ୍ତୁ',
    'no_local': 'ଏପର୍ଯ୍ୟନ୍ତ ସ୍ଥାନୀୟ ବିକଳ୍ପ ନାହିଁ',
    'online': 'ଅନଲାଇନ୍ ବିକଳ୍ପ',
    'refer': 'କାହାକୁ ଜାଣନ୍ତି? ରେଫର୍ କରନ୍ତୁ',
    'join': 'ବିକ୍ରେତା/ସେବା ପ୍ରଦାନକାରୀ? ASKODOXରେ ଯୋଗ ଦିଅନ୍ତୁ',
    'send_request': 'ଅନୁରୋଧ ପଠାନ୍ତୁ',
    'details': 'ବିବରଣୀ',
    'open': 'ଖୋଲନ୍ତୁ',
    'compare': 'ତୁଳନା କରନ୍ତୁ',
    'price_unverified': 'ମୂଲ୍ୟ ଯାଞ୍ଚ ହୋଇନାହିଁ',
  },
};
