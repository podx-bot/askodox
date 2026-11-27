import '../../../config/theme/askodox_look.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/flags/askodox_release_phase.dart';
import '../../home/presentation/question_mic.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart' show askodoxPaise;
import '../../pos/presentation/pos_common.dart';

/// The ONE business hub (owner 2026-11-18, design "నా బిజినెస్ — అన్ని పేజీల ప్లాన్"):
///   hub -> 6 groups -> inner page -> one thing.
/// Every page has the same shape: a coloured header with the path ("నా బిజినెస్ › మెనూ › బిర్యానీలు"), today's
/// numbers, big buttons ("రోజూ వాడేవి" then "ఒకసారి సెట్ చేసేవి"), history at the bottom and the ASK bar.
/// One colour per group, inner pages keep it. Every business type gets the same 6 groups; the names inside adapt.

class AskodoxBizTone {
  const AskodoxBizTone(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

const askodoxBizTones = <String, AskodoxBizTone>{
  'orders': AskodoxBizTone(Color(0xFF242D43), Color(0xFFAFC8FC)),
  'money': AskodoxBizTone(Color(0xFF1A3429), Color(0xFF7CD3A2)),
  'menu': AskodoxBizTone(Color(0xFF3F280D), Color(0xFFFB9E6A)),
  'staff': AskodoxBizTone(Color(0xFF332842), Color(0xFFCDBAFF)),
  'customers': AskodoxBizTone(Color(0xFF412331), Color(0xFFFBA1BF)),
  'settings': AskodoxBizTone(Color(0xFF1F2432), Color(0xFFC0CDE0)),
  'reports': AskodoxBizTone(Color(0xFF332842), Color(0xFFCDBAFF)),
  'teal': AskodoxBizTone(Color(0xFF113437), Color(0xFF7DCCE9)),
  'pink': AskodoxBizTone(Color(0xFF412331), Color(0xFFFBA1BF)),
  'gray': AskodoxBizTone(Color(0xFF1F2432), Color(0xFFC0CDE0)),
  'blue': AskodoxBizTone(Color(0xFF242D43), Color(0xFFAFC8FC)),
  'green': AskodoxBizTone(Color(0xFF1A3429), Color(0xFF7CD3A2)),
  'orange': AskodoxBizTone(Color(0xFF3F280D), Color(0xFFFB9E6A)),
  'purple': AskodoxBizTone(Color(0xFF332842), Color(0xFFCDBAFF)),
};

const _ink = Color(0xFFF7F9FC);
const _muted = Color(0xFFB9C5D5);
const _askPurple = Color(0xFFCDBAFF);

/// What kind of business decides a few names inside the groups (never the groups themselves).
enum AskodoxBizKind { food, service, retail }

AskodoxBizKind askodoxBizKind(Object? template) => switch ('${template ?? ''}') {
      'restaurant' || 'bakery' => AskodoxBizKind.food,
      'salon' || 'repair' => AskodoxBizKind.service,
      _ => AskodoxBizKind.retail,
    };

/// A shop's pages (Business Kit, owner 2026-11-24): the server's `kit.page_family` comes from the ways of working of
/// EVERYTHING the shop picked (a hotel that also sells sweets gets tables + kitchen whatever its kind); a shop from an
/// older server falls back to its kind.
AskodoxBizKind askodoxBizKindOf(Object? business) {
  if (business is! Map) return AskodoxBizKind.retail;
  final kit = business['kit'];
  if (kit is Map) {
    switch ('${kit['page_family'] ?? ''}') {
      case 'food':
        return AskodoxBizKind.food;
      case 'service':
        return AskodoxBizKind.service;
      case 'retail':
        return AskodoxBizKind.retail;
    }
  }
  return askodoxBizKind(business['template']);
}

/// The shop's ways of working from its Business Kit picks ('1'..'6'); empty from an older server.
Set<String> askodoxKitFlows(Object? business) {
  final kit = business is Map ? business['kit'] : null;
  final flows = kit is Map ? kit['flows'] : null;
  return flows is List ? {for (final f in flows) '$f'} : const <String>{};
}

/// Every page the hub, the ASK bar and the chat may open: page key -> route. Keys match the server's
/// `pos_hub.PAGES`; a key without a route here falls back to the group page.
String askodoxBizRoute(String id, String page) => switch (page) {
      'hub' => '/biz/$id',
      'orders.incoming' || 'orders.calls' => '/desk/$id',
      'orders.tables' => '/pos/$id/tables',
      'orders.kitchen' => '/pos/$id/kitchen',
      'orders.delivery' => '/desk/$id',
      'orders.qr' => '/desk/$id/qr',
      'orders.alerts' => '/desk/$id/settings',
      'orders.bookings' => '/biz/$id/bookings',
      'orders.jobs' => '/biz/$id/jobs',
      'orders.send' => '/pos/$id/deliveries',
      'orders.team' => '/pos/$id/team',
      'orders.branches' => '/me/branches?shop=$id',
      'money.monthly' => '/biz/$id/monthly',
      'money.bill' => '/me/business/$id/bill',
      'money.counter' => '/pos/$id/sale',
      'money.dues' => '/biz/$id/money/dues',
      'money.cashbook' => '/biz/$id/money/cashbook',
      'money.sound' => askodoxRouteShownNow('/pos') ? '/pos/$id/payment-alerts' : '/me/payment-alerts/$id',
      // Owner 2026-11-23: the shop's accounts page -- each account ON / OFF for THIS shop (the QR is one tap inside).
      'money.accounts' => '/me/payments/phone?open=accounts&shop=$id',
      'money.sales' => '/desk/$id/sales',
      'money.history' => '/biz/$id/money/history',
      'money.gst' => '/pos/$id/gst',
      'money.day' => '/pos/$id/day',
      'money.purchases' => '/pos/$id/suppliers',
      'menu.add' || 'menu.today' => '/desk/$id/menu',
      'menu.photo' => '/desk/$id/menu?full=1',
      'menu.sort' => '/biz/$id/menu/sort',
      'menu.stock' => '/pos/$id/items',
      'staff.add' || 'staff.people' => askodoxRouteShownNow('/pos') ? '/pos/$id/staff' : '/desk/$id/settings',
      'staff.alerts' => '/desk/$id/settings',
      'staff.attendance' => '/biz/$id/staff/today',
      'reports' || 'reports.day' => '/biz/$id/reports',
      'reports.settings' => '/biz/$id/reports/settings',
      'staff.checkin' => '/biz/$id/staff/checkin',
      'staff.salary' => '/biz/$id/staff/salary',
      'staff.tasks' => '/biz/$id/staff/tasks',
      'customers.page' || 'customers.reviews' => '/shops/$id',
      'customers.post' => '/shops/$id/post',
      'customers.link' => '/pos/$id/link',
      'customers.welcome' => '/desk/$id/settings',
      'customers.list' => '/pos/$id/customers',
      'customers.crm' => '/pos/$id/crm',
      'customers.offers' => '/business/promotions',
      'customers.autoreply' => '/business/automation',
      'settings.details' => '/me/business/$id/profile',
      'settings.gst' => '/pos/$id/gst',
      'settings.printer' => '/pos/$id/printer',
      'settings.accounts' => '/me/payment-methods',
      'settings.selfshop' => '/pos/$id/selfshop',
      'settings.agents' => '/pos/$id/agents',
      _ => '/biz/$id/${page.split('.').first}',
    };

class AskodoxBizTileSpec {
  const AskodoxBizTileSpec(this.page, this.icon, this.en, this.te, this.subEn, this.subTe,
      {required this.tone, this.key, this.badge, this.setup = false, this.perm});
  final String page;
  final IconData icon;
  final String en, te, subEn, subTe;
  final String tone;

  /// A widget key that must stay findable (approved feature registry / walkthroughs).
  final String? key;
  final String? Function(AskodoxJson hub)? badge;

  /// True = "ఒకసారి సెట్ చేసేవి" (set once); false = "రోజూ వాడేవి" (every day).
  final bool setup;

  /// The POS permission the person needs to see it (null = every member).
  final String? perm;
}

class AskodoxBizGroupSpec {
  const AskodoxBizGroupSpec(this.id, this.icon, this.en, this.te,
      {required this.tiles, required this.strip, required this.sub, this.history, this.perm});
  final String id;
  final IconData icon;
  final String en, te;
  final List<AskodoxBizTileSpec> tiles;
  final List<(String, String, String, Color)> Function(AskodoxJson hub) strip; // (en, te, value, colour)
  final String Function(AskodoxJson hub, bool te) sub;
  final (String, String, String, String, String)? history; // (en, te, subEn, subTe, page)
  final String? perm;

  AskodoxBizTone get tone => askodoxBizTones[id]!;
}

String _rs(Object? paise) => askodoxPaise(askodoxPosInt(paise));
String? _n(Object? v) => askodoxPosInt(v) > 0 ? '${askodoxPosInt(v)}' : null;

/// The 6 groups. [kind] only renames a few things (food has tables + kitchen, a service shop calls items "services").
List<AskodoxBizGroupSpec> askodoxBizGroups(AskodoxBizKind kind, {Set<String> flows = const <String>{}}) {
  final food = kind == AskodoxBizKind.food;
  final service = kind == AskodoxBizKind.service;
  return [
    AskodoxBizGroupSpec('orders', Icons.receipt_long_outlined,
        service ? 'Orders & bookings' : 'Orders', service ? 'ఆర్డర్లు & బుకింగ్స్' : 'ఆర్డర్లు',
        sub: (h, te) => te
            ? 'కొత్తవి ${askodoxPosInt(askodoxPosMap(h['orders'])['new'])} · పిలుపులు ${askodoxPosInt(h['calls'])}'
            : 'New ${askodoxPosInt(askodoxPosMap(h['orders'])['new'])} · calls ${askodoxPosInt(h['calls'])}',
        strip: (h) {
          final o = askodoxPosMap(h['orders']);
          return [
            ('New', 'కొత్తవి', '${askodoxPosInt(o['new'])}', const Color(0xFFAFC8FC)),
            (food ? 'Cooking' : 'In progress', food ? 'వంటలో' : 'జరుగుతున్నవి', '${askodoxPosInt(o['cooking'])}', const Color(0xFFFB9E6A)),
            ('Done', 'పూర్తి', '${askodoxPosInt(o['done'])}', const Color(0xFF7CD3A2)),
          ];
        },
        history: ('Order history', 'ఆర్డర్ల చరిత్ర', 'Search by date, table, customer', 'తేదీ, టేబుల్, కస్టమర్‌తో వెతకండి', 'orders.incoming'),
        tiles: [
          AskodoxBizTileSpec('orders.incoming', Icons.receipt_long_outlined, 'Incoming orders', 'వచ్చిన ఆర్డర్లు',
              'Accept / refuse', 'ఒప్పుకో / తిరస్కరించు', tone: 'blue', key: 'askodoxMyBusinessDesk',
              badge: (h) => _n(askodoxPosMap(h['orders'])['new'])),
          // Business Kit ways 3 + 4 (owner 2026-11-24): bookings and job cards for the shops that work that way.
          if (flows.contains('3'))
            const AskodoxBizTileSpec('orders.bookings', Icons.event_available_outlined, 'Bookings', 'బుకింగ్స్',
                'Rooms, chairs, slots, hall', 'రూమ్‌లు, కుర్చీలు, సమయాలు, హాల్', tone: 'teal', perm: 'customers'),
          if (flows.contains('4'))
            const AskodoxBizTileSpec('orders.jobs', Icons.build_circle_outlined, 'Job cards', 'జాబ్ కార్డ్స్',
                'Received → ready → given', 'తీసుకున్నాం → రెడీ → ఇచ్చేశాం', tone: 'orange', perm: 'customers'),
          // Way 6 (enquiry -> site visit -> deal) is the Business CRM: up front for the shops that work that way.
          if (flows.contains('6'))
            const AskodoxBizTileSpec('customers.crm', Icons.forum_outlined, 'Enquiries', 'ఎంక్వైరీలు',
                'Enquiry → visit → quote → deal', 'ఎంక్వైరీ → విజిట్ → కొటేషన్ → డీల్', tone: 'blue', perm: 'crm'),
          if (food) ...[
            const AskodoxBizTileSpec('orders.tables', Icons.table_restaurant_outlined, 'Tables', 'టేబుల్స్',
                'Free / busy', 'ఖాళీ / బిజీ', tone: 'teal', perm: 'tables'),
            AskodoxBizTileSpec('orders.calls', Icons.front_hand_outlined, 'Table calls', 'టేబుల్ పిలుపులు',
                'Water, gravy, bill…', 'నీళ్లు, గ్రేవీ, బిల్లు…', tone: 'orange', badge: (h) => _n(h['calls'])),
            const AskodoxBizTileSpec('orders.kitchen', Icons.soup_kitchen_outlined, 'Kitchen (KOT)', 'వంటగది KOT',
                'What to cook, in order', 'వండాల్సినవి వరుసగా', tone: 'pink', perm: 'kitchen'),
          ],
          const AskodoxBizTileSpec('orders.delivery', Icons.delivery_dining_outlined, 'Delivery / parcel', 'డెలివరీ / పార్సిల్',
              'Swiggy, Zomato, phone orders', 'Swiggy, Zomato, ఫోన్ ఆర్డర్లు', tone: 'purple'),
          AskodoxBizTileSpec('orders.qr', Icons.qr_code_2, food ? 'Table QR codes' : 'Shop QR code',
              food ? 'టేబుల్ QR కోడ్‌లు' : 'షాప్ QR కోడ్', 'Print and stick', 'ప్రింట్ చేసి పెట్టండి', tone: 'gray', setup: true,
              perm: 'settings'),
          const AskodoxBizTileSpec('orders.alerts', Icons.notifications_active_outlined, 'Who accepts & alerts',
              'ఎవరు ఒప్పుకోవాలి & అలర్ట్స్', 'Who is told at each step', 'ఏ దశలో ఎవరికి సౌండ్', tone: 'blue', setup: true,
              key: 'askodoxMyBusinessOrderAlerts', perm: 'settings'),
        ]),
    AskodoxBizGroupSpec('money', Icons.account_balance_wallet_outlined, 'Bills & money', 'బిల్లులు & డబ్బు',
        sub: (h, te) => te
            ? 'బిల్లు, బాకీ, పేమెంట్ సౌండ్ · ఈ రోజు ${_rs(askodoxPosMap(h['sales'])['paise'])}'
            : 'Bill, dues, payment sound · today ${_rs(askodoxPosMap(h['sales'])['paise'])}',
        strip: (h) {
          final s = askodoxPosMap(h['split']);
          return [
            ('Cash', 'క్యాష్', _rs(s['cash_paise']), const Color(0xFF7CD3A2)),
            ('Online', 'ఆన్‌లైన్', _rs(s['online_paise']), const Color(0xFFAFC8FC)),
            ('Dues', 'బాకీ', _rs(askodoxPosMap(h['dues'])['paise']), const Color(0xFFFB9E6A)),
          ];
        },
        history: ('Bill history', 'బిల్లుల చరిత్ర', 'Number, customer, date · ✏ same-day edit',
            'నంబర్, కస్టమర్, తేదీతో వెతకండి · ✏ అదే రోజు మార్చు', 'money.history'),
        tiles: [
          const AskodoxBizTileSpec('money.bill', Icons.calculate_outlined, 'Make a bill', 'బిల్లు చేయి',
              'Cash | Online | Baaki', 'క్యాష్ | ఆన్‌లైన్ | బాకీ', tone: 'green', key: 'askodoxMyBusinessBill', perm: 'sell'),
          const AskodoxBizTileSpec('money.cashbook', Icons.import_contacts_outlined, 'Cashbook', 'క్యాష్‌బుక్',
              'Money in + money out', 'ఆదాయం + ఖర్చు', tone: 'blue', perm: 'reports'),
          AskodoxBizTileSpec('money.dues', Icons.menu_book_outlined, 'Dues', 'బాకీలు', 'Who owes how much',
              'ఎవరు ఎంత ఇవ్వాలి', tone: 'orange', badge: (h) => _n(askodoxPosMap(h['dues'])['people']), perm: 'customers'),
          if (flows.contains('5'))
            const AskodoxBizTileSpec('money.monthly', Icons.event_repeat_outlined, 'Monthly members', 'నెలవారీ సభ్యులు',
                'Milk, tuition, gym, PG', 'పాలు, ట్యూషన్, జిమ్, PG', tone: 'purple', perm: 'customers'),
          AskodoxBizTileSpec('money.sound', Icons.volume_up_outlined, 'Payment sound', 'పేమెంట్ సౌండ్',
              'Says each payment aloud', 'డబ్బు రాగానే చెబుతుంది', tone: 'teal', badge: (h) => _n(h['sounds'])),
          const AskodoxBizTileSpec('money.accounts', Icons.qr_code_2, 'My QR / accounts', 'నా QR / ఖాతాలు',
              'Money comes straight to you', 'డబ్బు నేరుగా మీ ఖాతాకే', tone: 'blue', key: 'askodoxMyBusinessAccounts',
              perm: 'settings'),
          const AskodoxBizTileSpec('money.sales', Icons.insights_outlined, 'Sales', 'అమ్మకాలు', 'Day, week, month',
              'రోజు, వారం, నెల', tone: 'purple', key: 'askodoxMyBusinessSales', setup: true, perm: 'reports'),
          const AskodoxBizTileSpec('money.day', Icons.schedule_outlined, 'Close the day', 'రోజు ముగింపు',
              'Count the cash', 'క్యాష్ సరిచూడు', tone: 'gray', setup: true, perm: 'day_close'),
          const AskodoxBizTileSpec('money.gst', Icons.description_outlined, 'GST report', 'GST రిపోర్ట్', 'For monthly filing',
              'నెలవారీ ఫైలింగ్‌కి', tone: 'gray', setup: true, perm: 'reports'),
          const AskodoxBizTileSpec('money.purchases', Icons.local_shipping_outlined, 'Purchases',
              'కొనుగోళ్లు', 'Purchase bills, stock in', 'కొనుగోలు బిల్లులు, స్టాక్', tone: 'gray', setup: true,
              perm: 'purchases'),
          const AskodoxBizTileSpec('money.counter', Icons.point_of_sale_outlined, 'Counter bill',
              'కౌంటర్ బిల్లు', 'GST bill, offline bills, printer', 'GST బిల్లు, ఆఫ్‌లైన్, ప్రింటర్', tone: 'gray',
              setup: true, perm: 'sell'),
        ]),
    AskodoxBizGroupSpec('menu', service ? Icons.content_cut : Icons.restaurant_menu,
        food ? 'Menu & items' : (service ? 'Services & prices' : 'Items & stock'),
        food ? 'మెనూ & ఐటమ్స్' : (service ? 'సేవలు & ధరలు' : 'ఐటమ్స్ & స్టాక్'),
        sub: (h, te) {
          final m = askodoxPosMap(h['menu']);
          return te
              ? '${askodoxPosInt(m['items'])} ఐటమ్స్ · ${askodoxPosInt(m['sections'])} విభాగాలు'
              : '${askodoxPosInt(m['items'])} items · ${askodoxPosInt(m['sections'])} sections';
        },
        strip: (h) {
          final m = askodoxPosMap(h['menu']);
          return [
            ('Items', 'ఐటమ్స్', '${askodoxPosInt(m['items'])}', const Color(0xFFFB9E6A)),
            ('Sections', 'విభాగాలు', '${askodoxPosInt(m['sections'])}', const Color(0xFFAFC8FC)),
            if (food || askodoxPosInt(m['low_stock']) == 0)
              ('No section', 'విభాగం లేనివి', '${askodoxPosInt(m['no_section'])}', const Color(0xFFFEA195))
            else
              ('Low stock', 'స్టాక్ తక్కువ', '${askodoxPosInt(m['low_stock'])}', const Color(0xFFFEA195)),
          ];
        },
        tiles: [
          const AskodoxBizTileSpec('menu.add', Icons.add_circle_outline, 'Add an item', 'ఐటమ్ చేర్చు', 'Name, price, photo',
              'పేరు, ధర, ఫోటో', tone: 'orange', perm: 'products'),
          const AskodoxBizTileSpec('menu.photo', Icons.photo_camera_outlined, 'Menu photo', 'మెనూ ఫోటో',
              'Reads it and adds items', 'ఫోటో చదివి చేరుస్తుంది', tone: 'orange', perm: 'products'),
          const AskodoxBizTileSpec('menu.sort', Icons.auto_awesome, 'Sort with AI', 'AI తో సర్దు',
              'Sections + veg / non-veg', 'విభాగాలు + వెజ్/నాన్-వెజ్', tone: 'purple', perm: 'products'),
          const AskodoxBizTileSpec('menu.today', Icons.toggle_on_outlined, 'Available today', 'ఈ రోజు ఉన్నవి',
              'Switch off what ran out', 'అయిపోతే ఆఫ్ చేయి', tone: 'green'),
          const AskodoxBizTileSpec('menu.stock', Icons.inventory_2_outlined, 'Stock & barcodes', 'స్టాక్ & బార్‌కోడ్',
              'Quantity, batches, GST', 'పరిమాణం, బ్యాచ్‌లు, GST', tone: 'gray', setup: true, perm: 'stock'),
        ]),
    AskodoxBizGroupSpec('staff', Icons.groups_outlined, 'Staff & attendance', 'సిబ్బంది & హాజరు',
        sub: (h, te) => te ? '${askodoxPosInt(h['staff'])} మంది' : '${askodoxPosInt(h['staff'])} people',
        strip: (h) => [
              ('Staff', 'సిబ్బంది', '${askodoxPosInt(h['staff'])}', const Color(0xFFCDBAFF)),
              ('Calls answered', 'పిలుపులు ఉన్నవి', '${askodoxPosInt(h['calls'])}', const Color(0xFFFB9E6A)),
              ('Payment sounds', 'పేమెంట్ సౌండ్', '${askodoxPosInt(h['sounds'])}', const Color(0xFF7CD3A2)),
            ],
        tiles: const [
          AskodoxBizTileSpec('staff.people', Icons.badge_outlined, 'Staff & roles', 'సిబ్బంది & పాత్రలు',
              'Who does what', 'ఎవరు ఏ పని', tone: 'purple'),
          AskodoxBizTileSpec('staff.add', Icons.person_add_alt_1_outlined, 'Add staff', 'సిబ్బందిని చేర్చు',
              'Name, number, role', 'పేరు, నంబర్, పాత్ర', tone: 'gray'),
          AskodoxBizTileSpec('staff.alerts', Icons.notifications_active_outlined, 'Who hears what', 'ఎవరికి ఏ సౌండ్',
              'One table', 'ఒక్క పట్టిక', tone: 'purple', setup: true),
        ]),
    AskodoxBizGroupSpec('customers', Icons.star_outline_rounded, 'Customers & shop page', 'కస్టమర్లు & షాప్ పేజీ',
        sub: (h, te) {
          final r = askodoxPosMap(h['reviews']);
          final avg = r['average'] is num ? '★ ${(r['average'] as num).toStringAsFixed(1)} · ' : '';
          return te ? '$avg${askodoxPosInt(r['count'])} రివ్యూలు' : '$avg${askodoxPosInt(r['count'])} reviews';
        },
        strip: (h) {
          final r = askodoxPosMap(h['reviews']);
          return [
            ('Rating', 'రేటింగ్', r['average'] is num ? '★ ${(r['average'] as num).toStringAsFixed(1)}' : '—',
                const Color(0xFFFB9E6A)),
            ('Reviews', 'రివ్యూలు', '${askodoxPosInt(r['count'])}', const Color(0xFFFBA1BF)),
            ('To answer', 'జవాబు ఇవ్వాలి', '${askodoxPosInt(r['unanswered'])}', const Color(0xFFAFC8FC)),
          ];
        },
        tiles: [
          const AskodoxBizTileSpec('customers.page', Icons.storefront_outlined, 'My shop page', 'నా షాప్ పేజీ',
              'What customers see', 'కస్టమర్లు చూసేది', tone: 'pink', key: 'askodoxMyBusinessPage'),
          AskodoxBizTileSpec('customers.reviews', Icons.star_outline_rounded, 'Reviews', 'రివ్యూలు', 'Reply to them',
              'జవాబు ఇవ్వండి', tone: 'pink', badge: (h) => _n(askodoxPosMap(h['reviews'])['unanswered'])),
          const AskodoxBizTileSpec('customers.post', Icons.campaign_outlined, "Today's post", 'ఈ రోజు పోస్ట్',
              'One picture for followers', 'ఫాలోవర్లకు ఒక ఫోటో', tone: 'orange', key: 'askodoxMyBusinessPost'),
          const AskodoxBizTileSpec('customers.welcome', Icons.waving_hand_outlined, 'Welcome / thanks',
              'స్వాగతం / ధన్యవాదాలు', 'Message on the QR scan', 'QR స్కాన్ మెసేజ్', tone: 'orange', perm: 'settings'),
          const AskodoxBizTileSpec('customers.list', Icons.people_outline, 'Customer list', 'కస్టమర్ల లిస్ట్',
              'Visits, dues', 'ఎన్నిసార్లు, బాకీ', tone: 'blue', setup: true, perm: 'customers'),
          const AskodoxBizTileSpec('customers.crm', Icons.forum_outlined, 'Enquiries', 'ఎంక్వైరీలు',
              'Leads, quotes, complaints', 'లీడ్స్, కొటేషన్, ఫిర్యాదులు', tone: 'blue', setup: true, perm: 'crm'),
          const AskodoxBizTileSpec('customers.offers', Icons.local_offer_outlined, 'Offers', 'ఆఫర్లు',
              'For new / returning customers', 'కొత్త / మళ్ళీ వచ్చేవారికి', tone: 'purple', setup: true, perm: 'settings'),
          const AskodoxBizTileSpec('customers.autoreply', Icons.quickreply_outlined, 'Auto replies', 'ఆటో జవాబులు',
              'Answers when you are busy', 'మీరు బిజీగా ఉన్నప్పుడు జవాబు', tone: 'gray', setup: true, perm: 'settings'),
        ]),
    AskodoxBizGroupSpec('settings', Icons.settings_outlined, 'Settings', 'సెట్టింగ్స్', perm: 'settings',
        sub: (h, te) => te ? 'వివరాలు, GST, ప్రింటర్, ఖాతాలు' : 'Details, GST, printer, accounts',
        strip: (h) => const [],
        tiles: const [
          AskodoxBizTileSpec('settings.details', Icons.badge_outlined, 'Business details', 'బిజినెస్ వివరాలు',
              'Name, address, hours', 'పేరు, అడ్రస్, సమయం', tone: 'gray', key: 'askodoxMyBusinessDetails'),
          AskodoxBizTileSpec('settings.gst', Icons.description_outlined, 'GST report', 'GST రిపోర్ట్', 'Regular / composition / none',
              'రెగ్యులర్ / కంపోజిషన్ / లేదు', tone: 'orange'),
          AskodoxBizTileSpec('settings.accounts', Icons.qr_code_2, 'My QR / accounts', 'నా QR / ఖాతాలు',
              'Which account for what', 'ఏ ఖాతా దేనికి', tone: 'blue'),
          AskodoxBizTileSpec('settings.printer', Icons.print_outlined, 'Printer', 'ప్రింటర్', 'Bluetooth / USB',
              'బ్లూటూత్ / USB', tone: 'teal', setup: true),
          AskodoxBizTileSpec('settings.selfshop', Icons.shopping_basket_outlined, 'Self-shopping', 'సెల్ఫ్ షాపింగ్',
              'Customers scan and shop', 'కస్టమర్లే స్కాన్ చేసి కొంటారు', tone: 'gray', setup: true),
          AskodoxBizTileSpec('settings.agents', Icons.smart_toy_outlined, 'AI agents', 'AI Agents',
              'One per role', 'పాత్రకు ఒకటి', tone: 'purple', setup: true),
        ]),
  ];
}

/// The groups / tiles a person may see: the owner everything, staff only what their role allows.
bool askodoxBizAllowed(String? perm, AskodoxJson business) {
  if (perm == null) return true;
  final role = '${business['my_role'] ?? business['role'] ?? ''}';
  if (role == 'owner') return true;
  final perms = (business['permissions'] as List?)?.map((e) => '$e').toSet() ?? const <String>{};
  return perms.contains(perm);
}

// ============================================================================================ shared building blocks

/// The coloured page head + body + ASK bar every business page uses.
class AskodoxBizScaffold extends StatelessWidget {
  const AskodoxBizScaffold({
    super.key,
    required this.businessId,
    required this.tone,
    required this.icon,
    required this.title,
    required this.trail,
    required this.page,
    required this.children,
    this.onRefresh,
    this.actions = const [],
    this.bottom,
    this.askHint,
  });

  final String businessId;
  final AskodoxBizTone tone;
  final IconData icon;
  final String title;

  /// The path under "My business" (group, inner page ...), shown above the title.
  final List<String> trail;

  /// The ASK bar's page key (what "here" means for a sentence).
  final String page;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final List<Widget> actions;
  final Widget? bottom;
  final String? askHint;

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final path = [te ? 'నా బిజినెస్' : 'My business', ...trail].join(' › ');
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      children: children,
    );
    return Scaffold(
      backgroundColor: const Color(0xFF1F2432),
      appBar: AppBar(
        backgroundColor: tone.bg,
        surfaceTintColor: tone.bg,
        elevation: 0,
        titleSpacing: 0,
        toolbarHeight: 72,
        actions: actions,
        title: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AskodoxLook.sheet, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: tone.fg, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (trail.isNotEmpty)
                Text(path,
                    key: const Key('askodoxBizTrail'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: _muted)),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _ink)),
            ]),
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list)),
        if (bottom != null) bottom!,
        AskodoxAskBar(businessId: businessId, page: page, hint: askHint),
      ]),
    );
  }
}

/// Three numbers in white boxes ("ఈ రోజు").
class AskodoxBizStrip extends StatelessWidget {
  const AskodoxBizStrip({super.key, required this.cells});
  final List<(String, String, Color)> cells; // (label, value, colour)

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      for (final (i, c) in cells.indexed) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: AskodoxLook.sheet, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: _muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(c.$2, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c.$3)),
              ),
            ]),
          ),
        ),
      ],
    ]);
  }
}

/// A grey section label ("రోజూ వాడేవి").
class AskodoxBizSection extends StatelessWidget {
  const AskodoxBizSection(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 2, 6),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _muted))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// One coloured button: icon in a white square, title, one line under it, an optional count badge.
class AskodoxBizTile extends StatelessWidget {
  const AskodoxBizTile({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
    required this.tone,
    required this.onTap,
    this.badge,
    this.minHeight = 92,
  });
  final IconData icon;
  final String title;
  final String sub;
  final AskodoxBizTone tone;
  final VoidCallback onTap;
  final String? badge;
  final double minHeight;

  @override
  Widget build(BuildContext context) => Material(
        color: tone.bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight),
            padding: const EdgeInsets.all(12),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AskodoxLook.sheet, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: tone.fg, size: 20),
                ),
                const SizedBox(height: 6),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _ink)),
                if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 11.5, color: _muted)),
              ]),
              if (badge != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: tone.fg, borderRadius: BorderRadius.circular(9)),
                    child: Text(badge!, style: const TextStyle(color: AskodoxLook.sheet, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// Two tiles per row (an odd last tile takes the full row).
class AskodoxBizGrid extends StatelessWidget {
  const AskodoxBizGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final half = (box.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final (i, c) in children.indexed)
            SizedBox(width: i == children.length - 1 && children.length.isOdd ? box.maxWidth : half, child: c),
        ]);
      });
}

/// The history row at the bottom of a group page.
class AskodoxBizHistoryRow extends StatelessWidget {
  const AskodoxBizHistoryRow({super.key, required this.title, required this.sub, required this.onTap});
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Material(
          color: AskodoxLook.sheet,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF4A526B))),
          child: InkWell(
            key: const Key('askodoxBizHistory'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                const Icon(Icons.history, color: Color(0xFFC0CDE0)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: _ink)),
                    Text(sub, style: const TextStyle(fontSize: 11.5, color: _muted)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF9299A4)),
              ]),
            ),
          ),
        ),
      );
}

// ============================================================================================ the ASK bar

/// The ASK bar at the bottom of every business page: type or speak one sentence. Opening a page or answering from the
/// shop's numbers happens at once; a CHANGE is shown first and runs only after the person's ✓ (owner 2026-11-18).
class AskodoxAskBar extends ConsumerStatefulWidget {
  const AskodoxAskBar({super.key, required this.businessId, required this.page, this.hint});
  final String businessId;
  final String page;
  final String? hint;

  @override
  ConsumerState<AskodoxAskBar> createState() => _AskodoxAskBarState();
}

class _AskodoxAskBarState extends ConsumerState<AskodoxAskBar> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String words) async {
    final text = words.trim();
    if (text.isEmpty || _busy) return;
    final te = askodoxPosTe(context);
    setState(() => _busy = true);
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final out = await repo.ask(widget.businessId, text, page: widget.page, lang: te ? 'te' : 'en');
      _text.clear();
      if (!mounted) return;
      final confirm = askodoxPosMap(out['confirm']);
      final open = '${out['open'] ?? ''}';
      if (confirm.isNotEmpty) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(te ? 'ఇలా మార్చనా?' : 'Make this change?'),
            content: Text('${confirm['summary'] ?? out['reply'] ?? ''}', style: const TextStyle(fontSize: 16)),
            actions: [
              TextButton(
                  key: const Key('askodoxAskNo'),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(te ? '✗ వద్దు' : '✗ No')),
              FilledButton(
                  key: const Key('askodoxAskYes'),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(te ? '✓ అవును, చేయి' : '✓ Yes, do it')),
            ],
          ),
        );
        if (yes != true || !mounted) return;
        await repo.askConfirm(widget.businessId, {
          for (final e in confirm.entries)
            if (e.key != 'summary' && e.value != null) e.key: e.value,
        });
        if (mounted) askodoxPosSnack(context, te ? 'చేశాను ✓' : 'Done ✓');
        return;
      }
      if ('${out['reply'] ?? ''}'.isNotEmpty) {
        if (open.isNotEmpty) {
          askodoxPosSnack(context, '${out['reply']}');
        } else {
          await showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Text('${out['reply']}', key: const Key('askodoxAskReply'), style: const TextStyle(fontSize: 16)),
              ),
            ),
          );
        }
      }
      if (open.isNotEmpty && mounted) unawaited(context.push(askodoxBizRoute(widget.businessId, open)));
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } catch (_) {
      if (mounted) askodoxPosSnack(context, te ? 'ఇప్పుడు కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'Could not do that now. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Container(
          key: const Key('askodoxAskBar'),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            color: AskodoxLook.sheet,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFF4F3D6C), width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 2))],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: _askPurple, borderRadius: BorderRadius.circular(8)),
              child: const Text('ASK', style: TextStyle(color: AskodoxLook.sheet, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('askodoxAskText'),
                controller: _text,
                enabled: !_busy,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.hint ?? (te ? 'ఏం చేయాలో చెప్పండి — నేనే చేస్తాను' : 'Say what to do — I will do it'),
                  hintStyle: const TextStyle(fontSize: 13, color: _muted),
                ),
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
              )
            else ...[
              IconButton(
                key: const Key('askodoxAskSend'),
                tooltip: te ? 'పంపు' : 'Send',
                icon: const Icon(Icons.send_rounded, color: _askPurple),
                onPressed: () => _send(_text.text),
              ),
              AskodoxQuestionMic(key: const Key('askodoxAskMic'), lang: te ? 'te' : 'en', followCentre: false, onText: _send),
              const SizedBox(width: 4),
            ],
          ]),
        ),
      ),
    );
  }
}

// ============================================================================================ hub + group pages

/// The business + today's numbers, loaded together for the hub and the group pages.
final askodoxBizHubProvider = FutureProvider.autoDispose.family<(AskodoxJson, AskodoxJson), String>((ref, id) async {
  final repo = ref.watch(askodoxPosRepositoryProvider);
  final results = await Future.wait([repo.business(id), repo.hub(id)]);
  return (results[0], results[1]);
});

/// The hub's own content: today's numbers, three every-day buttons and the 6 group tiles. Used inside
/// "My business" (`/me/business`) and as the full hub page (`/pos/:id`).
class AskodoxBizHubBody extends ConsumerWidget {
  const AskodoxBizHubBody({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    final data = ref.watch(askodoxBizHubProvider(businessId));
    return data.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => AskodoxPosError(error: e, onRetry: () => ref.invalidate(askodoxBizHubProvider(businessId))),
      data: (pair) {
        final (business, hub) = pair;
        final groups = askodoxBizGroups(askodoxBizKindOf(business), flows: askodoxKitFlows(business))
            .where((g) => askodoxBizAllowed(g.perm, business))
            .toList();
        final sales = askodoxPosMap(hub['sales']);
        final orders = askodoxPosMap(hub['orders']);
        final quick = <(String, IconData, String, Color, String?)>[
          if (askodoxBizAllowed('sell', business)) ('money.bill', Icons.calculate_outlined, te ? 'బిల్లు చేయి' : 'Make a bill',
              const Color(0xFF7CD3A2), 'askodoxBizQuick-bill'),
          ('orders.incoming', Icons.receipt_long_outlined,
              '${te ? 'ఆర్డర్లు' : 'Orders'}${askodoxPosInt(orders['new']) > 0 ? ' ${askodoxPosInt(orders['new'])}' : ''}',
              const Color(0xFFAFC8FC), 'askodoxBizQuick-orders'),
          ('orders.qr', Icons.qr_code_2, te ? 'QR చూపు' : 'Show QR', const Color(0xFFC0CDE0), 'askodoxBizQuick-qr'),
        ].where((q) => askodoxRouteShownNow(askodoxBizRoute(businessId, q.$1))).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AskodoxBizStrip(cells: [
            (te ? 'ఈ రోజు అమ్మకం' : "Today's sales", askodoxPaise(askodoxPosInt(sales['paise'])), const Color(0xFF7CD3A2)),
            (te ? 'బాకీ' : 'Dues', askodoxPaise(askodoxPosInt(askodoxPosMap(hub['dues'])['paise'])), const Color(0xFFFB9E6A)),
            (te ? 'పేమెంట్ సౌండ్' : 'Payment sound', te ? '${askodoxPosInt(hub['sounds'])} సార్లు' : '${askodoxPosInt(hub['sounds'])}×',
                const Color(0xFFAFC8FC)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (final (i, q) in quick.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: q.$5 == null ? null : Key(q.$5!),
                  style: FilledButton.styleFrom(
                      backgroundColor: q.$4,
                      minimumSize: const Size.fromHeight(50),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: () => context.push(askodoxBizRoute(businessId, q.$1)),
                  icon: Icon(q.$2, size: 18),
                  label: FittedBox(child: Text(q.$3, style: const TextStyle(fontWeight: FontWeight.w800))),
                ),
              ),
            ],
          ]),
          if (askodoxBizAllowed('reports', business)) ...[
            const SizedBox(height: 10),
            Material(
              color: const Color(0xFF332842),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: const Key('askodoxBizReportsCard'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/biz/$businessId/reports'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Text('📊', style: TextStyle(fontSize: 34)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(te ? 'రిపోర్ట్స్ & అనాలిటిక్స్' : 'Reports & analytics',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFCDBAFF))),
                        Text(te ? 'ఈ రోజు ఎలా ఉంది, సమస్యలు + కారణాలు, సలహాలు, వినండి' : 'How today went, problems + why, what to do, listen',
                            style: const TextStyle(fontSize: 12, color: Color(0xFFB9C5D5))),
                      ]),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFFCDBAFF)),
                  ]),
                ),
              ),
            ),
          ],
          AskodoxBizSection(te ? '${groups.length} విభాగాలు — ఒకటి నొక్కితే దాని పనులన్నీ' : 'Tap a group to see everything in it'),
          AskodoxBizGrid(children: [
            for (final g in groups)
              AskodoxBizTile(
                key: Key('askodoxBizGroup-${g.id}'),
                icon: g.icon,
                title: te ? g.te : g.en,
                sub: g.sub(hub, te),
                tone: g.tone,
                minHeight: 104,
                badge: switch (g.id) {
                  'orders' => _n(askodoxPosInt(orders['new']) + askodoxPosInt(hub['calls'])),
                  'customers' => _n(askodoxPosMap(hub['reviews'])['unanswered']),
                  'menu' => _n(askodoxPosMap(hub['menu'])['no_section']),
                  _ => null,
                },
                onTap: () => context.push('/biz/$businessId/${g.id}'),
              ),
          ]),
          const SizedBox(height: 12),
          TextButton.icon(
            key: const Key('askodoxBizIdea'),
            onPressed: () => context.push('/me/ideas?about=business'),
            icon: const Icon(Icons.lightbulb_outline, color: Color(0xFFE0B467)),
            label: Text(te ? 'మీ ఐడియా చెప్పండి — ఏది ఇంకా సులువుగా ఉండాలి?' : 'Tell us your idea — what should be easier?',
                style: const TextStyle(color: Color(0xFFE0B467), fontWeight: FontWeight.w800)),
          ),
        ]);
      },
    );
  }
}

/// `/biz/:id` -- the hub as its own page (staff open their shop here).
class AskodoxBizHubScreen extends ConsumerWidget {
  const AskodoxBizHubScreen({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    final name = ref.watch(askodoxBizHubProvider(businessId)).valueOrNull?.$1['name'];
    return AskodoxBizScaffold(
      key: const Key('askodoxBizHub'),
      businessId: businessId,
      tone: askodoxBizTones['menu']!,
      icon: Icons.storefront_outlined,
      title: '${name ?? (te ? 'నా బిజినెస్' : 'My business')}',
      trail: const [],
      page: 'hub',
      onRefresh: () async => ref.invalidate(askodoxBizHubProvider(businessId)),
      askHint: te ? '"ఈ రోజు ఎంత అమ్మాం?" "చికెన్ 65 ఆఫ్ చెయ్యి"' : '"How much did we sell today?"',
      children: [AskodoxBizHubBody(businessId: businessId)],
    );
  }
}

/// `/biz/:id/:group` -- one of the 6 groups: today's numbers, every-day buttons, set-once buttons, history.
class AskodoxBizGroupScreen extends ConsumerWidget {
  const AskodoxBizGroupScreen({super.key, required this.businessId, required this.groupId, this.extra = const []});
  final String businessId;
  final String groupId;

  /// Extra content a group shows under its buttons (the menu sections).
  final List<Widget> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    final data = ref.watch(askodoxBizHubProvider(businessId));
    final kind = askodoxBizKindOf(data.valueOrNull?.$1);
    final flows = askodoxKitFlows(data.valueOrNull?.$1);
    final group = askodoxBizGroups(kind, flows: flows)
        .firstWhere((g) => g.id == groupId, orElse: () => askodoxBizGroups(kind, flows: flows).first);
    Future<void> refresh() async => ref.invalidate(askodoxBizHubProvider(businessId));
    return AskodoxBizScaffold(
      key: Key('askodoxBizGroupPage-${group.id}'),
      businessId: businessId,
      tone: group.tone,
      icon: group.icon,
      title: te ? group.te : group.en,
      trail: [te ? group.te : group.en],
      page: group.id,
      onRefresh: refresh,
      children: data.when(
        loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
        error: (e, _) => [AskodoxPosError(error: e, onRetry: refresh)],
        data: (pair) {
          final (business, hub) = pair;
          // A tile whose page is not in this build (Phase 2 POS screens in a Phase 1 build) is not shown.
          final tiles = group.tiles
              .where((t) => askodoxBizAllowed(t.perm, business) && askodoxRouteShownNow(askodoxBizRoute(businessId, t.page)))
              .toList();
          Widget tile(AskodoxBizTileSpec t) => AskodoxBizTile(
                key: Key(t.key ?? 'askodoxBizTile-${t.page}'),
                icon: t.icon,
                title: te ? t.te : t.en,
                sub: te ? t.subTe : t.subEn,
                tone: askodoxBizTones[t.tone]!,
                badge: t.badge?.call(hub),
                minHeight: t.setup ? 80 : 92,
                onTap: () => context.push(askodoxBizRoute(businessId, t.page)),
              );
          final daily = tiles.where((t) => !t.setup).toList();
          final setup = tiles.where((t) => t.setup).toList();
          final strip = group.strip(hub);
          return [
            AskodoxBizStrip(cells: [for (final c in strip) (te ? c.$2 : c.$1, c.$3, c.$4)]),
            if (daily.isNotEmpty) ...[
              AskodoxBizSection(te ? 'రోజూ వాడేవి' : 'Every day'),
              AskodoxBizGrid(children: [for (final t in daily) tile(t)]),
            ],
            ...extra,
            if (setup.isNotEmpty) ...[
              AskodoxBizSection(te ? 'ఒకసారి సెట్ చేసేవి' : 'Set once'),
              AskodoxBizGrid(children: [for (final t in setup) tile(t)]),
            ],
            if (group.history != null)
              AskodoxBizHistoryRow(
                title: te ? group.history!.$2 : group.history!.$1,
                sub: te ? group.history!.$4 : group.history!.$3,
                onTap: () => context.push(askodoxBizRoute(businessId, group.history!.$5)),
              ),
          ];
        },
      ),
    );
  }
}
