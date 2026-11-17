import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/shop_rating_screens.dart' show askodoxRatingLine;
import '../application/chat_shop_cart.dart';

/// A shop's menu INSIDE the chat (owner 2026-11-16): tap + / − (or arrive with the order already prepared from the
/// person's own words), choose parcel / delivery / eat here, and send. Nothing is ordered until the person taps Send.
/// Parcel and eat-here are placed right here; delivery opens the order screen (address + map pin) with the cart filled.
class AskodoxChatShopMenuCard extends ConsumerStatefulWidget {
  const AskodoxChatShopMenuCard({super.key, required this.card, required this.te});

  /// Backend `shop_menu`: {business_id, name, code, open, message, modes, items, more, last_items, prepared}.
  final Map<String, Object?> card;
  final bool te;

  @override
  ConsumerState<AskodoxChatShopMenuCard> createState() => _AskodoxChatShopMenuCardState();
}

class _AskodoxChatShopMenuCardState extends ConsumerState<AskodoxChatShopMenuCard> {
  final _qty = <String, int>{};
  final _cardKey = GlobalKey();
  late String _kind;
  bool _busy = false;
  String? _orderId;
  String _txn = askodoxNewTxnId();
  String _group = '';
  String _food = ''; // '' all, 'veg', 'nonveg'
  bool _all = false;
  StateController<AskodoxChatShopCart?>? _cartSlot;
  AskodoxJson? _shop; // follow state + the shop's own links (best effort)
  bool _followBusy = false;

  List<AskodoxJson> get _items => askodoxPosList(widget.card['items']);
  List<String> get _modes => [for (final m in (widget.card['modes'] as List? ?? const [])) '$m'];
  String get _code => '${widget.card['code'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _kind = _modes.contains('dine_in') ? 'dine_in' : 'takeaway';
    _fill(askodoxPosList(widget.card['prepared']));
    _cartSlot = ref.read(askodoxChatShopCartProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
    _loadShop();
  }

  Future<void> _loadShop() async {
    final id = '${widget.card['business_id'] ?? ''}';
    if (id.isEmpty) return;
    try {
      final shop = await ref.read(askodoxPosRepositoryProvider).shopState(id);
      if (mounted) setState(() => _shop = shop);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    final shop = _shop;
    if (shop == null || _followBusy) return;
    final id = '${widget.card['business_id']}';
    final repo = ref.read(askodoxPosRepositoryProvider);
    setState(() => _followBusy = true);
    try {
      final updated = shop['following'] == true ? await repo.unfollowShop(id) : await repo.followShop(id);
      if (mounted) setState(() => _shop = updated);
    } on AskodoxPosException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message(widget.te))));
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  /// Follow on ASKODOX + the shop's own Instagram / Facebook / YouTube links (following THERE is the person's own tap).
  Widget _followRow(bool te) {
    final shop = _shop;
    final fields = askodoxPosMap(askodoxPosMap(shop?['profile'])['fields']);
    final links = [
      for (final s in const [('instagram', 'Instagram'), ('facebook', 'Facebook'), ('youtube', 'YouTube')])
        if ('${fields[s.$1] ?? ''}'.trim().isNotEmpty) (s.$1, s.$2, '${fields[s.$1]}'.trim()),
    ];
    final following = shop?['following'] == true;
    return Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (shop != null && shop['is_owner'] != true)
        FilledButton.tonalIcon(
          key: const Key('askodoxChatShopFollow'),
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: _followBusy ? null : _toggleFollow,
          icon: Icon(following ? Icons.check : Icons.add, size: 16),
          label: Text(following ? (te ? 'ఫాలో అవుతున్నారు' : 'Following') : (te ? 'ఫాలో' : 'Follow')),
        ),
      TextButton(
        key: const Key('askodoxChatShopPage'),
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: () => context.push('/shops/${widget.card['business_id']}'),
        child: Text(te ? 'షాప్ పేజీ ›' : 'Shop page ›'),
      ),
      for (final l in links)
        ActionChip(
          key: Key('askodoxChatShopSocial-${l.$1}'),
          visualDensity: VisualDensity.compact,
          label: Text('${l.$2} ↗', style: const TextStyle(fontSize: 12)),
          onPressed: () {
            final uri = Uri.tryParse(l.$3.startsWith('http') ? l.$3 : 'https://${l.$3}');
            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
          },
        ),
    ]);
  }

  @override
  void dispose() {
    final slot = _cartSlot;
    if (slot != null && slot.state?.owner == this) {
      Future.microtask(() {
        if (slot.state?.owner == this) slot.state = null;
      });
    }
    super.dispose();
  }

  /// The bar above the message box follows this card's cart (until it is sent).
  void _publish() {
    if (!mounted) return;
    final slot = _cartSlot!;
    if (widget.card['open'] != true || _orderId != null) {
      if (slot.state?.owner == this) slot.state = null;
      return;
    }
    slot.state = AskodoxChatShopCart(
      owner: this,
      shopName: '${widget.card['name'] ?? ''}',
      count: _qty.values.fold<int>(0, (a, b) => a + b),
      totalPaise: _total,
      kindLabel: _kindLabel(_kind),
      send: _send,
      hear: _hear,
      show: () {
        final ctx = _cardKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250));
      },
    );
  }

  /// A typed / spoken line from the chat box: the shop's receptionist reads it against THIS menu.
  Future<String?> _hear(String text) async {
    if (_orderId != null || widget.card['open'] != true) return null;
    try {
      final heard = await ref.read(askodoxPosRepositoryProvider).deskAssist(
          _code,
          text,
          [
            for (final e in _qty.entries)
              {'product_id': e.key, 'qty': e.value, 'price_paise': _priceOf(e.key)},
          ],
          te: widget.te);
      if (!askodoxHeardIsAboutMenu(heard)) return null;
      if (!mounted) return null;
      setState(() {
        final next = askodoxApplyHeard(_qty, heard);
        _qty
          ..clear()
          ..addAll(next);
        _txn = askodoxNewTxnId();
      });
      _publish();
      if (heard['confirm'] == true && _qty.isNotEmpty) await _send();
      return '${heard['reply'] ?? ''}'.trim().isEmpty ? null : '${heard['reply']}';
    } catch (_) {
      return null;
    }
  }

  int _priceOf(String id) {
    for (final m in _items) {
      if ('${m['id']}' == id) return askodoxPosInt(m['price_paise']);
    }
    return 0;
  }

  void _fill(List<AskodoxJson> lines) {
    final live = {for (final m in _items) if (m['available'] == true) '${m['id']}'};
    for (final line in lines) {
      final id = '${line['product_id']}';
      final qty = (line['qty'] is num) ? (line['qty'] as num).round() : 1;
      if (live.contains(id) && qty > 0) _qty[id] = qty;
    }
  }

  int get _total {
    var sum = 0;
    for (final m in _items) {
      sum += askodoxPosInt(m['price_paise']) * (_qty['${m['id']}'] ?? 0);
    }
    return sum;
  }

  String _rupees(int paise) => paise % 100 == 0 ? '₹${paise ~/ 100}' : '₹${(paise / 100).toStringAsFixed(2)}';

  String _kindLabel(String kind) => switch (kind) {
        'dine_in' => widget.te ? 'ఇక్కడ తింటాను' : 'Eat here',
        'delivery' => widget.te ? 'డెలివరీ' : 'Delivery',
        _ => widget.te ? 'పార్సిల్' : 'Parcel',
      };

  void _change(String id, int by) {
    setState(() {
      final next = (_qty[id] ?? 0) + by;
      if (next <= 0) {
        _qty.remove(id);
      } else if (next <= 50) {
        _qty[id] = next;
      }
      _txn = askodoxNewTxnId();
    });
    _publish();
  }

  Future<void> _send() async {
    final te = widget.te;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    if (_qty.isEmpty) return;
    if (_kind == 'delivery') {
      // The address and the map pin live on the order screen; it opens with this cart.
      final cart = [for (final e in _qty.entries) '${e.key}:${e.value}'].join(',');
      router.push('/order-desk?code=${Uri.encodeQueryComponent(_code)}&kind=delivery&cart=${Uri.encodeQueryComponent(cart)}');
      return;
    }
    setState(() => _busy = true);
    try {
      final order = await ref.read(askodoxPosRepositoryProvider).deskPlace({
        'code': _code,
        'items': [for (final e in _qty.entries) {'product_id': e.key, 'qty': e.value}],
        'kind': _kind,
        'client_txn_id': _txn,
      });
      if (mounted) setState(() => _orderId = '${order['id']}');
      _publish();
    } on AskodoxPosException catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.kind == 'sign_in'
              ? (te ? 'ఆర్డర్ పెట్టడానికి సైన్ ఇన్ చేయండి.' : 'Sign in to place an order.')
              : e.message(te))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The shop's own menu sections, in menu order (none set -> no tabs).
  List<String> get _groups => [
        for (final g in {for (final m in _items) '${m['menu_group'] ?? ''}'.trim()}) if (g.isNotEmpty) g,
      ];

  bool get _hasFoodMarks => _items.any((m) => '${m['food_type'] ?? ''}'.isNotEmpty);

  /// Items under the chosen section and veg / non-veg (egg counts as non-veg), what the person asked for first.
  List<AskodoxJson> get _shown => [
        for (final m in _items)
          if ((_group.isEmpty || '${m['menu_group'] ?? ''}'.trim() == _group) &&
              (_food.isEmpty || (_food == 'veg' ? m['food_type'] == 'veg' : const ['nonveg', 'egg'].contains(m['food_type']))))
            m,
      ]..sort((a, b) => ((_qty['${b['id']}'] ?? 0) > 0 ? 1 : 0).compareTo((_qty['${a['id']}'] ?? 0) > 0 ? 1 : 0));

  Widget _foodDot(String type) {
    final color = type == 'veg' ? const Color(0xFF17784C) : (type == 'egg' ? const Color(0xFFB45309) : const Color(0xFFB91C1C));
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(border: Border.all(color: color, width: 1.5), borderRadius: BorderRadius.circular(3)),
      alignment: Alignment.center,
      child: Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }

  Widget _foodChip(String type, String label, Color color) => FilterChip(
        key: Key('askodoxChatShopMenuFood-$type'),
        avatar: _foodDot(type),
        label: Text(label),
        selected: _food == type,
        selectedColor: color.withValues(alpha: 0.12),
        onSelected: (on) => setState(() {
          _food = on ? type : '';
          _all = false;
        }),
      );

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final open = widget.card['open'] == true;
    final last = askodoxPosList(widget.card['last_items']);
    final more = askodoxPosInt(widget.card['more']);
    final count = _qty.values.fold<int>(0, (a, b) => a + b);
    return Card(
      key: _cardKey,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(key: ValueKey('askodoxChatShopMenu-${widget.card['business_id']}'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${widget.card['name'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Row(children: [
                  Text(open ? (te ? 'ఇప్పుడు తెరిచి ఉంది · ASKODOX లో' : 'Open now · on ASKODOX') : (te ? 'ఇప్పుడు మూసి ఉంది' : 'Closed now'),
                      style: TextStyle(fontSize: 12, color: open ? const Color(0xFF1F7A4A) : const Color(0xFFB4530A))),
                  const SizedBox(width: 6),
                  askodoxRatingLine(widget.card['rating'], size: 12),
                ]),
              ]),
            ),
            if (open && last.isNotEmpty && _orderId == null)
              OutlinedButton(
                key: const Key('askodoxChatShopMenuAgain'),
                onPressed: () => setState(() {
                  _qty.clear();
                  _fill(last);
                  _txn = askodoxNewTxnId();
                  WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
                }),
                child: Text(te ? 'మళ్ళీ అదే' : 'Same again'),
              ),
          ]),
          _followRow(te),
          if (_orderId != null) ...[
            const SizedBox(height: 10),
            Text(te ? 'ఆర్డర్ పంపాం ✓ షాప్ అంగీకరించగానే బిల్లు, Pay ఇక్కడే వస్తాయి.' : 'Order sent ✓ The bill and Pay arrive once the shop accepts.',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('askodoxChatShopMenuTrack'),
              onPressed: () => context.push('/order-desk/track/$_orderId'),
              icon: const Icon(Icons.receipt_long),
              label: Text(te ? 'ఆర్డర్ ఎక్కడుంది / బిల్లు' : 'Track the order / bill'),
            ),
          ] else if (open) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final m in _modes)
                ChoiceChip(
                  key: Key('askodoxChatShopMenuKind-$m'),
                  label: Text(_kindLabel(m)),
                  selected: _kind == m,
                  onSelected: (_) {
                    setState(() => _kind = m);
                    _publish();
                  },
                ),
            ]),
            if (_groups.length > 1 || _hasFoodMarks) ...[
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  if (_hasFoodMarks) ...[
                    _foodChip('veg', te ? 'వెజ్' : 'Veg', const Color(0xFF17784C)),
                    const SizedBox(width: 6),
                    _foodChip('nonveg', te ? 'నాన్-వెజ్' : 'Non-veg', const Color(0xFFB91C1C)),
                    const SizedBox(width: 10),
                  ],
                  if (_groups.length > 1)
                    for (final g in ['', ..._groups])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: Key('askodoxChatShopMenuGroup-${g.isEmpty ? 'all' : g}'),
                          label: Text(g.isEmpty ? (te ? 'అన్నీ' : 'All') : g),
                          selected: _group == g,
                          onSelected: (_) => setState(() {
                            _group = g;
                            _all = false;
                          }),
                        ),
                      ),
                ]),
              ),
            ],
            for (final m in _shown.take(_all ? 500 : 8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  if ('${m['food_type'] ?? ''}'.isNotEmpty) ...[
                    _foodDot('${m['food_type']}'),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                        m['available'] == true
                            ? '${m['item_no'] != null ? '#${m['item_no']} ' : ''}${te && '${m['name_te'] ?? ''}'.isNotEmpty ? m['name_te'] : m['name']}  ${_rupees(askodoxPosInt(m['price_paise']))}'
                            : '${m['name']} — ${te ? 'ఈరోజు అయిపోయింది' : 'finished today'}',
                        style: TextStyle(color: m['available'] == true ? null : const Color(0xFF5B6475))),
                  ),
                  askodoxRatingLine(m['rating'], size: 11),
                  if (m['available'] == true && (_qty['${m['id']}'] ?? 0) == 0)
                    OutlinedButton(
                      key: Key('askodoxChatShopMenuAdd-${m['id']}'),
                      onPressed: () => _change('${m['id']}', 1),
                      child: Text(te ? 'చేర్చు' : 'Add'),
                    ),
                  if (m['available'] == true && (_qty['${m['id']}'] ?? 0) > 0) ...[
                    IconButton(
                        key: Key('askodoxChatShopMenuLess-${m['id']}'),
                        tooltip: te ? 'తగ్గించు' : 'Less',
                        onPressed: () => _change('${m['id']}', -1),
                        icon: const Icon(Icons.remove_circle_outline)),
                    Text('${_qty['${m['id']}']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                        key: Key('askodoxChatShopMenuMore-${m['id']}'),
                        tooltip: te ? 'పెంచు' : 'More',
                        onPressed: () => _change('${m['id']}', 1),
                        icon: const Icon(Icons.add_circle)),
                  ],
                ]),
              ),
            if (!_all && _shown.length > 8)
              TextButton(
                key: const Key('askodoxChatShopMenuAll'),
                onPressed: () => setState(() => _all = true),
                child: Text(te ? 'ఇంకా ${_shown.length - 8} ఐటమ్స్ ▾' : '${_shown.length - 8} more items ▾'),
              )
            else if (more > 0)
              TextButton(
                key: const Key('askodoxChatShopMenuWhole'),
                onPressed: () => context.push('/order-desk?code=${Uri.encodeQueryComponent(_code)}'),
                child: Text(te ? 'మొత్తం మెనూ (+$more)' : 'Whole menu (+$more)'),
              ),
            const SizedBox(height: 4),
            FilledButton(
              key: const Key('askodoxChatShopMenuSend'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: count == 0 || _busy ? null : _send,
              child: Text(count == 0
                  ? (te ? 'ఐటమ్స్ చేర్చండి, లేదా కింద చెప్పండి' : 'Add items, or say them below')
                  : '$count ${te ? 'ఐటమ్స్' : 'items'} · ${_rupees(_total)} · ${_kindLabel(_kind)} — ${te ? 'ఆర్డర్ పెట్టు' : 'Place order'}'),
            ),
          ] else
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${widget.card['message'] ?? ''}', style: const TextStyle(fontSize: 13))),
        ]),
      ),
    );
  }
}
