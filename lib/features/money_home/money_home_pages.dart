import 'package:flutter/material.dart';

import '../../core/flags/askodox_release_phase.dart';
import '../business/presentation/biz_hub.dart' show AskodoxBizKind, askodoxBizAllowed, askodoxBizKind, askodoxBizRoute;
import '../pos/data/pos_repository.dart' show AskodoxJson;
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
}

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
  AskodoxLaunchPage('b.qr', 'My QR / accounts', 'నా QR / ఖాతాలు', Icons.qr_code_2_rounded, Color(0xFF10204A),
      route: '/me/payment-methods'),
  AskodoxLaunchPage('b.voice', 'Payment voice', 'పేమెంట్ వాయిస్', Icons.volume_up_rounded, Color(0xFF0D9488),
      action: 'voice'),
  AskodoxLaunchPage('b.bills', 'My bills', 'నా బిల్లులు', Icons.receipt_long_rounded, Color(0xFFEA580C), route: '/me/bills'),
  AskodoxLaunchPage('b.dues', 'Coming up', 'కట్టాల్సినవి', Icons.event_note_rounded, Color(0xFFB45309), action: 'dues'),
  AskodoxLaunchPage('b.ordercode', 'Order by code / QR', 'కోడ్ / QR ఆర్డర్', Icons.qr_code_scanner_rounded, Color(0xFF2563EB),
      route: '/order-desk/enter', keyName: 'askodoxShoppingOrderCode'),
  AskodoxLaunchPage('b.updates', 'My orders & updates', 'నా ఆర్డర్లు', Icons.local_shipping_outlined, Color(0xFF7C3AED),
      route: '/updates'),
  AskodoxLaunchPage('b.following', 'Shops I follow', 'ఫాలో షాప్‌లు', Icons.favorite_rounded, Color(0xFFDC2626),
      route: '/me/following', keyName: 'askodoxShoppingFollowing'),
  AskodoxLaunchPage('b.shopfeed', 'Shop updates', 'షాప్ అప్‌డేట్స్', Icons.newspaper_rounded, Color(0xFF0284C7),
      route: '/me/shop-feed'),
  AskodoxLaunchPage('b.apps', 'Apps that are read', 'ఏ యాప్స్ చదవాలి', Icons.apps_rounded, Color(0xFF2563EB),
      route: '/me/payments/phone?open=apps'),
  AskodoxLaunchPage('b.accounts', 'Account names', 'ఖాతాల పేర్లు', Icons.account_balance_outlined, Color(0xFF475569),
      route: '/me/payments/phone?open=accounts'),
  AskodoxLaunchPage('b.language', 'Voice & language', 'భాష & వాయిస్', Icons.record_voice_over_outlined, Color(0xFF0E7490),
      route: '/me/payments/phone?open=voice'),
];

AskodoxLaunchLayout askodoxBuyerShippedLayout() => const AskodoxLaunchLayout([
      AskodoxLaunchEntry.page('b.qr'),
      AskodoxLaunchEntry.page('b.voice'),
      AskodoxLaunchEntry.page('b.bills'),
      AskodoxLaunchEntry.page('b.dues'),
      AskodoxLaunchEntry.page('b.ordercode'),
      AskodoxLaunchEntry.page('b.updates'),
      AskodoxLaunchEntry.folder('shops', '', ['b.following', 'b.shopfeed']),
      AskodoxLaunchEntry.folder('mine', '', ['b.apps', 'b.accounts', 'b.language']),
    ]);

// ------------------------------------------------------------------------------------------------ Seller (అమ్ము)

/// (id, page key in the business hub, en, te, icon, colour, permission, food only)
const _sellerSpecs = <(String, String, String, String, IconData, Color, String?, bool)>[
  ('s.bill', 'money.bill', 'Make a bill', 'బిల్లు చేయి', Icons.calculate_rounded, Color(0xFF16A34A), 'sell', false),
  ('s.orders', 'orders.incoming', 'Incoming orders', 'వచ్చిన ఆర్డర్లు', Icons.inbox_rounded, Color(0xFF2563EB), null, false),
  ('s.dues', 'money.dues', 'Dues', 'బాకీలు', Icons.menu_book_rounded, Color(0xFFEA580C), 'customers', false),
  ('s.qr', 'money.accounts', 'My QR / accounts', 'నా QR / ఖాతాలు', Icons.qr_code_2_rounded, Color(0xFF10204A), 'settings', false),
  ('s.history', 'money.history', 'Bill history', 'బిల్లుల చరిత్ర', Icons.history_rounded, Color(0xFF0284C7), null, false),
  ('s.sales', 'money.sales', 'Sales', 'అమ్మకాలు', Icons.trending_up_rounded, Color(0xFF7C3AED), 'reports', false),
  ('s.reports', 'reports', 'Reports', 'రిపోర్ట్స్', Icons.bar_chart_rounded, Color(0xFF4F46E5), 'reports', false),
  ('s.cashbook', 'money.cashbook', 'Cashbook', 'క్యాష్‌బుక్', Icons.import_contacts_rounded, Color(0xFF2563EB), 'reports', false),
  ('s.day', 'money.day', 'Close the day', 'రోజు ముగింపు', Icons.nightlight_round, Color(0xFF1E293B), 'day_close', false),
  ('s.gst', 'money.gst', 'GST report', 'GST రిపోర్ట్', Icons.description_rounded, Color(0xFF9A3412), 'reports', false),
  ('s.purchases', 'money.purchases', 'Purchases', 'కొనుగోళ్లు', Icons.local_shipping_rounded, Color(0xFFB45309), 'purchases', false),
  ('s.counter', 'money.counter', 'Counter billing', 'కౌంటర్ బిల్లింగ్', Icons.point_of_sale_rounded, Color(0xFF334155), 'sell', false),
  ('s.tables', 'orders.tables', 'Tables', 'టేబుల్స్', Icons.table_restaurant_rounded, Color(0xFF0D9488), 'tables', true),
  ('s.kitchen', 'orders.kitchen', 'Kitchen (KOT)', 'వంటగది KOT', Icons.soup_kitchen_rounded, Color(0xFFDB2777), 'kitchen', true),
  ('s.menu', 'menu', 'Items list', 'ఐటమ్స్ లిస్ట్', Icons.list_alt_rounded, Color(0xFFEA580C), null, false),
  ('s.additem', 'menu.add', 'Add an item', 'ఐటమ్ చేర్చు', Icons.add_box_rounded, Color(0xFF16A34A), 'products', false),
  ('s.sort', 'menu.sort', 'Sort with AI', 'AI తో సర్దు', Icons.auto_fix_high_rounded, Color(0xFF7C3AED), 'products', false),
  ('s.stock', 'menu.stock', 'Stock & barcodes', 'స్టాక్ & బార్‌కోడ్', Icons.qr_code_rounded, Color(0xFF334155), 'stock', false),
  ('s.attendance', 'staff.attendance', "Today's attendance", 'ఈ రోజు హాజరు', Icons.how_to_reg_rounded, Color(0xFF16A34A), null, false),
  ('s.checkin', 'staff.checkin', 'Check in / out', 'హాజరు వేయి', Icons.fingerprint_rounded, Color(0xFF7C3AED), null, false),
  ('s.tasks', 'staff.tasks', 'Tasks', 'పనులు', Icons.checklist_rounded, Color(0xFF4F46E5), null, false),
  ('s.salary', 'staff.salary', 'Salary & advance', 'జీతాలు & అడ్వాన్స్', Icons.payments_rounded, Color(0xFF059669), null, false),
  ('s.post', 'customers.post', "Today's post", 'ఈ రోజు పోస్ట్', Icons.campaign_rounded, Color(0xFFEA580C), null, false),
  ('s.page', 'customers.page', 'Shop page & reviews', 'షాప్ పేజీ & రివ్యూలు', Icons.star_rounded, Color(0xFFDB2777), null, false),
  ('s.customers', 'customers.list', 'Customer list', 'కస్టమర్ల లిస్ట్', Icons.contacts_rounded, Color(0xFF2563EB), 'customers', false),
  ('s.crm', 'customers.crm', 'Enquiries', 'ఎంక్వైరీలు', Icons.forum_rounded, Color(0xFF0284C7), 'crm', false),
  ('s.orderalerts', 'orders.alerts', 'Who accepts & alerts', 'ఎవరు ఒప్పుకోవాలి', Icons.notifications_active_rounded, Color(0xFF7C3AED), 'settings', false),
  ('s.qrcodes', 'orders.qr', 'QR codes', 'QR కోడ్‌లు', Icons.qr_code_2_rounded, Color(0xFF334155), 'settings', false),
  ('s.kiosk', 'staff.kiosk', 'Shop phone attendance', 'షాప్ ఫోన్ హాజరు', Icons.phone_android_rounded, Color(0xFF0D9488), null, false),
  ('s.people', 'staff.people', 'Staff & roles', 'సిబ్బంది & పాత్రలు', Icons.groups_rounded, Color(0xFF2563EB), null, false),
  ('s.attsetup', 'staff.setup', 'Attendance setup', 'హాజరు సెటప్', Icons.schedule_rounded, Color(0xFF475569), null, false),
  ('s.details', 'settings.details', 'Business details', 'బిజినెస్ వివరాలు', Icons.apartment_rounded, Color(0xFF475569), 'settings', false),
  ('s.printer', 'settings.printer', 'Printer', 'ప్రింటర్', Icons.print_rounded, Color(0xFF0D9488), 'settings', false),
  ('s.selfshop', 'settings.selfshop', 'Self-shopping', 'సెల్ఫ్ షాపింగ్', Icons.shopping_cart_rounded, Color(0xFF16A34A), 'settings', false),
  ('s.agents', 'settings.agents', 'AI helpers', 'AI సహాయకులు', Icons.smart_toy_rounded, Color(0xFF7C3AED), 'settings', false),
  ('s.reportset', 'reports.settings', 'Report settings', 'రిపోర్ట్ సెట్టింగ్స్', Icons.edit_calendar_rounded, Color(0xFF475569), 'reports', false),
];

/// Pages the hub has no fixed route for (staff inner pages): their own routes.
String _sellerRoute(String id, String page) => switch (page) {
      'staff.kiosk' => '/biz/$id/staff/kiosk',
      'staff.setup' => '/biz/$id/staff/setup',
      _ => askodoxBizRoute(id, page),
    };

/// The Seller side for shop [businessId]: the shop's own tools, only those this person's role allows and this build
/// opens (Phase 2 screens stay out), hotel pages only for a hotel / restaurant. The Payment voice folder is first-class.
List<AskodoxLaunchPage> askodoxSellerPages(String businessId, AskodoxJson business) {
  final food = askodoxBizKind(business['template']) == AskodoxBizKind.food;
  return [
    for (final (id, page, en, te, icon, color, perm, foodOnly) in _sellerSpecs)
      if ((!foodOnly || food) &&
          askodoxBizAllowed(perm, business) &&
          askodoxRouteShownNow(_sellerRoute(businessId, page)))
        AskodoxLaunchPage(id, en, te, icon, color, route: _sellerRoute(businessId, page), perm: perm, foodOnly: foodOnly),
    const AskodoxLaunchPage('s.voice', 'Payment voice', 'పేమెంట్ వాయిస్', Icons.volume_up_rounded, Color(0xFF0D9488),
        action: 'voice'),
  ];
}

AskodoxLaunchLayout askodoxSellerShippedLayout() => const AskodoxLaunchLayout([
      AskodoxLaunchEntry.page('s.bill'),
      AskodoxLaunchEntry.page('s.orders'),
      AskodoxLaunchEntry.page('s.dues'),
      AskodoxLaunchEntry.page('s.qr'),
      AskodoxLaunchEntry.page('s.voice'),
      AskodoxLaunchEntry.page('s.history'),
      AskodoxLaunchEntry.page('s.sales'),
      AskodoxLaunchEntry.page('s.reports'),
      AskodoxLaunchEntry.folder('money', '', ['s.cashbook', 's.day', 's.gst', 's.purchases', 's.counter']),
      AskodoxLaunchEntry.folder('hotel', '', ['s.tables', 's.kitchen']),
      AskodoxLaunchEntry.folder('items', '', ['s.menu', 's.additem', 's.sort', 's.stock']),
      AskodoxLaunchEntry.folder('shopset', '', ['s.details', 's.printer', 's.selfshop', 's.agents', 's.reportset']),
      AskodoxLaunchEntry.page('s.attendance'),
      AskodoxLaunchEntry.page('s.checkin'),
      AskodoxLaunchEntry.page('s.tasks'),
      AskodoxLaunchEntry.page('s.salary'),
      AskodoxLaunchEntry.page('s.post'),
      AskodoxLaunchEntry.page('s.page'),
      AskodoxLaunchEntry.page('s.customers'),
      AskodoxLaunchEntry.page('s.crm'),
      AskodoxLaunchEntry.page('s.orderalerts'),
      AskodoxLaunchEntry.page('s.qrcodes'),
      AskodoxLaunchEntry.folder('staff', '', ['s.kiosk', 's.people', 's.attsetup']),
    ]);
