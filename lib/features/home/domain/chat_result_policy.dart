import 'package:flutter/foundation.dart';

import '../../matching/data/universal_match_repository.dart';

/// What a result card embedded in the ASKODOX chat lets the user do.
///
/// * [connect] -- a Party B from `/deals/{id}/matches` (or a sandbox demo
///   match): Party A accepts via `acceptMatch`, the existing consent-first
///   interest flow. Contact stays hidden until both sides accept.
/// * [sendRequest] -- a real seller listing from `/api/products/search`:
///   the existing order request, which the seller must Accept/Decline.
/// * [openLink] -- an online (normal or affiliate) destination.
/// * [watchVideo] -- a video / social result.
enum ChatResultAction { connect, sendRequest, openLink, watchVideo }

ChatResultAction chatResultActionFor(UniversalMatch match) {
  final source = match.source.toLowerCase();
  if (source == 'video') return ChatResultAction.watchVideo;
  // Online pages and nearby shops not registered on ASKODOX are links: there
  // is no ASKODOX seller on the other side to accept a request.
  if (source == 'online' || source == 'external') {
    return ChatResultAction.openLink;
  }
  if (source == 'interest' ||
      source == 'demo_discovery' ||
      match.id.startsWith('demo-')) {
    return ChatResultAction.connect;
  }
  // Only a numeric seller_products id can become an order request.
  if (int.tryParse(match.id) != null) return ChatResultAction.sendRequest;
  final url = match.destinationUrl?.trim() ?? '';
  return url.isNotEmpty ? ChatResultAction.openLink : ChatResultAction.connect;
}

/// The result set ASKODOX embeds under one assistant reply in the chat.
@immutable
class AskodoxChatResults {
  const AskodoxChatResults({
    this.dealId,
    this.matches = const <UniversalMatch>[],
    this.failed = false,
    this.signInRequired = false,
    this.missingFields = const <String>[],
    this.sourceStatus = const <String, String>{},
    this.searched = false,
  });

  final String? dealId;

  /// Backend-reported outcome per source (ok / no_results / unavailable).
  final Map<String, String> sourceStatus;

  /// A real search ran. With no rows the chat says so honestly instead of
  /// showing placeholder cards.
  final bool searched;
  final List<UniversalMatch> matches;

  /// Matching could not be reached (network / server error). The chat shows
  /// a retry action instead of pretending nothing matched.
  final bool failed;

  /// The backend refused because the user is signed out.
  final bool signInRequired;

  /// Backend said the request still needs these details (HTTP 422).
  final List<String> missingFields;

  List<UniversalMatch> get local => [
        for (final m in matches)
          if (chatResultActionFor(m) == ChatResultAction.connect ||
              chatResultActionFor(m) == ChatResultAction.sendRequest)
            m,
      ];

  List<UniversalMatch> get online => [
        for (final m in matches)
          if (chatResultActionFor(m) == ChatResultAction.openLink) m,
      ];

  List<UniversalMatch> get videos => [
        for (final m in matches)
          if (chatResultActionFor(m) == ChatResultAction.watchVideo) m,
      ];

  bool get hasLocal => local.isNotEmpty;
  bool get isEmpty => matches.isEmpty && !failed && !signInRequired && !searched;

  /// Sources that were consulted but returned nothing, and sources that are
  /// not available right now -- shown as a one-line honest note.
  List<String> sourcesWith(String status) => [
        for (final e in sourceStatus.entries)
          if (e.value == status) e.key,
      ];
}

/// Combines the user's words with facts extracted from an attached photo or
/// file so the same intent → category → questions → matching pipeline runs
/// on both.
String askodoxAttachmentRequest(String userText, Object? facts) {
  final text = userText.trim();
  final clean = (facts ?? '').toString().trim();
  if (clean.isEmpty || clean.toLowerCase() == 'null') return text;
  return '$text\nAttachment facts: $clean';
}

/// Reply used when the AI reply is unavailable and the deal still needs a
/// category-specific detail (the deal brain's `lastQuestion`).
String askodoxDetailQuestionReply(String question, {required bool telugu}) =>
    telugu ? 'ఇంకా ఒక వివరం కావాలి: $question' : question;

/// Deterministic reply describing the embedded results when the AI reply is
/// unavailable. Honest about local vs online vs failure.
String askodoxResultsReply(AskodoxChatResults results, {required bool telugu}) {
  if (results.missingFields.isNotEmpty && results.matches.isEmpty) {
    final fields = results.missingFields
        .map((field) => field.replaceAll('_', ' '))
        .join(', ');
    return telugu
        ? 'మీకు సరైన match వెతకడానికి ఇంకా ఈ వివరాలు కావాలి: $fields'
        : 'To find the right match I still need: $fields';
  }
  if (results.signInRequired && !results.hasLocal) {
    return telugu
        ? 'స్థానిక విక్రేతలకు అభ్యర్థన పంపడానికి సైన్ ఇన్ చేయండి.'
        : 'Sign in to send requests to local sellers and providers.';
  }
  if (results.failed) {
    return telugu
        ? 'ఇప్పుడు మ్యాచింగ్ సేవను చేరుకోలేకపోయాం. మీ అభ్యర్థన సురక్షితంగా ఉంది -- క్రింద "మళ్లీ ప్రయత్నించండి" నొక్కండి.'
        : 'I could not reach matching right now. Your request is safe -- tap Retry below.';
  }
  if (results.hasLocal) {
    return telugu
        ? 'మీ అభ్యర్థనకు సరిపోయే స్థానిక ఎంపికలు ఇవి. అభ్యర్థన పంపండి -- వారు అంగీకరించాకే కాంటాక్ట్ వివరాలు కనిపిస్తాయి.'
        : 'Here are local options that match your request. Send a request -- contact details appear only after they accept.';
  }
  if (results.online.isNotEmpty || results.videos.isNotEmpty) {
    return telugu
        ? 'ప్రస్తుతం ధృవీకరించిన స్థానిక match దొరకలేదు. మీ అవసరాన్ని సేవ్ చేశాను; ఈలోగా ఆన్‌లైన్ ఎంపికలు, వీడియోలు ఇవి.'
        : 'No verified local match yet. I saved your need; meanwhile here are online options and videos.';
  }
  return telugu
      ? 'ఈ అభ్యర్థనకు ప్రస్తుతం ధృవీకరించిన match దొరకలేదు. మీ అవసరాన్ని సేవ్ చేశాను; సరైన అవకాశం లభిస్తే ASKODOX మీకు తెలియజేస్తుంది.'
      : 'I could not find a verified match for this request yet. I saved your need and ASKODOX will notify you when a suitable option becomes available.';
}


/// Result sections shown in chat, in display order. Each row carries a
/// backend `segment`; rows from older backends fall back by source.
enum AskodoxResultSegment {
  askodoxMatches,
  registered,
  individual,
  used,
  surplus,
  deals,
  nearbyExternal,
  widerLocal,
  online,
  video,
}

AskodoxResultSegment askodoxSegmentOf(UniversalMatch match) {
  switch (match.segment) {
    case 'registered':
      return AskodoxResultSegment.registered;
    case 'individual':
      return AskodoxResultSegment.individual;
    case 'used':
      return AskodoxResultSegment.used;
    case 'surplus':
      return AskodoxResultSegment.surplus;
    case 'deals':
      return AskodoxResultSegment.deals;
    case 'nearby_external':
      return AskodoxResultSegment.nearbyExternal;
    case 'wider_local':
      return AskodoxResultSegment.widerLocal;
  }
  return switch (chatResultActionFor(match)) {
    ChatResultAction.watchVideo => AskodoxResultSegment.video,
    ChatResultAction.openLink => AskodoxResultSegment.online,
    ChatResultAction.connect => AskodoxResultSegment.askodoxMatches,
    ChatResultAction.sendRequest => AskodoxResultSegment.registered,
  };
}

String askodoxSegmentTitle(
  AskodoxResultSegment segment, {
  required bool telugu,
  required bool hasLocal,
}) {
  if (telugu) {
    return switch (segment) {
      AskodoxResultSegment.askodoxMatches => 'ASKODOX మ్యాచ్‌లు',
      AskodoxResultSegment.registered => 'ASKODOX విక్రేతలు',
      AskodoxResultSegment.individual => 'వ్యక్తిగత విక్రేతలు',
      AskodoxResultSegment.used => 'వాడిన / సెకండ్ హ్యాండ్',
      AskodoxResultSegment.surplus => 'సర్ప్లస్ / క్లియరెన్స్ / ఓపెన్-బాక్స్',
      AskodoxResultSegment.deals => 'డీల్స్ & ఆఫర్లు',
      AskodoxResultSegment.nearbyExternal => 'దగ్గరలోని షాపులు',
      AskodoxResultSegment.widerLocal => 'కొంచెం దూరంలోని షాపులు',
      AskodoxResultSegment.online => hasLocal
          ? 'ఆన్‌లైన్ ఎంపికలు'
          : 'స్థానిక match లేదు -- ఆన్‌లైన్ ఎంపికలు',
      AskodoxResultSegment.video => 'వీడియోలు & రివ్యూలు',
    };
  }
  return switch (segment) {
    AskodoxResultSegment.askodoxMatches => 'ASKODOX matches',
    AskodoxResultSegment.registered => 'ASKODOX sellers',
    AskodoxResultSegment.individual => 'Individual sellers',
    AskodoxResultSegment.used => 'Used / second-hand',
    AskodoxResultSegment.surplus => 'Surplus / clearance / open-box',
    AskodoxResultSegment.deals => 'Deals & offers',
    AskodoxResultSegment.nearbyExternal => 'Nearby shops',
    AskodoxResultSegment.widerLocal => 'Shops a little farther away',
    AskodoxResultSegment.online =>
      hasLocal ? 'Online options' : 'No local match yet -- online options',
    AskodoxResultSegment.video => 'Videos & reviews',
  };
}

/// Groups rows into non-empty sections in display order (no empty sections
/// are ever shown just to fill the screen).
List<(AskodoxResultSegment, List<UniversalMatch>)> askodoxGroupResults(
  List<UniversalMatch> matches,
) {
  final groups = <AskodoxResultSegment, List<UniversalMatch>>{};
  for (final match in matches) {
    groups.putIfAbsent(askodoxSegmentOf(match), () => []).add(match);
  }
  return [
    for (final segment in AskodoxResultSegment.values)
      if (groups[segment] case final rows?) (segment, rows),
  ];
}

// ------------------------------------------------------ AI-first deal flow --

/// Messages that genuinely need the seller/provider (confirmation,
/// negotiation, booking, availability): only then are Send request /
/// Connect exposed on the local options.
bool askodoxWantsHumanAction(String text) {
  final t = ' ${text.toLowerCase()} ';
  return [
    r'\bcontact (the )?(seller|provider|shop|owner)\b',
    r'\bsend (a |the )?request\b',
    r'\b(book|reserve) (it|this|that|now|a slot)\b',
    r'\bconfirm (availability|the price|stock)\b',
    r'\bnegotiat',
    r"\bi('ll| will) take (it|this|that)\b",
    r'\b(place|confirm) (the )?order\b',
    r'\bcall (the )?(seller|shop|provider)\b',
    r'విక్రేతను సంప్రదించ',
    r'బుక్ చేయ',
    r'ఆర్డర్ చేయ',
  ].any((p) => RegExp(p).hasMatch(t));
}

/// Questions about options already shown (compare, reviews, distance...).
/// These stay in the AI conversation instead of starting a new search.
bool askodoxIsResultsQuestion(String text) {
  final t = ' ${text.toLowerCase()} ';
  final explicit = [
    r'\bcompare\b',
    r'\bwhich (one|is|should|of)\b',
    r'\bdifference between\b',
    r'\bhow far\b',
    r'\bis (it|this|that) (new|used|available|good|genuine)\b',
    r'\b(this|that|first|second|third|last) (one|option)\b',
    r'\breviews? (of|for|about) (this|that|it|them)\b',
    r'ఏది మంచిది',
    r'పోల్చ',
  ].any((p) => RegExp(p).hasMatch(t));
  // "best/cheapest/closest" only counts when asked as a question about the
  // shown options -- "I want the best mixer grinder" is a new request.
  final comparativeQuestion = t.contains('?') &&
      RegExp(r'\b(better|best|cheapest|cheaper|closest|nearest|reviews?)\b').hasMatch(t);
  return explicit || comparativeQuestion;
}

/// Short, factual description of an option so ASKODOX AI can discuss it.
String askodoxOptionContext(UniversalMatch match) {
  final parts = <String>[match.title];
  if (match.subtitle?.trim().isNotEmpty == true) parts.add(match.subtitle!.trim());
  if (match.price != null) parts.add('price ₹${match.price!.toStringAsFixed(0)}');
  if (match.distanceKm != null) parts.add('${match.distanceKm!.toStringAsFixed(1)} km away');
  if (match.availability?.trim().isNotEmpty == true) parts.add(match.availability!.trim());
  if (match.ratingAverage != null) {
    parts.add('rated ${match.ratingAverage!.toStringAsFixed(1)} (${match.reviewCount} reviews)');
  }
  if (match.segment?.isNotEmpty == true) parts.add('type: ${match.segment}');
  return parts.join('; ');
}

// --------------------------------------------------------- support policy --

enum AskodoxSupportNeed { none, afterAiAttempt, immediate }

class AskodoxSupportAssessment {
  const AskodoxSupportAssessment(this.need, {this.category = 'GENERAL'});
  final AskodoxSupportNeed need;
  final String category;
  bool get critical => need == AskodoxSupportNeed.immediate;
}

const _criticalSupport = <String, List<String>>{
  'PAYMENT': [r'\bpayment (failed|failure|issue|problem|stuck|not (done|received|reflected|confirmed))', r'\brefund\b', r'money (was )?(deducted|debited)', r'\bupi\b.*\b(fail|stuck)', r'డబ్బులు (పోయాయి|కట్)'],
  'DISPUTE': [r'\bdispute\b', r'\bcheat', r'\bscam\b', r'\bfraud\b', r'మోసం'],
  'ORDER': [r'order (not|never) (delivered|received|arrived)', r'\bwrong (item|product)\b', r'\bdamaged\b', r'\bmissing item'],
  'SAFETY': [r'\bunsafe\b', r'\bharass', r'\bthreat', r'\babuse', r'\bemergency\b'],
  'ACCOUNT': [r'account (hacked|blocked|locked|suspended)', r"\bcan('|no)t (log ?in|sign in)\b", r'\botp not\b'],
};

const _issueWords = [
  r'\bproblem\b', r'\bissue\b', r'not working', r'\berror\b', r'\bcomplain', r'\bbroken\b',
  r'\bcrash', r'\bfailed\b', r'సమస్య', r'పని చేయడం లేదు',
];

const _unresolvedWords = [
  r'\bstill\b', r"didn'?t (help|work)", r'not (solved|resolved|fixed)', r'ఇంకా అలాగే',
];

const _askForHumanWords = [
  r'\bhuman\b', r'\b(real )?agent\b', r'\b(talk|speak|chat) (to|with) (support|someone|a person)\b',
  r'customer (care|support)', r'సపోర్ట్',
];

bool _matchesAny(String text, List<String> patterns) =>
    patterns.any((p) => RegExp(p).hasMatch(text));

/// ASKODOX AI is first-line support. Support escalation is offered only
/// when the AI could not resolve the issue ([previousIssueTurns] earlier
/// problem messages, or the user says it is still unresolved), or
/// immediately for critical payment/dispute/order/safety/account problems.
AskodoxSupportAssessment askodoxAssessSupport(
  String text, {
  required int previousIssueTurns,
}) {
  final t = ' ${text.toLowerCase()} ';
  for (final entry in _criticalSupport.entries) {
    if (_matchesAny(t, entry.value)) {
      return AskodoxSupportAssessment(AskodoxSupportNeed.immediate, category: entry.key);
    }
  }
  // The user explicitly asks for a person.
  if (_matchesAny(t, _askForHumanWords)) {
    return const AskodoxSupportAssessment(AskodoxSupportNeed.afterAiAttempt);
  }
  // The same problem persists after ASKODOX AI already tried to help.
  final issue = _matchesAny(t, _issueWords) || _matchesAny(t, _unresolvedWords);
  if (issue && previousIssueTurns >= 1) {
    return const AskodoxSupportAssessment(AskodoxSupportNeed.afterAiAttempt, category: 'TECHNICAL');
  }
  return const AskodoxSupportAssessment(AskodoxSupportNeed.none);
}

/// Whether a message describes a problem (used to count AI attempts).
bool askodoxLooksLikeIssue(String text) {
  final t = ' ${text.toLowerCase()} ';
  return _matchesAny(t, _issueWords) ||
      _matchesAny(t, _unresolvedWords) ||
      _criticalSupport.values.any((patterns) => _matchesAny(t, patterns));
}

/// Deterministic reply when the user asks about one option and the AI reply
/// is unavailable: stay in the conversation, facts first, human last.
String askodoxOptionReply(String optionContext, {required bool telugu}) => telugu
    ? 'ఈ ఎంపిక గురించి నాకు తెలిసింది: $optionContext. ఇంకా ఏమైనా అడగండి; విక్రేత నిర్ధారణ కావాలనుకుంటే "అభ్యర్థన పంపండి" నొక్కండి.'
    : 'Here is what I know about this option: $optionContext. Ask me anything else, or tap Send request when you want the seller to confirm.';

/// Reply when the user needs the seller/provider to act.
String askodoxHumanActionReply({required bool telugu}) => telugu
    ? 'సరే. మీకు నచ్చిన ఎంపికపై "అభ్యర్థన పంపండి" నొక్కండి -- విక్రేత అంగీకరించిన తర్వాతే కాంటాక్ట్ వివరాలు కనిపిస్తాయి.'
    : 'Sure. Tap Send request on the option you want -- the seller confirms first, and contact details are shared only after they accept.';
