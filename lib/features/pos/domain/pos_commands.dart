import 'pos_money.dart';
import 'pos_name_sound.dart';

/// Typed / spoken counter commands in English and Telugu, e.g.
/// "add 2 kg chicken at 240 per kg", "అర కిలో చికెన్", "remove chicken",
/// "discount 10%", and an item said in any script ("రెండు చికెన్ బిర్యానీ" finds "Chicken Biryani",
/// see pos_name_sound.dart). The parser only PROPOSES an action; the cart changes only
/// after the cashier confirms it (AI never edits a cart, price or invoice
/// silently), and a changed price is still checked by the server's roles.
enum AskodoxPosCommandKind { add, remove, discount, clear, checkout, unknown }

class AskodoxPosItemRef {
  const AskodoxPosItemRef({required this.id, required this.name, this.nameTe = '', required this.unit, this.itemNo = 0});
  final String id;
  final String name;
  final String nameTe;
  final String unit;

  /// The item's menu number (0 = none): "number 20 two", "20 నంబర్ 2", "#20 x2" pick it.
  final int itemNo;
}

final _itemNumberPattern = RegExp(
    r'(?:#|\bno\.?\s*|\bnumber\s*|\bnum\s*|నంబర్\s*|నెంబర్\s*|నంబరు\s*)(\d+)|(\d+)\s*(?:\bnumber\b|నంబర్|నెంబర్|నంబరు|వ\s*నంబర్)');

class AskodoxPosCommand {
  const AskodoxPosCommand(this.kind,
      {this.item, this.query = '', this.qtyMilli, this.pricePaise, this.discountPaise, this.discountBp, this.candidates = const []});
  final AskodoxPosCommandKind kind;
  final AskodoxPosItemRef? item;
  final String query;

  /// In the ITEM's own unit (milli-kg for a kg item, milli-pieces for pcs).
  final int? qtyMilli;
  final int? pricePaise;
  final int? discountPaise;
  final int? discountBp;

  /// More than one item matched, or only part of a name was heard: the cashier picks (never auto-picked).
  final List<AskodoxPosItemRef> candidates;

  bool get needsChoice => item == null && candidates.isNotEmpty;

  String describe(bool te) {
    final name = item == null ? query : (te && item!.nameTe.isNotEmpty ? item!.nameTe : item!.name);
    return switch (kind) {
      AskodoxPosCommandKind.add => [
          te ? 'జోడించాలా:' : 'Add:',
          if (qtyMilli != null) askodoxQty(qtyMilli!, item?.unit ?? ''),
          name,
          if (pricePaise != null) '@ ${askodoxPaise(pricePaise!)}${te ? ' (ధర మార్పు)' : ' (price change)'}',
        ].join(' '),
      AskodoxPosCommandKind.remove => '${te ? 'తీసేయాలా:' : 'Remove:'} $name',
      AskodoxPosCommandKind.discount => discountBp != null
          ? '${te ? 'డిస్కౌంట్:' : 'Discount:'} ${askodoxRate(discountBp!)}'
          : '${te ? 'డిస్కౌంట్:' : 'Discount:'} ${askodoxPaise(discountPaise ?? 0)}',
      AskodoxPosCommandKind.clear => te ? 'బిల్లు మొత్తం ఖాళీ చేయాలా?' : 'Clear the whole bill?',
      AskodoxPosCommandKind.checkout => te ? 'బిల్లు చేయాలా?' : 'Go to payment?',
      AskodoxPosCommandKind.unknown => te ? 'అర్థం కాలేదు' : 'Not understood',
    };
  }
}

const _fractionWords = {
  'అర': 500, 'అరకిలో': 500, 'half': 500, 'పావు': 250, 'quarter': 250, 'ముప్పావు': 750, 'ఒకటిన్నర': 1500,
  'pav': 250, 'paav': 250, 'pavu': 250, 'paavu': 250, 'ara': 500, 'muppavu': 750, 'pavukilo': 250,
  'ఒక': 1000, 'ఒకటి': 1000, 'రెండు': 2000, 'మూడు': 3000, 'నాలుగు': 4000, 'ఐదు': 5000, 'one': 1000, 'two': 2000,
  'three': 3000, 'four': 4000, 'five': 5000,
  'ఒక్క': 1000, 'ఒక్కటి': 1000, 'ఆరు': 6000, 'ఏడు': 7000, 'ఎనిమిది': 8000, 'తొమ్మిది': 9000, 'పది': 10000,
  'six': 6000, 'seven': 7000, 'eight': 8000, 'nine': 9000, 'ten': 10000,
  'एक': 1000, 'दो': 2000, 'तीन': 3000, 'चार': 4000, 'पांच': 5000, 'पाँच': 5000, 'छह': 6000, 'सात': 7000, 'आठ': 8000,
  'नौ': 9000, 'दस': 10000, 'आधा': 500, 'पाव': 250,
};

const _unitWords = {
  'kg': 'kg', 'kgs': 'kg', 'kilo': 'kg', 'kilos': 'kg', 'kilogram': 'kg', 'కిలో': 'kg', 'కిలోలు': 'kg', 'కేజీ': 'kg',
  'g': 'g', 'gm': 'g', 'gms': 'g', 'gram': 'g', 'grams': 'g', 'గ్రాములు': 'g', 'గ్రాము': 'g',
  'l': 'l', 'litre': 'l', 'liter': 'l', 'litres': 'l', 'లీటర్': 'l', 'లీటరు': 'l',
  'ml': 'ml',
  'pcs': 'pcs', 'pc': 'pcs', 'piece': 'pcs', 'pieces': 'pcs', 'nos': 'pcs', 'ముక్కలు': 'pcs',
  'dozen': 'dozen', 'డజను': 'dozen', 'plate': 'plate', 'plates': 'plate', 'ప్లేట్': 'plate',
  'packet': 'pack', 'packets': 'pack', 'pack': 'pack',
  'కిలోల': 'kg', 'కేజీలు': 'kg', 'గ్రాముల': 'g', 'లీటర్లు': 'l', 'లీటర్ల': 'l', 'ప్యాకెట్లు': 'pack', 'ప్యాకెట్': 'pack',
  'పీస్': 'pcs', 'పీసులు': 'pcs', 'పీస్‌లు': 'pcs', 'ముక్క': 'pcs', 'ప్లేట్లు': 'plate', 'ప్లేటు': 'plate', 'ప్యాక్': 'pack',
  'किलो': 'kg', 'ग्राम': 'g', 'लीटर': 'l', 'पीस': 'pcs', 'प्लेट': 'plate', 'पैकेट': 'pack',
};

const _removeWords = {'remove', 'delete', 'cancel', 'తీసేయ్', 'తీసేయి', 'తీసేయండి', 'వద్దు', 'తొలగించు'};
const _addWords = {'add', 'put', 'give', 'జోడించు', 'వేయి', 'వెయ్', 'ఇవ్వు', 'కావాలి', 'plus'};
const _fillerWords = {
  'and', 'of', 'the', 'a', 'an', 'please', 'ఇంకా', 'కూడా', 'per', 'each', 'rs', 'rupees', 'రూపాయలు', 'రూ',
  // how the order is packed or asked for -- never part of an item's name (owner 2026-11-24: "... బిర్యానీ పార్సెల్")
  'parcel', 'పార్సెల్', 'పార్శిల్', 'పార్సిల్', 'takeaway', 'టేకవే', 'టేక్అవే', 'pls', 'ప్లీజ్', 'ఇవ్వండి', 'వేయండి',
  'పెట్టు', 'పెట్టండి', 'पार्सल', 'चाहिए', 'दीजिए',
};

/// Counted units are one count: "2 plates" of a pieces item is 2 pieces.
const _countUnits = {'pcs', 'plate', 'pack', 'box'};

/// Lower case, ASCII digits (౬౫ -> 65), no sentence marks: a spoken "పార్సెల్." loses its full stop, "1.5" keeps its point.
String _plain(String text) => askodoxLatinDigits(text.toLowerCase())
    .replaceAll(RegExp(r'(?<!\d)\.|\.(?!\d)'), ' ')
    .replaceAll(RegExp('[।॥"“”]'), ' ');

bool _isNumber(String w) => RegExp(r'^\d+$').hasMatch(w);

/// "Chicken 65": a number that is part of a name, keyed by the sound of the word before it in that name.
Map<String, Set<String>> _nameNumbers(List<AskodoxPosItemRef> items) {
  final out = <String, Set<String>>{};
  for (final i in items) {
    for (final name in [i.name, i.nameTe]) {
      final words = askodoxSoundWords(name);
      for (var k = 1; k < words.length; k++) {
        if (_isNumber(words[k]) && !_isNumber(words[k - 1])) (out[words[k]] ??= {}).add(words[k - 1]);
      }
    }
  }
  return out;
}

/// "చికెన్ 65" / "chicken 65": the 65 is the name, not the quantity, when an item is called that.
bool _isNameNumber(String number, String? wordBefore, Map<String, Set<String>> nameNumbers) {
  final names = nameNumbers[number];
  if (names == null || wordBefore == null) return false;
  final before = askodoxSoundWords(wordBefore);
  return before.isNotEmpty && names.any((n) => askodoxSameSound(n, before.last));
}

/// Converts a spoken quantity in [spokenUnit] to milli-units of [itemUnit];
/// null when the two units cannot be converted (e.g. "kg" for a pieces item).
int? askodoxConvertQty(int milli, String? spokenUnit, String itemUnit) {
  if (spokenUnit == null || spokenUnit == itemUnit) return milli;
  if (_countUnits.contains(spokenUnit) && _countUnits.contains(itemUnit)) return milli;
  return switch ((spokenUnit, itemUnit)) {
    ('g', 'kg') || ('ml', 'l') => askodoxRoundDiv(milli, 1000),
    ('kg', 'g') || ('l', 'ml') => milli * 1000,
    ('dozen', 'pcs') => milli * 12,
    _ => null,
  };
}

/// [pick] = the item the cashier chose for this phrase by hand: the phrase gives only the quantity / price then.
AskodoxPosCommand askodoxParsePosCommand(String text, List<AskodoxPosItemRef> items, {AskodoxPosItemRef? pick}) {
  if (pick != null) items = [pick];
  var s = _plain(text).replaceAll('₹', ' rs ').replaceAll(RegExp(r'[,!?]'), ' ').trim();
  if (s.isEmpty) return const AskodoxPosCommand(AskodoxPosCommandKind.unknown);
  final words = s.split(RegExp(r'\s+'));
  bool has(Set<String> set) => words.any(set.contains);
  if (RegExp(r'^(clear|new bill|reset)\b').hasMatch(s) || s.contains('బిల్లు ఖాళీ')) {
    return const AskodoxPosCommand(AskodoxPosCommandKind.clear);
  }
  if (RegExp(r'^(checkout|pay|payment|total|bill it|finish)\b').hasMatch(s) || s.contains('బిల్లు చేయి') ||
      s.contains('బిల్ చేయి')) {
    return const AskodoxPosCommand(AskodoxPosCommandKind.checkout);
  }
  final discount = RegExp(r'(?:discount|డిస్కౌంట్|తగ్గింపు)\s*(?:of\s*)?(?:rs\s*)?(\d+(?:\.\d+)?)\s*(%|percent|శాతం)?').firstMatch(s);
  if (discount != null) {
    final percent = discount.group(2) != null;
    if (percent) {
      final bp = askodoxParsePaise(discount.group(1)!); // 10 -> 1000 bp, 12.5 -> 1250 bp
      if (bp != null && bp > 0 && bp <= 10000) return AskodoxPosCommand(AskodoxPosCommandKind.discount, discountBp: bp);
    } else {
      final paise = askodoxParsePaise(discount.group(1)!);
      if (paise != null && paise > 0) return AskodoxPosCommand(AskodoxPosCommandKind.discount, discountPaise: paise);
    }
    return const AskodoxPosCommand(AskodoxPosCommandKind.unknown);
  }

  // Owner 2026-11-20: the item's menu number picks it ("number 20 two" / "20 నంబర్ 2" / "#20 x2"); the other number is
  // the quantity.
  final numbered = _itemNumberPattern.firstMatch(s);
  if (numbered != null) {
    final no = int.tryParse(numbered.group(1) ?? numbered.group(2) ?? '') ?? 0;
    final hits = items.where((i) => i.itemNo > 0 && i.itemNo == no).toList();
    if (hits.length == 1) {
      final left = s.replaceRange(numbered.start, numbered.end, ' ');
      final remove = left.split(RegExp(r'\s+')).any(_removeWords.contains);
      final qtyMatch = RegExp(r'(\d+(?:\.\d{1,3})?)').firstMatch(left);
      final qty = qtyMatch == null ? 1000 : askodoxParseMilli(qtyMatch.group(1)!) ?? 1000;
      return AskodoxPosCommand(remove ? AskodoxPosCommandKind.remove : AskodoxPosCommandKind.add,
          item: hits.single, query: hits.single.name, qtyMilli: remove ? null : qty);
    }
  }

  // price: "at 240", "@240", "240 per kg", "కిలో 240"
  int? price;
  final priceMatch = RegExp(r'(?:@|\bat\b|\brate\b|ధర)\s*(?:rs\s*)?(\d+(?:\.\d{1,2})?)').firstMatch(s) ??
      RegExp(r'(?:rs\s*)?(\d+(?:\.\d{1,2})?)\s*(?:rs\s*)?(?:per|/)\s*\w+').firstMatch(s);
  if (priceMatch != null) {
    price = askodoxParsePaise(priceMatch.group(1)!);
    s = s.replaceRange(priceMatch.start, priceMatch.end, ' ');
  }

  int? qty;
  String? unit;
  String? unitWord; // the word that gave [unit]: dropped again when it is part of the item's name ("Family Pack ...")
  final nameNumbers = _nameNumbers(items);
  RegExpMatch? numberUnit;
  for (final m in RegExp(r'(\d+(?:\.\d{1,3})?)\s*([a-zఀ-౿]+)?').allMatches(s)) {
    final before = s.substring(0, m.start).trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).lastOrNull;
    if (_isNameNumber(m.group(1)!, before, nameNumbers)) continue; // "chicken 65" -- the 65 stays in the name
    numberUnit = m;
    break;
  }
  final rest = <String>[];
  var tokens = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (numberUnit != null) {
    qty = askodoxParseMilli(numberUnit.group(1)!);
    final maybeUnit = numberUnit.group(2);
    if (maybeUnit != null && _unitWords.containsKey(maybeUnit)) {
      unit = _unitWords[maybeUnit];
      unitWord = maybeUnit;
    }
    s = s.replaceRange(numberUnit.start, numberUnit.end, maybeUnit != null && unit == null ? ' $maybeUnit ' : ' ');
    tokens = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  }
  for (final w in tokens) {
    if (qty == null && _fractionWords.containsKey(w)) {
      qty = _fractionWords[w];
      continue;
    }
    if (w.startsWith('అరకిలో')) {
      qty ??= 500;
      unit ??= 'kg';
      continue;
    }
    if (_unitWords.containsKey(w)) {
      if (unit == null) {
        unit = _unitWords[w];
        unitWord = w;
      }
      // "Family Pack ..." / "Fry Piece Biryani": the unit word is also a name word -- it counts for the match too.
      if (_inSomeName(w, items)) rest.add(w);
      continue;
    }
    if (_removeWords.contains(w) || _addWords.contains(w) || _fillerWords.contains(w)) continue;
    rest.add(w);
  }
  final query = rest.join(' ').trim();
  final remove = has(_removeWords);
  if (query.isEmpty && pick == null) return const AskodoxPosCommand(AskodoxPosCommandKind.unknown);
  final matches = pick != null ? [pick] : askodoxMatchItems(query, items);
  final kind = remove ? AskodoxPosCommandKind.remove : AskodoxPosCommandKind.add;
  if (matches.length != 1) {
    // Nothing fits the whole phrase: items that share part of the name are offered to pick, never added by themselves.
    final offer = matches.isEmpty ? askodoxSuggestItems(query, items) : matches;
    return AskodoxPosCommand(kind, query: query, candidates: offer, qtyMilli: null, pricePaise: price);
  }
  final item = matches.single;
  if (unitWord != null && _inSomeName(unitWord, [item])) unit = null; // "1 family pack biryani" = one of that item
  int? itemQty;
  if (!remove) {
    itemQty = askodoxConvertQty(qty ?? 1000, unit, item.unit);
    if (itemQty == null || itemQty <= 0) {
      return AskodoxPosCommand(AskodoxPosCommandKind.unknown, query: query);
    }
  }
  return AskodoxPosCommand(kind, item: item, query: query, qtyMilli: itemQty, pricePaise: remove ? null : price);
}

/// A spoken plural back to its stem: "samosas" -> "samosa", "సమోసాలు" -> "సమోసా".
String _stem(String word) {
  if (word.endsWith('లు') && word.length > 3) return word.substring(0, word.length - 2);
  if (word.endsWith('es') && word.length > 4 && RegExp(r'(ch|sh|x|o)es$').hasMatch(word)) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('s') && !word.endsWith('ss') && word.length > 3) return word.substring(0, word.length - 1);
  return word;
}

/// Items whose English or Telugu name contains every word of [query] (plurals
/// allowed), else items whose whole name is inside the query (the longest such
/// name wins, so "kandi pappu" picks "Kandi pappu" over "Pappu"). Exact names win.
List<AskodoxPosItemRef> askodoxMatchItems(String query, List<AskodoxPosItemRef> items) {
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return const [];
  final stemQ = q.split(RegExp(r'\s+')).map(_stem).join(' ');
  String stemName(String name) => name.toLowerCase().split(RegExp(r'\s+')).map(_stem).join(' ');
  final exact = items
      .where((i) => i.name.toLowerCase() == q || i.nameTe == q || stemName(i.name) == stemQ || (i.nameTe.isNotEmpty && stemName(i.nameTe) == stemQ))
      .toList();
  if (exact.isNotEmpty) return exact;
  final parts = stemQ.split(' ');
  bool every(String name) {
    final n = name.toLowerCase();
    return n.isNotEmpty && parts.every(n.contains);
  }

  final all = items.where((i) => every(i.name) || every(i.nameTe)).toList();
  if (all.isNotEmpty) return all;
  int inside(String name) {
    final n = stemName(name);
    return n.isNotEmpty && (stemQ.contains(n) || q.contains(name.toLowerCase())) ? n.length : 0;
  }

  // Said in another script or spelled another way ("చికెన్ బిర్యానీ" / "chiken biriyani" = "Chicken Biryani").
  final bySound = _soundMatch(q, items);
  if (bySound.isNotEmpty) return bySound;
  final scored = [for (final i in items) (item: i, score: inside(i.name) > inside(i.nameTe) ? inside(i.name) : inside(i.nameTe))]
      .where((e) => e.score > 0)
      .toList();
  if (scored.isEmpty) return const [];
  final best = scored.map((e) => e.score).reduce((a, b) => a > b ? a : b);
  return [for (final e in scored) if (e.score == best) e.item];
}

/// How well the heard word sounds fit one name: name words heard, name words, heard words used.
({int covered, int words, int heard}) _soundFit(List<String> said, String name) {
  final words = askodoxSoundWords(name).toSet().toList();
  final used = <int>{};
  for (final w in words) {
    for (var k = 0; k < said.length; k++) {
      if (!used.contains(k) && askodoxSameSound(w, said[k])) {
        used.add(k);
        break;
      }
    }
  }
  return (covered: used.length, words: words.length, heard: used.length);
}

/// Items that fit the heard words by sound: the whole name was heard (extra words like "parcel" do not matter), or
/// every heard word is in the name. Most heard words explained wins, then a fully heard name; ties are all returned
/// (the cashier picks): "బిర్యానీ" with three biryanis on the menu offers the three.
List<AskodoxPosItemRef> _soundMatch(String query, List<AskodoxPosItemRef> items) {
  final said = askodoxSoundWords(query);
  if (said.isEmpty) return const [];
  var best = (heard: 0, full: 0);
  final out = <AskodoxPosItemRef>[];
  for (final i in items) {
    var mine = (heard: 0, full: 0);
    for (final name in [i.name, i.nameTe]) {
      final f = _soundFit(said, name);
      if (f.words == 0 || (f.covered < f.words && f.heard < said.length)) continue;
      final key = (heard: f.heard, full: f.covered == f.words ? 1 : 0);
      if (key.heard > mine.heard || (key.heard == mine.heard && key.full > mine.full)) mine = key;
    }
    if (mine.heard == 0) continue;
    if (mine.heard > best.heard || (mine.heard == best.heard && mine.full > best.full)) {
      best = mine;
      out
        ..clear()
        ..add(i);
    } else if (mine == best) {
      out.add(i);
    }
  }
  return out;
}

/// Only part of a name was heard ("ఫ్రై పీస్ బిర్యానీ" when the shop has "Chicken Biryani" only): the items sharing the
/// most heard words (3+ letter sounds or numbers), at most 6, to offer -- never to add without a tap.
List<AskodoxPosItemRef> askodoxSuggestItems(String query, List<AskodoxPosItemRef> items) {
  final said = [for (final w in askodoxSoundWords(query)) if (w.length >= 3 || _isNumber(w)) w];
  if (said.isEmpty) return const [];
  var best = 0;
  final out = <AskodoxPosItemRef>[];
  for (final i in items) {
    final f1 = _soundFit(said, i.name).heard;
    final f2 = _soundFit(said, i.nameTe).heard;
    final score = f1 > f2 ? f1 : f2;
    if (score == 0) continue;
    if (score > best) {
      best = score;
      out.clear();
    }
    if (score == best) out.add(i);
  }
  return out.take(6).toList();
}

/// The word sounds like a word of one of these items' names.
bool _inSomeName(String word, List<AskodoxPosItemRef> items) {
  final heard = askodoxSoundWords(word);
  if (heard.isEmpty) return false;
  return items.any((i) {
    final named = askodoxSoundWords('${i.name} ${i.nameTe}');
    return heard.every((h) => named.any((n) => askodoxSameSound(n, h)));
  });
}

bool _isQtyToken(String w) =>
    RegExp(r'^\d+(?:\.\d{1,3})?[a-zఀ-౿]*$').hasMatch(w) || _fractionWords.containsKey(w) || w.startsWith('అరకిలో');

bool _isUnitToken(String w) => _unitWords.containsKey(w);

const _priceWords = {'at', '@', 'rate', 'ధర', 'rs', 'per'};

/// Splits a spoken order of several items into one phrase per item:
/// commas / "and" / "మరియు" / new lines, and — when the speaker gave none —
/// a new quantity after an item name ("10 kg kandi pappu 20 samosa").
/// [items] (optional) keep a number that is part of a name with it ("రెండు చికెన్ 65 ఒక బిర్యానీ").
List<String> askodoxSplitPosOrder(String text, [List<AskodoxPosItemRef> items = const []]) {
  final nameNumbers = _nameNumbers(items);
  final out = <String>[];
  for (final raw in _plain(text).split(RegExp(r'[,;\n]+|\s+and\s+|\s+మరియు\s+|\s+ఇంకా\s+|\s+plus\s+', caseSensitive: false))) {
    // "number 20 two" / "20 నంబర్ 2" -> "#20 2": the menu number stays one name-like token with its quantity.
    final chunk = raw.toLowerCase().replaceAllMapped(_itemNumberPattern, (m) => ' #${m.group(1) ?? m.group(2)} ');
    final tokens = chunk.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (tokens.isEmpty) continue;
    // Command words, fillers and a spoken price ("at 240", "240 per kg") belong to the item they are with.
    bool neutral(int i) {
      final w = tokens[i];
      if (_addWords.contains(w) || _removeWords.contains(w) || _fillerWords.contains(w) || _priceWords.contains(w)) return true;
      if (i > 0 && _priceWords.contains(tokens[i - 1])) return true;
      if (i + 1 < tokens.length && (tokens[i + 1] == 'per' || tokens[i + 1] == '/')) return true;
      return false;
    }

    final firstReal = [for (var i = 0; i < tokens.length; i++) if (!neutral(i)) i].firstOrNull;
    final qtyFirst = firstReal != null && _isQtyToken(tokens[firstReal]);
    var current = <String>[];
    var hasName = false;
    var hasQty = false;
    void flush() {
      if (current.isNotEmpty) out.add(current.join(' '));
      current = [];
      hasName = false;
      hasQty = false;
    }

    for (var i = 0; i < tokens.length; i++) {
      final w = tokens[i];
      if (neutral(i)) {
        current.add(w);
        continue;
      }
      final unit = _isUnitToken(w);
      // "chicken 65" when the shop has an item called that: the number belongs to the name.
      final qty = _isQtyToken(w) && !(hasName && i > 0 && _isNumber(w) && _isNameNumber(w, tokens[i - 1], nameNumbers));
      if (qtyFirst) {
        // "10 kg dal 20 samosa": a quantity after a name starts the next item.
        if (qty && hasName) flush();
      } else {
        // "dal 10 kg samosa 20": a name after the quantity (+unit) starts the next item.
        if (!qty && !unit && hasName && hasQty) flush();
      }
      current.add(w);
      if (qty) {
        hasQty = true;
      } else if (!unit) {
        hasName = true;
      }
    }
    flush();
  }
  return out;
}

/// Every item of a spoken / typed order, parsed on its own (see [askodoxSplitPosOrder]).
List<({String phrase, AskodoxPosCommand command})> askodoxParsePosOrder(String text, List<AskodoxPosItemRef> items) => [
      for (final phrase in askodoxSplitPosOrder(text, items)) (phrase: phrase, command: askodoxParsePosCommand(phrase, items)),
    ];
