/// Contextual tool discovery: "how many bricks for my wall", "open the
/// compass", "check this chicken quality", "ఇటుకలు ఎన్ని కావాలి" open the
/// matching Smart Tool instead of a search. Deliberately conservative: a
/// message that is about buying / selling / hiring / prices is commerce and
/// is never taken over, and a tool that is not built is reported honestly
/// instead of opened.
library;

import 'smart_tool_catalog.dart';

class AskodoxToolIntent {
  const AskodoxToolIntent(this.tool, {this.domain, this.explicit = false});
  final AskodoxSmartTool tool;

  /// The user named the tool itself ("open the compass"), as opposed to a
  /// question a tool can answer ("how many bricks..."). Only explicit asks
  /// may interrupt a conversation that already has results on screen.
  final bool explicit;

  /// Inspection domain for the photo tool (food, vehicle, ...).
  final String? domain;

  String? get route {
    final base = tool.route;
    if (base == null || !tool.opens) return null;
    if (domain == null || base.contains('?')) return base;
    return '$base?domain=$domain';
  }
}

final _ascii = RegExp(r'^[a-z0-9 ?]+$');
final _wordCache = <String, RegExp>{};

/// English words match whole words only ("car" never matches "card",
/// "order" never "border"); Telugu / other scripts match as substrings
/// (suffixes attach to the word).
bool _has(String q, List<String> words) => words.any((w) {
      if (!_ascii.hasMatch(w)) return q.contains(w);
      final pattern = _wordCache.putIfAbsent(
          w, () => RegExp('(^|[^a-z0-9])${RegExp.escape(w.trim())}(s|es)?(\$|[^a-z0-9])'));
      return pattern.hasMatch(q);
    });

// Commerce / hiring words: these messages belong to the deal flow.
const _commerce = [
  'buy', 'sell', 'price', 'cost', 'rate of', 'cheap', 'order', 'deliver', 'supplier', 'dealer', 'shop',
  'near me', 'nearby', 'delivery', 'hire', 'mason', 'contractor', 'plumber', 'painter', 'electrician', 'booking', 'book ',
  'కొనాలి', 'అమ్మాలి', 'ధర', 'రేటు', 'షాప్', 'దగ్గర', 'కావాలి ఎక్కడ', 'ఆర్డర్', 'మేస్త్రీ', 'కాంట్రాక్టర్',
  'kharid', 'bech', 'dukaan',
];

// "How many / how much / calculate / estimate" -- a quantity question.
const _quantityAsk = [
  'how many', 'how much', 'calculate', 'calculator', 'estimate', 'quantity', 'required for', 'needed for',
  'ఎన్ని', 'ఎంత', 'లెక్క', 'కావాలి?', 'kitne', 'kitna',
];

const _inspectAsk = [
  'check this', 'check the', 'inspect', 'is this fresh', 'fresh or not', 'quality of this', 'this quality',
  'condition of this', 'look at this', 'scan this', 'damage', 'chudu', 'చూడు', 'చెక్ చేయి', 'పరిశీలించు',
  'ఫ్రెష్‌గా ఉందా', 'తాజాగా ఉందా', 'నాణ్యత',
];

const _domainWords = <String, List<String>>{
  'food': ['chicken', 'mutton', 'fish', 'meat', 'milk', 'fruit', 'vegetable', 'egg', 'చికెన్', 'మటన్', 'చేప',
    'పాలు', 'పండ్లు', 'కూరగాయలు', 'గుడ్లు'],
  'dish': ['biryani', 'recipe', 'dish', 'curry', 'బిర్యానీ', 'వంటకం', 'రెసిపీ'],
  'vehicle': ['car', 'bike', 'scooter', 'vehicle', 'కారు', 'బైక్', 'వాహనం'],
  'tyre': ['tyre', 'tire', 'టైర్'],
  'crop': ['leaf', 'crop', 'plant', 'paddy', 'cotton', 'ఆకు', 'పంట', 'మొక్క', 'వరి', 'పత్తి'],
  'livestock': ['goat', 'sheep', 'cow', 'buffalo', 'మేక', 'గొర్రె', 'ఆవు', 'గేదె'],
  'construction': ['crack', 'wall', 'ceiling', 'పగులు', 'గోడ'],
};

/// Returns the tool a message asks for, or null when it is not a tool ask.
AskodoxToolIntent? askodoxToolIntent(String text) {
  final q = ' ${text.toLowerCase().trim()} ';
  if (q.trim().isEmpty || q.trim().length > 240) return null;

  final tool = askodoxToolById;

  // Explicit tool names win, even with numbers in the message.
  if (_has(q, ['spirit level', 'bubble level', 'leveller', 'level tool', 'లెవెల్'])) {
    return AskodoxToolIntent(tool('level')!, explicit: true);
  }
  if (_has(q, ['inclinometer', 'slope angle', 'angle finder', 'measure angle', 'measure the angle', 'వాలు'])) {
    return AskodoxToolIntent(tool('inclinometer')!, explicit: true);
  }
  if (_has(q, ['compass', 'which direction is north', 'north direction', 'దిక్సూచి', 'ఉత్తరం ఎటు'])) {
    return AskodoxToolIntent(tool('compass')!, explicit: true);
  }
  if (_has(q, ['bluetooth scale', 'weighing scale', 'తూకం యంత్రం'])) {
    return AskodoxToolIntent(tool('bt_scale')!, explicit: true);
  }
  if (_has(q, ['connect my tv', 'connect my ac', 'connect my speaker', 'connect my light', 'smart home',
    'universal remote', 'tv remote', 'ac remote'])) {
    return AskodoxToolIntent(tool('smart_home')!, explicit: true);
  }
  if (_has(q, ['walkie talkie', 'walkie-talkie', 'push to talk', 'push-to-talk', 'వాకీ టాకీ', 'వాకీ-టాకీ'])) {
    return AskodoxToolIntent(tool('walkie')!, explicit: true);
  }
  if (_has(q, ['pair my', 'pair the', 'pair with', 'add device', 'add a device', 'my devices', 'bluetooth device',
    'బ్లూటూత్', 'కనెక్ట్ చేయి'])) {
    return AskodoxToolIntent(tool('pairing')!, explicit: true);
  }

  // Round 2 tools named explicitly. General tax / scam QUESTIONS are left to
  // the conversation brain, which attaches its sourced card.
  if (_has(q, ['income tax calculator', 'tax calculator', 'calculate my income tax', 'calculate income tax',
    'పన్ను లెక్కించు', 'ట్యాక్స్ క్యాలిక్యులేటర్'])) {
    return AskodoxToolIntent(tool('income_tax')!, explicit: true);
  }
  if (_has(q, ['gst calculator', 'gst tool', 'calculate gst', 'జీఎస్టీ లెక్క'])) {
    return AskodoxToolIntent(tool('gst')!, explicit: true);
  }
  if (_has(q, ['scam checklist', 'scam checklists', 'fraud checklist', 'మోసాల చెక్‌లిస్ట్'])) {
    return AskodoxToolIntent(tool('fraud_check')!, explicit: true);
  }

  final commerce = _has(q, _commerce);
  final quantity = _has(q, _quantityAsk);

  if (!commerce && quantity) {
    if (_has(q, ['brick', 'block', 'ఇటుక', 'ఇటుకలు', 'బ్లాక్'])) return AskodoxToolIntent(tool('brick')!);
    if (_has(q, ['tile', 'tiles', 'flooring', 'టైల్'])) return AskodoxToolIntent(tool('tile')!);
    if (_has(q, ['paint', 'పెయింట్', 'రంగు డబ్బా'])) return AskodoxToolIntent(tool('paint')!);
    if (_has(q, ['cement', 'concrete', 'plaster', 'sand', 'సిమెంట్', 'ఇసుక', 'ప్లాస్టరింగ్'])) {
      return AskodoxToolIntent(tool('cement')!);
    }
    if (_has(q, ['load', 'fit in', 'boxes in', 'cargo', 'truck', 'లోడ్'])) return AskodoxToolIntent(tool('load')!);
    if (_has(q, ['area', 'square feet', 'sq ft', 'sqft', 'వైశాల్యం', 'చదరపు'])) return AskodoxToolIntent(tool('area')!);
    if (_has(q, ['volume', 'litres', 'liters', 'capacity', 'ఘనపరిమాణం'])) return AskodoxToolIntent(tool('volume')!);
  }

  if (!commerce && _has(q, ['measure this', 'measure the', 'measure my', 'కొలవాలి', 'కొలత'])) {
    // Camera / AR measuring is not built: open the manual area tool.
    return AskodoxToolIntent(tool('area')!);
  }

  if (!commerce && _has(q, _inspectAsk)) {
    for (final entry in _domainWords.entries) {
      if (_has(q, entry.value)) {
        if (entry.key == 'construction') return AskodoxToolIntent(tool('crack')!);
        if (entry.key == 'livestock' && _has(q, ['weight', 'బరువు'])) {
          return AskodoxToolIntent(tool('animal_weight')!);
        }
        return AskodoxToolIntent(tool('inspect')!, domain: entry.key);
      }
    }
  }
  if (!commerce && _has(q, ['weight of this goat', 'goat weight', 'sheep weight', 'మేక బరువు', 'గొర్రె బరువు'])) {
    return AskodoxToolIntent(tool('animal_weight')!);
  }
  return null;
}
