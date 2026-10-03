/// The customer is ending the conversation ("bye", "good night", "thanks,
/// that's all", "శుభరాత్రి", "धन्यवाद", "adiós" ...). Only short messages made
/// of closing words count -- "thanks, now show me fridges" is not a goodbye.
/// Unknown languages simply fall through to the normal (AI) reply.
bool askodoxIsSignOff(String text) {
  final clean = text
      .toLowerCase()
      .replaceAll(RegExp(r"['’]"), '')
      .replaceAll(RegExp(r'[!.,?¡¿"…]+'), ' ')
      .trim();
  if (clean.isEmpty) return false;
  final words = clean.split(RegExp(r'\s+'));
  if (words.length > 6) return false;
  final rest = _closings.fold<String>(' $clean ', (acc, phrase) => acc.replaceAll(' $phrase ', ' '));
  final leftover = rest.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !_fillers.contains(w));
  return leftover.isEmpty && rest.trim().length < clean.length;
}

const _closings = [
  // longest first
  'thats all', 'thank you', 'good night', 'see you', 'take care', 'have a nice day', 'talk later',
  'good bye', 'goodbye', 'bye bye', 'bye', 'thanks', 'thx', 'ttyl',
  'శుభరాత్రి', 'ధన్యవాదాలు', 'థాంక్స్', 'బై', 'సెలవు', 'ఇక చాలు',
  'शुभ रात्रि', 'धन्यवाद', 'शुक्रिया', 'अलविदा', 'बाय', 'फिर मिलेंगे',
  'நன்றி', 'இரவு வணக்கம்', 'ಧನ್ಯವಾದ', 'ಶುಭ ರಾತ್ರಿ', 'നന്ദി', 'ശുഭരാത്രി', 'ধন্যবাদ', 'শুভ রাত্রি',
  'adiós', 'adios', 'gracias', 'buenas noches', 'hasta luego', 'au revoir', 'merci', 'bonne nuit',
  'tschüss', 'danke', 'gute nacht', 'obrigado', 'obrigada', 'tchau', 'boa noite', 'شكرا', 'مع السلامة',
  'تصبح على خير', 'спасибо', 'пока', 'спокойной ночи', 'ありがとう', 'さようなら', 'おやすみ', '谢谢', '再见', '晚安',
];

const _fillers = {'ok', 'okay', 'ok,', 'sare', 'సరే', 'ठीक', 'है', 'a', 'and', 'so', 'much', 'very', 'all', 'for', 'now',
  'sir', 'madam', 'askodox', 'అండి', 'जी', 'you'};

/// Reasoning context when no sign-off template exists in the customer's
/// language: the AI writes one, in that language, without questions.
const askodoxSignOffGuidance =
    'The customer is ending the conversation. Reply with ONE short, warm sign-off in the language of the '
    'conversation (use their first name if known, "good night" if it is late). No questions, no suggestions, '
    'no results, no referral or join prompts.';

// Not in the lexicon on purpose: "tata" (also a brand), "gn" (ambiguous).
