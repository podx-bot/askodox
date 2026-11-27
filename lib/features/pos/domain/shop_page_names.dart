/// ONE name per shop page (owner 2026-11-24: "New bill" and "Counter bill" were two pins above the chat that opened
/// the SAME counter page). Route template (`<id>` = the shop) -> (English, Telugu). Every place that names one of these
/// pages takes the name from here: the Seller Money pages, the shop dashboard tiles, `/my-shop/<tool>` (chat buttons
/// and pins), the pins above the chat (old pins are renamed on load) and the screen guide. The chat's buttons
/// (backend `chat_actions.CATALOG`) are checked against this file by `test_chat_actions.py`.
/// A NEW shop page gets ONE line here; never give a page a second name somewhere else.
library;

const askodoxShopPageNames = <String, (String, String)>{
  '/pos/<id>/sale': ('Counter bill', 'కౌంటర్ బిల్లు'),
  '/pos/<id>/payment-alerts': ('Payment alerts', 'పేమెంట్ అలర్ట్స్'),
  '/pos/<id>/collect': ('Collect by UPI', 'UPI తో కట్టించుకోండి'),
  '/pos/<id>/deliveries': ('Send delivery', 'డెలివరీ పంపు'),
  '/pos/<id>/team': ('Workers & team', 'పని వాళ్ళు & టీమ్'),
  '/desk/<id>': ('Incoming orders', 'వచ్చిన ఆర్డర్లు'),
  '/pos/<id>/tables': ('Tables', 'టేబుల్స్'),
  '/pos/<id>/kitchen': ('Kitchen (KOT)', 'వంటగది KOT'),
  '/pos/<id>/items': ('Stock & barcodes', 'స్టాక్ & బార్‌కోడ్'),
  '/pos/<id>/suppliers': ('Purchases', 'కొనుగోళ్లు'),
  '/pos/<id>/stock-report': ('Expiry & stock value', 'ఎక్స్‌పైరీ & స్టాక్ విలువ'),
  '/pos/<id>/customers': ('Customer list', 'కస్టమర్ల లిస్ట్'),
  '/pos/<id>/dues': ('Baaki reminders', 'బాకీ గుర్తులు'),
  '/pos/<id>/agents': ('My team', 'నా టీమ్'),
  '/pos/<id>/invoices': ('Bills', 'బిల్లులు'),
  '/pos/<id>/day': ('Close the day', 'రోజు ముగింపు'),
  '/pos/<id>/gst': ('GST report', 'GST రిపోర్ట్'),
  '/pos/<id>/staff': ('Staff & roles', 'సిబ్బంది & పాత్రలు'),
  '/pos/<id>/printer': ('Printer', 'ప్రింటర్'),
  '/pos/<id>/advance': ('Shop advance', 'షాప్ అడ్వాన్స్'),
  '/pos/<id>/selfshop': ('Self-shopping', 'సెల్ఫ్ షాపింగ్'),
  '/pos/<id>/crm': ('Enquiries', 'ఎంక్వైరీలు'),
  '/biz/<id>/bookings': ('Bookings', 'బుకింగ్స్'),
  '/biz/<id>/jobs': ('Job cards', 'జాబ్ కార్డ్స్'),
  '/biz/<id>/monthly': ('Monthly members', 'నెలవారీ సభ్యులు'),
  '/biz/<id>/members': ('Members & attendance', 'సభ్యులు & హాజరు'),
  '/pos/<id>/yield': ('Yield & rates', 'యీల్డ్ & రేట్లు'),
};

/// `/my-shop/<tool>` (chat + pins, "the person's own shop") -> the shop page it opens.
const askodoxShopToolPages = <String, String>{
  'sale': '/pos/<id>/sale',
  'payment-alerts': '/pos/<id>/payment-alerts',
  'collect': '/pos/<id>/collect',
  'orders': '/desk/<id>',
  'tables': '/pos/<id>/tables',
  'kitchen': '/pos/<id>/kitchen',
  'items': '/pos/<id>/items',
  'suppliers': '/pos/<id>/suppliers',
  'expiry': '/pos/<id>/stock-report',
  'customers': '/pos/<id>/customers',
  'dues': '/pos/<id>/dues',
  'agents': '/pos/<id>/agents',
  'bills': '/pos/<id>/invoices',
  'day': '/pos/<id>/day',
  'gst': '/pos/<id>/gst',
  'staff': '/pos/<id>/staff',
  'printer': '/pos/<id>/printer',
  'advance': '/pos/<id>/advance',
  'selfshop': '/pos/<id>/selfshop',
};

final _templates = [
  for (final t in askodoxShopPageNames.keys)
    (t, RegExp('^${t.split('<id>').map(RegExp.escape).join('([^/]+)')}\$')),
];

/// Which shop page a route opens, and for which shop: `/pos/A/sale` -> (page `/pos/<id>/sale`, shop `A`);
/// `/my-shop/sale` -> (page `/pos/<id>/sale`, shop `*` = the person's own shop); anything else -> (its path, shop "").
({String page, String shop}) askodoxShopPagePlace(String route) {
  final path = route.split('?').first;
  final mine = RegExp(r'^/my-shop/([^/]+)$').firstMatch(path);
  if (mine != null) {
    final page = askodoxShopToolPages[mine[1]];
    if (page != null) return (page: page, shop: '*');
  }
  for (final (template, re) in _templates) {
    final m = re.firstMatch(path);
    if (m != null) return (page: template, shop: m[1]!);
  }
  return (page: path, shop: '');
}

/// The one (English, Telugu) name of the shop page [route] opens; null when it is not a shop page.
(String, String)? askodoxShopPageName(String route) => askodoxShopPageNames[askodoxShopPagePlace(route).page];

/// Two routes open the same page: same shop page of the same shop ("/my-shop/sale" = any of the person's shops), or the
/// very same route for any other page.
bool askodoxSamePage(String a, String b) {
  final x = askodoxShopPagePlace(a), y = askodoxShopPagePlace(b);
  if (x.shop.isEmpty || y.shop.isEmpty) return a == b;
  return x.page == y.page && (x.shop == y.shop || x.shop == '*' || y.shop == '*');
}
