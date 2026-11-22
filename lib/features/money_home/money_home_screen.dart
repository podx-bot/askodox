import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/backend_providers.dart';
import '../business/presentation/biz_hub.dart' show askodoxBizHubProvider;
import '../home/domain/shopping_mode.dart';
import '../pos/data/pos_payment_alerts.dart';
import '../pos/data/pos_repository.dart';
import '../pos/domain/money_ledger.dart';
import '../pos/domain/pos_money.dart' show askodoxPaise;
import '../pos/presentation/money_screens.dart' show AskodoxDuesScreen;
import 'launcher_layout.dart';
import 'money_home_pages.dart';
import 'money_home_store.dart';
import 'payment_voice_sheet.dart';
import 'shop_setup_card.dart';

const _buyerColor = Color(0xFF6C4DFF);
const _sellerColor = Color(0xFF0B7A4B);
const _ink = Color(0xFF16203F);

/// "Money" on the bottom bar, in BOTH sides (owner 2026-11-22):
/// - Buyer side = the person's own money: one card (this month in / out + the latest two) and their pages;
/// - Seller side = the shop's money: the shop in view (a chooser when they run / help in more than one), today's
///   numbers and that shop's own tools, only those the person's role allows. Never mixed with the personal account.
/// Pages sit like apps on a phone: icon + name, folders of 4-5, more screens when one is full. Press and hold to
/// arrange: drop a page on another = a folder, beside it = move there, to the screen's edge = the next screen; folders
/// can be renamed, pages hidden (never deleted) and brought back; "Reset" brings the shipped screen back.
class AskodoxMoneyHomeScreen extends ConsumerStatefulWidget {
  const AskodoxMoneyHomeScreen({super.key});

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

  Future<void> _load() async {
    final buyer = await askodoxLoadMoneyLayout(false);
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
    unawaited(askodoxLoadMoneyLayout(true, shop: id).then((l) {
      _loadingShops.remove(id);
      if (mounted) setState(() => _shops[id] = l);
    }));
  }

  AskodoxLaunchLayout _layoutFor(String? shop, List<String> available) {
    final saved = shop == null ? _buyer : _shops[shop];
    final shipped = shop == null ? askodoxBuyerShippedLayout() : askodoxSellerShippedLayout();
    return (saved ?? shipped).fitTo(available);
  }

  void _change(String? shop, AskodoxLaunchLayout? next) {
    setState(() {
      if (shop == null) {
        _buyer = next;
      } else {
        _shops[shop] = next;
      }
    });
    unawaited(askodoxSaveMoneyLayout(shop != null, next, shop: shop));
  }

  void _startEditing() {
    if (_editing) return;
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    setState(() => _editing = true);
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
        pages: askodoxBuyerPages,
        card: _buyerCard(te),
        canEdit: true,
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
        return _launcher(
          te: te,
          shop: id,
          color: _sellerColor,
          pages: askodoxSellerPages(id, business),
          card: _sellerCard(te, list, shop, hub.valueOrNull?.$2),
          // A staff member's pages are known once the shop answers: arranging before that could lose hidden ones.
          canEdit: hub.hasValue && _shops.containsKey(id),
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
        (te ? 'వచ్చింది' : 'In', askodoxPaise(totals.inPaise), const Color(0xFF12A150)),
        (te ? 'పోయింది' : 'Out', askodoxPaise(totals.outPaise), const Color(0xFFC4251A)),
      ],
      lines: [
        for (final i in latest)
          (i.title.isEmpty ? (te ? 'పేమెంట్' : 'Payment') : i.title, '${i.direction == 'in' ? '+' : '−'}${askodoxPaise(i.amountPaise)}',
              i.direction == 'in' ? const Color(0xFF12A150) : const Color(0xFFC4251A)),
        if (latest.isEmpty)
          (m?.enabled == true
              ? (te ? 'ఇంకా పేమెంట్లు రాలేదు' : 'No payments yet')
              : (te ? 'పేమెంట్ వాయిస్ ఆన్ చేస్తే ఇక్కడ కనిపిస్తాయి' : 'Turn on Payment voice to see them here'), '', const Color(0xFF5B6475)),
      ],
    );
  }

  /// Seller: the shop in view (chooser), today's sales / dues / new orders; tap = the shop's full money history.
  Widget _sellerCard(bool te, List<AskodoxJson> shops, AskodoxJson shop, AskodoxJson? hub) {
    final id = '${shop['id']}';
    final staff = '${shop['role']}' != 'owner';
    return _card(
      key: const Key('askodoxMoneyHomeCard'),
      color: _sellerColor,
      onTap: () => context.push('/money?owner=$id&lock=1'),
      title: '${shop['name'] ?? ''}${staff ? (te ? ' · సిబ్బంది' : ' · staff') : ''}',
      trailing: PopupMenuButton<String>(
        key: const Key('askodoxMoneyShopChooser'),
        tooltip: te ? 'షాప్ మార్చు' : 'Change shop',
        icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white),
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
          for (final s in shops)
            PopupMenuItem(
                value: '${s['id']}',
                key: ValueKey('askodoxMoneyShop-${s['id']}'),
                child: Text('${s['name'] ?? ''}', style: TextStyle(fontWeight: '${s['id']}' == id ? FontWeight.w900 : FontWeight.w500))),
          PopupMenuItem(value: '__add__', child: Text(te ? '+ కొత్త షాప్' : '+ Add a shop')),
        ],
      ),
      numbers: [
        (te ? 'ఈ రోజు అమ్మకం' : 'Today', hub == null ? '…' : askodoxPaise(askodoxPosInt(askodoxPosMap(hub['sales'])['paise'])),
            const Color(0xFF12A150)),
        (te ? 'బాకీ' : 'Dues', hub == null ? '…' : askodoxPaise(askodoxPosInt(askodoxPosMap(hub['dues'])['paise'])),
            const Color(0xFFB45309)),
        (te ? 'కొత్త ఆర్డర్లు' : 'New orders', hub == null ? '…' : '${askodoxPosInt(askodoxPosMap(hub['orders'])['new'])}',
            const Color(0xFF1E3FA0)),
      ],
      lines: const [],
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
            color: Colors.white,
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
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
                    if (trailing != null) trailing else const Icon(Icons.chevron_right_rounded, color: Colors.white),
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
                              Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B6475))),
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
  }) {
    final byId = {for (final p in pages) p.id: p};
    final layout = _layoutFor(shop, [for (final p in pages) p.id]);
    return Column(key: const Key('askodoxMoneyHome'), children: [
      if (_editing) _editBar(te, shop, layout, byId, color),
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
                    return _screen(te, shop, layout, byId, entries, start, i == 0 ? card : null, canEdit);
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
                          color: i == page ? color : const Color(0xFFC9CED8), borderRadius: BorderRadius.circular(4)),
                    ),
                ]),
              ),
            ]),
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
      // Not over the page's own (now empty) place: a press-and-release only starts arranging, it never moves the page.
      onWillAcceptWithDetails: (d) => _editing && !(_tileBoxes[d.data]?.contains(d.offset) ?? false),
      onAcceptWithDetails: (d) {
        final from = layout.indexOf(d.data);
        var to = start + entries.length;
        if (from >= 0 && from < to) to -= 1;
        _change(shop, layout.move(d.data, to));
      },
      builder: (context, _, __) => grid,
    );
    return Column(children: [
      if (card != null) card,
      Expanded(child: body),
    ]);
  }

  // ------------------------------------------------------------------------------------------------ tiles

  Widget _tile(bool te, String? shop, AskodoxLaunchLayout layout, Map<String, AskodoxLaunchPage> byId, AskodoxLaunchEntry e,
      bool canEdit) {
    final face = _face(te, byId, e);
    final keyName = e.isFolder ? null : byId[e.page]?.keyName;
    final tile = InkWell(
      key: ValueKey('askodoxMoneyTile-${e.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (e.isFolder) {
          unawaited(_openFolder(te, shop, e.folder!, byId));
        } else {
          _open(byId[e.page]!, shop);
        }
      },
      child: keyName == null ? face : KeyedSubtree(key: ValueKey(keyName), child: face),
    );
    final target = DragTarget<String>(
      onWillAcceptWithDetails: (d) => _editing && d.data != e.id,
      onAcceptWithDetails: (d) {
        // Where on the tile it was dropped: the left / right quarter = move beside it, the middle = a folder.
        var zone = 'middle';
        final r = _tileBoxes[e.id];
        if (r != null) {
          final x = d.offset.dx - r.left;
          if (x < r.width * .25) zone = 'before';
          if (x > r.width * .75) zone = 'after';
        }
        final dragged = layout.entry(d.data);
        if (dragged == null) return;
        if (zone == 'middle' && !dragged.isFolder) {
          final name = e.isFolder ? e.name : (te ? 'కొత్త ఫోల్డర్' : 'New folder');
          _change(shop, layout.combine(d.data, e.id, newFolderId: 'u${DateTime.now().microsecondsSinceEpoch}', name: name));
          return;
        }
        final from = layout.indexOf(d.data);
        var to = layout.indexOf(e.id) + (zone == 'after' ? 1 : 0);
        if (from < to) to -= 1;
        _change(shop, layout.move(d.data, to));
      },
      builder: (context, candidates, _) => _Measured(
        id: e.id,
        boxes: _tileBoxes,
        child: AnimatedScale(
          scale: candidates.isNotEmpty ? 1.12 : 1,
          duration: const Duration(milliseconds: 120),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: tile),
            if (_editing && !e.isFolder)
              Positioned(
                top: 0,
                right: 6,
                child: GestureDetector(
                  key: ValueKey('askodoxMoneyTileHide-${e.id}'),
                  onTap: () => _change(shop, layout.hide(e.page!)),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(color: Color(0xFF5B6475), shape: BoxShape.circle),
                    child: const Icon(Icons.remove_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
    if (!canEdit) return target;
    return LongPressDraggable<String>(
      data: e.id,
      delay: _editing ? const Duration(milliseconds: 150) : const Duration(milliseconds: 450),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: _startEditing,
      onDragEnd: (_) => _edge?.cancel(),
      feedback: Transform.translate(
        offset: const Offset(-36, -40),
        child: Material(color: Colors.transparent, child: SizedBox(width: 78, height: _tileHeight, child: _face(te, byId, e))),
      ),
      childWhenDragging: const SizedBox.shrink(),
      child: target,
    );
  }

  /// Each tile's place on the screen (for "beside it" vs "on it" drops).
  final Map<String, Rect> _tileBoxes = {};

  Widget _face(bool te, Map<String, AskodoxLaunchPage> byId, AskodoxLaunchEntry e) {
    final label = e.isFolder
        ? (e.name.isEmpty ? askodoxLaunchFolderName(e.folder!, te) : e.name)
        : byId[e.page]!.label(te);
    final icon = e.isFolder
        ? Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: const Color(0xFFE7EAF2), borderRadius: BorderRadius.circular(16)),
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
                      child: Icon(byId[c]!.icon, size: 12, color: Colors.white),
                    ),
              ],
            ),
          )
        : Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: byId[e.page]!.color, borderRadius: BorderRadius.circular(16)),
            child: Icon(byId[e.page]!.icon, color: Colors.white, size: 28),
          );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(children: [
        icon,
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

  // ------------------------------------------------------------------------------------------------ opening

  void _open(AskodoxLaunchPage page, String? shop) {
    if (_editing) return;
    switch (page.action) {
      case 'voice':
        unawaited(askodoxOpenPaymentVoice(context, businessId: shop));
        return;
      case 'dues':
        final m = _mine;
        final items = askodoxItemsFromPhone(_events, m?.places ?? const [], m?.assigned ?? const {}, m?.links ?? const {});
        unawaited(Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => AskodoxDuesScreen(phoneEvents: _events, items: items))));
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

  Future<void> _openFolder(bool te, String? shop, String folderId, Map<String, AskodoxLaunchPage> byId) async {
    final opened = await showModalBottomSheet<AskodoxLaunchPage>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FolderSheet(
        te: te,
        folderId: folderId,
        byId: byId,
        editing: _editing,
        layout: () {
          final pages = byId.keys.toList();
          return _layoutFor(shop, pages);
        },
        apply: (next) => _change(shop, next),
      ),
    );
    if (opened != null && mounted) _open(opened, shop);
  }

  // ------------------------------------------------------------------------------------------------ arranging

  Widget _editBar(bool te, String? shop, AskodoxLaunchLayout layout, Map<String, AskodoxLaunchPage> byId, Color color) =>
      Container(
        key: const Key('askodoxMoneyHomeEditBar'),
        color: color.withValues(alpha: 0.08),
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(te ? 'సర్దుతున్నారు' : 'Arranging',
                  style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 15)),
            ),
            TextButton(
              key: const Key('askodoxMoneyHomeHidden'),
              onPressed: layout.hidden.isEmpty ? null : () => _hiddenSheet(te, shop, byId),
              child: Text(te ? 'దాచినవి (${layout.hidden.length})' : 'Hidden (${layout.hidden.length})'),
            ),
            TextButton(
              key: const Key('askodoxMoneyHomeReset'),
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
            FilledButton(
              key: const Key('askodoxMoneyHomeDone'),
              style: FilledButton.styleFrom(backgroundColor: color, visualDensity: VisualDensity.compact),
              onPressed: () => setState(() => _editing = false),
              child: Text(te ? 'పూర్తి' : 'Done'),
            ),
          ]),
          Text(
              te
                  ? 'పట్టుకుని లాగండి: వేరే దాని మీద వదిలితే ఫోల్డర్, పక్కన వదిలితే అక్కడికి, అంచుకి లాగితే తర్వాతి స్క్రీన్. "−" = దాచు.'
                  : 'Hold and drag: drop on another = a folder, beside it = move there, to the edge = next screen. "−" = hide.',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B6475))),
        ]),
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
                      child: Icon(byId[id]!.icon, color: Colors.white, size: 20),
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

/// A folder opened: its pages (tap opens one). While arranging: rename it, take a page out, hide one, add one.
class _FolderSheet extends StatefulWidget {
  const _FolderSheet({
    required this.te,
    required this.folderId,
    required this.byId,
    required this.editing,
    required this.layout,
    required this.apply,
  });
  final bool te;
  final String folderId;
  final Map<String, AskodoxLaunchPage> byId;
  final bool editing;
  final AskodoxLaunchLayout Function() layout;
  final void Function(AskodoxLaunchLayout) apply;

  @override
  State<_FolderSheet> createState() => _FolderSheetState();
}

class _FolderSheetState extends State<_FolderSheet> {
  late final TextEditingController _name;

  AskodoxLaunchEntry? get _folder => widget.layout().entry('f:${widget.folderId}');

  @override
  void initState() {
    super.initState();
    final f = _folder;
    _name = TextEditingController(
        text: f == null ? '' : (f.name.isEmpty ? askodoxLaunchFolderName(widget.folderId, widget.te) : f.name));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _do(AskodoxLaunchLayout Function(AskodoxLaunchLayout) edit) {
    widget.apply(edit(widget.layout()));
    if (_folder == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final f = _folder;
    if (f == null) return const SizedBox(height: 40);
    final loose = [
      for (final e in widget.layout().entries)
        if (!e.isFolder && widget.byId[e.page] != null) widget.byId[e.page]!,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(key: ValueKey('askodoxMoneyFolder-${widget.folderId}'), mainAxisSize: MainAxisSize.min, children: [
          if (widget.editing)
            TextField(
              key: const Key('askodoxMoneyFolderName'),
              controller: _name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              decoration: InputDecoration(
                  hintText: te ? 'ఫోల్డర్ పేరు' : 'Folder name', suffixIcon: const Icon(Icons.edit_rounded, size: 18)),
              onSubmitted: (v) => _do((l) => l.rename(widget.folderId, v)),
              onChanged: (v) {
                if (v.trim().isNotEmpty) widget.apply(widget.layout().rename(widget.folderId, v));
              },
            )
          else
            Text(_name.text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 12),
          GridView(
            gridDelegate:
                SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: widget.editing ? 128 : 96),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final id in f.children)
                if (widget.byId[id] != null)
                  Column(children: [
                    InkWell(
                      key: ValueKey('askodoxMoneyFolderPage-$id'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: widget.editing ? null : () => Navigator.of(context).pop(widget.byId[id]),
                      child: Column(children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(color: widget.byId[id]!.color, borderRadius: BorderRadius.circular(15)),
                          child: Icon(widget.byId[id]!.icon, color: Colors.white, size: 26),
                        ),
                        const SizedBox(height: 4),
                        Text(widget.byId[id]!.label(te),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    if (widget.editing)
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton(
                          key: ValueKey('askodoxMoneyTakeOut-$id'),
                          tooltip: te ? 'బయటకు తీయి' : 'Take out',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.north_east_rounded, size: 18),
                          onPressed: () => _do((l) => l.takeOut(id)),
                        ),
                        IconButton(
                          key: ValueKey('askodoxMoneyFolderHide-$id'),
                          tooltip: te ? 'దాచు' : 'Hide',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.visibility_off_outlined, size: 18),
                          onPressed: () => _do((l) => l.hide(id)),
                        ),
                      ]),
                  ]),
            ],
          ),
          if (widget.editing && loose.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                key: const Key('askodoxMoneyFolderAdd'),
                onSelected: (id) => _do((l) => l.addToFolder(widget.folderId, id)),
                itemBuilder: (_) => [
                  for (final p in loose) PopupMenuItem(value: p.id, child: Text(p.label(te))),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(te ? '+ పేజీ చేర్చు' : '+ Add a page',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2B4BC0))),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
