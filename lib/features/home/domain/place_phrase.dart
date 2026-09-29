import '../../../services/place_name_service.dart';

/// One place for composing "thing in place" in the conversation
/// language. It never repeats a place that is already in the text and
/// never mixes connectors -- the real-phone bug was
/// "Vuyyuru, Andhra Pradeshలో in Vuyyuru, Andhra Pradesh".

const _postpositions = r'(లోని|లోనే|లో|దగ్గర|వద్ద|में|के पास|पास)';

/// "Vuyyuru, Andhra Pradeshలో" / "in Vuyyuru, Andhra Pradesh, India" ->
/// "Vuyyuru, Andhra Pradesh".
String askodoxCleanPlace(String place) {
  var text = place.trim();
  text = text.replaceFirst(RegExp(r'^(in|at|near)\s+', caseSensitive: false), '');
  text = text.replaceFirst(RegExp('\\s*$_postpositions\\s*\$'), '');
  return askodoxJoinPlace([text]);
}

/// The town alone ("Vuyyuru") -- what people say in a sentence.
String askodoxShortPlace(String place) => askodoxCleanPlace(place).split(',').first.trim();

/// Removes the place (full or town, with its connector) from [text].
String askodoxWithoutPlace(String text, String place) {
  final full = askodoxCleanPlace(place);
  if (full.isEmpty) return text.trim();
  var out = text;
  for (final p in {full, askodoxShortPlace(full)}) {
    if (p.isEmpty) continue;
    final escaped = RegExp.escape(p);
    out = out
        .replaceAll(RegExp('\\b(in|at|near)\\s+$escaped(,\\s*[^,\\d]+)?(,\\s*india)?', caseSensitive: false), ' ')
        .replaceAll(RegExp('$escaped(,\\s*[^,\\sలమ]+( [^,\\sలమ]+)?)?\\s*$_postpositions', caseSensitive: false), ' ')
        .replaceAll(RegExp('(^|\\s)$escaped(\\s|\$)', caseSensitive: false), ' ');
  }
  return out.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'\s+,'), ',').trim();
}

/// "subject in town" in [lang] (te / hi put the place first).
String askodoxWithPlace(String subject, String place, String lang) {
  final town = askodoxShortPlace(place);
  final thing = askodoxWithoutPlace(subject, place);
  if (town.isEmpty) return thing;
  return switch (lang) {
    'te' => '$townలో $thing'.trim(),
    'hi' => '$town में $thing'.trim(),
    _ => '$thing in $town'.trim(),
  };
}
