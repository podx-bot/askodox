/// Words that are also ordinary words or places ("MG Road", "1.5 HP pump",
/// "1 kg apple", "Usha" the person) are deliberately left out.
/// Brands people name while refining ANY request (cars, TVs, fridges, ACs,
/// phones, bikes...). One universal vocabulary -- not a per-category flow:
/// when the customer names a brand, it becomes part of what is searched
/// and replaces the brand (and that brand's model) searched before.
library;

const _brands = <String>[
  // vehicles
  'maruti suzuki', 'maruti', 'suzuki', 'tata', 'mahindra', 'hyundai', 'honda', 'toyota', 'kia', 'renault',
  'nissan', 'skoda', 'volkswagen', 'mg motor', 'ford', 'citroen', 'bajaj', 'hero motocorp', 'tvs', 'royal enfield',
  'yamaha', 'ola electric', 'ather',
  // electronics & appliances
  'samsung', 'lg', 'sony', 'tcl', 'xiaomi', 'redmi', 'oneplus', 'vu', 'panasonic', 'philips', 'haier',
  'whirlpool', 'godrej', 'voltas', 'blue star', 'daikin', 'hitachi', 'lloyd', 'ifb', 'bosch',
  'iphone', 'realme', 'vivo', 'oppo', 'motorola', 'nokia', 'dell', 'lenovo', 'asus', 'acer',
  'bajaj electricals', 'havells', 'prestige', 'butterfly', 'preethi', 'crompton', 'kent ro', 'aquaguard',
];

final _brandPattern = RegExp(
  '\\b(${(_brands.toList()..sort((a, b) => b.length.compareTo(a.length))).map(RegExp.escape).join('|')})\\b',
  caseSensitive: false,
);

/// The brand named in [text], in display case ("Tata"), or null.
String? askodoxDetectBrand(String text) {
  final match = _brandPattern.firstMatch(text);
  if (match == null) return null;
  return match.group(0)!.split(' ').map((w) => w.length <= 2 ? w.toUpperCase() : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');
}

const _units = {'inch', 'inches', 'in', 'kg', 'g', 'l', 'litre', 'liter', 'litres', 'ltr', 'ton', 'tons', 'cc',
  'gb', 'tb', 'mah', 'w', 'watt', 'hp', 'seater', 'door', 'star'};

/// [subject] with [brand] as its brand: a DIFFERENT brand and that brand's
/// model number ("Maruti 800") are removed, never mixed ("Tata Maruti 800").
/// Sizes/capacities ("43 inch", "250 l") are kept.
String askodoxSubjectWithBrand(String subject, String brand) {
  final words = subject.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final wanted = brand.toLowerCase();
  final kept = <String>[];
  var i = 0;
  while (i < words.length) {
    // Longest brand phrase starting here (e.g. "maruti suzuki").
    String? hit;
    for (final length in [3, 2, 1]) {
      if (i + length > words.length) continue;
      final phrase = words.sublist(i, i + length).join(' ');
      final m = _brandPattern.matchAsPrefix(phrase);
      if (m != null && m.end == phrase.length) {
        hit = phrase;
        break;
      }
    }
    if (hit == null) {
      kept.add(words[i]);
      i++;
      continue;
    }
    final span = hit.split(' ').length;
    if (hit.toLowerCase() == wanted) {
      i += span; // re-added in front below
      continue;
    }
    i += span;
    // The old brand's model number goes with it -- unless it is a size.
    if (i < words.length && RegExp(r'\d').hasMatch(words[i])) {
      final next = i + 1 < words.length ? words[i + 1].toLowerCase() : '';
      if (!_units.contains(next) && !RegExp(r'(inch|kg|l|gb|cc)$').hasMatch(words[i].toLowerCase())) i++;
    }
  }
  final rest = kept.join(' ').trim();
  return rest.isEmpty ? brand : '$brand $rest';
}
