import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../location/presentation/map_pin_picker.dart';
import '../../shops/presentation/my_business_screens.dart' show askodoxBoxMic;
import '../data/pos_hardware.dart' show AskodoxScanException;
import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import 'pos_collect_screens.dart' show askodoxQrReaderProvider;
import 'pos_common.dart';

/// Front desk, customer side (owner 2026-11-15): scan / type the shop's order code -> the menu + a receptionist
/// (voice or typing) -> one order that goes to the kitchen, then follow it live. Money is paid to the shop's own UPI.

String _itemName(AskodoxJson item, bool te) =>
    te && '${item['name_te'] ?? ''}'.isNotEmpty ? '${item['name_te']}' : '${item['name'] ?? ''}';

String _kindLabel(String kind, bool te) => switch (kind) {
      'dine_in' => te ? 'ఇక్కడ తింటాను' : 'Dine in',
      'delivery' => te ? 'డెలివరీ' : 'Delivery',
      _ => te ? 'పార్సిల్' : 'Takeaway',
    };

// =============================================================== enter the code (or arrive from a QR)
class AskodoxOrderCodeScreen extends ConsumerStatefulWidget {
  const AskodoxOrderCodeScreen({super.key});

  @override
  ConsumerState<AskodoxOrderCodeScreen> createState() => _AskodoxOrderCodeScreenState();
}

class _AskodoxOrderCodeScreenState extends ConsumerState<AskodoxOrderCodeScreen> {
  final _code = TextEditingController();
  final _shop = TextEditingController();
  List<AskodoxJson> _mine = const [];
  List<AskodoxJson> _shops = const [];
  bool _searched = false;
  Timer? _debounce;

  /// A customer cannot type a long code: photograph the shop / table QR instead (read on this phone).
  Future<void> _scan(String source) async {
    final te = askodoxPosTe(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final text = await ref.read(askodoxQrReaderProvider).read(source);
      if (text == null || !mounted) return;
      if (!text.toUpperCase().startsWith('ASKODOX-ORDER:')) {
        messenger.showSnackBar(SnackBar(
            content: Text(te ? 'ఇది ASKODOX ఆర్డర్ QR కాదు. షాప్ / టేబుల్ మీది QR తీయండి.' : 'That is not an ASKODOX order QR. Photograph the one on the shop / table.')));
        return;
      }
      _open(text);
    } on AskodoxScanException {
      messenger.showSnackBar(SnackBar(
          content: Text(te ? 'QR కనబడలేదు. దగ్గరగా, వెలుతురులో మళ్ళీ తీయండి — లేదా షాప్ పేరు వెతకండి.' : 'No QR found. Try closer, in good light — or search the shop by name.')));
    }
  }

  void _searchSoon(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final q = text.trim();
      if (q.length < 2) {
        if (mounted) {
          setState(() {
            _shops = const [];
            _searched = false;
          });
        }
        return;
      }
      try {
        final rows = await ref.read(askodoxPosRepositoryProvider).deskShops(q);
        if (mounted && _shop.text.trim() == q) {
          setState(() {
            _shops = rows;
            _searched = true;
          });
        }
      } on AskodoxPosException {
        // the code box and the QR still work
      }
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadMine());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _code.dispose();
    _shop.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    try {
      final rows = await ref.read(askodoxPosRepositoryProvider).deskMine();
      if (mounted) setState(() => _mine = rows);
    } catch (_) {}
  }

  void _open(String code) {
    final text = code.trim();
    if (text.isEmpty) return;
    context.push('/order-desk?code=${Uri.encodeQueryComponent(text)}');
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'షాప్ / టేబుల్ ఆర్డర్' : 'Order at a shop / table')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(
            child: FilledButton.icon(
                key: const Key('askodoxOrderScanCamera'),
                onPressed: () => _scan('camera'),
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(te ? 'QR ఫోటో తీయి' : 'Photograph the QR')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
                key: const Key('askodoxOrderScanGallery'),
                onPressed: () => _scan('photos'),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(te ? 'గ్యాలరీ నుంచి' : 'From gallery')),
          ),
        ]),
        const SizedBox(height: 14),
        TextField(
          key: const Key('askodoxOrderShopSearch'),
          controller: _shop,
          onChanged: _searchSoon,
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              labelText: te ? 'లేదా షాప్ పేరు వెతకండి' : 'Or search the shop by name'),
        ),
        for (final s in _shops)
          Card(
            child: ListTile(
              key: ValueKey('askodoxOrderShop-${s['id']}'),
              title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(s['open'] == true ? (te ? 'తెరిచి ఉంది' : 'Open') : (te ? 'ఇప్పుడు మూసి ఉంది' : 'Closed now')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open('${s['code']}'),
            ),
          ),
        if (_searched && _shops.isEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(te ? 'ఈ పేరుతో ASKODOX లో షాప్ కనబడలేదు.' : 'No shop with this name on ASKODOX.', style: const TextStyle(fontSize: 13))),
        const SizedBox(height: 14),
        Text(te ? 'లేదా QR కింద ఉన్న కోడ్ రాయండి (ASKODOX-ORDER: తో మొదలవుతుంది).' : 'Or type the code printed under the QR (it starts with ASKODOX-ORDER:).',
            style: const TextStyle(fontSize: 12.5)),
        const SizedBox(height: 8),
        TextField(
          key: const Key('askodoxOrderCode'),
          controller: _code,
          decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: te ? 'ఆర్డర్ కోడ్' : 'Order code',
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _open(_code.text))),
          onSubmitted: _open,
        ),
        const SizedBox(height: 18),
        if (_mine.isNotEmpty) Text(te ? 'నా ఆర్డర్లు' : 'My orders', style: const TextStyle(fontWeight: FontWeight.w800)),
        for (final o in _mine)
          Card(
            child: ListTile(
              title: Text('${o['business_name']} · ${_kindLabel('${o['kind']}', te)}'),
              subtitle: Text('${(o['stage_text'] as Map?)?[te ? 'te' : 'en'] ?? ''}'),
              trailing: Wrap(spacing: 4, children: [
                if (!['done', 'rejected', 'cancelled'].contains(o['stage']))
                  const Icon(Icons.chevron_right)
                else
                  TextButton(
                    key: Key('askodoxOrderAgain-${o['id']}'),
                    onPressed: () => _open('ASKODOX-ORDER:${o['business_id']}'),
                    child: Text(te ? 'మళ్ళీ' : 'Again'),
                  ),
              ]),
              onTap: () => context.push('/order-desk/track/${o['id']}'),
            ),
          ),
      ]),
    );
  }
}

// =============================================================== menu + receptionist + cart
class AskodoxOrderDeskScreen extends ConsumerStatefulWidget {
  const AskodoxOrderDeskScreen({super.key, required this.code, this.kind = '', this.cart = ''});
  final String code;

  /// From the chat's menu card: the way chosen there and the cart ("productId:qty,productId:qty").
  final String kind;
  final String cart;

  @override
  ConsumerState<AskodoxOrderDeskScreen> createState() => _AskodoxOrderDeskScreenState();
}

class _AskodoxOrderDeskScreenState extends ConsumerState<AskodoxOrderDeskScreen> {
  AskodoxJson? _data;
  Object? _error;
  final _qty = <String, double>{};
  final _itemNote = <String, String>{};
  final _say = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _landmark = TextEditingController();
  final _notes = TextEditingController();
  String _kind = 'takeaway';
  String _reply = '';
  double? _lat;
  double? _lng;
  bool _busy = false;
  String _txn = askodoxNewTxnId();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [_say, _name, _phone, _address, _landmark, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(askodoxPosRepositoryProvider).deskResolve(widget.code);
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        final modes = (data['modes'] as List? ?? const []).map((e) => '$e').toList();
        _kind = modes.contains('dine_in') ? 'dine_in' : 'takeaway';
        if (modes.contains(widget.kind)) _kind = widget.kind;
        if (_qty.isEmpty) {
          for (final part in widget.cart.split(',')) {
            final at = part.lastIndexOf(':');
            if (at <= 0) continue;
            final id = part.substring(0, at);
            final qty = double.tryParse(part.substring(at + 1)) ?? 0;
            final item = _item(id);
            if (item != null && item['available'] == true && qty > 0 && qty <= 50) _qty[id] = qty;
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<AskodoxJson> get _menu => askodoxPosList(_data?['menu']);

  AskodoxJson? _item(String id) {
    for (final m in _menu) {
      if ('${m['id']}' == id) return m;
    }
    return null;
  }

  int get _total {
    var sum = 0;
    _qty.forEach((id, q) {
      final item = _item(id);
      if (item != null) sum += (askodoxPosInt(item['price_paise']) * q).round();
    });
    return sum;
  }

  void _change(String id, double by) {
    setState(() {
      final next = (_qty[id] ?? 0) + by;
      if (next <= 0) {
        _qty.remove(id);
      } else {
        _qty[id] = next > 50 ? 50 : next;
      }
      _txn = askodoxNewTxnId();
    });
  }

  List<AskodoxJson> _cartJson() => [
        for (final e in _qty.entries)
          {'product_id': e.key, 'qty': e.value.round(), 'price_paise': askodoxPosInt(_item(e.key)?['price_paise'])}
      ];

  Future<void> _ask([String? text]) async {
    final te = askodoxPosTe(context);
    final said = (text ?? _say.text).trim();
    if (said.isEmpty) return;
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).deskAssist(widget.code, said, _cartJson(), te: te);
      if (!mounted) return;
      setState(() {
        _say.clear();
        _reply = '${out['reply'] ?? ''}';
        if (out['clear'] == true) _qty.clear();
        for (final id in (out['remove'] as List? ?? const [])) {
          _qty.remove('$id');
        }
        for (final line in askodoxPosList(out['add'])) {
          final id = '${line['product_id']}';
          if (_item(id) != null) _qty[id] = (_qty[id] ?? 0) + askodoxPosInt(line['qty']).toDouble();
        }
        final who = '${out['name'] ?? ''}';
        if (who.isNotEmpty && _name.text.trim().isEmpty) _name.text = who;
        _txn = askodoxNewTxnId();
      });
      if (out['confirm'] == true) await _place();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _pin() async {
    final te = askodoxPosTe(context);
    final place = await AskodoxMapPinPicker.open(context, title: te ? 'డెలివరీ చోటు' : 'Delivery spot');
    if (place == null || !mounted) return;
    setState(() {
      _lat = place.latitude;
      _lng = place.longitude;
      if (_address.text.trim().isEmpty) _address.text = place.label;
    });
  }

  Future<void> _place() async {
    final te = askodoxPosTe(context);
    if (_qty.isEmpty) {
      askodoxPosSnack(context, te ? 'ముందు ఐటమ్స్ ఎంచుకోండి.' : 'Choose items first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final order = await ref.read(askodoxPosRepositoryProvider).deskPlace({
        'code': widget.code,
        'items': [
          for (final e in _qty.entries)
            {'product_id': e.key, 'qty': e.value, if ((_itemNote[e.key] ?? '').isNotEmpty) 'note': _itemNote[e.key]},
        ],
        'kind': _kind,
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'landmark': _landmark.text.trim(),
        'lat': _lat,
        'lng': _lng,
        'notes': _notes.text.trim(),
        'client_txn_id': _txn,
      });
      if (mounted) context.pushReplacement('/order-desk/track/${order['id']}');
    } on AskodoxPosException catch (e) {
      if (mounted) {
        final message = e.code == 'address'
            ? (te ? 'డెలివరీకి అడ్రస్ రాయండి (లేదా మ్యాప్‌లో పిన్ పెట్టండి).' : 'Delivery needs an address (or a map pin).')
            : e.message(te);
        askodoxPosSnack(context, message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: Text('${(d?['business'] as Map?)?['name'] ?? (te ? 'ఆర్డర్' : 'Order')}')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : _body(context, d, te),
    );
  }

  Widget _body(BuildContext context, AskodoxJson d, bool te) {
    final modes = (d['modes'] as List? ?? const []).map((e) => '$e').toList();
    final table = d['table'] as Map?;
    final last = askodoxPosList(d['last_items']);
    final open = d['open'] == true;
    final gst = (d['business'] as Map?)?['gst'] == true;
    if (!open) {
      return Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text('${d['message']}', textAlign: TextAlign.center)));
    }
    return ListView(key: const Key('askodoxOrderDesk'), padding: const EdgeInsets.all(14), children: [
      if (table != null)
        Card(child: ListTile(leading: const Icon(Icons.table_restaurant), title: Text(te ? 'టేబుల్ ${table['name']}' : 'Table ${table['name']}'))),
      Wrap(spacing: 8, children: [
        for (final m in modes)
          ChoiceChip(
            key: Key('askodoxOrderKind-$m'),
            label: Text(_kindLabel(m, te)),
            selected: _kind == m,
            onSelected: (_) => setState(() => _kind = m),
          ),
      ]),
      const SizedBox(height: 10),
      TextField(
        key: const Key('askodoxOrderSay'),
        controller: _say,
        textInputAction: TextInputAction.send,
        onSubmitted: _ask,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: te ? 'చెప్పండి: "2 చికెన్ బిర్యానీ"' : 'Say it: "2 chicken biryani"',
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            askodoxBoxMic(context, _say, changed: () => unawaited(_ask())),
            IconButton(icon: const Icon(Icons.send), onPressed: _ask),
          ]),
        ),
      ),
      if (_reply.isNotEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_reply, key: const Key('askodoxOrderReply'))),
      if (last.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            key: const Key('askodoxOrderRepeat'),
            avatar: const Icon(Icons.history, size: 18),
            label: Text(te ? 'మునుపటిలాగే' : 'Same as last time'),
            onPressed: () => setState(() {
              for (final l in last) {
                final id = '${l['product_id']}';
                if (_item(id) != null) _qty[id] = (l['qty'] as num).toDouble();
              }
              _txn = askodoxNewTxnId();
            }),
          ),
        ),
      const SizedBox(height: 6),
      for (final m in _menu) _menuRow(m, te),
      const Divider(height: 24),
      if (_kind == 'delivery') ...[
        TextField(
            key: const Key('askodoxOrderAddress'),
            controller: _address,
            maxLines: 2,
            decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'డెలివరీ అడ్రస్' : 'Delivery address')),
        const SizedBox(height: 8),
        TextField(
            controller: _landmark,
            decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'ల్యాండ్‌మార్క్' : 'Landmark')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            key: const Key('askodoxOrderPin'),
            onPressed: _pin,
            icon: const Icon(Icons.place_outlined),
            label: Text(_lat == null ? (te ? 'మ్యాప్‌లో పిన్ పెట్టండి' : 'Pin on the map') : (te ? 'పిన్ పెట్టాం ✓' : 'Pin set ✓'))),
        const SizedBox(height: 8),
      ],
      TextField(
          controller: _name,
          decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'మీ పేరు (ఇష్టమైతే)' : 'Your name (optional)')),
      const SizedBox(height: 8),
      TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'ఫోన్ (ఇష్టమైతే)' : 'Phone (optional)')),
      const SizedBox(height: 8),
      TextField(
          controller: _notes,
          decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'షాప్‌కి నోట్ (కారం తక్కువ…)' : 'Note for the kitchen')),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text(te ? 'సుమారు మొత్తం' : 'About', style: const TextStyle(fontWeight: FontWeight.w800))),
        Text(askodoxPaise(_total), key: const Key('askodoxOrderTotal'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ]),
      Text(
          gst
              ? (te ? 'GST బిల్లులో చూపిస్తారు. డబ్బు నేరుగా షాప్ UPI కి.' : 'GST is shown on the bill. You pay the shop directly.')
              : (te ? 'ఈ షాప్‌కి GST లేదు. డబ్బు నేరుగా షాప్ UPI కి.' : 'This shop has no GST. You pay the shop directly.'),
          style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 10),
      FilledButton.icon(
        key: const Key('askodoxOrderPlace'),
        onPressed: _busy || _qty.isEmpty ? null : _place,
        icon: const Icon(Icons.restaurant_menu),
        label: Text(te ? 'ఆర్డర్ పంపండి' : 'Send the order'),
      ),
    ]);
  }

  /// A note for one item: tap a common one or type your own (it goes to the kitchen next to the item).
  Future<void> _editNote(String id, bool te) async {
    final box = TextEditingController(text: _itemNote[id] ?? '');
    final quick = te
        ? ['తక్కువ కారం', 'ఎక్కువ కారం', 'ఉల్లిపాయ వద్దు', 'తక్కువ నూనె', 'ముందు ఇవ్వండి']
        : ['Less spicy', 'More spicy', 'No onion', 'Less oil', 'Serve first'];
    final saved = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(te ? 'ఈ ఐటమ్‌కి నోట్' : 'Note for this item'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Wrap(spacing: 6, children: [
                  for (final q in quick) ActionChip(label: Text(q), onPressed: () => box.text = q),
                ]),
                const SizedBox(height: 8),
                TextField(
                    key: const Key('askodoxItemNoteBox'),
                    controller: box,
                    maxLength: 120,
                    decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'మీ నోట్' : 'Your note')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(te ? 'తీసేయి' : 'Clear')),
                FilledButton(onPressed: () => Navigator.pop(ctx, box.text.trim()), child: Text(te ? 'సరే' : 'Done')),
              ],
            ));
    box.dispose();
    if (saved == null || !mounted) return;
    setState(() {
      if (saved.isEmpty) {
        _itemNote.remove(id);
      } else {
        _itemNote[id] = saved;
      }
      _txn = askodoxNewTxnId();
    });
  }

  Widget _menuRow(AskodoxJson m, bool te) {
    final id = '${m['id']}';
    final q = _qty[id] ?? 0;
    final available = m['available'] == true;
    return ListTile(
      key: Key('askodoxOrderItem-$id'),
      contentPadding: EdgeInsets.zero,
      enabled: available,
      title: Text(_itemName(m, te) + (m['today_only'] == true ? (te ? '  ⭐ ఈ రోజు' : '  ⭐ today') : '')),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(available ? '${askodoxPaise(askodoxPosInt(m['price_paise']))} / ${m['unit']}' : (te ? 'ఈ రోజు అయిపోయింది' : 'Finished for today')),
        if (available && q > 0)
          InkWell(
            key: Key('askodoxOrderItemNote-$id'),
            onTap: () => _editNote(id, te),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                  (_itemNote[id] ?? '').isEmpty ? (te ? '✏️ నోట్ (తక్కువ కారం, ఉల్లిపాయ వద్దు…)' : '✏️ Add a note (less spicy, no onion…)') : '✏️ ${_itemNote[id]}',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13)),
            ),
          ),
      ]),
      trailing: !available
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (q > 0) IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _change(id, -1)),
              if (q > 0) Text(q.round().toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
              IconButton(icon: const Icon(Icons.add_circle), onPressed: () => _change(id, 1)),
            ]),
    );
  }
}

// =============================================================== follow the order
class AskodoxOrderTrackScreen extends ConsumerStatefulWidget {
  const AskodoxOrderTrackScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<AskodoxOrderTrackScreen> createState() => _AskodoxOrderTrackScreenState();
}

class _AskodoxOrderTrackScreenState extends ConsumerState<AskodoxOrderTrackScreen> {
  AskodoxJson? _order;
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await ref.read(askodoxPosRepositoryProvider).deskMineOne(widget.orderId);
      if (mounted) {
        setState(() {
          _order = o;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _order == null) setState(() => _error = e);
    }
  }

  Future<void> _cancel() async {
    final te = askodoxPosTe(context);
    try {
      final o = await ref.read(askodoxPosRepositoryProvider).deskCancelMine(widget.orderId);
      if (mounted) setState(() => _order = o);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _pay(String link) async {
    final uri = Uri.tryParse(link);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final o = _order;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'నా ఆర్డర్' : 'My order')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : o == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(key: const Key('askodoxOrderTrack'), padding: const EdgeInsets.all(14), children: [
                  Text('${o['business_name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('${_kindLabel('${o['kind']}', te)}${o['table_name'] != null ? ' · ${o['table_name']}' : ''}'),
                  const SizedBox(height: 10),
                  Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text('${(o['stage_text'] as Map)[te ? 'te' : 'en']}',
                              key: const Key('askodoxOrderStage'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
                  if ('${o['reason']}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${o['reason']}')),
                  const SizedBox(height: 8),
                  for (final i in askodoxPosList(o['items']))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${i['name']} × ${(i['qty'] as num).round()}',
                          style: TextStyle(decoration: i['status'] == 'unavailable' ? TextDecoration.lineThrough : null)),
                      subtitle: i['status'] == 'unavailable'
                          ? Text(te ? 'ఇది ఈ రోజు లేదు' : 'Not available today')
                          : ('${i['note'] ?? ''}'.isNotEmpty ? Text('✏️ ${i['note']}') : null),
                      trailing: Text(askodoxPaise(askodoxPosInt(i['price_paise']) * (i['qty'] as num).round())),
                    ),
                  Row(children: [
                    Expanded(child: Text(te ? 'సుమారు మొత్తం' : 'About')),
                    Text(askodoxPaise(askodoxPosInt(o['estimate_paise'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  if (o['kind'] == 'dine_in' && !const ['placed', 'done', 'rejected', 'cancelled'].contains('${o['stage']}'))
                    AskodoxTableRequestsPanel(key: const Key('askodoxTableRequests'), orderId: widget.orderId),
                  if (o['invoice'] is Map) ...[
                    const Divider(),
                    Text('${te ? 'బిల్లు' : 'Bill'} ${(o['invoice'] as Map)['number']}: ${askodoxPaise(askodoxPosInt((o['invoice'] as Map)['total_paise']))}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (askodoxPosInt((o['invoice'] as Map)['balance_paise']) > 0)
                      Text('${te ? 'ఇంకా కట్టాల్సింది' : 'Still to pay'}: ${askodoxPaise(askodoxPosInt((o['invoice'] as Map)['balance_paise']))}'),
                  ],
                  for (final p in askodoxPosList(o['pay']))
                    if ('${p['upi_link'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.icon(
                            key: const Key('askodoxOrderPayUpi'),
                            onPressed: () => _pay('${p['upi_link']}'),
                            icon: const Icon(Icons.payments_outlined),
                            label: Text(te ? 'షాప్ UPI కి కట్టండి' : "Pay the shop's UPI")),
                      ),
                  const Divider(height: 28),
                  for (final t in askodoxPosList(o['timeline']))
                    ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle, size: 18),
                        title: Text('${t['stage']}'),
                        subtitle: Text('${t['at'] ?? ''}')),
                  if (o['can_cancel'] == true)
                    OutlinedButton(key: const Key('askodoxOrderCancel'), onPressed: _cancel, child: Text(te ? 'ఆర్డర్ రద్దు' : 'Cancel the order')),
                  if ('${o['business_phone']}'.isNotEmpty)
                    TextButton.icon(
                        onPressed: () => launchUrl(Uri.parse('tel:${o['business_phone']}')),
                        icon: const Icon(Icons.call),
                        label: Text(te ? 'షాప్‌కి కాల్' : 'Call the shop')),
                ]),
    );
  }
}


/// "Need something?" on a running dine-in order: tap water / extra gravy / onions / bring the bill / call the waiter
/// (the shop chooses the list), or say it in words. The waiter gets it with the table's name.
class AskodoxTableRequestsPanel extends ConsumerStatefulWidget {
  const AskodoxTableRequestsPanel({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<AskodoxTableRequestsPanel> createState() => _AskodoxTableRequestsPanelState();
}

class _AskodoxTableRequestsPanelState extends ConsumerState<AskodoxTableRequestsPanel> {
  AskodoxJson? _data;
  final _say = TextEditingController();
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _say.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).deskMyRequests(widget.orderId);
      if (mounted) setState(() => _data = d);
    } catch (_) {}
  }

  Future<void> _ask({List<String> kinds = const [], String text = ''}) async {
    if (_busy) return;
    final te = askodoxPosTe(context);
    setState(() => _busy = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).deskAsk(widget.orderId, kinds: kinds, text: text);
      if (!mounted) return;
      _say.clear();
      final asked = askodoxPosList(out['asked']);
      askodoxPosSnack(
          context,
          asked.isEmpty
              ? (te ? 'ఇప్పటికే చెప్పారు, వెయిటర్ వస్తున్నారు.' : 'Already asked, the waiter is coming.')
              : (te ? 'వెయిటర్‌కి చెప్పాం ✓' : 'Told the waiter ✓'));
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final d = _data;
    if (d == null || d['can_ask'] != true) return const SizedBox.shrink();
    final waiting = askodoxPosList(d['requests']).where((r) => r['status'] == 'open').toList();
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(te ? 'ఏమైనా కావాలా?' : 'Need something?', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final q in askodoxPosList(d['quick']))
              ActionChip(
                key: Key('askodoxTableAsk-${q['key']}'),
                avatar: Icon(q['key'] == 'bill' ? Icons.receipt_long : (q['key'] == 'call' ? Icons.notifications_active : Icons.add), size: 18),
                label: Text(te ? '${q['te']}' : '${q['en']}'),
                onPressed: _busy ? null : () => _ask(kinds: ['${q['key']}']),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            key: const Key('askodoxTableSay'),
            controller: _say,
            textInputAction: TextInputAction.send,
            onSubmitted: (t) => _ask(text: t),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              labelText: te ? 'చెప్పండి: "ఆనియన్స్, నీళ్లు"' : 'Say it: "onions and water"',
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                askodoxBoxMic(context, _say, changed: () => unawaited(_ask(text: _say.text))),
                IconButton(icon: const Icon(Icons.send), onPressed: () => _ask(text: _say.text)),
              ]),
            ),
          ),
          if (waiting.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${te ? 'వేచి ఉన్నవి' : 'Waiting'}: ${waiting.map((r) => ('${r['text']}'.isNotEmpty ? '${r['text']}' : '${r['label']}')).join(', ')}',
                key: const Key('askodoxTableWaiting'), style: const TextStyle(fontSize: 13)),
          ],
        ]),
      ),
    );
  }
}
