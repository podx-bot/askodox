/// Owner 2026-11-23: the payment voice speaks the language of the region the person is in (from their location) when
/// they have not chosen one; the person's OWN choice always wins, and the voice follows whatever is chosen.
library;

/// Languages the payment voice speaks (the phone's sentence tables).
const askodoxVoiceLanguages = {'te', 'hi', 'en', 'ta', 'kn', 'ml', 'bn', 'mr', 'gu', 'pa', 'or', 'ur'};

/// A shop counter's voice (server settings) speaks these.
const askodoxShopVoiceLanguages = {'te', 'hi', 'en'};

/// State / union territory names (English and the state's own script, as phones name places) -> language.
const _regionLanguage = <String, String>{
  'andhra pradesh': 'te', 'ఆంధ్రప్రదేశ్': 'te', 'ఆంధ్ర ప్రదేశ్': 'te', 'telangana': 'te', 'తెలంగాణ': 'te',
  'karnataka': 'kn', 'ಕರ್ನಾಟಕ': 'kn',
  'tamil nadu': 'ta', 'தமிழ்நாடு': 'ta', 'puducherry': 'ta', 'pondicherry': 'ta',
  'kerala': 'ml', 'കേരളം': 'ml', 'lakshadweep': 'ml',
  'maharashtra': 'mr', 'महाराष्ट्र': 'mr',
  'gujarat': 'gu', 'ગુજરાત': 'gu', 'dadra': 'gu', 'daman': 'gu',
  'west bengal': 'bn', 'পশ্চিমবঙ্গ': 'bn', 'tripura': 'bn', 'ত্রিপুরা': 'bn',
  'odisha': 'or', 'orissa': 'or', 'ଓଡ଼ିଶା': 'or',
  'punjab': 'pa', 'ਪੰਜਾਬ': 'pa', 'chandigarh': 'pa',
  'jammu and kashmir': 'ur', 'jammu & kashmir': 'ur',
  'uttar pradesh': 'hi', 'उत्तर प्रदेश': 'hi', 'bihar': 'hi', 'बिहार': 'hi', 'madhya pradesh': 'hi', 'मध्य प्रदेश': 'hi',
  'rajasthan': 'hi', 'राजस्थान': 'hi', 'haryana': 'hi', 'हरियाणा': 'hi', 'delhi': 'hi', 'दिल्ली': 'hi',
  'himachal pradesh': 'hi', 'हिमाचल प्रदेश': 'hi', 'uttarakhand': 'hi', 'उत्तराखंड': 'hi', 'jharkhand': 'hi',
  'झारखंड': 'hi', 'chhattisgarh': 'hi', 'छत्तीसगढ़': 'hi', 'ladakh': 'hi',
};

/// The region's language from a place name ("Vuyyuru, Andhra Pradesh" -> te), or null when no Indian state is named.
String? askodoxRegionLanguage(String? place) {
  final text = (place ?? '').toLowerCase().trim();
  if (text.isEmpty) return null;
  // Longest name first ("west bengal" before a shorter name inside it).
  final keys = _regionLanguage.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (text.contains(k)) return _regionLanguage[k];
  }
  return null;
}

/// The voice language to start with: the person's own choice, else the region's language (location), else the phone's
/// language, else English -- always one of [allowed].
String askodoxSuggestedVoiceLanguage({String? chosen, String? place, String? device, Set<String> allowed = askodoxVoiceLanguages}) {
  for (final c in [chosen, askodoxRegionLanguage(place), device]) {
    if (c != null && allowed.contains(c)) return c;
  }
  return allowed.contains('en') ? 'en' : allowed.first;
}
