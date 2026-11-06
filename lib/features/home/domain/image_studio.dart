/// Photo edit / create in the chat (POST /api/images/edit).
///
/// Whether a message asks for a picture is decided by the photo-analysis
/// model from the customer's own words (`image_request` in the attachment
/// analysis) -- never by keyword lists in the app.
library;

/// True when the analysis of an attached photo says the customer's words ask
/// to edit it or to make a new picture from it.
bool askodoxAnalysisWantsImage(Map<String, Object?>? analysis) {
  final value = '${analysis?['image_request'] ?? ''}'.trim().toUpperCase();
  return value == 'EDIT' || value == 'CREATE';
}

/// The reply shown with the finished picture.
String askodoxImageStudioDoneText(bool te) => te
    ? 'మీరు చెప్పినట్టు ఫోటో తయారైంది. పెద్దగా చూడటానికి లేదా షేర్ చేయడానికి ఫోటోపై నొక్కండి.\n'
        'ఇది AI తో మార్చిన ఫోటో; నిజమైన ఫోటోగా ఎవరికీ చూపించకండి.'
    : 'Here is the picture you asked for. Tap it to view it large or share it.\n'
        'This photo was changed by AI; do not present it as a real photo.';

/// One honest sentence for every way a picture can fail to come back.
String askodoxImageStudioFailureText(String code, bool te, {int? dailyLimit}) => switch (code) {
      'sign_in' => te
          ? 'ఫోటో ఎడిట్ చేయడానికి ముందుగా Sign in చేయండి (Profile → Sign in).'
          : 'Please sign in first to edit photos (Profile → Sign in).',
      'daily_limit' => te
          ? 'ఈ రోజు ${dailyLimit ?? ''} ఫోటోల పరిమితి అయిపోయింది. రేపు మళ్లీ ప్రయత్నించండి.'
          : "Today's limit of ${dailyLimit ?? ''} pictures is used up. Please try again tomorrow.",
      'credits_low' => te
          ? 'AI Credits సరిపోవడం లేదు. Profile → AI Credits లో చూడండి.'
          : 'Not enough AI Credits. See Profile → AI Credits.',
      'not_configured' || 'off' => te
          ? 'ఫోటో ఎడిటింగ్ ఇంకా ఆన్ కాలేదు. త్వరలో అందుబాటులోకి వస్తుంది.'
          : 'Photo editing is not switched on yet.',
      'busy' => te
          ? 'చాలా ఫోటోలు ఒకేసారి అడిగారు. ఒక నిమిషం ఆగి మళ్లీ ప్రయత్నించండి.'
          : 'Too many pictures at once. Please wait a minute and try again.',
      _ => te
          ? 'ఈసారి ఫోటో తయారు కాలేదు. మళ్లీ ప్రయత్నించండి.'
          : 'The picture could not be made this time. Please try again.',
    };
