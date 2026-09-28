/// A typed confirmation ("yes", "order it", "send request", "book it",
/// "confirm", "సరే పంపండి", "हाँ भेजो") is the SAME action as tapping the
/// option's Send request / Connect button -- never just more chat text.
library;

import '../../matching/data/universal_match_repository.dart';

final _confirm = RegExp(
  r'^(yes|yeah|yep|ok|okay|sure|go ahead|proceed|confirm|confirmed|done|do it|please do|go)\b'
  r'|\b(order (it|this|that|now|the)|place (the |an |my )?order|send (the |a |my )?request|send it'
  r"|book (it|this|that|now)|buy (it|this|that|now)|i('ll| will) (take|buy) (it|this|that)|go with"
  r"|i want (this|that|it)( one)?$|i('ll| will) buy|get (it|this|that) for me"
  r'|(contact|call|message|connect (me )?(with|to)) (the |this |that )?(seller|provider|shop|owner|store)'
  r'|connect me)\b'
  r'|అవును|సరే|ఓకే|పంపండి|పంపు|ఆర్డర్ చేయ|బుక్ చేయ|కొంటాను'
  r'|हाँ|हां|ठीक है|भेजो|भेज दो|ऑर्डर कर|बुक कर',
  caseSensitive: false,
);

final _negative = RegExp(
  r"\b(no|not|don'?t|do not|cancel|wait|stop|later|never|instead|other|another|cheaper|compare)\b"
  r'|వద్దు|కాదు|ఆగండి|नहीं|मत|रुको',
  caseSensitive: false,
);

/// True for a short, affirmative instruction to act on the shown option.
bool askodoxConfirmsAction(String text) {
  final t = text.trim();
  if (t.isEmpty || t.contains('?')) return false;
  if (t.split(RegExp(r'\s+')).length > 9) return false;
  if (_negative.hasMatch(t)) return false;
  return _confirm.hasMatch(t);
}

const _ordinals = <String, int>{
  // Not "one": "the second one" must never read as the first option.
  'first': 0, '1st': 0, 'మొదటి': 0, 'पहला': 0, 'पहले': 0,
  'second': 1, '2nd': 1, 'రెండవ': 1, 'రెండో': 1, 'दूसरा': 1, 'दूसरे': 1,
  'third': 2, '3rd': 2, 'మూడవ': 2, 'మూడో': 2, 'तीसरा': 2,
};

Set<String> _words(String text) => {
      for (final w in text.toLowerCase().split(RegExp(r'[^a-z0-9ఀ-౿ऀ-ॿ]+')))
        if (w.length > 1) w,
    };

/// Which option the confirmation is about: an ordinal ("the second one",
/// "option 2"), a named title, the option the user was just discussing,
/// else the top-ranked actionable option.
UniversalMatch? askodoxPickTarget(
  String text,
  List<UniversalMatch> actionable, {
  UniversalMatch? focused,
}) {
  if (actionable.isEmpty) return null;
  final lower = text.toLowerCase();
  final numbered = RegExp(r'\b(?:option|no\.?|number|#)\s*(\d)\b').firstMatch(lower);
  if (numbered != null) {
    final i = int.parse(numbered.group(1)!) - 1;
    if (i >= 0 && i < actionable.length) return actionable[i];
  }
  for (final entry in _ordinals.entries) {
    if (RegExp('(^|\\s)${RegExp.escape(entry.key)}(\\s|\$)').hasMatch(lower) &&
        entry.value < actionable.length) {
      return actionable[entry.value];
    }
  }
  final said = _words(text);
  // Only words that tell the options apart ("LG" vs "Sony"), not the ones
  // every option shares ("43 inch TV").
  final shared = actionable.length < 2
      ? <String>{}
      : actionable.map((m) => _words(m.title)).reduce((a, b) => a.intersection(b));
  UniversalMatch? best;
  var bestHits = 0;
  for (final match in actionable) {
    final hits = _words(match.title).difference(shared).intersection(said).length;
    if (hits > bestHits) {
      best = match;
      bestHits = hits;
    }
  }
  if (best != null && bestHits >= 1) return best;
  if (focused != null && actionable.any((m) => m.id == focused.id)) return focused;
  return actionable.first;
}

final _listIntent = RegExp(
  r'\b(sell|selling|list|post|publish|put up) (this|it|these|my)\b|\bfor sale\b|\bcatalog(ue)? (this|it)\b'
  r'|అమ్మాలి|అమ్ముతాను|లిస్ట్ చేయ|बेचना|बेचो',
  caseSensitive: false,
);

/// "Sell this" / "list this" with a photo or video: build a catalog draft.
bool askodoxWantsToList(String text) => _listIntent.hasMatch(text);
