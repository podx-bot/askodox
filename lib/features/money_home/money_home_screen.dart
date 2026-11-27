import '../../config/theme/askodox_look.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/backend_providers.dart';
import '../business/presentation/biz_hub.dart' show askodoxBizHubProvider, askodoxBizRoute;
import '../home/domain/shopping_mode.dart';
import '../pos/data/pos_payment_alerts.dart';
import '../pos/data/pos_repository.dart';
import '../pos/domain/money_ledger.dart';
import '../pos/domain/pos_money.dart' show askodoxPaise;
import '../../shared/widgets/chat_pins.dart' show AskodoxChatPin, askodoxChatPinsProvider, askodoxOfferChatPin;
import 'launcher_layout.dart';
import 'money_home_pages.dart';
import 'money_home_store.dart';
import 'one_touch.dart';
import 'payment_voice_sheet.dart';
import 'shop_setup_card.dart';

const _buyerColor = Color(0xFFADAEFD);
const _sellerColor = Color(0xFF77D49F);
const _ink = Color(0xFFF7F9FC);

/// "Money" on the bottom bar, in BOTH sides (owner 2026-11-22):
/// - Buyer side = the person's own money: one card (this month in / out + the latest two) and their pages;
/// - Seller side = the shop's money: the shop in view (a chooser when they run / help in more than one), today's
///   numbers and that shop's own tools, only those the person's role allows. Never mixed with the personal account.
/// Pages sit like apps on a phone: icon + name, more screens when one is full. Nothing comes grouped -- every page
/// starts on its own and the person makes their own folders (owner 2026-11-22). Press and hold: let go = the page's
/// menu (put it above the Home chat -- the same five shortcuts for everyone --, move, take out of a folder, hide); move
/// it = arrange: drop it anywhere = it sits there and the rest shift (never a group, owner 2026-11-23; folders only from
/// the menu), to the screen's edge = the next screen, out of an
/// open folder = back on the screen, inside a folder = its new place. Pages are hidden (never deleted) and brought
/// back; "Reset" brings the shipped screen back.
class AskodoxMoneyHomeScreen extends ConsumerStatefulWidget {
  const AskodoxMoneyHomeScreen({super.key, this.section = 'money'});

  /// Owner 2026-11-23: `money` = the Money tab (money only); `side` = the కొను / అమ్ము page (everything else of the
  /// side: orders, shops, items, staff, customers, settings).
  final String section;

  @override
  ConsumerState<AskodoxMoneyHomeScreen> createState() => _AskodoxMoneyHomeScreenState();
}

class _AskodoxMoneyHomeScreenState extends ConsumerState<AskodoxMoneyHomeScreen> {
  final _pager = PageController();
  int _page = 0;
  bool _editing = false;

  /// Saved screens: the Buyer one, and the Seller one per shop (null = the shipped screen).
  AskodoxLaunchLayout? _buyer;
  final Map<String, AskodoxLaunchLayout?> _shops = {};
  final Set<String> _loadingShops = {};
  Timer? _edge;

  List<AskodoxJson> _events = const [];
  AskodoxMyPhoneAlerts? _mine;

  /// The folder open over the screen (its id), and whether a page is being dragged out of it (the folder then fades so
  /// the screen under it takes the page).
  String? _folderOpen;
  bool _folderLeaving = false;
  final _panelKey = GlobalKey();

  /// What is on screen now (the menus act on it after the person chooses).
  AskodoxLaunchLayout _current = const AskodoxLaunchLayout([]);

  /// The pages on the screen now (for the "put in a folder" list).
  List<AskodoxLaunchPage> _pagesNow = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _edge?.cancel();
    _pager.dispose();
    super.dispose();
  }

  bool get _side => widget.section == 'side';

  /// The page search on the కొను / అమ్ము page (owner 2026-11-23): finds a page of either section of this side.
  String _query = '';

  Future<void> _load() async {
    final buyer = await askodoxLoadMoneyLayout(false, side: _side);
    List<AskodoxJson> events = const [];
    AskodoxMyPhoneAlerts? mine;
    try {
      events = await ref.read(askodoxPaymentAlertsBridgeProvider).localEvents();
    } catch (_) {}
    try {
      mine = await AskodoxMyPhoneAlerts.load();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _buyer = buyer;
      _events = events;
      _mine = mine;
    });
  }

  void _loadShop(String id) {
    if (_shops.containsKey(id) || _loadingShops.contains(id)) return;
    _loadingShops.add(id);
    unawaited(askodoxLoadMoneyLayout(true, shop: id, side: _side).then((l) {
      _loadingShops.remove(id);
      if (mounted) setState(() => _shops[id] = l);
    }));
  }

  AskodoxLaunchLayout _layoutFor(String? shop, List<String> available) {
    final saved = shop == null ? _buyer : _shops[shop];
    final shipped = shop == null ? askodoxBuyerShippedLayout() : askodoxSellerShippedLayout();
    return (saved ?? shipped).withoutFolders(askodoxRetiredFolderIds).fitTo(available);
  }

  void _change(String? shop, AskodoxLaunchLayout? next) {
    setState(() {
      if (shop == null) {
        _buyer = next;
      } else {
        _shops[shop] = next;
      }
    });
    unawaited(askodoxSaveMoneyLayout(shop != null, next, shop: shop, side: _side));
  }

  // ------------------------------------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final seller = ref.watch(askodoxSellerModeProvider);
    if (!seller) {
      return _launcher(
        te: te,
        shop: null,
        color: _buyerColor,
        pages: askodoxPagesFor(askodoxBuyerPages, widget.section),
        allPages: askodoxBuyerPages,
        card: _side ? _buyerSideCard(te) : _buyerCard(te),
        canEdit: true,
        oneTouch: _side ? AskodoxBuyerOneTouch(signedIn: ref.watch(authSessionProvider).user != null) : null,
      );
    }
    final signedIn = ref.watch(authSessionProvider).user != null;
    if (!signedIn) return _signIn(te);
    final shops = ref.watch(askodoxMyShopsProvider);
    return shops.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _retry(te, () => ref.invalidate(askodoxMyShopsProvider)),
      data: (list) {
        if (list.isEmpty) {
          return AskodoxShopSetupCard(onCreated: (id) async {
            await ref.read(askodoxMoneyShopProvider.notifier).choose(id);
            ref.invalidate(askodoxMyShopsProvider);
          });
        }
        final shop = askodoxPickShop(list, ref.watch(askodoxMoneyShopProvider))!;
        final id = '${shop['id']}';
        _loadShop(id);
        final hub = ref.watch(askodoxBizHubProvider(id));
        final business = hub.valueOrNull?.$1 ?? shop;
        final all = askodoxSellerPages(id, business);
        return _launcher(
          te: te,
          shop: id,
          color: _sellerColor,
          pages: askodoxPagesFor(all, widget.section),
          allPages: all,
          card: _sellerCard(te, list, shop, hub.valueOrNull?.$2),
          // A staff member's pages are known once the shop answers: arranging before that could lose hidden ones.
          canEdit: hub.hasValue && _shops.containsKey(id),
          oneTouch: _side
              ? AskodoxSellerOneTouch(
                  key: ValueKey('askodoxSellerOneTouch-$id'),
                  shop: {...business, 'role': shop['role'], 'status': business['status'] ?? shop['status']})
              : null,
        );
      },
    );
  }

  Widget _signIn(bool te) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.storefront_rounded, size: 48, color: _sellerColor),
            const SizedBox(height: 10),
            Text(te ? 'షాప్ డబ్బు చూడటానికి సైన్ ఇన్ చేయండి' : 'Sign in to see your shop money',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('askodoxMoneyHomeSignIn'),
              style: FilledButton.styleFrom(backgroundColor: _sellerColor),
              onPressed: () => context.push('/onboarding?signin=1'),
              child: Text(te ? 'సైన్ ఇన్' : 'Sign in'),
            ),
          ]),
        ),
      );

  Widget _retry(bool te, VoidCallback onRetry) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(te ? 'షాప్ వివరాలు రాలేదు. ఇంటర్నెట్ చూసి మళ్ళీ ప్రయత్నించండి.' : 'Could not load your shops. Check the internet and try again.',
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: Text(te ? 'మళ్ళీ' : 'Try again')),
        ]),
      );

  // ------------------------------------------------------------------------------------------------ the cards

  /// Buyer: this month's money on this phone + the latest two; tap = the full history (own money only).
  Widget _buyerCard(bool te) {
    final m = _mine;
    final items = askodoxItemsFromPhone(_events, m?.places ?? const [], m?.assigned ?? const {}, m?.links ?? const {})
      ..sort((a, b) => b.at.compareTo(a.at));
    final now = DateTime.now();
    final totals = askodoxTotals(items, DateTime(now.year, now.month), DateTime(now.year, now.month + 1),
        rowCategory: m?.rowCategory ?? const {}, payeeCategory: m?.payeeCategory ?? const {});
    final latest = items.where((i) => i.kind == 'payment').take(2).toList();
    return _card(
      key: const Key('askodoxMoneyHomeCard'),
      color: _buyerColor,
      onTap: () => context.push('/money?owner=me&lock=1'),
      title: te ? 'నా డబ్బు · ఈ నెల' : 'My money · this month',
      numbers: [
        (te ? 'వచ్చింది' : 'In', askodoxPaise(totals.inPaise), const Color(0xFF66CA82)),
        (te ? 'పోయింది' : 'Out', askodoxPaise(totals.outPaise), const Color(0xFFFF9C8D)),
      ],
      lines: [
        for (final i in latest)
          (i.title.isEmpty ? (te ? 'పేమెంట్' : 'Payment') : i.title, '${i.direction == 'in' ? '+' : '−'}${askodoxPaise(i.amountPaise)}',
              i.direction == 'in' ? const Color(0xFF66CA82) : const Color(0xFFFF9C8D)),
        if (latest.isEmpty)
          (m?.enabled == true
              ? (te ? 'ఇంకా పేమెంట్లు రాలేదు' : 'No payments yet')
              : (te ? 'పేమెంట్ వాయిస్ ఆన్ చేస్తే ఇక్కడ కనిపిస్తాయి' : 'Turn on Payment voice to see them here'), '', const Color(0xFFB4BED1)),
      ],
    );
  }

  /// Buyer page (కొను): what the person buys -- orders, shops they follow, shop updates (money stays in Money).
  Widget _buyerSideCard(bool te) => _card(
        key: const Key('askodoxBuyPageCard'),
        color: _buyerColor,
        onTap: () => context.push('/updates'),
        title: te ? 'కొను — నా ఆర్డర్లు, షాప్‌లు' : 'Buy — my orders and shops',
        numbers: const [],
        lines: [
          (te ? 'ఆర్డర్ల స్థితి, ఫాలో చేసే షాప్‌లు, వాటి అప్‌డేట్స్ — అన్నీ ఇక్కడ.' : 'Order status, shops you follow and their updates — all here.',
              '', const Color(0xFFB4BED1)),
          (te ? 'డబ్బు, బిల్లులు, ఖాతాలు కింద "మనీ" లో.' : 'Money, bills and accounts are under "Money".', '', const Color(0xFFB4BED1)),
        ],
      );

  /// Seller: the shop in view (chooser), today's sales / dues / new orders; tap = the shop's full money history.
  Widget _sellerCard(bool te, List<AskodoxJson> shops, AskodoxJson shop, AskodoxJson? hub) {
    final id = '${shop['id']}';
    final staff = '${shop['role']}' != 'owner';
    final owned = [for (final s in shops) if ('${s['role']}' == 'owner') s];
    final working = [for (final s in shops) if ('${s['role']}' != 'owner') s];
    PopupMenuItem<String> shopItem(AskodoxJson s) => PopupMenuItem(
        value: '${s['id']}',
        key: ValueKey('askodoxMoneyShop-${s['id']}'),
        child: Text('${s['name'] ?? ''}', style: TextStyle(fontWeight: '${s['id']}' == id ? FontWeight.w900 : FontWeight.w500)));
    PopupMenuItem<String> heading(String text) => PopupMenuItem(
        enabled: false,
        height: 30,
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFB4BED1))));
    return _card(
      key: Key(_side ? 'askodoxShopPageCard' : 'askodoxMoneyHomeCard'),
      color: _sellerColor,
      onTap: () => context.push(_side ? askodoxBizRoute(id, 'orders.incoming') : '/money?owner=$id&lock=1'),
      // Owner 2026-11-22: one person can own a shop AND work in another -- each shows that person's side of it.
      title: '${shop['name'] ?? ''}${staff ? (te ? ' · నేను ఇక్కడ సిబ్బంది' : ' · I work here') : ''}',
      trailing: PopupMenuButton<String>(
        key: const Key('askodoxMoneyShopChooser'),
        tooltip: te ? 'షాప్ మార్చు' : 'Change shop',
        icon: const Icon(Icons.swap_horiz_rounded, color: AskodoxLook.sheet),
        onSelected: (v) {
          if (v == '__add__') {
            context.push('/me/business');
          } else {
            setState(() => _page = 0);
            if (_pager.hasClients) _pager.jumpToPage(0);
            unawaited(ref.read(askodoxMoneyShopProvider.notifier).choose(v));
          }
        },
        itemBuilder: (_) => [
          if (owned.isNotEmpty) heading(te ? 'నా బిజినెస్‌లు' : 'My businesses'),
          for (final s in owned) shopItem(s),
          if (working.isNotEmpty) heading(te ? 'నేను పనిచేసే చోట్లు' : 'Where I work'),
          for (final s in working) shopItem(s),
          PopupMenuItem(value: '__add__', child: Text(te ? '+ కొత్త షాప్' : '+ Add a shop')),
        ],
      ),
      numbers: _side
          ? [
              (te ? 'కొత్త ఆర్డర్లు' : 'New orders', hub == null ? '…' : '${askodoxPosInt(askodoxPosMap(hub['orders'])['new'])}',
                  const Color(0xFFAFC8FC)),
            ]
          : [
        (te ? 'ఈ రోజు అమ్మకం' : 'Today', hub == null ? '…' : askodoxPaise(askodoxPosInt(askodoxPosMap(hub['sales'])['paise'])),
            const Color(0xFF66CA82)),
        (te ? 'బాకీ' : 'Dues', hub == null ? '…' : askodoxPaise(askodoxPosInt(askodoxPosMap(hub['dues'])['paise'])),
            const Color(0xFFFB9E6A)),
        (te ? 'కొత్త ఆర్డర్లు' : 'New orders', hub == null ? '…' : '${askodoxPosInt(askodoxPosMap(hub['orders'])['new'])}',
            const Color(0xFFAFC8FC)),
      ],
      lines: _side
          ? [(te ? 'ఆర్డర్లు, ఐటమ్స్, సిబ్బంది, కస్టమర్లు, సెట్టింగ్స్' : 'Orders, items, staff, customers, settings', '',
              const Color(0xFFB4BED1))]
          : const [],
    );
  }

  static const _cardHeight = 150.0;

  Widget _card({
    required Key key,
    required Color color,
    required VoidCallback onTap,
    required String title,
    required List<(String, String, Color)> numbers,
    required List<(String, String, Color)> lines,
    Widget? trailing,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: SizedBox(
          height: _cardHeight - 16,
          child: Material(
            color: AskodoxLook.sheet,
            elevation: 1,
            shadowColor: const Color(0x22000000),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: key,
              onTap: _editing ? null : onTap,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  color: color,
                  padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Row(children: [
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AskodoxLook.sheet, fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
                    if (trailing != null) trailing else const Icon(Icons.chevron_right_rounded, color: AskodoxLook.sheet),
                  ]),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        for (final (label, value, c) in numbers)
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0xFFB4BED1))),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c)),
                              ),
                            ]),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      for (final (text, amount, c) in lines)
                        Row(children: [
                          Expanded(
                            child: Text(text,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: _ink)),
                          ),
                          if (amount.isNotEmpty)
                            Text(amount, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: c)),
                        ]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  // ------------------------------------------------------------------------------------------------ the screens

  static const _cols = 4;
  static const _tileHeight = 96.0;
  static const _dotsHeight = 26.0;

  Widget _launcher({
    required bool te,
    required String? shop,
    required Color color,
    required List<AskodoxLaunchPage> pages,
    required Widget card,
    required bool canEdit,
    List<AskodoxLaunchPage> allPages = const [],
    Widget? oneTouch,
  }) {
    if (_side && _query.trim().isNotEmpty) return _searchResults(te, shop, allPages, color);
    final byId = {for (final p in pages) p.id: p};
    final layout = _layoutFor(shop, [for (final p in pages) p.id]);
    _current = layout;
    _pagesNow = pages;
    // While arranging, the account card's place shows the arranging panel: nothing on the screen moves under the
    // finger (a moved grid would drop a page on the wrong neighbour).
    final editPanel = _editing ? _editBar(te, shop, layout, byId, color) : null;
    return Column(key: Key(_side ? 'askodoxSidePage' : 'askodoxMoneyHome'), children: [
      if (_side && !_editing) _searchBox(te),
      // ONE TOUCH (owner 2026-11-25): the side's everyday jobs on one strip, above the pages.
      if (_side && !_editing && oneTouch != null) oneTouch,
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final h = box.maxHeight.isFinite ? box.maxHeight : 600.0;
          final firstRows = math.max(1, ((h - _cardHeight - _dotsHeight) / _tileHeight).floor());
          final otherRows = math.max(1, ((h - _dotsHeight) / _tileHeight).floor());
          final firstSlots = firstRows * _cols;
          final slots = otherRows * _cols;
          final screens = askodoxLaunchScreens(layout.entries, firstSlots, slots);
          // While arranging, one empty screen more: a page can be moved to a screen of its own.
          final count = screens.length + (_editing ? 1 : 0);
          final page = _page.clamp(0, count - 1);
          return Stack(children: [
            Column(children: [
              Expanded(
                child: PageView.builder(
                  key: const Key('askodoxMoneyHomePages'),
                  controller: _pager,
                  itemCount: count,
                  onPageChanged: (p) => setState(() => _page = p),
                  itemBuilder: (context, i) {
                    final entries = i < screens.length ? screens[i] : const <AskodoxLaunchEntry>[];
                    final start = askodoxLaunchScreenStart(i, firstSlots, slots);
                    return _screen(te, shop, layout, byId, entries, start, i == 0 ? (editPanel ?? card) : null, canEdit);
                  },
                ),
              ),
              SizedBox(
                height: _dotsHeight,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < count; i++)
                    AnimatedContainer(
                      key: ValueKey('askodoxMoneyHomeDot-$i'),
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == page ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: i == page ? color : const Color(0xFF9498A2), borderRadius: BorderRadius.circular(4)),
                    ),
                ]),
              ),
            ]),
            // On the other screens "Done" floats (the panel lives on the first screen).
            if (_editing && page > 0)
              Positioned(
                right: 12,
                bottom: _dotsHeight + 6,
                child: FilledButton(
                  key: const Key('askodoxMoneyHomeDoneFloat'),
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: () => setState(() => _editing = false),
                  child: Text(te ? 'పూర్తి' : 'Done'),
                ),
              ),
            // An open folder sits over the screen (like a phone): its pages can be opened, moved inside it, or dragged
            // out onto the screen.
            if (_folderOpen != null) _folderPanel(te, shop, layout, byId, canEdit),
            // Drag a page to the screen's edge: the next / earlier screen comes (like a phone).
            if (_editing) ...[
              Positioned(left: 0, top: 0, bottom: _dotsHeight, width: 22, child: _edgeTarget(-1, count)),
              Positioned(right: 0, top: 0, bottom: _dotsHeight, width: 22, child: _edgeTarget(1, count)),
            ],
          ]);
        }),
      ),
    ]);
  }

  /// "Which page? Search here" (owner 2026-11-23 design): any page of this side, in Money or here.
  Widget _searchBox(bool te) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: TextField(
          key: const Key('askodoxSidePageSearch'),
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: te ? 'ఏ పేజీ కావాలి? ఇక్కడ వెతకండి' : 'Which page? Search here',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  Widget _searchResults(bool te, String? shop, List<AskodoxLaunchPage> all, Color color) {
    final q = _query.trim().toLowerCase();
    final hits = [
      for (final p in all)
        if (p.en.toLowerCase().contains(q) || p.te.contains(q)) p,
    ];
    return Column(key: const Key('askodoxSidePage'), children: [
      _searchBox(te),
      Expanded(
        child: hits.isEmpty
            ? Center(child: Text(te ? 'ఆ పేరుతో పేజీ లేదు' : 'No page by that name'))
            : ListView(children: [
                for (final p in hits)
                  ListTile(
                    key: ValueKey('askodoxSidePageHit-${p.id}'),
                    leading: CircleAvatar(backgroundColor: p.color, child: Icon(p.icon, color: AskodoxLook.sheet, size: 20)),
                    title: Text(te ? p.te : p.en),
                    subtitle: Text(askodoxMoneySectionIds.contains(p.id) ? (te ? 'మనీ లో' : 'in Money') : (te ? 'ఈ పేజీలో' : 'on this page')),
                    onTap: () => _open(p, shop),
                  ),
              ]),
      ),
    ]);
  }

  Widget _edgeTarget(int step, int count) => DragTarget<String>(
        onWillAcceptWithDetails: (_) {
          _edge?.cancel();
          _edge = Timer(const Duration(milliseconds: 550), () {
            final next = (_page + step).clamp(0, count - 1);
            if (next != _page && _pager.hasClients) {
              _pager.animateToPage(next, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
            }
          });
          return false;
        },
        onLeave: (_) => _edge?.cancel(),
        builder: (context, _, __) => const SizedBox.expand(),
      );

  Widget _screen(bool te, String? shop, AskodoxLaunchLayout layout, Map<String, AskodoxLaunchPage> byId,
      List<AskodoxLaunchEntry> entries, int start, Widget? card, bool canEdit) {
    final grid = GridView(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _cols, mainAxisExtent: _tileHeight),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final e in entries) _tile(te, shop, layout, byId, e, canEdit),
      ],
    );
    // Dropping on the empty part of a screen puts the page at the end of that screen.
    final body = DragTarget<String>(
      // Not over the page's own (now empty) place on the screen: a press-and-release never moves it. A page from a
      // folder may land anywhere.
      onWillAcceptWithDetails: (d) =>
          _editing && (layout.folderOf(d.data) != null || !(_tileBoxes[d.data]?.contains(d.offset) ?? false)),
      onAcceptWithDetails: (d) {
        final base = _loosen(layout, d.data);
        final from = base.indexOf(d.data);
        var to = start + entries.length;
        if (from >= 0 && from < to) to -= 1;
        _change(shop, base.move(d.data, to));
      },
      builder: (context, _, __) => grid,
    );
    return Column(children: [
      if (card != null) card,
      Expanded(child: body),
    ]);
  }

  // ------------------------------------------------------------------------------------------------ tiles

  /// A page dragged out of a folder becomes a page on the screen first (where its folder was).
  AskodoxLaunchLayout _loosen(AskodoxLaunchLayout l, String id) => l.folderOf(id) != null ? l.takeOut(id) : l;

  Widget _tile(bool te, String? shop, AskodoxLaunchLayout layout, Map<String, AskodoxLaunchPage> byId, AskodoxLaunchEntry e,
      bool canEdit) {
    final face = _face(te, byId, e);
    final keyName = e.isFolder ? null : byId[e.page]?.keyName;
    final tile = InkWell(
      key: ValueKey('askodoxMoneyTile-${e.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (e.isFolder) {
          setState(() => _folderOpen = e.folder);
        } else {
          _open(byId[e.page]!, shop);
        }
      },
      child: keyName == null ? face : KeyedSubtree(key: ValueKey(keyName), child: face),
    );
    final target = DragTarget<String>(
      onWillAcceptWithDetails: (d) => _editing && d.data != e.id,
      onAcceptWithDetails: (d) => _dropOnTile(te, shop, layout, e, d),
      builder: (context, candidates, _) => _Measured(
        id: e.id,
        boxes: _tileBoxes,
        child: AnimatedScale(
          scale: candidates.isNotEmpty ? 1.12 : 1,
          duration: const Duration(milliseconds: 120),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: tile),
            if (_editing && !e.isFolder) _hideBadge(shop, layout, e.page!),
          ]),
        ),
      ),
    );
    if (!canEdit) return target;
    return _lift(
      id: e.id,
      face: face,
      child: target,
      onMenu: () {
        if (e.isFolder) {
          unawaited(_folderMenu(te, shop, e));
        } else {
          unawaited(_pageMenu(te, shop, byId[e.page]!));
        }
      },
    );
  }

  Widget _hideBadge(String? shop, AskodoxLaunchLayout layout, String page) => Positioned(
        top: 0,
        right: 6,
        child: GestureDetector(
          key: ValueKey('askodoxMoneyTileHide-$page'),
          onTap: () => _change(shop, layout.hide(page)),
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(color: Color(0xFFB4BED1), shape: BoxShape.circle),
            child: const Icon(Icons.remove_rounded, size: 16, color: AskodoxLook.sheet),
          ),
        ),
      );

  void _dropOnTile(bool te, String? shop, AskodoxLaunchLayout layout, AskodoxLaunchEntry e, DragTargetDetails<String> d) {
    // Back onto its own folder: it stays inside.
    if (e.isFolder && e.children.contains(d.data)) return;
    // Owner 2026-11-23: a page dropped on another page takes THAT place (the rest shift) -- it never becomes a group.
    // Folders are made only from the page's menu. Only a folder the person already made takes a page dropped on its
    // middle; its left / right quarter = beside it.
    var zone = 'middle';
    final r = _tileBoxes[e.id];
    if (r != null) {
      final x = d.offset.dx - r.left;
      if (x < r.width * .25) zone = 'before';
      if (x > r.width * .75) zone = 'after';
    }
    final base = _loosen(layout, d.data);
    final dragged = base.entry(d.data);
    if (dragged == null || base.entry(e.id) == null) {
      _change(shop, base);
      return;
    }
    if (!e.isFolder || dragged.isFolder) {
      _change(shop, base.placeAt(d.data, e.id));
      return;
    }
    if (zone == 'middle') {
      _change(shop, base.combine(d.data, e.id, newFolderId: e.folder!, name: e.name));
      return;
    }
    final from = base.indexOf(d.data);
    var to = base.indexOf(e.id) + (zone == 'after' ? 1 : 0);
    if (from < to) to -= 1;
    _change(shop, base.move(d.data, to));
  }

  /// Press and hold lifts a page / folder. Moving it = arranging; letting go where it was = its menu.
  Widget _lift({
    required String id,
    required Widget face,
    required Widget child,
    required VoidCallback onMenu,
    bool inFolder = false,
  }) =>
      LongPressDraggable<String>(
        data: id,
        delay: _editing ? const Duration(milliseconds: 150) : const Duration(milliseconds: 450),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: () => unawaited(HapticFeedback.mediumImpact().catchError((Object _) {})),
        onDragUpdate: (d) {
          final home = _tileBoxes[id];
          final away = home == null || !home.inflate(10).contains(d.globalPosition);
          if (away && !_editing) setState(() => _editing = true);
          if (inFolder && away && !_folderLeaving) {
            final panel = _panelRect();
            if (panel == null || !panel.contains(d.globalPosition)) setState(() => _folderLeaving = true);
          }
        },
        onDraggableCanceled: (_, offset) {
          final home = _tileBoxes[id];
          final stayed = home != null && home.inflate(10).contains(offset);
          final wasEditing = _editing;
          _endDrag();
          if (stayed && !wasEditing) onMenu();
        },
        onDragCompleted: _endDrag,
        feedback: Transform.translate(
          offset: const Offset(-36, -40),
          child: Material(color: Colors.transparent, child: SizedBox(width: 78, height: _tileHeight, child: face)),
        ),
        childWhenDragging: Opacity(opacity: .3, child: face),
        child: child,
      );

  void _endDrag() {
    _edge?.cancel();
    if (!mounted || !_folderLeaving) return;
    setState(() {
      _folderOpen = null;
      _folderLeaving = false;
    });
  }

  Rect? _panelRect() {
    final box = _panelKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Each tile's place on the screen (for "beside it" vs "on it" drops).
  final Map<String, Rect> _tileBoxes = {};

  Widget _pageFace(bool te, AskodoxLaunchPage p, {double size = 56}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: p.color, borderRadius: BorderRadius.circular(size * .29)),
            child: Icon(p.icon, color: AskodoxLook.sheet, size: size / 2),
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(p.label(te),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, height: 1.15, fontWeight: FontWeight.w700, color: _ink)),
          ),
        ]),
      );

  Widget _face(bool te, Map<String, AskodoxLaunchPage> byId, AskodoxLaunchEntry e) {
    if (!e.isFolder) return _pageFace(te, byId[e.page]!);
    final label = e.name.isEmpty ? askodoxLaunchFolderName(e.folder!, te) : e.name;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(children: [
        Container(
          width: 56,
          height: 56,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: const Color(0xFF4A526B), borderRadius: BorderRadius.circular(16)),
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              for (final c in e.children.take(4))
                if (byId[c] != null)
                  Container(
                    decoration: BoxDecoration(color: byId[c]!.color, borderRadius: BorderRadius.circular(5)),
                    child: Icon(byId[c]!.icon, size: 12, color: AskodoxLook.sheet),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, height: 1.15, fontWeight: FontWeight.w700, color: _ink)),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------------------------------------ an open folder

  Widget _folderPanel(bool te, String? shop, AskodoxLaunchLayout layout, Map<String, AskodoxLaunchPage> byId, bool canEdit) {
    final f = layout.entry('f:$_folderOpen');
    if (f == null) {
      // Its last pages went out: the folder is gone.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _folderOpen != null && !_folderLeaving) setState(() => _folderOpen = null);
      });
      return const SizedBox.shrink();
    }
    final name = f.name.isEmpty ? askodoxLaunchFolderName(f.folder!, te) : f.name;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: _folderLeaving,
        child: AnimatedOpacity(
          opacity: _folderLeaving ? 0 : 1,
          duration: const Duration(milliseconds: 150),
          child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                key: const Key('askodoxMoneyFolderClose'),
                onTap: () => setState(() => _folderOpen = null),
                child: const ColoredBox(color: Color(0x66000000)),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Material(
                  key: _panelKey,
                  color: AskodoxLook.sheet,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                    child: Column(key: ValueKey('askodoxMoneyFolder-${f.folder}'), mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        const SizedBox(width: 40),
                        Expanded(
                          child: Text(name,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: _ink)),
                        ),
                        IconButton(
                          key: const Key('askodoxMoneyFolderRename'),
                          tooltip: te ? 'పేరు మార్చు' : 'Rename',
                          icon: const Icon(Icons.edit_rounded, size: 20),
                          onPressed: () => _rename(te, shop, f),
                        ),
                      ]),
                      Text(
                          te
                              ? 'పట్టుకుని బయటకు లాగితే పేజీ స్క్రీన్ మీదకు వస్తుంది; లోపలే లాగితే వరుస మారుతుంది.'
                              : 'Hold and drag a page out to put it on the screen; inside the folder to change its place.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFFB4BED1))),
                      const SizedBox(height: 6),
                      GridView(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _cols, mainAxisExtent: _tileHeight),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (final (i, c) in f.children.indexed)
                            if (byId[c] != null) _folderTile(te, shop, layout, byId[c]!, f, i, canEdit),
                        ],
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _folderTile(bool te, String? shop, AskodoxLaunchLayout layout, AskodoxLaunchPage p, AskodoxLaunchEntry f, int index,
      bool canEdit) {
    final face = _pageFace(te, p);
    final tile = InkWell(
      key: ValueKey('askodoxMoneyFolderPage-${p.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (_editing) return;
        setState(() => _folderOpen = null);
        _open(p, shop);
      },
      child: p.keyName == null ? face : KeyedSubtree(key: ValueKey(p.keyName), child: face),
    );
    final target = DragTarget<String>(
      // Another page of this folder = a new place inside it; a page from the screen = into this folder here.
      onWillAcceptWithDetails: (d) => d.data != p.id && !d.data.startsWith('f:'),
      onAcceptWithDetails: (d) => _change(shop, layout.moveInFolder(f.folder!, d.data, index)),
      builder: (context, candidates, _) => _Measured(
        id: p.id,
        boxes: _tileBoxes,
        child: AnimatedScale(
          scale: candidates.isNotEmpty ? 1.1 : 1,
          duration: const Duration(milliseconds: 120),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: tile),
            if (_editing) _hideBadge(shop, layout, p.id),
          ]),
        ),
      ),
    );
    if (!canEdit) return target;
    return _lift(id: p.id, face: face, child: target, inFolder: true, onMenu: () => unawaited(_pageMenu(te, shop, p)));
  }

  // ------------------------------------------------------------------------------------------------ menus

  Future<String?> _menu(Rect? at, List<(String, IconData, String)> items) {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final rect = at ?? Rect.fromCenter(center: overlay.size.center(Offset.zero), width: 1, height: 1);
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        for (final (id, icon, text) in items)
          PopupMenuItem(
            value: id,
            key: ValueKey('askodoxMoneyMenu-$id'),
            child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 10), Flexible(child: Text(text))]),
          ),
      ],
    );
  }

  /// A page's own menu: put it above the Home chat (one of the same five shortcuts for everyone), move, take it out of
  /// its folder, hide.
  Future<void> _pageMenu(bool te, String? shop, AskodoxLaunchPage page) async {
    final pinId = 'money:${shop ?? 'me'}:${page.id}';
    final mine = AskodoxChatPin(id: pinId, route: page.pinRoute(shop), en: page.en, te: page.te);
    final pinned = ref.read(askodoxChatPinsProvider).pins.any((p) => p.samePageAs(mine));
    final inFolder = _current.folderOf(page.id) != null;
    final choice = await _menu(_tileBoxes[page.id], [
      ('pin', Icons.push_pin_rounded,
          pinned ? (te ? 'హోమ్ చాట్ షార్ట్‌కట్ (మార్చు / తీసేయి)' : 'Home chat shortcut (move / remove)') : (te ? 'హోమ్ చాట్ పైన పెట్టు' : 'Put above the Home chat')),
      ('arrange', Icons.open_with_rounded, te ? 'జరుపు' : 'Move'),
      if (!inFolder) ('folder', Icons.create_new_folder_rounded, te ? 'ఫోల్డర్‌లో పెట్టు' : 'Put in a folder'),
      if (inFolder) ('out', Icons.north_east_rounded, te ? 'ఫోల్డర్ నుంచి బయటకు' : 'Take out of the folder'),
      ('hide', Icons.visibility_off_outlined, te ? 'దాచు' : 'Hide'),
    ]);
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'pin':
        await askodoxOfferChatPin(context, mine);
      case 'arrange':
        setState(() => _editing = true);
      case 'folder':
        await _folderSheet(te, shop, page);
      case 'out':
        _change(shop, _current.takeOut(page.id));
      case 'hide':
        _change(shop, _current.hide(page.id));
    }
  }

  /// Folders are the person's own choice, made here (never by a drop): into a folder they already have, or a new one
  /// with another page.
  Future<void> _folderSheet(bool te, String? shop, AskodoxLaunchPage page) async {
    final byId = {for (final p in _pagesNow) p.id: p};
    final layout = _current;
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Text(te ? '"${page.label(te)}" ని దేనితో కలిపి ఫోల్డర్ చేయాలి?' : 'Put "${page.label(te)}" in a folder with…',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 6),
          for (final e in layout.entries)
            if (e.isFolder)
              ListTile(
                key: ValueKey('askodoxMoneyFolderPick-${e.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_rounded),
                title: Text(e.name.isEmpty ? askodoxLaunchFolderName(e.folder!, te) : e.name),
                onTap: () => Navigator.pop(sheet, e.id),
              )
            else if (e.page != page.id && byId[e.page] != null)
              ListTile(
                key: ValueKey('askodoxMoneyFolderPick-${e.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: byId[e.page]!.color, borderRadius: BorderRadius.circular(10)),
                  child: Icon(byId[e.page]!.icon, color: AskodoxLook.sheet, size: 20),
                ),
                title: Text(byId[e.page]!.label(te)),
                onTap: () => Navigator.pop(sheet, e.id),
              ),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    final now = _current;
    if (pick.startsWith('f:')) {
      _change(shop, now.addToFolder(pick.substring(2), page.id));
    } else {
      _change(
        shop,
        now.combine(page.id, pick,
            newFolderId: 'u${DateTime.now().microsecondsSinceEpoch}', name: te ? 'కొత్త ఫోల్డర్' : 'New folder'),
      );
    }
  }

  Future<void> _folderMenu(bool te, String? shop, AskodoxLaunchEntry f) async {
    final choice = await _menu(_tileBoxes[f.id], [
      ('open', Icons.folder_open_rounded, te ? 'తెరువు' : 'Open'),
      ('rename', Icons.edit_rounded, te ? 'పేరు మార్చు' : 'Rename'),
      ('ungroup', Icons.unfold_more_rounded, te ? 'ఫోల్డర్ విడదీయి (పేజీలు బయటకు)' : 'Ungroup (pages back out)'),
      ('arrange', Icons.open_with_rounded, te ? 'జరుపు' : 'Move'),
    ]);
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'open':
        setState(() => _folderOpen = f.folder);
      case 'rename':
        await _rename(te, shop, f);
      case 'ungroup':
        _change(shop, _current.ungroup(f.folder!));
      case 'arrange':
        setState(() => _editing = true);
    }
  }

  Future<void> _rename(bool te, String? shop, AskodoxLaunchEntry f) async {
    final box = TextEditingController(text: f.name.isEmpty ? askodoxLaunchFolderName(f.folder!, te) : f.name);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? 'ఫోల్డర్ పేరు' : 'Folder name'),
        content: TextField(
          key: const Key('askodoxMoneyFolderName'),
          controller: box,
          autofocus: true,
          maxLength: 30,
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
            key: const Key('askodoxMoneyFolderNameSave'),
            onPressed: () => Navigator.pop(d, box.text),
            child: Text(te ? 'సేవ్' : 'Save'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    _change(shop, _current.rename(f.folder!, name));
  }

  // ------------------------------------------------------------------------------------------------ opening

  void _open(AskodoxLaunchPage page, String? shop) {
    if (_editing) return;
    if (page.action == 'voice') {
      unawaited(askodoxOpenPaymentVoice(context, businessId: shop));
      return;
    }
    final route = page.route;
    if (route == null) return;
    // A bottom-bar tab is switched to, never stacked on top.
    if (route == '/updates' || route == '/profile') {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  // ------------------------------------------------------------------------------------------------ arranging

  Widget _editBar(bool te, String? shop, AskodoxLaunchLayout layout, Map<String, AskodoxLaunchPage> byId, Color color) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: SizedBox(
          height: _cardHeight - 16,
          child: Container(
        key: const Key('askodoxMoneyHomeEditBar'),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(te ? 'సర్దుతున్నారు' : 'Arranging',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 15)),
            ),
            FilledButton(
              key: const Key('askodoxMoneyHomeDone'),
              style: FilledButton.styleFrom(backgroundColor: color, visualDensity: VisualDensity.compact),
              onPressed: () => setState(() => _editing = false),
              child: Text(te ? 'పూర్తి' : 'Done'),
            ),
          ]),
          // A narrow phone wraps these instead of squeezing the title.
          Wrap(spacing: 4, children: [
            TextButton(
              key: const Key('askodoxMoneyHomeHidden'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: layout.hidden.isEmpty ? null : () => _hiddenSheet(te, shop, byId),
              child: Text(te ? 'దాచినవి (${layout.hidden.length})' : 'Hidden (${layout.hidden.length})'),
            ),
            TextButton(
              key: const Key('askodoxMoneyHomeReset'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    content: Text(te ? 'మొదట ఉన్నట్టు పెట్టాలా? మీ ఫోల్డర్లు, వరుస పోతాయి.' : 'Put the screen back as it came? Your folders and order go.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: Text(te ? 'వద్దు' : 'No')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(te ? 'అవును' : 'Yes')),
                    ],
                  ),
                );
                if (ok == true) _change(shop, null);
              },
              child: Text(te ? 'మొదటిలా' : 'Reset'),
            ),
          ]),
          Text(
              te
                  ? 'పట్టుకుని లాగండి: ఎక్కడ వదిలితే అక్కడే ఉంటుంది, మిగతావి జరుగుతాయి. అంచుకి = తర్వాతి స్క్రీన్. ఫోల్డర్: నొక్కి పట్టి వదిలి "ఫోల్డర్‌లో పెట్టు". "−" = దాచు.'
                  : 'Hold and drag: it stays where you drop it, the others shift. Edge = next screen. Folder: press, hold, let go → "Put in a folder". "−" = hide.',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFB4BED1))),
        ])),
          ),
        ),
      );

  Future<void> _hiddenSheet(bool te, String? shop, Map<String, AskodoxLaunchPage> byId) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => StatefulBuilder(builder: (sheet, setSheet) {
          final layout = _layoutFor(shop, byId.keys.toList());
          return SafeArea(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
              Text(te ? 'దాచిన పేజీలు' : 'Hidden pages', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 6),
              if (layout.hidden.isEmpty) Text(te ? 'ఏమీ లేవు' : 'None'),
              for (final id in layout.hidden)
                if (byId[id] != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: byId[id]!.color, borderRadius: BorderRadius.circular(10)),
                      child: Icon(byId[id]!.icon, color: AskodoxLook.sheet, size: 20),
                    ),
                    title: Text(byId[id]!.label(te)),
                    trailing: TextButton(
                      key: ValueKey('askodoxMoneyRestore-$id'),
                      onPressed: () {
                        _change(shop, layout.restore(id));
                        setSheet(() {});
                      },
                      child: Text(te ? 'తిరిగి పెట్టు' : 'Bring back'),
                    ),
                  ),
            ]),
          );
        }),
      );
}

/// Measures where its tile sits on the screen.
class _Measured extends StatefulWidget {
  const _Measured({required this.id, required this.boxes, required this.child});
  final String id;
  final Map<String, Rect> boxes;
  final Widget child;

  @override
  State<_Measured> createState() => _MeasuredState();
}

class _MeasuredState extends State<_Measured> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        widget.boxes[widget.id] = box.localToGlobal(Offset.zero) & box.size;
      }
    });
    return widget.child;
  }
}
