/// Smart Answer chips (owner 2026-11-08): the brain's short "tap to say next"
/// options under the latest reply (backend `reply_suggestions.py`). The server
/// already cleans them; this is the app's own last guard so a bad payload can
/// never draw a long, duplicated or link-like chip.
library;

const int askodoxMaxSuggestionChips = 5;
const int askodoxMaxSuggestionChars = 40;

final RegExp _askodoxChipLink = RegExp(r'(https?://|www\.|@)', caseSensitive: false);

/// 2-5 distinct, short chips in the server's order, or none.
List<String> askodoxSuggestionChips(Iterable<String> raw) {
  final seen = <String>{};
  final chips = <String>[];
  for (final value in raw) {
    final chip = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (chip.isEmpty || chip.length > askodoxMaxSuggestionChars || _askodoxChipLink.hasMatch(chip)) continue;
    if (!seen.add(chip.toLowerCase())) continue;
    chips.add(chip);
    if (chips.length == askodoxMaxSuggestionChips) break;
  }
  return chips.length >= 2 ? List.unmodifiable(chips) : const <String>[];
}
