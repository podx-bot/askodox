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

/// Very common function words of Indian languages typed in English letters
/// ("naku TV kavali", "mujhe AC chahiye"). Two or more distinct markers of
/// one language (and more than any other) mean the customer is using that
/// language -- universal table, not a per-language special case.
const _romanizedMarkers = <String, Set<String>>{
  'te': {'naku', 'nenu', 'kavali', 'kaavali', 'ekkada', 'enti', 'emiti', 'undi', 'ledu', 'cheppu', 'cheppandi',
         'kosam', 'entha', 'ela', 'ivvandi', 'chupinchu', 'dorukutundi', 'ikkada', 'meeru', 'manchi', 'unnaya',
         'kavalante', 'ayindi', 'chesi', 'cheyali', 'emaina'},
  'hi': {'mujhe', 'chahiye', 'kahan', 'kya', 'nahi', 'kitna', 'kitne', 'kaise', 'batao', 'dikhao', 'mera', 'meri',
         'aap', 'karo', 'hain', 'wala', 'wali', 'sasta', 'accha', 'kaha', 'milega', 'chahie'},
  'ta': {'enakku', 'venum', 'venam', 'enga', 'enna', 'irukku', 'illa', 'sollunga', 'evvalavu', 'kidaikkum'},
  'kn': {'nanage', 'beku', 'elli', 'yenu', 'ide', 'illa', 'heli', 'eshtu', 'sigutte'},
  'ml': {'enikku', 'venam', 'evide', 'entha', 'undo', 'illa', 'parayu', 'ethra', 'kittum'},
  'bn': {'amar', 'lagbe', 'kothay', 'ki', 'ache', 'nei', 'bolo', 'koto', 'pabo'},
};

String? askodoxRomanizedLanguage(String message) {
  final words = message.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty).toSet();
  String? best;
  var bestHits = 0;
  var tie = false;
  for (final entry in _romanizedMarkers.entries) {
    final hits = words.where(entry.value.contains).length;
    if (hits > bestHits) {
      best = entry.key;
      bestHits = hits;
      tie = false;
    } else if (hits == bestHits && hits > 0) {
      tie = true;
    }
  }
  return bestHits >= 2 && !tie ? best : null;
}

/// The conversation language after [message], given the [current] one.
String askodoxNextConversationLanguage({required String current, required String message}) {
  for (final entry in _explicitSwitch.entries) {
    if (entry.key.hasMatch(message)) return entry.value;
  }
  final script = askodoxScriptLanguage(message);
  if (script != null) return script;
  final romanized = askodoxRomanizedLanguage(message);
  if (romanized != null) return romanized;
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
    'partner': 'Partner stores',
    'attach_analyzing': 'Reading your attachment…',
    'attach_failed': 'The attachment could not be analyzed. It is still here -- try again.',
    'attach_unsupported': 'ASKODOX cannot read this file type yet. Send a photo, short video, PDF, Word, Excel, CSV or text file.',
    'attach_too_large': 'This file is too large. Please send a smaller one.',
    'attach_unavailable': 'Analysis for this type is not available right now; nothing was analyzed.',
    'attach_permission': 'Allow camera / photos access for ASKODOX in phone settings, then try again.',
    'attach_open_failed': 'The file could not be opened. Please try again.',
    'attach_limit': 'You can attach up to 4 files at a time.',
    'attach_not_understood': 'ASKODOX could not read anything useful from this file. Try a clearer photo -- for a scanned page, send a photo of it.',
    'attach_video_too_large': 'This video is too long to read here. Please send a shorter clip (under 30 seconds).',
    'retry': 'Retry',
    'cancel': 'Cancel',
    'offers': '{n} offer(s)',
    'up_to': 'up to',
    'terms': 'Terms',
    'get_coupon': 'Get coupon',
    'your_code': 'Your code',
    'min_purchase': 'Min purchase',
    'pay_with': 'Pay with',
    'expires': 'Valid till',
    'verified': 'Verified',
    'instant_discount': 'instant discount',
    'discount': 'off',
    'coupon': 'coupon',
    'cashback': 'cashback',
    'credit': 'ASKODOX credit',
    'gift': 'free',
    'reward': 'reward',
    'benefit': 'benefit',
    'sign_in_to_claim': 'Sign in to get this coupon.',
    'already_claimed': 'You already have this benefit.',
    'offer_unavailable': 'This offer is not available now.',
    'offers_note': 'Offers apply only if the conditions are met. Check the terms before paying.',
    'scratch_title': 'You unlocked a reward',
    'scratch_hint': 'Scratch or tap to reveal',
    'scratch_done': 'Added to your rewards',
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
    'partner': 'భాగస్వామి స్టోర్లు',
    'attach_analyzing': 'మీ అటాచ్‌మెంట్ చదువుతున్నాం…',
    'attach_failed': 'అటాచ్‌మెంట్‌ను విశ్లేషించలేకపోయాం. అది అలాగే ఉంది -- మళ్లీ ప్రయత్నించండి.',
    'attach_unsupported': 'ఈ ఫైల్ రకాన్ని ASKODOX ఇంకా చదవలేదు. ఫోటో, చిన్న వీడియో, PDF, Word, Excel, CSV లేదా టెక్స్ట్ పంపండి.',
    'attach_too_large': 'ఈ ఫైల్ చాలా పెద్దది. చిన్నది పంపండి.',
    'attach_unavailable': 'ఈ రకం విశ్లేషణ ప్రస్తుతం అందుబాటులో లేదు; ఏదీ విశ్లేషించలేదు.',
    'attach_permission': 'ఫోన్ సెట్టింగ్స్‌లో ASKODOXకి కెమెరా / ఫోటోల అనుమతి ఇవ్వండి, తర్వాత మళ్లీ ప్రయత్నించండి.',
    'attach_open_failed': 'ఫైల్ తెరవలేకపోయాం. మళ్లీ ప్రయత్నించండి.',
    'attach_limit': 'ఒకేసారి 4 ఫైల్స్ వరకు జత చేయవచ్చు.',
    'attach_not_understood': 'ఈ ఫైల్ నుండి ఉపయోగపడే సమాచారం చదవలేకపోయాం. స్పష్టమైన ఫోటో పంపండి -- స్కాన్ చేసిన పేజీ అయితే దాని ఫోటో పంపండి.',
    'attach_video_too_large': 'ఈ వీడియో చాలా పొడవుగా ఉంది. 30 సెకన్ల లోపు చిన్న క్లిప్ పంపండి.',
    'retry': 'మళ్లీ',
    'cancel': 'రద్దు',
    'offers': '{n} ఆఫర్(లు)',
    'up_to': 'గరిష్టం',
    'terms': 'నిబంధనలు',
    'get_coupon': 'కూపన్ పొందండి',
    'your_code': 'మీ కోడ్',
    'min_purchase': 'కనీస కొనుగోలు',
    'pay_with': 'చెల్లింపు',
    'expires': 'గడువు',
    'verified': 'ధృవీకరణ',
    'instant_discount': 'తక్షణ తగ్గింపు',
    'discount': 'తగ్గింపు',
    'coupon': 'కూపన్',
    'cashback': 'క్యాష్‌బ్యాక్',
    'credit': 'ASKODOX క్రెడిట్',
    'gift': 'ఉచితం',
    'reward': 'రివార్డ్',
    'benefit': 'ప్రయోజనం',
    'sign_in_to_claim': 'ఈ కూపన్ కోసం సైన్ ఇన్ చేయండి.',
    'already_claimed': 'ఈ ప్రయోజనం ఇప్పటికే మీకు ఉంది.',
    'offer_unavailable': 'ఈ ఆఫర్ ఇప్పుడు అందుబాటులో లేదు.',
    'offers_note': 'నిబంధనలు నెరవేరితేనే ఆఫర్లు వర్తిస్తాయి. చెల్లించే ముందు నిబంధనలు చూడండి.',
    'scratch_title': 'మీకు ఒక రివార్డ్ వచ్చింది',
    'scratch_hint': 'స్క్రాచ్ చేయండి లేదా తాకండి',
    'scratch_done': 'మీ రివార్డ్స్‌లో చేరింది',
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
    'partner': 'पार्टनर स्टोर',
    'attach_analyzing': 'आपका अटैचमेंट पढ़ रहे हैं…',
    'attach_failed': 'अटैचमेंट का विश्लेषण नहीं हो सका। वह अभी भी यहीं है -- फिर कोशिश करें।',
    'attach_unsupported': 'ASKODOX यह फ़ाइल प्रकार अभी नहीं पढ़ सकता। फ़ोटो, छोटा वीडियो, PDF, Word, Excel, CSV या टेक्स्ट भेजें।',
    'attach_too_large': 'यह फ़ाइल बहुत बड़ी है। छोटी फ़ाइल भेजें।',
    'attach_unavailable': 'इस प्रकार का विश्लेषण अभी उपलब्ध नहीं है; कुछ भी विश्लेषित नहीं हुआ।',
    'attach_permission': 'फ़ोन सेटिंग्स में ASKODOX को कैमरा / फ़ोटो अनुमति दें, फिर कोशिश करें।',
    'attach_open_failed': 'फ़ाइल नहीं खुल सकी। फिर कोशिश करें।',
    'attach_limit': 'एक बार में 4 फ़ाइलें तक जोड़ सकते हैं।',
    'attach_not_understood': 'इस फ़ाइल से काम की जानकारी नहीं पढ़ी जा सकी। साफ़ फ़ोटो भेजें -- स्कैन किए पेज की फ़ोटो भेजें।',
    'attach_video_too_large': 'यह वीडियो यहाँ पढ़ने के लिए बहुत लंबा है। 30 सेकंड से छोटी क्लिप भेजें।',
    'retry': 'फिर से',
    'cancel': 'रद्द करें',
    'offers': '{n} ऑफ़र',
    'up_to': 'अधिकतम',
    'terms': 'शर्तें',
    'get_coupon': 'कूपन लें',
    'your_code': 'आपका कोड',
    'min_purchase': 'न्यूनतम खरीद',
    'pay_with': 'भुगतान',
    'expires': 'मान्य तक',
    'verified': 'सत्यापित',
    'instant_discount': 'तुरंत छूट',
    'discount': 'छूट',
    'coupon': 'कूपन',
    'cashback': 'कैशबैक',
    'credit': 'ASKODOX क्रेडिट',
    'gift': 'मुफ़्त',
    'reward': 'इनाम',
    'benefit': 'लाभ',
    'sign_in_to_claim': 'यह कूपन पाने के लिए साइन इन करें।',
    'already_claimed': 'यह लाभ आपके पास पहले से है।',
    'offer_unavailable': 'यह ऑफ़र अभी उपलब्ध नहीं है।',
    'offers_note': 'ऑफ़र केवल शर्तें पूरी होने पर लागू होते हैं। भुगतान से पहले शर्तें देखें।',
    'scratch_title': 'आपको एक इनाम मिला',
    'scratch_hint': 'स्क्रैच करें या टैप करें',
    'scratch_done': 'आपके इनामों में जुड़ गया',
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
    'partner': 'ସହଯୋଗୀ ଷ୍ଟୋର୍',
    'attach_analyzing': 'ଆପଣଙ୍କ ଆଟାଚମେଣ୍ଟ ପଢୁଛୁ…',
    'attach_failed': 'ଆଟାଚମେଣ୍ଟ ବିଶ୍ଳେଷଣ ହୋଇପାରିଲା ନାହିଁ। ଏହା ଏଠାରେ ଅଛି -- ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।',
    'attach_unsupported': 'ASKODOX ଏହି ଫାଇଲ ପ୍ରକାର ଏବେ ପଢିପାରେ ନାହିଁ। ଫଟୋ, ଛୋଟ ଭିଡିଓ, PDF, Word, Excel, CSV କିମ୍ବା ଟେକ୍ସଟ ପଠାନ୍ତୁ।',
    'attach_too_large': 'ଏହି ଫାଇଲ ବହୁତ ବଡ। ଛୋଟ ଫାଇଲ ପଠାନ୍ତୁ।',
    'attach_unavailable': 'ଏହି ପ୍ରକାରର ବିଶ୍ଳେଷଣ ଏବେ ଉପଲବ୍ଧ ନାହିଁ; କିଛି ବିଶ୍ଳେଷଣ ହୋଇନାହିଁ।',
    'attach_permission': 'ଫୋନ ସେଟିଂସରେ ASKODOX କୁ କ୍ୟାମେରା / ଫଟୋ ଅନୁମତି ଦିଅନ୍ତୁ, ତାପରେ ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।',
    'attach_open_failed': 'ଫାଇଲ ଖୋଲିପାରିଲା ନାହିଁ। ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।',
    'attach_limit': 'ଥରକେ 4ଟି ଫାଇଲ ପର୍ଯ୍ୟନ୍ତ ଯୋଡିପାରିବେ।',
    'attach_not_understood': 'ଏହି ଫାଇଲରୁ କାମର ତଥ୍ୟ ପଢିହେଲା ନାହିଁ। ସ୍ପଷ୍ଟ ଫଟୋ କିମ୍ବା ଅନ୍ୟ ଫାଇଲ ପଠାନ୍ତୁ।',
    'attach_video_too_large': 'ଏହି ଭିଡିଓ ବହୁତ ଲମ୍ବା। 30 ସେକେଣ୍ଡରୁ କମ ଛୋଟ କ୍ଲିପ ପଠାନ୍ତୁ।',
    'retry': 'ପୁଣି',
    'cancel': 'ବାତିଲ',
    'offers': '{n}ଟି ଅଫର୍',
    'up_to': 'ସର୍ବାଧିକ',
    'terms': 'ସର୍ତ୍ତାବଳୀ',
    'get_coupon': 'କୁପନ୍ ନିଅନ୍ତୁ',
    'your_code': 'ଆପଣଙ୍କ କୋଡ୍',
    'min_purchase': 'ସର୍ବନିମ୍ନ କ୍ରୟ',
    'pay_with': 'ଦେୟ',
    'expires': 'ବୈଧ ପର୍ଯ୍ୟନ୍ତ',
    'verified': 'ଯାଞ୍ଚିତ',
    'instant_discount': 'ତୁରନ୍ତ ରିହାତି',
    'discount': 'ରିହାତି',
    'coupon': 'କୁପନ୍',
    'cashback': 'କ୍ୟାସବ୍ୟାକ୍',
    'credit': 'ASKODOX କ୍ରେଡିଟ୍',
    'gift': 'ମାଗଣା',
    'reward': 'ପୁରସ୍କାର',
    'benefit': 'ଲାଭ',
    'sign_in_to_claim': 'ଏହି କୁପନ୍ ପାଇଁ ସାଇନ୍ ଇନ୍ କରନ୍ତୁ।',
    'already_claimed': 'ଏହି ଲାଭ ଆପଣଙ୍କ ପାଖରେ ଅଛି।',
    'offer_unavailable': 'ଏହି ଅଫର୍ ଏବେ ଉପଲବ୍ଧ ନାହିଁ।',
    'offers_note': 'ସର୍ତ୍ତ ପୂରଣ ହେଲେ ହିଁ ଅଫର୍ ଲାଗୁ ହୁଏ। ଦେୟ ପୂର୍ବରୁ ସର୍ତ୍ତାବଳୀ ଦେଖନ୍ତୁ।',
    'scratch_title': 'ଆପଣ ଏକ ପୁରସ୍କାର ପାଇଲେ',
    'scratch_hint': 'ସ୍କ୍ରାଚ୍ କରନ୍ତୁ କିମ୍ବା ଛୁଅନ୍ତୁ',
    'scratch_done': 'ଆପଣଙ୍କ ପୁରସ୍କାରରେ ଯୋଡାଗଲା',
  },
};
