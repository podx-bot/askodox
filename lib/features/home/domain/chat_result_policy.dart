import 'package:flutter/foundation.dart';

import '../../matching/data/universal_match_repository.dart';
import '../../matching/domain/result_contract.dart';
import 'conversation_language.dart';

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
    this.broadcastSent,
    this.scopeMessage,
    this.advice = const [],
    this.nextActions = const [],
    this.traceKey,
    this.advisor,
    this.contract,
  });

  final String? dealId;

  /// The canonical sectioned result contract (null on an older backend).
  final ResultContract? contract;

  /// Universal Advisor view of this search (open question, guidance).
  final AskodoxAdvisorView? advisor;

  /// Admin flow trace of this search (selected result / action outcome
  /// are appended to it).
  final String? traceKey;

  /// At most two short, contextual advice lines (never a lecture).
  final List<({String text, String textTe})> advice;

  /// e.g. refer_provider / find_more / contact_external when no ASKODOX
  /// provider has this yet.
  final List<String> nextActions;

  /// Real in-app leads the backend created for registered providers.
  final int? broadcastSent;

  /// "No suitable option near X, expanding to the wider city (~25 km)."
  final String? scopeMessage;

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

/// The ask used for reasoning when an attachment is sent without words. It
/// is never shown as the customer's message and never decides the language
/// (the reply follows the conversation language).
const askodoxAttachmentOnlyAsk =
    'The customer sent this attachment without a question. Say what it is and help with the likely need '
    '(where to get it nearby or online, a service for it, or what the document means).';

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
    // Only what really happened: an open request id / a real broadcast.
    final id = results.dealId ?? '';
    final sent = results.broadcastSent ?? 0;
    final next = sent > 0
        ? (telugu ? ' మీ అభ్యర్థనను $sent నమోదైన ప్రొవైడర్లకు పంపాను.' : ' I sent your request to $sent registered provider(s).')
        : id.isNotEmpty
            ? (telugu ? ' అభ్యర్థన సేవ్ అయింది (ID $id).' : ' Request saved (ID $id).')
            : '';
    return telugu
        ? 'ప్రస్తుతం ధృవీకరించిన స్థానిక match దొరకలేదు.$next ఈలోగా ఆన్‌లైన్ ఎంపికలు, వీడియోలు ఇవి.'
        : 'No verified local match yet.$next Meanwhile here are online options and videos.';
  }
  // The full, honest status (what was searched, broadcast count, open
  // request) is the notice under this reply -- not repeated here.
  return telugu ? 'ఇంకా సరైన ఫలితం దొరకలేదు -- వివరాలు క్రింద.' : 'Nothing suitable yet -- details below.';
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
  jobs,
  online,
  // Affiliate / partner stores (Partner Hub): after local and normal online.
  partner,
  // Paid placements (Command Center sponsored campaigns): their own labelled
  // section, never ranked among organic results.
  sponsored,
  video,
}

AskodoxResultSegment askodoxSegmentOf(UniversalMatch match) {
  if (match.sponsored) return AskodoxResultSegment.sponsored;
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
    case 'jobs':
      return AskodoxResultSegment.jobs;
    case 'partner':
      return AskodoxResultSegment.partner;
  }
  return switch (chatResultActionFor(match)) {
    ChatResultAction.watchVideo => AskodoxResultSegment.video,
    ChatResultAction.openLink => AskodoxResultSegment.online,
    ChatResultAction.connect => AskodoxResultSegment.askodoxMatches,
    ChatResultAction.sendRequest => AskodoxResultSegment.registered,
  };
}

/// Plain label for a result's condition/source segment (Details sheet).
String askodoxSegmentLabel(String segment) => switch (segment) {
      'used' => 'Used / second-hand',
      'surplus' => 'Surplus / open-box / clearance',
      'deals' => 'Deal / offer',
      'individual' => 'Individual seller',
      'registered' => 'New (ASKODOX seller)',
      'nearby_external' => 'Nearby shop',
      'wider_local' => 'Wider local area',
      'jobs' => 'Job opening (from a job site)',
      'partner' => 'Partner store (affiliate link)',
      'sponsored' => 'Sponsored (paid placement)',
      _ => segment,
    };

String askodoxSegmentTitle(
  AskodoxResultSegment segment, {
  required bool telugu,
  required bool hasLocal,
  String lang = 'en',
}) {
  // Other app languages: the online/no-local headings from the label table.
  if (segment == AskodoxResultSegment.sponsored) {
    return switch (lang) {
      'te' => 'స్పాన్సర్డ్',
      'hi' => 'प्रायोजित',
      _ => telugu ? 'స్పాన్సర్డ్' : 'Sponsored',
    };
  }
  if (lang != 'en' && lang != 'te' && segment == AskodoxResultSegment.partner) {
    return askodoxChatLabel('partner', lang);
  }
  if (lang != 'en' && lang != 'te' && segment == AskodoxResultSegment.online) {
    return hasLocal
        ? askodoxChatLabel('online', lang)
        : '${askodoxChatLabel('no_local', lang)} -- ${askodoxChatLabel('online', lang)}';
  }
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
      AskodoxResultSegment.jobs => 'ఉద్యోగ అవకాశాలు',
      AskodoxResultSegment.online => hasLocal
          ? 'ఆన్‌లైన్ ఎంపికలు'
          : 'స్థానిక match లేదు -- ఆన్‌లైన్ ఎంపికలు',
      AskodoxResultSegment.partner => 'భాగస్వామి స్టోర్లు',
      AskodoxResultSegment.sponsored => 'స్పాన్సర్డ్',
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
    AskodoxResultSegment.jobs => 'Job openings',
    AskodoxResultSegment.online =>
      hasLocal ? 'Online options' : 'No local match yet -- online options',
    AskodoxResultSegment.partner => 'Partner stores',
    AskodoxResultSegment.sponsored => 'Sponsored',
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

/// Sent with every question about shown options: ASKODOX answers only from
/// what the source actually provided -- never an invented rating, review,
/// condition, stock, specification, distance or seller reputation.
const askodoxGroundingRule =
    'Answer ONLY from the facts listed for each option. If a fact (price, rating, reviews, condition, stock, '
    'specifications, distance, seller verification) is "not provided", say it is not provided by the source -- '
    'never guess it, never say customers generally rate it well. Offer to ask the seller for seller-only facts.';

/// Short, factual description of an option so ASKODOX AI can discuss it.
/// Facts the source did not give are stated as "not provided".
String askodoxOptionContext(UniversalMatch match) {
  final parts = <String>[match.title];
  if (match.subtitle?.trim().isNotEmpty == true) parts.add(match.subtitle!.trim());
  parts.add(match.price == null
      ? 'price: not provided'
      : match.priceVerified
          ? 'price ₹${match.price!.toStringAsFixed(0)}'
          : 'page text mentions ₹${match.price!.toStringAsFixed(0)} (unverified)');
  if (match.salaryText?.trim().isNotEmpty == true) parts.add('salary as stated: ${match.salaryText!.trim()}');
  parts.add(match.distanceKm == null ? 'distance: not provided' : '${match.distanceKm!.toStringAsFixed(1)} km away');
  parts.add(match.availability?.trim().isNotEmpty == true ? match.availability!.trim() : 'stock/availability: not provided');
  parts.add(match.ratingAverage == null
      ? 'rating/reviews: not provided'
      : 'rated ${match.ratingAverage!.toStringAsFixed(1)} (${match.reviewCount} reviews)');
  if (match.sourceName?.trim().isNotEmpty == true) parts.add('source: ${match.sourceName!.trim()}');
  if (match.segment?.isNotEmpty == true) parts.add('type: ${match.segment}');
  return parts.join('; ');
}

// ------------------------------------------------ universal routing --
// ONE decision for every question, any category:
//   ASKODOX AI answers what it can know (specs, comparisons, process, shown
//   data) -> the seller/provider only for facts/actions only they can give
//   (stock, final/negotiated price, delivery or appointment commitment)
//   -> Customer Care when AI + seller cannot resolve (support policy below).

enum AskodoxRoute { ai, seller, support }

/// Questions ASKODOX must not guess: seller-specific facts or commitments.
bool askodoxNeedsSeller(String text) {
  final t = ' ${text.toLowerCase()} ';
  return [
    r'\b(in|out of) stock\b',
    r'\bstock\b',
    r'\bis (it|this|that) (still )?available\b',
    r'\bavailable (today|tomorrow|now|this week)\b',
    r'\b(final|lowest|best|last) price\b',
    r'\bdiscount\b',
    r'\bcan (they|you|he|she) (do|give|make it)\b',
    r'\b(reduce|lower) the price\b',
    r'\bnegotiat',
    r'\b(deliver|delivery)\b.*\b(today|tomorrow|by|when|included|free|charge)\b',
    r'\b(free|home) delivery\b',
    r'\binstallation (included|free|charge)\b',
    r'\b(slot|appointment)\b',
    r'\b(come|visit|arrive) (today|tomorrow|at|on|by)\b',
    r'\bwhen can (they|you|he|she) (come|deliver|start)\b',
    'స్టాక్',
    'తగ్గిస్తారా',
    'తగ్గించ',
    'డిస్కౌంట్',
    'డెలివరీ',
    'ఎప్పుడు వస్తారు',
    'అందుబాటులో ఉందా',
    'ఫైనల్ ధర',
  ].any((p) => RegExp(p).hasMatch(t));
}

/// A price the customer proposes ("can they do ₹24,000?", "24000 ki istara").
double? askodoxOfferAmount(String text) {
  final match = RegExp(r'(?:₹|rs\.?|inr)?\s*(\d{1,3}(?:,\d{2,3})+|\d{3,7})(?:\s*(?:/-|rupees|రూపాయ))?',
          caseSensitive: false)
      .firstMatch(text);
  if (match == null) return null;
  final amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
  final negotiating = RegExp(r'(can (they|you|he|she) do|for|at|offer|ok with|కి ఇస్తారా|ఇస్తారా|తగ్గించ)',
          caseSensitive: false)
      .hasMatch(text);
  return amount != null && amount >= 100 && negotiating ? amount : null;
}

/// Where this message goes. [hasOpenDeal]: a request is already with a
/// seller/provider in this conversation, so a seller question can be
/// relayed; otherwise ASKODOX answers what it can and offers Send request.
AskodoxRoute askodoxRouteMessage(String text,
    {required bool hasOpenDeal, int previousIssueTurns = 0}) {
  final support = askodoxAssessSupport(text, previousIssueTurns: previousIssueTurns);
  if (support.need != AskodoxSupportNeed.none) return AskodoxRoute.support;
  if (hasOpenDeal && askodoxNeedsSeller(text)) return AskodoxRoute.seller;
  return AskodoxRoute.ai;
}

String askodoxSellerRelayReply({required bool offer, required bool telugu}) => telugu
    ? (offer
        ? 'మీ ధర ప్రతిపాదనను ASKODOX ద్వారా విక్రేతకు పంపాను. వారి సమాధానం క్రింది డీల్ కార్డ్‌లో కనిపిస్తుంది; మీ ఫోన్ నంబర్ పంచుకోబడదు.'
        : 'ఈ ప్రశ్నకు విక్రేత మాత్రమే ఖచ్చితంగా చెప్పగలరు, కాబట్టి ASKODOX ద్వారా వారిని అడిగాను. వారి సమాధానం క్రింది డీల్ కార్డ్‌లో కనిపిస్తుంది.')
    : (offer
        ? "I've sent your price proposal to the seller through ASKODOX. Their answer will appear on the deal card below -- your phone number is not shared."
        : 'Only the seller can confirm this, so I asked them through ASKODOX. Their answer will appear on the deal card below.');

String askodoxSellerQuestionHint({required bool telugu}) => telugu
    ? '\n\nస్టాక్/ఫైనల్ ధర/డెలివరీని విక్రేత మాత్రమే నిర్ధారించగలరు — ఎంపికపై "అభ్యర్థన పంపండి" నొక్కితే ఈ ప్రశ్నను వారికి పంపుతాను.'
    : '\n\nStock, final price and delivery can only be confirmed by the seller -- tap "Send request" on an option and I will send them this question.';

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


const _sourceNames = {
  'askodox': ('ASKODOX sellers', 'ASKODOX విక్రేతలు'),
  'nearby': ('nearby businesses', 'దగ్గరలోని వ్యాపారాలు'),
  'used_deals': ('used/deals pages', 'పాత/ఆఫర్ పేజీలు'),
  'online': ('online stores', 'ఆన్‌లైన్ స్టోర్లు'),
  'videos': ('videos', 'వీడియోలు'),
};

/// Honest empty-results line: what was actually searched, what could not be
/// reached, and what happens next (a real broadcast count, the open
/// request, or signing in to save it) -- never a generic "saved".
const _downStatuses = {'error', 'unavailable', 'disabled', 'quota_exhausted', 'needs_location', 'not_configured'};

final _claimsResults = RegExp(
    r"\b(here are|here is|i(?:'m| am) (?:now )?(?:showing|finding|searching|checking|looking|fetching)|"
    r'showing (?:you )?(?:some |the |a few )?(?:options|results|choices)|found (?:some|these|a few|\d+)|'
    r'results? (?:will )?(?:appear|are|is) (?:below|shown)|let me (?:find|show|check|search|look)|'
    r'finding (?:you )?(?:some |the )?(?:options|results)|options below)\b'
    r'|చూపిస్తున్నాను|వెతుకుతున్నాను|ఇవి ఉన్నాయి|క్రింద ఉన్నాయి|दिखा रहा|दिखा रही|ढूंढ रहा|ढूंढ रही|ये रहे',
    caseSensitive: false);

/// The reply says results are shown / being found.
bool askodoxReplyClaimsResults(String reply) => _claimsResults.hasMatch(reply);

/// The reply names a size other than the one the customer gave ("Size 8
/// or 9" when they said 9) -- an explicit constraint must never change.
bool askodoxReplyAltersSize(String reply, String? size) {
  final kept = (size ?? '').replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (kept.isEmpty || kept == 'any') return false;
  final said = RegExp(r'\bsize\s*([0-9]{1,2}(?:\.5)?(?:\s*(?:or|/|-|to)\s*[0-9]{1,2}(?:\.5)?)?)',
          caseSensitive: false)
      .allMatches(reply)
      .map((m) => m.group(1)!.replaceAll(RegExp(r'\s+'), '').toLowerCase());
  return said.any((value) => value != kept && kept != 'uk$value' && kept != 'eu$value');
}

/// What to say when NO cards are shown this turn: the next question when
/// one is pending, the honest search outcome when a search ran, else a plain
/// "not searched yet" -- never "showing options".
String askodoxNoCardsReply({AskodoxChatResults? results, String? question, required bool telugu}) {
  if (question != null && question.trim().isNotEmpty) return askodoxDetailQuestionReply(question, telugu: telugu);
  if (results != null) return askodoxResultsReply(results, telugu: telugu);
  return telugu
      ? 'ఇంకా వెతకలేదు -- మీకు ఏం కావాలో కొంచెం చెప్పండి.'
      : "I haven't searched yet -- tell me a little more about what you need.";
}

String askodoxNoResultsText(AskodoxChatResults results, {required bool telugu}) {
  String names(String status) => [
        for (final e in results.sourceStatus.entries)
          if (e.value == status && _sourceNames.containsKey(e.key))
            telugu ? _sourceNames[e.key]!.$2 : _sourceNames[e.key]!.$1,
      ].join(', ');
  final searched = names('no_results');
  // Every way a source can be down is said -- never silently skipped
  // (Brave out of credit, Places not enabled, a source switched off).
  final failed = [
    for (final e in results.sourceStatus.entries)
      if (_downStatuses.contains(e.value) && _sourceNames.containsKey(e.key))
        telugu ? _sourceNames[e.key]!.$2 : _sourceNames[e.key]!.$1,
  ].join(', ');
  final parts = <String>[];
  if (searched.isNotEmpty) {
    parts.add(telugu ? 'వెతికాను: $searched -- సరైన ఫలితం లేదు.' : 'Searched $searched -- nothing suitable yet.');
  } else {
    parts.add(telugu ? 'ఇంకా సరైన ఫలితం దొరకలేదు.' : 'No suitable result yet.');
  }
  if (failed.isNotEmpty) {
    parts.add(telugu ? '$failed ఇప్పుడు అందుబాటులో లేవు.' : '$failed could not be reached right now.');
  }
  final sent = results.broadcastSent ?? 0;
  final id = results.dealId ?? '';
  if (sent > 0) {
    parts.add(telugu
        ? 'మీ అభ్యర్థనను దగ్గరలోని $sent నమోదైన ASKODOX ప్రొవైడర్లకు పంపాను; వారి సమాధానాలు ఇక్కడే కనిపిస్తాయి.'
        : 'I sent your request to $sent registered ASKODOX provider(s) nearby; their replies will appear here.');
  } else if (id.isNotEmpty) {
    parts.add(telugu
        ? 'అభ్యర్థన సేవ్ అయింది (ID $id); ఎవరైనా స్పందించగానే తెలియజేస్తాను. ఇది చేసే వారు తెలుసా? వారిని ASKODOX కి సూచించండి -- వారికి నేరుగా స్థానిక లీడ్స్ వస్తాయి.'
        : 'Request saved (ID $id) -- I will tell you when someone responds. Know someone who does this? Refer them to ASKODOX -- they get direct local leads.');
  } else {
    parts.add(telugu
        ? 'ప్రొవైడర్లు మీకు స్పందించేలా ఈ అవసరాన్ని సేవ్ చేయడానికి సైన్ ఇన్ చేయండి.'
        : 'Sign in to save this need so providers can reply to you.');
  }
  return parts.join(' ');
}

/// The comparison columns shown after a request (the approved reference:
/// LOCAL | SPONSORED | ONLINE, extended only when a type is present).
/// Paid placements keep their own column and label; they never change the
/// order of the organic rows inside the other columns.
enum AskodoxCompareKind { local, jobs, deals, sponsored, online, affiliate, used, surplus, videos, shorts }

AskodoxCompareKind askodoxCompareKindOf(UniversalMatch match) => switch (askodoxSegmentOf(match)) {
      AskodoxResultSegment.askodoxMatches ||
      AskodoxResultSegment.registered ||
      AskodoxResultSegment.individual ||
      AskodoxResultSegment.nearbyExternal ||
      AskodoxResultSegment.widerLocal =>
        AskodoxCompareKind.local,
      AskodoxResultSegment.jobs => AskodoxCompareKind.jobs,
      AskodoxResultSegment.deals => AskodoxCompareKind.deals,
      AskodoxResultSegment.sponsored => AskodoxCompareKind.sponsored,
      AskodoxResultSegment.online => AskodoxCompareKind.online,
      AskodoxResultSegment.partner => AskodoxCompareKind.affiliate,
      AskodoxResultSegment.used => AskodoxCompareKind.used,
      AskodoxResultSegment.surplus => AskodoxCompareKind.surplus,
      // A confidently identified YouTube Short gets its own group;
      // ordinary videos stay in Videos.
      AskodoxResultSegment.video =>
        match.videoFormat == 'short' ? AskodoxCompareKind.shorts : AskodoxCompareKind.videos,
    };

/// Only the kinds this request actually returned, in column order; rows keep
/// their organic order inside each kind.
List<(AskodoxCompareKind, List<UniversalMatch>)> askodoxCompareGroups(List<UniversalMatch> matches) {
  final groups = <AskodoxCompareKind, List<UniversalMatch>>{};
  for (final match in matches) {
    groups.putIfAbsent(askodoxCompareKindOf(match), () => []).add(match);
  }
  return [
    for (final kind in AskodoxCompareKind.values)
      if (groups[kind] case final rows?) (kind, rows),
  ];
}

/// How many results of each group the "All" tab previews; the rest are one
/// tap away ("View all" / the group's own tab).
const askodoxAllPreviewPerGroup = 2;

/// Width of a result card in a horizontal rail (a phone shows ~1.5).
const askodoxCompactCardWidth = 236.0;

String askodoxCompareLabel(AskodoxCompareKind kind, String lang) => switch (lang) {
      'te' => switch (kind) {
          AskodoxCompareKind.local => 'స్థానికం',
          AskodoxCompareKind.jobs => 'ఉద్యోగాలు',
          AskodoxCompareKind.deals => 'డీల్స్',
          AskodoxCompareKind.sponsored => 'స్పాన్సర్డ్',
          AskodoxCompareKind.online => 'ఆన్‌లైన్',
          AskodoxCompareKind.affiliate => 'అఫిలియేట్',
          AskodoxCompareKind.used => 'వాడినవి',
          AskodoxCompareKind.surplus => 'సర్ప్లస్',
          AskodoxCompareKind.videos => 'వీడియోలు',
          AskodoxCompareKind.shorts => 'షార్ట్స్',
        },
      'hi' => switch (kind) {
          AskodoxCompareKind.local => 'लोकल',
          AskodoxCompareKind.jobs => 'नौकरियाँ',
          AskodoxCompareKind.deals => 'डील्स',
          AskodoxCompareKind.sponsored => 'प्रायोजित',
          AskodoxCompareKind.online => 'ऑनलाइन',
          AskodoxCompareKind.affiliate => 'एफ़िलिएट',
          AskodoxCompareKind.used => 'पुराना',
          AskodoxCompareKind.surplus => 'सरप्लस',
          AskodoxCompareKind.videos => 'वीडियो',
          AskodoxCompareKind.shorts => 'शॉर्ट्स',
        },
      _ => switch (kind) {
          AskodoxCompareKind.local => 'Local',
          AskodoxCompareKind.jobs => 'Jobs',
          AskodoxCompareKind.deals => 'Deals',
          AskodoxCompareKind.sponsored => 'Sponsored',
          AskodoxCompareKind.online => 'Online',
          AskodoxCompareKind.affiliate => 'Affiliate',
          AskodoxCompareKind.used => 'Used',
          AskodoxCompareKind.surplus => 'Surplus',
          AskodoxCompareKind.videos => 'Videos',
          AskodoxCompareKind.shorts => 'Shorts',
        },
    };


/// The customer asked for videos / reviews / demos (English, Telugu, Hindi).
/// Such a message is always a real search -- the chat never answers it with
/// an AI "here are the videos" claim that shows nothing.
final _videoAsk = RegExp(
    r'\b(videos?|reviews?|youtube|unboxing|demo|comparison)\b|(వీడియో|విడియో|రివ్యూ|రివ్యు|సమీక్ష|పోలిక|యూట్యూబ్|वीडियो|रिव्यू|समीक्षा)',
    caseSensitive: false);

bool askodoxAsksForVideos(String text) => _videoAsk.hasMatch(text);

/// The price line of a result card. A staff-catalog price is shown as the
/// listed price with its MRP / discount when the source states them; a price
/// found only in web-page text stays "Page mentions ₹X".
String? askodoxPriceLabel(UniversalMatch match, {required bool te}) {
  final price = match.price;
  if (price == null) return null;
  final amount = '₹${price.toStringAsFixed(0)}';
  if (match.priceVerified) return amount;
  if (match.priceSource == 'catalog') {
    final mrp = match.originalPrice;
    if (mrp != null && mrp > price) {
      final off = match.discountPercent ?? ((mrp - price) / mrp * 100).round();
      return te
          ? '$amount (MRP ₹${mrp.toStringAsFixed(0)}, $off% తగ్గింపు)'
          : '$amount (MRP ₹${mrp.toStringAsFixed(0)}, $off% off)';
    }
    return amount;
  }
  return te ? 'పేజీలో $amount' : 'Page mentions $amount';
}

/// "In stock" only when the source actually tracks stock; UNKNOWN is never
/// shown as a fact.
String? askodoxStockLabel(UniversalMatch match, {required bool te}) {
  switch ((match.stockStatus ?? '').toUpperCase()) {
    case 'IN_STOCK':
      return te ? 'స్టాక్‌లో ఉంది' : 'In stock';
    case 'OUT_OF_STOCK':
      return te ? 'స్టాక్ లేదు' : 'Out of stock';
  }
  return null;
}

/// When the price / stock was last checked, e.g. "Checked 3 Oct".
String? askodoxCheckedLabel(UniversalMatch match, {required bool te}) {
  final at = DateTime.tryParse(match.lastChecked ?? '');
  if (at == null) return null;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final local = at.toLocal();
  final day = '${local.day} ${months[local.month - 1]}';
  return te ? '$day న తనిఖీ' : 'Checked $day';
}


/// The size the customer stated, EXACTLY as stated ("size 9" -> "9",
/// "UK 9.5" -> "UK 9.5", "size 8 or 9" -> "8 or 9", "సైజు 9" -> "9").
/// Null when no size was named. Never widened or rounded.
String? askodoxExplicitSize(String text) {
  final t = text.trim();
  const number = r'[0-9]{1,2}(?:\.5)?';
  final range = '$number(?:\\s*(?:or|/|-|to)\\s*$number)?';
  final sized = RegExp('(?:\\bsize|సైజు|సైజ్|साइज़|साइज)\\s*(?:is\\s*|:\\s*)?($range|xxxl|xxl|xl|xs|s|m|l)\\b',
      caseSensitive: false).firstMatch(t);
  if (sized != null) return sized.group(1)!.trim();
  final system = RegExp('\\b(uk|eu)\\s*($number)\\b', caseSensitive: false).firstMatch(t);
  if (system != null) return '${system.group(1)!.toUpperCase()} ${system.group(2)}';
  return null;
}

/// "any", "no preference", "ఏదైనా", "कोई भी"...: the user does not mind for
/// THE field just asked -- it settles that one field only.
bool askodoxIsNoPreference(String text) {
  final t = text.trim().toLowerCase().replaceAll(RegExp(r'[.!?,]+$'), '');
  const words = {
    'any', 'anything', 'any brand', 'any one', 'anyone', 'no preference', "doesn't matter", 'does not matter',
    "don't care", 'dont care', 'whatever', 'no idea', 'not sure', 'skip',
    'ఏదైనా', 'ఏదైనా సరే', 'ఏదో ఒకటి', 'పర్వాలేదు', 'ఏదైనా పర్వాలేదు', 'తెలియదు',
    'कोई भी', 'कुछ भी', 'कोई फर्क नहीं', 'पता नहीं',
  };
  return words.contains(t);
}

/// Final recommendations wait while the advisor still needs a REQUIRED,
/// decision-changing answer (e.g. budget for a TV) -- unless the user asked
/// to see options now or asked for videos.
bool askodoxAdvisorHolds(AskodoxAdvisorView? advisor, {required bool showNow, required bool videoAsk}) =>
    advisor != null &&
    !advisor.ready &&
    advisor.required &&
    (advisor.question?.trim().isNotEmpty ?? false) &&
    !showNow &&
    !videoAsk;

/// Result groups named in the customer's own words (any of en / te / hi).
List<String> askodoxRequestedGroups(String text) {
  final t = text.toLowerCase();
  return [
    // Reviews are the videos group on the backend (review videos, unboxing).
    if (RegExp(r'\b(videos?|shorts?|reels?|youtube|reviews?|unboxing)\b|వీడియో|రివ్యూ|वीडियो|रिव्यू').hasMatch(t))
      'videos',
    if (RegExp(r'\b(deals?|offers?|discounts?|coupons?|cashback|bank offer)\b|ఆఫర్|డీల్|ऑफ़र|डील').hasMatch(t))
      'deals',
  ];
}


/// Which canonical sections the chat draws for [shown] rows, and the reason
/// for every returned section it does not draw (Result Diagnostics).
({List<String> rendered, Map<String, String> hidden}) askodoxRenderedSections(
    ResultContract contract, List<UniversalMatch> shown, {String? heldReason}) {
  final ids = {for (final m in shown) m.id};
  final rendered = <String>[];
  final hidden = <String, String>{};
  for (final section in contract.sections) {
    if (section.itemIds.isEmpty) {
      // An asked-for empty section is drawn as its honest notice.
      if (section.requested && heldReason == null) rendered.add(section.kind);
      continue;
    }
    if (heldReason != null) {
      hidden[section.kind] = heldReason;
    } else if (section.itemIds.any(ids.contains)) {
      rendered.add(section.kind);
    } else {
      hidden[section.kind] = 'rows not passed to the chat view';
    }
  }
  return (rendered: rendered, hidden: hidden);
}
