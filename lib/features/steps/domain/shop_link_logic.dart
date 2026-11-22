/// Shop link rules on the phone (owner 2026-11-22): the same slug rules as the server (`shop_links.py`), so the
/// owner sees `askodox.com/s/<name>` exactly as it will be before saving. The server still decides (taken names).
library;

const askodoxShopLinkBase = 'https://askodox.com/s/';

const askodoxShopLinkReserved = <String>{
  'admin', 'api', 'app', 'askodox', 'help', 'support', 'login', 'signin', 'www', 'shop', 'shops', 'static', //
  'staff', 'official', 'pay', 'bill', 'bills', 'order', 'orders', 'play', 'store', 's', 'p', 'b', 'go', //
  'about', 'terms', 'privacy', 'contact', 'news', 'jobs', 'test', 'demo', 'null', 'none', 'undefined',
};

/// The page colours (keys sent to the server; the server keeps the same list).
const askodoxShopLinkColors = <String, int>{
  'green': 0xFF0B7A4B,
  'blue': 0xFF1D4ED8,
  'maroon': 0xFF9D1D5A,
  'orange': 0xFFC2410C,
  'purple': 0xFF6D28D9,
  'dark': 0xFF1E293B,
};

/// Lower-case letters, digits and single hyphens; spaces / dots / underscores become a hyphen; other letters
/// (Telugu included) are dropped. At most 30 characters.
String askodoxCleanSlug(String text) {
  var s = text.trim().toLowerCase().replaceAll(RegExp(r'[\s._/]+'), '-');
  s = s.replaceAll(RegExp(r'[^a-z0-9-]'), '').replaceAll(RegExp(r'-{2,}'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > 30) s = s.substring(0, 30).replaceAll(RegExp(r'-+$'), '');
  return s;
}

/// '' = fine; else too_short / format / reserved (same keys as the server).
String askodoxSlugProblem(String slug) {
  if (slug.length < 3) return 'too_short';
  if (!RegExp(r'^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){2,29}$').hasMatch(slug)) return 'format';
  if (askodoxShopLinkReserved.contains(slug) || slug.startsWith('askodox')) return 'reserved';
  return '';
}

/// The owner's words for a slug problem (null = fine).
String? askodoxSlugProblemText(String problem, bool te) => switch (problem) {
      '' => null,
      'too_short' => te ? 'కనీసం 3 అక్షరాలు (English)' : 'At least 3 letters (English)',
      'reserved' => te ? 'ఈ పేరు వాడలేం — వేరే పేరు' : 'This name is kept — try another',
      'taken' => te ? 'ఈ పేరు వేరే షాప్‌ది — వేరే పేరు' : 'Another shop has it — try another',
      _ => te ? 'English అక్షరాలు, అంకెలు, - మాత్రమే' : 'English letters, numbers and - only',
    };

/// The message the owner sends to customers / WhatsApp groups / status.
String askodoxShopLinkShareText(String shop, String url, bool te) => te
    ? '$shop — మా మెనూ, ధరలు, ఆర్డర్ ఇక్కడ 👇\n$url'
    : '$shop — our menu, prices and orders here 👇\n$url';

/// Views / orders from the server's counts ({"today": {...}, "week": {...}, "month": {...}}).
int askodoxLinkCount(Map<String, Object?> stats, String span, List<String> kinds) {
  final block = stats[span];
  if (block is! Map) return 0;
  var n = 0;
  for (final k in kinds) {
    final v = block[k];
    n += v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  }
  return n;
}
