import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';

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
  late String _kind;
  bool _busy = false;
  String? _orderId;
  String _txn = askodoxNewTxnId();

  List<AskodoxJson> get _items => askodoxPosList(widget.card['items']);
  List<String> get _modes => [for (final m in (widget.card['modes'] as List? ?? const [])) '$m'];
  String get _code => '${widget.card['code'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _kind = _modes.contains('dine_in') ? 'dine_in' : 'takeaway';
    _fill(askodoxPosList(widget.card['prepared']));
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

  void _change(String id, int by) => setState(() {
        final next = (_qty[id] ?? 0) + by;
        if (next <= 0) {
          _qty.remove(id);
        } else if (next <= 50) {
          _qty[id] = next;
        }
        _txn = askodoxNewTxnId();
      });

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
    } on AskodoxPosException catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.kind == 'sign_in'
              ? (te ? 'ఆర్డర్ పెట్టడానికి సైన్ ఇన్ చేయండి.' : 'Sign in to place an order.')
              : e.message(te))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final open = widget.card['open'] == true;
    final last = askodoxPosList(widget.card['last_items']);
    final more = askodoxPosInt(widget.card['more']);
    final count = _qty.values.fold<int>(0, (a, b) => a + b);
    return Card(
      key: ValueKey('askodoxChatShopMenu-${widget.card['business_id']}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${widget.card['name'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(open ? (te ? 'ఇప్పుడు తెరిచి ఉంది · ASKODOX లో' : 'Open now · on ASKODOX') : (te ? 'ఇప్పుడు మూసి ఉంది' : 'Closed now'),
                    style: TextStyle(fontSize: 12, color: open ? const Color(0xFF1F7A4A) : const Color(0xFFB4530A))),
              ]),
            ),
            if (open && last.isNotEmpty && _orderId == null)
              OutlinedButton(
                key: const Key('askodoxChatShopMenuAgain'),
                onPressed: () => setState(() {
                  _qty.clear();
                  _fill(last);
                  _txn = askodoxNewTxnId();
                }),
                child: Text(te ? 'మళ్ళీ అదే' : 'Same again'),
              ),
          ]),
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
                  onSelected: (_) => setState(() => _kind = m),
                ),
            ]),
            for (final m in _items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        m['available'] == true
                            ? '${te && '${m['name_te'] ?? ''}'.isNotEmpty ? m['name_te'] : m['name']}  ${_rupees(askodoxPosInt(m['price_paise']))}'
                            : '${m['name']} — ${te ? 'ఈరోజు అయిపోయింది' : 'finished today'}',
                        style: TextStyle(color: m['available'] == true ? null : const Color(0xFF5B6475))),
                  ),
                  if (m['available'] == true && (_qty['${m['id']}'] ?? 0) == 0)
                    OutlinedButton(
                      key: Key('askodoxChatShopMenuAdd-${m['id']}'),
                      onPressed: () => _change('${m['id']}', 1),
                      child: Text(te ? '+ యాడ్' : '+ Add'),
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
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('askodoxChatShopMenuAll'),
                onPressed: () => context.push('/order-desk?code=${Uri.encodeQueryComponent(_code)}'),
                child: Text(more > 0 ? (te ? 'మొత్తం మెనూ చూడు (+$more)' : 'See the whole menu (+$more)') : (te ? 'మొత్తం మెనూ / చెప్పి ఆర్డర్' : 'Whole menu / order by voice')),
              ),
            ),
            FilledButton(
              key: const Key('askodoxChatShopMenuSend'),
              onPressed: count == 0 || _busy ? null : _send,
              child: Text(count == 0
                  ? (te ? 'ఐటమ్స్ ఎంచుకోండి' : 'Choose items')
                  : '$count ${te ? 'ఐటమ్స్' : 'items'} · ${_rupees(_total)} · ${_kindLabel(_kind)} — ${te ? 'సరే, పంపు' : 'Send'}'),
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
