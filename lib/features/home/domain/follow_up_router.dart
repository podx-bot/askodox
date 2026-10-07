import '../../matching/data/universal_match_repository.dart';
import 'chat_result_policy.dart';

/// What a follow-up message wants done with the results ALREADY on screen.
/// "Compare the best 3" compares the current set -- it never starts an
/// unrelated search or gets a canned "looking for videos" reply.
enum AskodoxFollowUp { compare, cheapest, nearest, topRated, underBudget, onlyLocal, onlyOnline, deals, reviews, directions }

final _num = RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*(k|thousand|వేల|हज़ार|हजार)?', caseSensitive: false);

/// The follow-up intent of [text] about shown results, or null for anything
/// else (a new request, a detail answer, advice ...).
AskodoxFollowUp? askodoxFollowUpIntent(String text) {
  final t = ' ${text.toLowerCase().trim()} ';
  bool has(String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(t);
  // A brand-new request ("compare iphone 15 and pixel 8 prices") names its
  // own products; the shown-results reading needs a pointer to them.
  final pointer = has(r'\b(these|them|those|(this|that|the) (one|shop|store|place|seller|option|product|item)|ones?|above|shown|results?|both|all of them)\b') ||
      has(r'\b(best|top|first)\s*(\d|two|three|four|five)\b') ||
      has(r'ఇవి|వీటి|వాటి');
  // "show me fridge options under 40000" / "find AC shops in Guntur" is a NEW
  // request -- only a pointer to what is shown makes it a follow-up.
  final newRequest = has(r'^\s*(show|find|search|need|buy|book)\b') ||
      has(r'\b(show me|find me|search for|i want|i need|looking for|get me|want to buy)\b') ||
      has(r'\b(near me|nearby|in [a-z]{3,})\b');
  if (newRequest && !pointer) return null;
  final aboutShown = pointer || has(r'\b(compare|cheapest|nearest|closest|which one|which is)\b') || has(r'పోల్చ|ఏది');
  if (!aboutShown) return null;
  if (has(r'\bcompare\b|\bcomparison\b|పోల్చ|पोलिक|तुलना')) return AskodoxFollowUp.compare;
  if (has(r'\b(cheapest|lowest price|least expensive|sort by price)\b|తక్కువ ధర|सबसे सस्ता')) return AskodoxFollowUp.cheapest;
  if (has(r'\b(nearest|closest|sort by distance)\b|దగ్గరగా ఉన్న|सबसे पास')) return AskodoxFollowUp.nearest;
  if (has(r'\b(best rated|top rated|highest rated|sort by rating)\b')) return AskodoxFollowUp.topRated;
  if (has(r'\b(under|below|less than|within|upto|up to)\s*(₹|rs\.?|inr)?\s*\d') || has(r'లోపు|से कम')) {
    return AskodoxFollowUp.underBudget;
  }
  if (has(r'\b(only|just) (local|nearby|shops?)\b|\blocal (ones|only)\b')) return AskodoxFollowUp.onlyLocal;
  if (has(r'\b(only|just) online\b|\bonline (ones|only)\b')) return AskodoxFollowUp.onlyOnline;
  if (has(r'\b(deals?|offers?|discounts?|coupons?)\b|ఆఫర్|డీల్|ऑफर')) return AskodoxFollowUp.deals;
  if (has(r'\b(reviews?|ratings?)\b|రివ్యూ|రేటింగ్|रिव्यू')) return AskodoxFollowUp.reviews;
  if (has(r'\b(directions?|route|how (do i|to) (get|reach|go))\b|దారి|రూట్|रास्ता')) return AskodoxFollowUp.directions;
  return null;
}

/// The amount in "under ₹40,000" / "below 40k" / "40 వేల లోపు".
double? askodoxFollowUpBudget(String text) {
  final m = _num.firstMatch(text.replaceAll('₹', ' '));
  if (m == null) return null;
  final value = double.tryParse(m.group(1)!.replaceAll(',', ''));
  if (value == null) return null;
  return m.group(2) == null ? value : value * 1000;
}

String _price(UniversalMatch m, bool te) => askodoxPriceLabel(m, te: te) ?? (te ? 'ధర ధృవీకరించలేదు' : 'Price not verified');

String _where(UniversalMatch m, bool te) {
  final local = m.source == 'local' || m.source == 'external' || m.segment == 'registered' || m.distanceKm != null;
  final registered = m.segment == 'registered';
  final kind = registered
      ? (te ? 'ASKODOX నమోదు విక్రేత' : 'ASKODOX registered seller')
      : local
          ? (te ? 'దగ్గరి షాప్ (Google)' : 'Nearby shop (Google listing)')
          : (m.sourceName?.trim().isNotEmpty == true ? m.sourceName!.trim() : (te ? 'ఆన్‌లైన్' : 'Online'));
  final distance = m.distanceKm == null ? '' : ' · ${askodoxDistanceLabel(m.distanceKm!, telugu: te)}';
  return '$kind$distance';
}

String _rating(UniversalMatch m, bool te) => m.ratingAverage == null
    ? (te ? 'రేటింగ్: ధృవీకరించలేదు' : 'Rating: Not verified')
    : '★ ${m.ratingAverage!.toStringAsFixed(1)}${m.reviewCount > 0 ? ' (${m.reviewCount})' : ''}';

String _stock(UniversalMatch m, bool te) =>
    askodoxStockLabel(m, te: te) ?? (te ? 'స్టాక్: ధృవీకరించలేదు' : 'Stock: Not verified');

String _name(UniversalMatch m, bool te) =>
    askodoxComparableLabel(m) ?? (te ? 'పేరు ఇవ్వని ఎంపిక' : 'Unnamed option');

String _line(int i, UniversalMatch m, bool te) =>
    '${i + 1}. ${_name(m, te)}\n   ${_price(m, te)} · ${_where(m, te)}\n   ${_rating(m, te)} · ${_stock(m, te)}'
    '${m.offerTitle?.trim().isNotEmpty == true ? '\n   ${te ? 'ఆఫర్' : 'Offer'}: ${m.offerTitle!.trim()}' : ''}';

/// Real result rows only (no videos / jobs / news) in the order shown.
List<UniversalMatch> askodoxComparableRows(List<UniversalMatch> rows) => [
      for (final m in rows)
        if (m.source != 'video' && m.source != 'content' && m.source != 'job' && m.videoId == null) m,
    ];

/// A deterministic answer from the shown results, or null when the follow-up
/// needs something the shown results cannot answer (then the normal flow
/// searches -- e.g. reviews when no row carries a rating).
String? askodoxAnswerFollowUp(AskodoxFollowUp intent, List<UniversalMatch> shown,
    {required bool te, double? budget, int top = 3}) {
  final rows = askodoxComparableRows(shown);
  if (rows.isEmpty) return null;
  String list(List<UniversalMatch> items) => [for (final e in items.indexed) _line(e.$1, e.$2, te)].join('\n');
  final notVerifiedNote = te
      ? 'మూలం ఇవ్వని వివరాలు "ధృవీకరించలేదు" అని ఉన్నాయి -- ఊహించలేదు.'
      : 'Anything the source did not state is marked "Not verified" -- nothing is guessed.';
  switch (intent) {
    case AskodoxFollowUp.compare:
      final pick = rows.take(top).toList();
      final priced = [for (final m in pick) if (m.price != null) m]..sort((a, b) => a.price!.compareTo(b.price!));
      final near = [for (final m in pick) if (m.distanceKm != null) m]
        ..sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
      final summary = <String>[
        if (priced.isNotEmpty) te ? 'తక్కువ ధర: ${_name(priced.first, te)}' : 'Lowest stated price: ${_name(priced.first, te)}',
        if (near.isNotEmpty) te ? 'దగ్గరగా: ${_name(near.first, te)}' : 'Nearest: ${_name(near.first, te)}',
      ];
      return [
        te ? 'చూపిన ${pick.length} ఆప్షన్ల పోలిక:' : 'Comparing the ${pick.length} options shown:',
        list(pick),
        if (summary.isNotEmpty) summary.join(' · '),
        notVerifiedNote,
      ].join('\n\n');
    case AskodoxFollowUp.cheapest:
      final priced = [for (final m in rows) if (m.price != null) m]..sort((a, b) => a.price!.compareTo(b.price!));
      if (priced.isEmpty) return te ? 'చూపిన ఆప్షన్లలో ధర ధృవీకరించబడలేదు.' : 'None of the shown options states a price.';
      return '${te ? 'ధర ప్రకారం (తక్కువ నుంచి):' : 'By stated price (lowest first):'}\n\n${list(priced.take(top).toList())}';
    case AskodoxFollowUp.nearest:
      final near = [for (final m in rows) if (m.distanceKm != null) m]
        ..sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
      if (near.isEmpty) return te ? 'చూపిన ఆప్షన్లకు దూరం లేదు (ఆన్‌లైన్).' : 'None of the shown options has a distance (they are online).';
      return '${te ? 'దూరం ప్రకారం:' : 'By distance:'}\n\n${list(near.take(top).toList())}';
    case AskodoxFollowUp.topRated:
      final rated = [for (final m in rows) if (m.ratingAverage != null) m]
        ..sort((a, b) => b.ratingAverage!.compareTo(a.ratingAverage!));
      if (rated.isEmpty) return null;
      return '${te ? 'రేటింగ్ ప్రకారం:' : 'By rating (as stated by the source):'}\n\n${list(rated.take(top).toList())}';
    case AskodoxFollowUp.underBudget:
      if (budget == null) return null;
      final within = [
        for (final m in rows)
          if (m.price != null && m.price! <= budget && m.priceKind != 'starting_from') m,
      ];
      final conditional = [
        for (final m in rows)
          if (!within.contains(m) && m.offerPrice != null && m.offerPrice! <= budget) m,
      ];
      final unknown = [
        for (final m in rows)
          if (!within.contains(m) && !conditional.contains(m) && (m.price == null || m.priceKind == 'starting_from')) m,
      ].length;
      final amount = '₹${budget.toStringAsFixed(0)}';
      if (within.isEmpty && conditional.isNotEmpty) {
        return [
          te ? '$amount లోపు సాధారణ ధర ఉన్నది లేదు. ఆఫర్‌తో మాత్రమే:' : 'None is within $amount at its normal price. Only with an eligible offer:',
          list(conditional.take(top + 2).toList()),
        ].join('\n\n');
      }
      if (within.isEmpty) {
        return te
            ? 'చూపిన వాటిలో $amount లోపు ధర ఉన్నది లేదు${unknown > 0 ? ' ($unknown ఆప్షన్లకు ధర ధృవీకరించలేదు)' : ''}.'
            : 'None of the shown options states a price within $amount'
                '${unknown > 0 ? ' ($unknown have no verified price)' : ''}.';
      }
      return [
        te ? '$amount లోపు (మూలం చెప్పిన ధర):' : 'Within $amount (price as stated by the source):',
        list(within.take(top + 2).toList()),
        if (conditional.isNotEmpty) te ? 'ఆఫర్‌తో మాత్రమే బడ్జెట్‌లో:' : 'Within budget only with an eligible offer:',
        if (conditional.isNotEmpty) list(conditional.take(top).toList()),
        if (unknown > 0) te ? '$unknown ఆప్షన్లకు ధర ధృవీకరించలేదు -- చేర్చలేదు.' : '$unknown option(s) have no verified price and are not included.',
      ].join('\n\n');
    case AskodoxFollowUp.onlyLocal:
      final local = [for (final m in rows) if (m.distanceKm != null || m.segment == 'registered' || m.source == 'local') m];
      if (local.isEmpty) return te ? 'చూపిన వాటిలో దగ్గరి షాపులు లేవు.' : 'No nearby shop is among the shown options.';
      return '${te ? 'దగ్గరి ఆప్షన్లు:' : 'Nearby options:'}\n\n${list(local.take(top + 2).toList())}';
    case AskodoxFollowUp.onlyOnline:
      final online = [for (final m in rows) if (m.distanceKm == null && m.segment != 'registered' && m.source != 'local') m];
      if (online.isEmpty) return te ? 'చూపిన వాటిలో ఆన్‌లైన్ ఆప్షన్లు లేవు.' : 'No online option is among the shown options.';
      return '${te ? 'ఆన్‌లైన్ ఆప్షన్లు:' : 'Online options:'}\n\n${list(online.take(top + 2).toList())}';
    case AskodoxFollowUp.deals:
      final deals = [
        for (final m in rows)
          if (m.offerTitle?.trim().isNotEmpty == true ||
              (m.originalPrice != null && m.price != null && m.originalPrice! > m.price!) ||
              m.discountPercent != null ||
              m.segment == 'deals' ||
              (m.benefits?.isNotEmpty ?? false))
            m,
      ];
      if (deals.isEmpty) return null; // search for deals instead
      return '${te ? 'చూపిన వాటిలో ఆఫర్లు / డీల్స్:' : 'Deals / offers among the shown options:'}\n\n${list(deals.take(top + 2).toList())}\n\n'
          '${te ? 'ఆఫర్ షరతులు (బ్యాంక్ కార్డ్ వంటివి) మూలం పేజీలో చూడండి.' : 'Check conditions (bank card, coupon, exchange) on the source page.'}';
    case AskodoxFollowUp.reviews:
      final rated = [for (final m in rows) if (m.ratingAverage != null) m];
      if (rated.isEmpty) return null; // look for real review videos instead
      return '${te ? 'మూలం చెప్పిన రేటింగ్‌లు:' : 'Ratings stated by the sources:'}\n\n${list(rated.take(top + 2).toList())}\n\n$notVerifiedNote';
    case AskodoxFollowUp.directions:
      return null; // handled by the caller (opens Maps for a local option)
  }
}
