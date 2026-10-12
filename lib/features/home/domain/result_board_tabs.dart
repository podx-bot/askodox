/// The compact Result Board tab row (Navigator UX):
/// "Result Board | Local | Online | Deals | Reviews | Videos | Minimize".
///
/// Pure functions over the SAME result set the board already holds -- tabs
/// are views, never extra searches, and nothing here is category-specific
/// (docs/UNIVERSAL_DEVELOPMENT_RULE.md). A tab with nothing grounded says so
/// honestly; it never fills itself with invented rows.
library;

import '../../matching/data/universal_match_repository.dart';
import 'chat_result_policy.dart';

enum AskodoxBoardTab { all, local, online, deals, reviews, videos }

/// Rows a tab shows, in the board's organic order (Reviews: best rated first).
List<UniversalMatch> askodoxBoardTabRows(AskodoxBoardTab tab, List<UniversalMatch> matches) {
  switch (tab) {
    case AskodoxBoardTab.all:
      return List<UniversalMatch>.of(matches);
    case AskodoxBoardTab.local:
      return [
        for (final m in matches)
          if (const {AskodoxCompareKind.local, AskodoxCompareKind.used, AskodoxCompareKind.surplus}
              .contains(askodoxCompareKindOf(m)))
            m,
      ];
    case AskodoxBoardTab.online:
      return [
        for (final m in matches)
          if (const {
            AskodoxCompareKind.online,
            AskodoxCompareKind.affiliate,
            AskodoxCompareKind.sponsored,
            AskodoxCompareKind.jobs,
            AskodoxCompareKind.news,
          }.contains(askodoxCompareKindOf(m)))
            m,
      ];
    case AskodoxBoardTab.deals:
      return [for (final m in matches) if (askodoxIsDeal(m)) m];
    case AskodoxBoardTab.reviews:
      final rows = [for (final m in matches) if (askodoxHasGroundedReviews(m)) m];
      rows.sort((a, b) {
        final byRating = (b.ratingAverage ?? 0).compareTo(a.ratingAverage ?? 0);
        return byRating != 0 ? byRating : b.reviewCount.compareTo(a.reviewCount);
      });
      return rows;
    case AskodoxBoardTab.videos:
      return [
        for (final m in matches)
          if (const {AskodoxCompareKind.videos, AskodoxCompareKind.shorts}.contains(askodoxCompareKindOf(m))) m,
      ];
  }
}

/// A deal = a deals-source row or a row carrying a real offer / discount
/// from its source (never a guessed one).
bool askodoxIsDeal(UniversalMatch m) =>
    askodoxCompareKindOf(m) == AskodoxCompareKind.deals ||
    m.offerPrice != null ||
    (m.discountPercent ?? 0) > 0 ||
    (m.offerTitle ?? '').trim().isNotEmpty;

/// Reviews only when the source reported both a rating and a review count.
bool askodoxHasGroundedReviews(UniversalMatch m) => m.ratingAverage != null && m.reviewCount > 0;

Map<AskodoxBoardTab, int> askodoxBoardTabCounts(List<UniversalMatch> matches) => {
      for (final tab in AskodoxBoardTab.values) tab: askodoxBoardTabRows(tab, matches).length,
    };

/// The same result set narrowed to one tab (notices / sources / advisor kept).
AskodoxChatResults askodoxResultsForTab(AskodoxChatResults results, AskodoxBoardTab tab) {
  if (tab == AskodoxBoardTab.all) return results;
  return AskodoxChatResults(
    dealId: results.dealId,
    matches: askodoxBoardTabRows(tab, results.matches),
    failed: results.failed,
    signInRequired: results.signInRequired,
    missingFields: results.missingFields,
    sourceStatus: results.sourceStatus,
    searched: results.searched,
    broadcastSent: null,
    scopeMessage: null,
    traceKey: results.traceKey,
    advisor: results.advisor,
    contract: results.contract,
  );
}

String askodoxBoardTabLabel(AskodoxBoardTab tab, String lang) => switch (lang) {
      'te' => switch (tab) {
          AskodoxBoardTab.all => 'ఫలితాలు',
          AskodoxBoardTab.local => 'స్థానికం',
          AskodoxBoardTab.online => 'ఆన్‌లైన్',
          AskodoxBoardTab.deals => 'డీల్స్',
          AskodoxBoardTab.reviews => 'రివ్యూలు',
          AskodoxBoardTab.videos => 'వీడియోలు',
        },
      'hi' => switch (tab) {
          AskodoxBoardTab.all => 'नतीजे',
          AskodoxBoardTab.local => 'लोकल',
          AskodoxBoardTab.online => 'ऑनलाइन',
          AskodoxBoardTab.deals => 'डील्स',
          AskodoxBoardTab.reviews => 'रिव्यू',
          AskodoxBoardTab.videos => 'वीडियो',
        },
      _ => switch (tab) {
          AskodoxBoardTab.all => 'Result Board',
          AskodoxBoardTab.local => 'Local',
          AskodoxBoardTab.online => 'Online',
          AskodoxBoardTab.deals => 'Deals',
          AskodoxBoardTab.reviews => 'Reviews',
          AskodoxBoardTab.videos => 'Videos',
        },
    };

/// Honest empty state for a tab with nothing grounded in this result set.
String askodoxBoardTabEmptyText(AskodoxBoardTab tab, String lang) {
  final te = lang == 'te';
  return switch (tab) {
    AskodoxBoardTab.local =>
      te ? 'ఈ అవసరానికి దగ్గరలో ఇంకా ఫలితాలు లేవు.' : 'No nearby results for this yet.',
    AskodoxBoardTab.online => te ? 'ఆన్‌లైన్ ఫలితాలు లేవు.' : 'No online results for this.',
    AskodoxBoardTab.deals =>
      te ? 'ధృవీకరించిన ఆఫర్లు ఏవీ లేవు.' : 'No verified offers for these results.',
    AskodoxBoardTab.reviews => te
        ? 'ఈ ఫలితాలకు ధృవీకరించిన రివ్యూలు లేవు -- రేటింగ్‌లు ఊహించము.'
        : 'No verified reviews for these results -- ratings are never guessed.',
    AskodoxBoardTab.videos => te ? 'ఈ అవసరానికి వీడియోలు లేవు.' : 'No videos for this.',
    AskodoxBoardTab.all => te ? 'ఫలితాలు లేవు.' : 'No results.',
  };
}

/// One filter chip of the Result Board: a structured detail sellers gave on
/// the SHOWN rows (never a guessed value) and how many rows carry it.
class AskodoxAttributeChip {
  const AskodoxAttributeChip(this.key, this.value, this.count);
  final String key, value;
  final int count;

  String get id => '$key=$value';

  /// "size_uk" -> "Size uk: 9"
  String get label {
    final words = key.replaceAll('_', ' ').trim();
    return '${words.isEmpty ? key : words[0].toUpperCase() + words.substring(1)}: $value';
  }
}

/// Filter chips from the rows' own attributes: a multi value ("Cash, UPI")
/// counts per part; a key appears only when the rows differ on it (a filter
/// that keeps every row is no filter). Most common first, at most [limit].
List<AskodoxAttributeChip> askodoxAttributeChips(List<UniversalMatch> matches, {int limit = 8}) {
  final counts = <String, Map<String, int>>{};
  for (final m in matches) {
    for (final e in m.attributes.entries) {
      for (final part in e.value.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toSet()) {
        (counts[e.key] ??= {})[part] = ((counts[e.key] ?? const {})[part] ?? 0) + 1;
      }
    }
  }
  final chips = <AskodoxAttributeChip>[
    for (final e in counts.entries)
      for (final v in e.value.entries)
        if (v.value < matches.length || e.value.length > 1) AskodoxAttributeChip(e.key, v.key, v.value),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return chips.take(limit).toList();
}

/// Rows carrying EVERY chosen detail (chips are views of the deck, never a
/// new search). Rows without that detail are not shown under the filter.
List<UniversalMatch> askodoxFilterByAttributes(List<UniversalMatch> matches, Set<String> chosen) {
  if (chosen.isEmpty) return matches;
  bool has(UniversalMatch m, String id) {
    final i = id.indexOf('=');
    final value = m.attributes[id.substring(0, i)];
    return value != null && value.split(',').map((v) => v.trim()).contains(id.substring(i + 1));
  }

  return [for (final m in matches) if (chosen.every((id) => has(m, id))) m];
}

/// The deck narrowed by chosen attribute chips (notices / sources kept).
AskodoxChatResults askodoxResultsForAttributes(AskodoxChatResults results, Set<String> chosen) {
  if (chosen.isEmpty) return results;
  return AskodoxChatResults(
    dealId: results.dealId,
    matches: askodoxFilterByAttributes(results.matches, chosen),
    failed: results.failed,
    signInRequired: results.signInRequired,
    missingFields: results.missingFields,
    sourceStatus: results.sourceStatus,
    searched: results.searched,
    broadcastSent: null,
    scopeMessage: null,
    traceKey: results.traceKey,
    advisor: results.advisor,
    contract: results.contract,
  );
}
