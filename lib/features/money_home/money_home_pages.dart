import 'package:flutter/material.dart';

import '../../core/flags/askodox_release_phase.dart';
import '../business/presentation/biz_hub.dart' show AskodoxBizKind, askodoxBizKindOf, askodoxBizRoute, askodoxKitFlows;
import '../pos/data/pos_repository.dart' show AskodoxJson;
import '../pos/domain/shop_page_names.dart';
import 'launcher_layout.dart';

/// One page on the Money screen (owner 2026-11-22): an icon with its name under it, phone style.
class AskodoxLaunchPage {
  const AskodoxLaunchPage(this.id, this.en, this.te, this.icon, this.color,
      {this.route, this.action, this.perm, this.foodOnly = false, this.keyName});

  /// Fixed id (the person's layout, guides and reports use it; never shown).
  final String id;
  final String en;
  final String te;
  final IconData icon;
  final Color color;

  /// The existing screen it opens (null = [action]).
  final String? route;

  /// A page that is not a route: 'voice' (Payment voice folder), 'dues' (Coming up).
  final String? action;

  /// The shop permission a staff member needs (null = every member).
  final String? perm;

  /// Only for hotels / restaurants (tables, kitchen).
  final bool foodOnly;

  /// A widget key that must stay findable (approved feature registry / walkthroughs).
  final String? keyName;

  String label(bool te) => te ? this.te : en;

  /// Where a Home chat shortcut of this page goes (owner 2026-11-22: any page can sit above the chat, up to five).
  /// [shop] = the shop it belongs to (Seller side).
  String pinRoute(String? shop) =>
      route ??
      switch (action) {
        'voice' => shop == null ? '/payment-voice' : '/payment-voice?shop=$shop',
        _ => '/money-home',
      };
}

/// Folders an earlier version made by itself (owner 2026-11-22: "don't group anything -- everyone groups as they
/// like"): their pages go back on the screen; the person's own folders stay.
const askodoxRetiredFolderIds = {'shops', 'mine', 'money', 'hotel', 'items', 'shopset', 'staff'};

/// The default folders' names (the person renames them; the ids stay).
const askodoxLaunchFolderNames = <String, (String, String)>{
  'shops': ('Shops', 'షాప్‌లు'),
  'mine': ('My settings', 'నా సెట్టింగ్స్'),
  'money': ('Money books', 'డబ్బు లెక్కలు'),
  'hotel': ('Hotel', 'హోటల్'),
  'items': ('Items', 'ఐటమ్స్'),
  'shopset': ('Shop settings', 'షాప్ సెట్టింగ్స్'),
  'staff': ('Staff', 'సిబ్బంది'),
};

String askodoxLaunchFolderName(String id, bool te) {
  final n = askodoxLaunchFolderNames[id];
  return n == null ? (te ? 'ఫోల్డర్' : 'Folder') : (te ? n.$2 : n.$1);
}

// ------------------------------------------------------------------------------------------------ Buyer (కొను)

/// The Buyer side: the person's own money, bills, orders from shops and shops they follow. History lives in the ☰ menu;
/// Home, Live Work and Ask are on the bottom bar, the bell on the header -- never repeated here.
const askodoxBuyerPages = <AskodoxLaunchPage>[
  // Owner 2026-11-23: one accounts page (ON / OFF per account for "My own"; "Account names" merged in; QR one tap in).
  AskodoxLaunchPage('b.qr', 'My QR / accounts', 'నా QR / ఖాతాలు', Icons.qr_code_2_rounded, Color(0xFF10204A),
      route: '/me/payments/phone?open=accounts'),
  AskodoxLaunchPage('b.voice', 'Payment voice', 'పేమెంట్ వాయిస్', Icons.volume_up_rounded, Color(0xFF0D9488),
      action: 'voice'),
  AskodoxLaunchPage('b.bills', 'My bills', 'నా బిల్లులు', Icons.receipt_long_rounded, Color(0xFFEA580C), route: '/me/bills'),
  AskodoxLaunchPage('b.dues', 'Coming up', 'కట్టాల్సినవి', Icons.event_note_rounded, Color(0xFFB45309), route: '/me/dues'),
  AskodoxLaunchPage('b.ordercode', 'Order by code / QR', 'కోడ్ / QR ఆర్డర్', Icons.qr_code_scanner_rounded, Color(0xFF2563EB),
      route: '/order-desk/enter', keyName: 'askodoxShoppingOrderCode'),
  AskodoxLaunchPage('b.updates', 'My orders & updates', 'నా ఆర్డర్లు', Icons.local_shipping_outlined, Color(0xFF7C3AED),
      route: '/updates'),
  // Business Kit (owner 2026-11-24): what I booked, gave for repair / stitching, pay monthly; and photo try-on.
  AskodoxLaunchPage('b.bookings', 'My bookings', 'నా బుకింగ్స్', Icons.event_available_rounded, Color(0xFF0D9488),
      route: '/me/bookings'),
  AskodoxLaunchPage('b.jobs', 'My repairs & orders', 'నా రిపేర్లు & ఆర్డర్లు', Icons.build_circle_rounded, Color(0xFFEA580C),
      route: '/me/jobs'),
  // The person's own delivery work for every shop they work for (colour, offers, the job, money).
  AskodoxLaunchPage('b.deliveries', 'My delivery work', 'నా డెలివరీ పని', Icons.delivery_dining_rounded, Color(0xFFEA580C),
      route: '/me/deliveries'),
  AskodoxLaunchPage('b.work', 'I want work', 'నేను పని చేస్తా', Icons.engineering_rounded, Color(0xFF0D9488),
      route: '/me/work'),
  AskodoxLaunchPage('b.hire', 'Hire a worker', 'పని వాళ్ళు కావాలి', Icons.person_search_rounded, Color(0xFF2563EB),
      route: '/hire'),
  AskodoxLaunchPage('b.monthly', 'My monthly plans', 'నా నెలవారీ', Icons.event_repeat_rounded, Color(0xFF7C3AED),
      route: '/me/monthly'),
  AskodoxLaunchPage('b.tryon', 'Try it on me', 'ట్రై చేసి చూడు', Icons.checkroom_rounded, Color(0xFFDB2777), route: '/try-on'),
  AskodoxLaunchPage('b.following', 'Shops I follow', 'ఫాలో షాప్‌లు', Icons.favorite_rounded, Color(0xFFDC2626),
      route: '/me/following', keyName: 'askodoxShoppingFollowing'),
  AskodoxLaunchPage('b.shopfeed', 'Shop updates', 'షాప్ అప్‌డేట్స్', Icons.newspaper_rounded, Color(0xFF0284C7),
      route: '/me/shop-feed'),
  AskodoxLaunchPage('b.apps', 'Apps that are read', 'ఏ యాప్స్ చదవాలి', Icons.apps_rounded, Color(0xFF2563EB),
      route: '/me/payments/phone?open=apps'),
  AskodoxLaunchPage('b.language', 'Voice & language', 'భాష & వాయిస్', Icons.record_voice_over_outlined, Color(0xFF0E7490),
      route: '/me/payments/phone?open=voice'),
];

/// Owner 2026-11-23 (design "Money · కొను · అమ్ము"): "Money" holds ONLY money -- payments, bills, dues, accounts,
/// reports. Every other page sits on the side's own page, opened by tapping కొను / అమ్ము on the bottom bar: the
/// Buyer page (orders, shops I follow, shop updates) and the Shop page (orders, items, staff, customers, settings).
const askodoxMoneySectionIds = {
  'b.qr', 'b.voice', 'b.bills', 'b.dues', 'b.apps', 'b.language', //
  's.bill', 's.counter', 's.dues', 's.qr', 's.voice', 's.history', 's.sales', 's.reports', 's.cashbook', 's.day',
  's.gst', 's.purchases', 's.salary', 's.reportset',
};

/// The pages of one section: `money` (the Money tab) or `side` (the కొను / అమ్ము page).
List<AskodoxLaunchPage> askodoxPagesFor(List<AskodoxLaunchPage> pages, String section) =>
    [for (final p in pages) if (askodoxMoneySectionIds.contains(p.id) == (section == 'money')) p];

/// Every page on its own (no folders): the person makes their own.
AskodoxLaunchLayout askodoxBuyerShippedLayout() =>
    AskodoxLaunchLayout([for (final p in askodoxBuyerPages) AskodoxLaunchEntry.page(p.id)]);

// ------------------------------------------------------------------------------------------------ Seller (అమ్ము)

/// Who sees a Seller page in a shop:
/// - `all`: the owner, and staff the owner gave the page's tool to (or, for older staff with no ticks, whose role
///   allows [perm]);
/// - `owner`: only the owner (shop settings, the owner's own accounts);
/// - `self`: everyone in the shop, for THEMSELF (check in, my attendance, my tasks) -- owner 2026-11-22: "I am a
///   businessman and an employee: I mark mine, they mark theirs";
/// - `staff`: only someone working there (my month's attendance and salary).
class _SellerSpec {
  const _SellerSpec(this.id, this.page, this.en, this.te, this.icon, this.color,
      {this.who = 'all', this.tool, this.perm, this.food = false, this.staffEn, this.staffTe, this.flow});
  final String id, page, en, te;
  final IconData icon;
  final Color color;
  final String who;

  /// The owner's tick(s) that give it to staff (`pos_store.TOOL_PERMISSIONS`; "a|b" = any of them).
  final String? tool;

  /// The role permission(s) for staff with no ticks ("a|b" = any of them).
  final String? perm;
  final bool food;

  /// The name a staff member sees ("My attendance" instead of "Today's attendance").
  final String? staffEn, staffTe;

  /// Business Kit way of working the shop must have ('3' bookings, '4' job cards, '5' monthly); null = every shop.
  final String? flow;
}

const _sellerSpecs = <_SellerSpec>[
  _SellerSpec('s.bill', 'money.bill', 'Make a bill', 'బిల్లు చేయి', Icons.calculate_rounded, Color(0xFF16A34A),
      tool: 'sale', perm: 'sell'),
  _SellerSpec('s.orders', 'orders.incoming', 'Incoming orders', 'వచ్చిన ఆర్డర్లు', Icons.inbox_rounded, Color(0xFF2563EB),
      tool: 'desk', perm: 'tables|kitchen|sell|deliver'),
  // Business Kit ways 3-5 (owner 2026-11-24): only for shops that work that way.
  // Owner plan 2026-11-24 step 1: one line -> job card -> who goes (free first) -> answers -> give.
  _SellerSpec('s.send', 'orders.send', 'Send delivery', 'డెలివరీ పంపు', Icons.delivery_dining_rounded, Color(0xFFEA580C),
      tool: 'desk|sale', perm: 'sell'),
  // Owner plan 2026-11-24 steps 3-6: workers under this business (GST / Udyam to find new ones), orders, postings.
  _SellerSpec('s.team', 'orders.team', 'Workers & team', 'పని వాళ్ళు & టీమ్', Icons.groups_rounded, Color(0xFF0D9488),
      who: 'owner'),
  // Owner 2026-11-24: owners with more than one branch link them -- shared delivery pool + all-branches today.
  _SellerSpec('s.branches', 'orders.branches', 'All my branches', 'నా అన్ని శాఖలు', Icons.account_tree_rounded,
      Color(0xFF7C3AED), who: 'owner'),
  _SellerSpec('s.bookings', 'orders.bookings', 'Bookings', 'బుకింగ్స్', Icons.event_available_rounded, Color(0xFF0D9488),
      tool: 'customers|sale', perm: 'customers', flow: '3'),
  _SellerSpec('s.jobs', 'orders.jobs', 'Job cards', 'జాబ్ కార్డ్స్', Icons.build_circle_rounded, Color(0xFFEA580C),
      tool: 'customers|sale', perm: 'customers', flow: '4'),
  _SellerSpec('s.monthly', 'money.monthly', 'Monthly members', 'నెలవారీ సభ్యులు', Icons.event_repeat_rounded,
      Color(0xFF7C3AED), tool: 'customers|sale', perm: 'customers', flow: '5'),
  _SellerSpec('s.dues', 'money.dues', 'Dues', 'బాకీలు', Icons.menu_book_rounded, Color(0xFFEA580C),
      tool: 'dues|customers', perm: 'customers|sell'),
  _SellerSpec('s.qr', 'money.accounts', 'My QR / accounts', 'నా QR / ఖాతాలు', Icons.qr_code_2_rounded, Color(0xFF10204A),
      who: 'owner'),
  _SellerSpec('s.history', 'money.history', 'Bill history', 'బిల్లుల చరిత్ర', Icons.history_rounded, Color(0xFF0284C7),
      tool: 'bills', perm: 'sell|return|cancel|reports'),
  _SellerSpec('s.sales', 'money.sales', 'Sales', 'అమ్మకాలు', Icons.trending_up_rounded, Color(0xFF7C3AED),
      tool: 'gst', perm: 'reports'),
  _SellerSpec('s.reports', 'reports', 'Reports', 'రిపోర్ట్స్', Icons.bar_chart_rounded, Color(0xFF4F46E5),
      tool: 'gst', perm: 'reports'),
  _SellerSpec('s.cashbook', 'money.cashbook', 'Cashbook', 'క్యాష్‌బుక్', Icons.import_contacts_rounded, Color(0xFF2563EB),
      tool: 'gst', perm: 'reports'),
  _SellerSpec('s.day', 'money.day', 'Close the day', 'రోజు ముగింపు', Icons.nightlight_round, Color(0xFF1E293B),
      tool: 'day', perm: 'day_close'),
  _SellerSpec('s.gst', 'money.gst', 'GST report', 'GST రిపోర్ట్', Icons.description_rounded, Color(0xFF9A3412),
      tool: 'gst', perm: 'reports'),
  _SellerSpec('s.purchases', 'money.purchases', 'Purchases', 'కొనుగోళ్లు', Icons.local_shipping_rounded, Color(0xFFB45309),
      tool: 'suppliers', perm: 'purchases'),
  _SellerSpec('s.counter', 'money.counter', 'Counter bill', 'కౌంటర్ బిల్లు', Icons.point_of_sale_rounded,
      Color(0xFF334155), tool: 'sale', perm: 'sell'),
  _SellerSpec('s.tables', 'orders.tables', 'Tables', 'టేబుల్స్', Icons.table_restaurant_rounded, Color(0xFF0D9488),
      tool: 'tables|desk', perm: 'tables', food: true),
  _SellerSpec('s.kitchen', 'orders.kitchen', 'Kitchen (KOT)', 'వంటగది KOT', Icons.soup_kitchen_rounded, Color(0xFFDB2777),
      tool: 'kitchen|desk', perm: 'kitchen', food: true),
  _SellerSpec('s.menu', 'menu', 'Items list', 'ఐటమ్స్ లిస్ట్', Icons.list_alt_rounded, Color(0xFFEA580C),
      tool: 'items', perm: 'products|sell'),
  _SellerSpec('s.additem', 'menu.add', 'Add an item', 'ఐటమ్ చేర్చు', Icons.add_box_rounded, Color(0xFF16A34A),
      tool: 'items', perm: 'products'),
  _SellerSpec('s.sort', 'menu.sort', 'Sort with AI', 'AI తో సర్దు', Icons.auto_fix_high_rounded, Color(0xFF7C3AED),
      tool: 'items', perm: 'products'),
  _SellerSpec('s.stock', 'menu.stock', 'Stock & barcodes', 'స్టాక్ & బార్‌కోడ్', Icons.qr_code_rounded, Color(0xFF334155),
      tool: 'stock', perm: 'stock'),
  _SellerSpec('s.checkin', 'staff.checkin', 'Check in / out', 'హాజరు వేయి', Icons.fingerprint_rounded, Color(0xFF7C3AED),
      who: 'self', staffEn: 'My check in / out', staffTe: 'నా హాజరు వేయి'),
  _SellerSpec('s.attendance', 'staff.attendance', "Today's attendance", 'ఈ రోజు హాజరు', Icons.how_to_reg_rounded,
      Color(0xFF16A34A), who: 'self', staffEn: 'My attendance today', staffTe: 'నా ఈ రోజు హాజరు'),
  _SellerSpec('s.mymonth', 'staff.me', 'My month & salary', 'నా నెల హాజరు & జీతం', Icons.calendar_month_rounded,
      Color(0xFF059669), who: 'staff'),
  _SellerSpec('s.tasks', 'staff.tasks', 'Tasks', 'పనులు', Icons.checklist_rounded, Color(0xFF4F46E5),
      who: 'self', staffEn: 'My tasks', staffTe: 'నా పనులు'),
  _SellerSpec('s.salary', 'staff.salary', 'Salary & advance', 'జీతాలు & అడ్వాన్స్', Icons.payments_rounded, Color(0xFF059669),
      tool: 'staff', perm: 'members'),
  _SellerSpec('s.post', 'customers.post', "Today's post", 'ఈ రోజు పోస్ట్', Icons.campaign_rounded, Color(0xFFEA580C),
      who: 'owner'),
  _SellerSpec('s.page', 'customers.page', 'Shop page & reviews', 'షాప్ పేజీ & రివ్యూలు', Icons.star_rounded, Color(0xFFDB2777),
      who: 'owner'),
  // Owner 2026-11-22: askodox.com/s/<name> -- menu, WhatsApp order, call, map, own UPI (made in 3 steps).
  _SellerSpec('s.link', 'customers.link', 'My shop link', 'నా షాప్ లింక్', Icons.link_rounded, Color(0xFF0B7A4B), who: 'owner'),
  _SellerSpec('s.customers', 'customers.list', 'Customer list', 'కస్టమర్ల లిస్ట్', Icons.contacts_rounded, Color(0xFF2563EB),
      tool: 'customers', perm: 'customers'),
  _SellerSpec('s.crm', 'customers.crm', 'Enquiries', 'ఎంక్వైరీలు', Icons.forum_rounded, Color(0xFF0284C7),
      tool: 'crm', perm: 'crm'),
  // Owner 2026-11-24: "Who accepts & alerts" is part of Staff & roles now (one page; its order-alert steps open there).
  _SellerSpec('s.qrcodes', 'orders.qr', 'QR codes', 'QR కోడ్‌లు', Icons.qr_code_2_rounded, Color(0xFF334155), who: 'owner'),
  _SellerSpec('s.kiosk', 'staff.kiosk', 'Shop phone attendance', 'షాప్ ఫోన్ హాజరు', Icons.phone_android_rounded,
      Color(0xFF0D9488), tool: 'staff', perm: 'members'),
  _SellerSpec('s.people', 'staff.people', 'Staff & roles', 'సిబ్బంది & పాత్రలు', Icons.groups_rounded, Color(0xFF2563EB),
      tool: 'staff', perm: 'members'),
  _SellerSpec('s.attsetup', 'staff.setup', 'Attendance setup', 'హాజరు సెటప్', Icons.schedule_rounded, Color(0xFF475569),
      tool: 'staff', perm: 'members'),
  _SellerSpec('s.details', 'settings.details', 'Business details', 'బిజినెస్ వివరాలు', Icons.apartment_rounded,
      Color(0xFF475569), who: 'owner'),
  _SellerSpec('s.printer', 'settings.printer', 'Printer', 'ప్రింటర్', Icons.print_rounded, Color(0xFF0D9488),
      tool: 'printer', perm: 'settings'),
  _SellerSpec('s.selfshop', 'settings.selfshop', 'Self-shopping', 'సెల్ఫ్ షాపింగ్', Icons.shopping_cart_rounded,
      Color(0xFF16A34A), tool: 'selfshop', perm: 'settings'),
  // Owner 2026-11-24: the "AI agents" page was unclear -- asking / doing things by voice lives in the guide + chat.
  _SellerSpec('s.reportset', 'reports.settings', 'Report settings', 'రిపోర్ట్ సెట్టింగ్స్', Icons.edit_calendar_rounded,
      Color(0xFF475569), who: 'owner'),
];

/// Pages the hub has no fixed route for (staff inner pages): their own routes.
String _sellerRoute(String id, String page) => switch (page) {
      'staff.kiosk' => '/biz/$id/staff/kiosk',
      'staff.setup' => '/biz/$id/staff/setup',
      'staff.me' => '/biz/$id/staff/person/me',
      _ => askodoxBizRoute(id, page),
    };

bool _anyOf(String? wanted, Set<String> have) =>
    wanted == null || wanted.split('|').any(have.contains);

/// Whether this person sees [spec] in a shop where their role is [role] (owner / manager / cashier ...).
bool _sees(_SellerSpec spec, String role, AskodoxJson business) {
  final owner = role == 'owner';
  switch (spec.who) {
    case 'owner':
      return owner;
    case 'self':
      return true;
    case 'staff':
      return !owner;
  }
  if (owner) return true;
  // Staff: the owner's ticks decide when the shop sends them (`tools`); older staff fall back to the role.
  final tools = business['tools'];
  if (tools is List) return spec.tool != null && _anyOf(spec.tool, {for (final t in tools) '$t'});
  final perms = (business['permissions'] as List?)?.map((e) => '$e').toSet() ?? const <String>{};
  return _anyOf(spec.perm ?? '-', perms);
}

/// The Seller side for shop [businessId]: its own tools -- for the owner every one, for staff only what the owner
/// gave them plus their OWN check in, attendance, tasks and month (a person can own a shop AND work in another one;
/// each shop shows that person's side of it). Phase 2 screens stay out; tables + kitchen only for a hotel.
List<AskodoxLaunchPage> askodoxSellerPages(String businessId, AskodoxJson business) {
  final food = askodoxBizKindOf(business) == AskodoxBizKind.food;
  final flows = askodoxKitFlows(business);
  final role = '${business['my_role'] ?? business['role'] ?? ''}';
  final staff = role != 'owner';
  final out = <AskodoxLaunchPage>[];
  for (final s in _sellerSpecs) {
    if (s.food && !food) continue;
    if (s.flow != null && !flows.contains(s.flow)) continue;
    final route = _sellerRoute(businessId, s.page);
    if (!askodoxRouteShownNow(route) || !_sees(s, role, business)) continue;
    // ONE name per shop page (owner 2026-11-24): a shop page is called what `shop_page_names.dart` calls it everywhere.
    final named = askodoxShopPageName(route);
    final en = named?.$1 ?? s.en, tel = named?.$2 ?? s.te;
    out.add(AskodoxLaunchPage(s.id, staff ? (s.staffEn ?? en) : en, staff ? (s.staffTe ?? tel) : tel, s.icon, s.color,
        route: route, perm: s.perm, foodOnly: s.food));
  }
  // The shop's payment sound on this phone: the owner, and staff the owner gave "Payment sound".
  final tools = business['tools'] is List ? business['tools'] as List : const ['payalerts'];
  if (!staff || _anyOf('payalerts', {for (final t in tools) '$t'})) {
    out.add(const AskodoxLaunchPage('s.voice', 'Payment voice', 'పేమెంట్ వాయిస్', Icons.volume_up_rounded, Color(0xFF0D9488),
        action: 'voice'));
  }
  return out;
}

/// Every page on its own (no folders): the person makes their own.
AskodoxLaunchLayout askodoxSellerShippedLayout() => const AskodoxLaunchLayout([
      AskodoxLaunchEntry.page('s.bill'),
      AskodoxLaunchEntry.page('s.orders'),
      AskodoxLaunchEntry.page('s.send'),
      AskodoxLaunchEntry.page('s.team'),
      AskodoxLaunchEntry.page('s.branches'),
      AskodoxLaunchEntry.page('s.bookings'),
      AskodoxLaunchEntry.page('s.jobs'),
      AskodoxLaunchEntry.page('s.monthly'),
      AskodoxLaunchEntry.page('s.checkin'),
      AskodoxLaunchEntry.page('s.attendance'),
      AskodoxLaunchEntry.page('s.mymonth'),
      AskodoxLaunchEntry.page('s.dues'),
      AskodoxLaunchEntry.page('s.qr'),
      AskodoxLaunchEntry.page('s.link'),
      AskodoxLaunchEntry.page('s.voice'),
      AskodoxLaunchEntry.page('s.history'),
      AskodoxLaunchEntry.page('s.sales'),
      AskodoxLaunchEntry.page('s.reports'),
      AskodoxLaunchEntry.page('s.tables'),
      AskodoxLaunchEntry.page('s.kitchen'),
      AskodoxLaunchEntry.page('s.menu'),
      AskodoxLaunchEntry.page('s.additem'),
      AskodoxLaunchEntry.page('s.stock'),
      AskodoxLaunchEntry.page('s.tasks'),
      AskodoxLaunchEntry.page('s.customers'),
      AskodoxLaunchEntry.page('s.crm'),
      AskodoxLaunchEntry.page('s.cashbook'),
      AskodoxLaunchEntry.page('s.day'),
      AskodoxLaunchEntry.page('s.gst'),
      AskodoxLaunchEntry.page('s.purchases'),
      AskodoxLaunchEntry.page('s.counter'),
      AskodoxLaunchEntry.page('s.sort'),
      AskodoxLaunchEntry.page('s.salary'),
      AskodoxLaunchEntry.page('s.people'),
      AskodoxLaunchEntry.page('s.kiosk'),
      AskodoxLaunchEntry.page('s.attsetup'),
      AskodoxLaunchEntry.page('s.post'),
      AskodoxLaunchEntry.page('s.page'),
      AskodoxLaunchEntry.page('s.orderalerts'),
      AskodoxLaunchEntry.page('s.qrcodes'),
      AskodoxLaunchEntry.page('s.details'),
      AskodoxLaunchEntry.page('s.printer'),
      AskodoxLaunchEntry.page('s.selfshop'),
      AskodoxLaunchEntry.page('s.agents'),
      AskodoxLaunchEntry.page('s.reportset'),
    ]);
