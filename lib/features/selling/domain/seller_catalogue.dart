import '../../home/domain/active_role.dart';
import '../data/catalogue_repository.dart';

/// Which ready-made catalogue a seller's words point to (grocery, fruits &
/// vegetables, fashion), in English / Telugu / Hindi. Null = none named.
String? askodoxCatalogueTemplateFor(String message) {
  final text = message.toLowerCase();
  bool has(String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(text);
  if (has(r'grocer|kirana|provision|general store|కిరాణా|కిరాణ|సరుకులు|किराना|राशन|परचून')) return 'grocery';
  if (has(r'vegetable|fruit|కూరగాయ|పండ్ల|పండ్లు|सब्ज़ी|सब्जी|फल')) return 'fruits_vegetables';
  if (has(r'fashion|cloth|garment|textile|apparel|saree|dress|ready-?made (garments?|clothes|dress)|బట్టలు|దుస్తులు|చీర|कपड़े|कपड़ा|साड़ी|फ़ैशन')) {
    return 'fashion';
  }
  return null;
}

/// A seller's request for a catalogue ("Do you have a ready-made grocery
/// catalogue?", "కిరాణా కేటలాగ్ ఉందా?", "मेरी दुकान के लिए कैटलॉग"):
/// * acting as Seller/Provider -> a shop cue or a catalogue category is
///   enough (their words describe what THEY offer);
/// * otherwise only an explicit shop/catalogue cue with a seller word.
bool askodoxWantsSellerCatalogue(String message, AskodoxUserRole active) {
  final shop = askodoxSellerShopCue(message);
  final catalogueWord = RegExp(r'catalog|కేటలాగ్|కాటలాగ్|క్యాటలాగ్|कैटलॉग|template', caseSensitive: false)
      .hasMatch(message);
  if (askodoxActsAsSupplier(active, message)) {
    return shop || catalogueWord || (askodoxCatalogueTemplateFor(message) != null && _shortTopic(message));
  }
  final sellerWords = RegExp(r'\b(my (shop|store)|i sell|to sell|seller)\b|నా (షాప్|దుకాణం)|అమ్ము|मेरी दुकान|बेच',
          caseSensitive: false)
      .hasMatch(message);
  return catalogueWord && sellerWords;
}

/// "grocery" / "fashion" said alone (or nearly) by a seller names their
/// line of business -- a longer sentence is left to the normal flow.
bool _shortTopic(String message) => message.trim().split(RegExp(r'\s+')).length <= 6;

/// A short reply while a catalogue is open.
enum AskodoxCatalogueReply { all, yes, no }

AskodoxCatalogueReply? askodoxCatalogueReply(String message) {
  final text = message.trim().toLowerCase().replaceAll(RegExp(r'[.!?।]+$'), '');
  if (RegExp(r'^(all|all of them|everything|select all|all categories|అన్నీ|అన్ని|అన్నీ కావాలి|సబ్|सब|सभी|सब कुछ)$')
      .hasMatch(text)) {
    return AskodoxCatalogueReply.all;
  }
  if (RegExp(r'^(yes|yeah|ok|okay|sure|go ahead|continue|next|అవును|సరే|ఓకే|హా|हाँ|हां|ठीक है|ओके)$').hasMatch(text)) {
    return AskodoxCatalogueReply.yes;
  }
  if (RegExp(r'^(no|not now|cancel|later|వద్దు|కాదు|नहीं|रहने दो)$').hasMatch(text)) {
    return AskodoxCatalogueReply.no;
  }
  return null;
}

String _pick(String lang, {required String en, required String te, required String hi}) =>
    switch (lang) { 'te' => te, 'hi' => hi, _ => en };

String askodoxCatalogueOfferReply(AskodoxCatalogueTemplate t, String lang) {
  final name = t.name(lang);
  final n = t.categories.length, m = t.itemCount;
  return _pick(lang,
      en: 'Yes -- a ready-made $name catalogue: $n categories, $m common items (no brands, no prices). '
          'Pick the categories you sell, or say "all". Then you set YOUR price, size and stock for each item, '
          'add photos if you like, check your shop details and publish.',
      te: 'అవును -- రెడీమేడ్ $name కేటలాగ్ ఉంది: $n విభాగాలు, $m సాధారణ వస్తువులు (బ్రాండ్లు, ధరలు లేవు). '
          'మీరు అమ్మే విభాగాలు ఎంచుకోండి, లేదా "అన్నీ" అని చెప్పండి. తర్వాత ప్రతి వస్తువుకు మీ ధర, సైజు, స్టాక్ పెట్టి, '
          'కావాలంటే ఫోటోలు జత చేసి, షాప్ వివరాలు చూసి ప్రచురించండి.',
      hi: 'हाँ -- तैयार $name कैटलॉग है: $n श्रेणियाँ, $m आम आइटम (बिना ब्रांड, बिना दाम)। '
          'जो श्रेणियाँ आप बेचते हैं चुनें, या "सब" कहें। फिर हर आइटम का अपना दाम, साइज़ और स्टॉक डालें, '
          'चाहें तो फ़ोटो जोड़ें, दुकान की जानकारी जाँचें और प्रकाशित करें।');
}

String askodoxCatalogueSelectedReply(AskodoxCatalogueTemplate t, Set<String> selected, String lang) {
  final cats = t.categories.where((c) => selected.contains(c.key)).toList();
  final items = cats.fold(0, (s, c) => s + c.items.length);
  final names = cats.map((c) => c.name(lang)).join(', ');
  return _pick(lang,
      en: '${cats.length} categories selected ($items items): $names. Set your prices -- items without a price stay as drafts.',
      te: '${cats.length} విభాగాలు ఎంచుకున్నారు ($items వస్తువులు): $names. మీ ధరలు పెట్టండి -- ధర లేనివి డ్రాఫ్ట్‌లుగా ఉంటాయి.',
      hi: '${cats.length} श्रेणियाँ चुनी गईं ($items आइटम): $names। अपने दाम डालें -- बिना दाम वाले ड्राफ़्ट में रहेंगे।');
}

String askodoxCatalogueNoTemplateReply(List<String> available, String lang, {required bool asked}) {
  final list = available.join(', ');
  return _pick(lang,
      en: '${asked ? 'There is no ready-made catalogue for this category yet' : 'Which catalogue do you need?'} '
          'Ready-made: $list. For anything else I can build your catalogue from a photo of your products or your '
          'price list (PDF/photo) -- tap the attach button -- or type items like "Toor dal 1 kg ₹160".',
      te: '${asked ? 'ఈ విభాగానికి రెడీమేడ్ కేటలాగ్ ఇంకా లేదు' : 'ఏ కేటలాగ్ కావాలి?'} '
          'రెడీమేడ్: $list. వేరే వాటికి, మీ వస్తువుల ఫోటో లేదా ధరల జాబితా (PDF/ఫోటో) తో మీ కేటలాగ్ తయారు చేస్తాను -- '
          'అటాచ్ బటన్ నొక్కండి -- లేదా "కంది పప్పు 1 కిలో ₹160" లా టైప్ చేయండి.',
      hi: '${asked ? 'इस श्रेणी के लिए अभी तैयार कैटलॉग नहीं है' : 'कौन-सा कैटलॉग चाहिए?'} '
          'तैयार: $list। बाकी के लिए आपके सामान की फ़ोटो या रेट लिस्ट (PDF/फ़ोटो) से कैटलॉग बना सकते हैं -- '
          'अटैच बटन दबाएँ -- या "तूर दाल 1 किलो ₹160" जैसा लिखें।');
}

String askodoxCatalogueClosedReply(String lang) => _pick(lang,
    en: 'Okay, the catalogue is closed. Tell me when you want to add products.',
    te: 'సరే, కేటలాగ్ మూసేశాను. వస్తువులు చేర్చాలనుకున్నప్పుడు చెప్పండి.',
    hi: 'ठीक है, कैटलॉग बंद कर दिया। जब सामान जोड़ना हो, बताइए।');

String askodoxCataloguePublishedReply(AskodoxCataloguePublishResult r, String lang) {
  if (!r.ok) {
    return switch (r.error) {
      'sign_in' => _pick(lang,
          en: 'Sign in with your phone number to publish your catalogue.',
          te: 'మీ కేటలాగ్ ప్రచురించడానికి ఫోన్ నంబర్‌తో సైన్ ఇన్ చేయండి.',
          hi: 'कैटलॉग प्रकाशित करने के लिए फ़ोन नंबर से साइन इन करें।'),
      _ => _pick(lang,
          en: 'The catalogue could not be published right now. Your selection is kept -- try again.',
          te: 'కేటలాగ్ ఇప్పుడు ప్రచురించలేకపోయాం. మీ ఎంపిక అలాగే ఉంది -- మళ్లీ ప్రయత్నించండి.',
          hi: 'कैटलॉग अभी प्रकाशित नहीं हो सका। आपका चुनाव रखा है -- फिर कोशिश करें।'),
    };
  }
  return _pick(lang,
      en: 'Published ${r.published} item(s) in your shop -- buyers nearby can now find them. '
          '${r.drafts > 0 ? '${r.drafts} without a price are saved as drafts. ' : ''}You can edit them any time in My listings.',
      te: 'మీ షాప్‌లో ${r.published} వస్తువులు ప్రచురించబడ్డాయి -- దగ్గరలోని కొనుగోలుదారులు ఇప్పుడు చూడగలరు. '
          '${r.drafts > 0 ? 'ధర లేని ${r.drafts} డ్రాఫ్ట్‌లుగా సేవ్ అయ్యాయి. ' : ''}"నా లిస్టింగ్స్"లో ఎప్పుడైనా మార్చుకోవచ్చు.',
      hi: 'आपकी दुकान में ${r.published} आइटम प्रकाशित हुए -- पास के ख़रीदार अब इन्हें देख सकते हैं। '
          '${r.drafts > 0 ? 'बिना दाम वाले ${r.drafts} ड्राफ़्ट में सेव हैं। ' : ''}"मेरी लिस्टिंग" में कभी भी बदल सकते हैं।');
}
