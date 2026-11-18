import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/navigator_section.dart' show AskodoxNavSection;
import '../../location/presentation/map_pin_picker.dart';
import '../../shops/presentation/my_business_screens.dart' show askodoxBoxMic;
import '../data/pos_hardware.dart' show AskodoxScanException;
import '../data/pos_repository.dart';
import '../domain/order_steps.dart';
import '../domain/pos_money.dart';
import 'pos_collect_screens.dart' show askodoxQrReaderProvider;
import 'pos_common.dart';
import 'shop_rating_screens.dart';

/// Front desk, customer side (owner 2026-11-15): scan / type the shop's order code -> the menu + a receptionist
/// (voice or typing) -> one order that goes to the kitchen, then follow it live. Money is paid to the shop's own UPI.

String _itemName(AskodoxJson item, bool te) =>
    te && '${item['name_te'] ?? ''}'.isNotEmpty ? '${item['name_te']}' : '${item['name'] ?? ''}';

/// The picture for a table request (water, gravy, onions, plate, tissue, bill, waiter; a shop's own = plus).
IconData askodoxTableAskIcon(String key) => switch (key) {
      'water' => Icons.water_drop_outlined,
      'extra_gravy' || 'gravy' => Icons.ramen_dining_outlined,
      'onions' || 'onion' => Icons.spa_outlined,
      'extra_plate' || 'plate' => Icons.restaurant_outlined,
      'tissue' => Icons.clean_hands_outlined,
      'bill' => Icons.receipt_long,
      'call' => Icons.front_hand_outlined,
      _ => Icons.add_circle_outline,
    };

/// The veg / non-veg / egg mark printed on Indian menus: a square with a dot (green / red / brown).
Widget askodoxFoodDot(String type) {
  final color = type == 'veg' ? const Color(0xFF17784C) : (type == 'egg' ? const Color(0xFFB45309) : const Color(0xFFB91C1C));
  return Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(border: Border.all(color: color, width: 1.5), borderRadius: BorderRadius.circular(3)),
    alignment: Alignment.center,
    child: Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
  );
}

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
  String _group = '';
  String _food = '';

  /// The shop's own menu sections in menu order ('' = items with no section).
  List<String> get _groups => [for (final g in {for (final m in _menu) '${m['menu_group'] ?? ''}'.trim()}) g];

  bool get _hasFoodMarks => _menu.any((m) => '${m['food_type'] ?? ''}'.isNotEmpty);

  bool _shows(AskodoxJson m) =>
      (_group.isEmpty || '${m['menu_group'] ?? ''}'.trim() == _group) &&
      (_food.isEmpty || (_food == 'veg' ? m['food_type'] == 'veg' : const ['nonveg', 'egg'].contains(m['food_type'])));

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
      bottomNavigationBar: d != null && d['open'] == true ? _cartBar(te) : null,
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
    final welcome = askodoxPosMap(d['welcome']);
    final biz = askodoxPosMap(d['business']);
    return ListView(key: const Key('askodoxOrderDesk'), padding: const EdgeInsets.all(14), children: [
      // Owner 2026-11-17: the shop greets the person by name on a QR scan (the shop can change or turn it off).
      if ('${welcome['text'] ?? ''}'.isNotEmpty)
        Container(
          key: const Key('askodoxOrderWelcome'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFF4E0), Color(0xFFFFE7EF)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Text('🙏', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${welcome['text']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                if (askodoxPosInt(welcome['visits_this_month']) > 1 || '${welcome['favourite'] ?? ''}'.isNotEmpty)
                  Text(
                      [
                        if (askodoxPosInt(welcome['visits_this_month']) > 1)
                          te ? 'ఈ నెల ${welcome['visits_this_month']}వ సారి' : 'Visit ${welcome['visits_this_month']} this month',
                        if ('${welcome['favourite'] ?? ''}'.isNotEmpty)
                          te ? 'మీ ఇష్టం: ${welcome['favourite']}' : 'Your usual: ${welcome['favourite']}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
              ]),
            ),
          ]),
        ),
      if ('${biz['id'] ?? ''}'.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('askodoxOrderDeskShopPage'),
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(te ? 'షాప్ పేజీ' : 'Shop page'),
              const SizedBox(width: 6),
              askodoxRatingLine(biz['rating']),
            ]),
            onPressed: () => context.push('/shops/${biz['id']}'),
          ),
        ),
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
      if (_groups.where((g) => g.isNotEmpty).length > 1 || _hasFoodMarks)
        SingleChildScrollView(
          key: const Key('askodoxOrderMenuTabs'),
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            if (_hasFoodMarks) ...[
              for (final f in const ['veg', 'nonveg'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    key: Key('askodoxOrderFood-$f'),
                    avatar: askodoxFoodDot(f),
                    label: Text(f == 'veg' ? (te ? 'వెజ్' : 'Veg') : (te ? 'నాన్-వెజ్' : 'Non-veg')),
                    selected: _food == f,
                    onSelected: (on) => setState(() => _food = on ? f : ''),
                  ),
                ),
              const SizedBox(width: 6),
            ],
            if (_groups.where((g) => g.isNotEmpty).length > 1)
              for (final g in ['', ..._groups.where((g) => g.isNotEmpty)])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: Key('askodoxOrderGroup-${g.isEmpty ? 'all' : g}'),
                    label: Text(g.isEmpty ? (te ? 'అన్నీ' : 'All') : g),
                    selected: _group == g,
                    onSelected: (_) => setState(() => _group = g),
                  ),
                ),
          ]),
        ),
      for (final g in _groups)
        if (_menu.any((m) => '${m['menu_group'] ?? ''}'.trim() == g && _shows(m))) ...[
          if (g.isNotEmpty && _groups.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 2),
              child: Text(g, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          for (final m in _menu)
            if ('${m['menu_group'] ?? ''}'.trim() == g && _shows(m)) _menuRow(m, te),
        ],
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
      Text(
          gst
              ? (te ? 'GST బిల్లులో చూపిస్తారు. డబ్బు నేరుగా షాప్ UPI కి.' : 'GST is shown on the bill. You pay the shop directly.')
              : (te ? 'ఈ షాప్‌కి GST లేదు. డబ్బు నేరుగా షాప్ UPI కి.' : 'This shop has no GST. You pay the shop directly.'),
          style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 80),
    ]);
  }

  /// Always at the bottom, whatever is scrolled (owner 2026-11-17): how many, how much, and the one button.
  Widget _cartBar(bool te) {
    final count = _qty.values.fold<double>(0, (a, b) => a + b).round();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x1A141E3C), blurRadius: 14, offset: Offset(0, -4))]),
        child: FilledButton(
          key: const Key('askodoxOrderPlace'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), padding: const EdgeInsets.symmetric(horizontal: 16)),
          onPressed: _busy || _qty.isEmpty ? null : _place,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(count == 0 ? (te ? 'ఐటమ్స్ ఎంచుకోండి' : 'Choose items') : '$count ${te ? 'ఐటమ్స్' : 'items'} · ${_kindLabel(_kind, te)}',
                    style: const TextStyle(fontSize: 12)),
                Text(askodoxPaise(_total), key: const Key('askodoxOrderTotal'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ]),
            ),
            Text(te ? 'ఆర్డర్ పంపు ›' : 'Send order ›', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
        ),
      ),
    );
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
      title: Row(children: [
        if ('${m['food_type'] ?? ''}'.isNotEmpty) ...[askodoxFoodDot('${m['food_type']}'), const SizedBox(width: 6)],
        Expanded(
            child: Text(
                '${m['item_no'] != null ? '#${m['item_no']} ' : ''}${_itemName(m, te)}${m['today_only'] == true ? (te ? '  ⭐ ఈ రోజు' : '  ⭐ today') : ''}')),
        askodoxRatingLine(m['rating'], size: 11.5),
      ]),
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
  bool _ratingAsked = false;
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
        // Owner 2026-11-17: the rating sheet opens by itself once the order is finished (the server decides
        // whether to ask: once, "later" = once more the next day).
        if (o['can_rate'] == true && !_ratingAsked) {
          _ratingAsked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (mounted && await askodoxAskRating(context, ref, widget.orderId) && mounted) {
              askodoxPosSnack(context, askodoxPosTe(context) ? 'ధన్యవాదాలు! ⭐' : 'Thank you! ⭐');
              unawaited(_load());
            }
          });
        }
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

  /// Owner 2026-11-18: cash or online is the customer's choice; the shop sees it on the order.
  Future<void> _choose(String choice, String? payLink) async {
    final te = askodoxPosTe(context);
    try {
      final o = await ref.read(askodoxPosRepositoryProvider).deskPayChoice(widget.orderId, choice);
      if (mounted) setState(() => _order = o);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (choice == 'online' && payLink != null) await _pay(payLink);
    if (choice == 'cash' && mounted) {
      askodoxPosSnack(context, te ? 'క్యాష్ కడతారని షాప్‌కి చెప్పాం' : 'The shop knows you will pay cash');
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final o = _order;
    final waiting = o != null && askodoxOrderAwaitsShop(o);
    final payLink = o == null ? null : askodoxOrderPayLink(o);
    final invoice = o?['invoice'] is Map ? o!['invoice'] as Map : null;
    final balance = invoice == null ? 0 : askodoxPosInt(invoice['balance_paise']);
    final toPay = balance > 0 ? balance : askodoxPosInt(o?['estimate_paise']);
    final closed = o != null && const ['rejected', 'cancelled'].contains('${o['stage']}');
    return Scaffold(
      appBar: AppBar(title: Text(o == null ? (te ? 'నా ఆర్డర్' : 'My order') : '${o['business_name']}')),
      bottomNavigationBar: o == null || closed || (invoice != null && balance == 0)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(
                      waiting
                          ? (te ? '${askodoxPaise(toPay)} — ఎలా కడతారు? (షాప్ ఒప్పుకున్నాక కట్టండి)' : '${askodoxPaise(toPay)} — how will you pay? (after the shop accepts)')
                          : (te ? '${askodoxPaise(toPay)} — ఎలా కడతారు?' : '${askodoxPaise(toPay)} — how will you pay?'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('askodoxOrderPayCash'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: o['pay_choice'] == 'cash' ? const Color(0xFFDCFCE7) : null),
                        onPressed: () => _choose('cash', payLink),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(o['pay_choice'] == 'cash' ? (te ? '✓ క్యాష్' : '✓ Cash') : (te ? 'క్యాష్' : 'Cash')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('askodoxOrderPayUpi'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        onPressed: waiting || payLink == null ? null : () => _choose('online', payLink),
                        icon: const Icon(Icons.qr_code_2),
                        label: Text(payLink == null && !waiting
                            ? (te ? 'బిల్లు రాగానే ఆన్‌లైన్' : 'Online once billed')
                            : (te ? 'ఆన్‌లైన్ (UPI)' : 'Online (UPI)')),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : o == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(key: const Key('askodoxOrderTrack'), padding: const EdgeInsets.all(14), children: [
                  if ('${o['thanks'] ?? ''}'.isNotEmpty || o['can_rate'] == true)
                    Container(
                      key: const Key('askodoxOrderThanks'),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFFF8EB), borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if ('${o['thanks'] ?? ''}'.isNotEmpty)
                          Text('🙏 ${o['thanks']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Wrap(spacing: 8, children: [
                          if (o['can_rate'] == true)
                            TextButton.icon(
                              key: const Key('askodoxOrderRate'),
                              icon: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                              label: Text(te ? 'రేటింగ్ ఇవ్వండి' : 'Rate'),
                              onPressed: () async {
                                if (await askodoxAskRating(context, ref, widget.orderId)) unawaited(_load());
                              },
                            ),
                          if ('${o['business_id'] ?? ''}'.isNotEmpty)
                            TextButton.icon(
                              key: const Key('askodoxOrderShopPage'),
                              icon: const Icon(Icons.storefront_outlined),
                              label: Text(te ? 'షాప్ పేజీ' : 'Shop page'),
                              onPressed: () => context.push('/shops/${o['business_id']}'),
                            ),
                        ]),
                      ]),
                    ),
                  Text('${_kindLabel('${o['kind']}', te)}${o['table_name'] != null ? ' · ${o['table_name']}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Container(
                    key: const Key('askodoxOrderStage'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: waiting ? const Color(0xFFFFF4E5) : (closed ? const Color(0xFFFDECEC) : const Color(0xFFE7F5EE)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(children: [
                      Text(
                          waiting
                              ? (te ? 'షాప్ ఒప్పుకోవడానికి వేచి ఉంది…' : 'Waiting for the shop to accept…')
                              : '${(o['stage_text'] as Map)[te ? 'te' : 'en']}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: waiting ? const Color(0xFF92400E) : (closed ? const Color(0xFFB91C1C) : const Color(0xFF17784C)))),
                      if (waiting)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                              te
                                  ? 'ఓనర్ / వాళ్లు అనుమతి ఇచ్చిన వ్యక్తి "ఒప్పుకున్నాను" నొక్కగానే మీకు చెప్తాం. ఇంకా డబ్బు కట్టకండి.'
                                  : 'You are told the moment the owner (or a person they allowed) accepts. Do not pay yet.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 13)),
                        ),
                    ]),
                  ),
                  if ('${o['reason'] ?? ''}'.isNotEmpty && '${o['reason']}' != 'null')
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text('${o['reason']}')),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Column(children: [
                        for (final st in askodoxOrderSteps(o))
                          Padding(
                            key: Key('askodoxOrderStep-${st.stage}'),
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(children: [
                              Icon(
                                  switch (st.state) {
                                    AskodoxStepState.done => Icons.check_circle,
                                    AskodoxStepState.now => Icons.radio_button_checked,
                                    AskodoxStepState.next => Icons.radio_button_unchecked,
                                  },
                                  size: 22,
                                  color: switch (st.state) {
                                    AskodoxStepState.done => const Color(0xFF17784C),
                                    AskodoxStepState.now => const Color(0xFFB45309),
                                    AskodoxStepState.next => const Color(0xFF9AA3B2),
                                  }),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(askodoxOrderStepName(st.stage, te),
                                      style: TextStyle(
                                          fontWeight: st.state == AskodoxStepState.next ? FontWeight.w500 : FontWeight.w800,
                                          color: st.state == AskodoxStepState.next ? const Color(0xFF5B6475) : null))),
                              Text(askodoxClockWords(st.at, te), style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(children: [
                        for (final i in askodoxPosList(o['items']))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${(i['qty'] as num).round()} × ${i['name']}',
                                      style: TextStyle(decoration: i['status'] == 'unavailable' ? TextDecoration.lineThrough : null)),
                                  if (i['status'] == 'unavailable')
                                    Text(te ? 'ఇది ఈ రోజు లేదు' : 'Not available today',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)))
                                  else if ('${i['note'] ?? ''}'.isNotEmpty)
                                    Text('${i['note']}', style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
                                ]),
                              ),
                              Text(askodoxPaise(askodoxPosInt(i['price_paise']) * (i['qty'] as num).round()),
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        const Divider(),
                        Row(children: [
                          Expanded(
                              child: Text(invoice != null ? '${te ? 'బిల్లు' : 'Bill'} ${invoice['number']}' : (te ? 'మొత్తం (సుమారు)' : 'Total (about)'),
                                  style: const TextStyle(fontWeight: FontWeight.w800))),
                          Text(askodoxPaise(invoice != null ? askodoxPosInt(invoice['total_paise']) : askodoxPosInt(o['estimate_paise'])),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ]),
                        if (invoice != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                                balance > 0
                                    ? '${te ? 'ఇంకా కట్టాల్సింది' : 'Still to pay'}: ${askodoxPaise(balance)}'
                                    : (te ? 'కట్టేశారు ✓' : 'Paid ✓'),
                                style: TextStyle(color: balance > 0 ? const Color(0xFFB45309) : const Color(0xFF17784C))),
                          ),
                      ]),
                    ),
                  ),
                  if (o['kind'] == 'dine_in' && !const ['placed', 'accepting', 'done', 'rejected', 'cancelled'].contains('${o['stage']}'))
                    AskodoxTableRequestsPanel(key: const Key('askodoxTableRequests'), orderId: widget.orderId),
                  const SizedBox(height: 6),
                  Row(children: [
                    if (o['can_cancel'] == true)
                      Expanded(
                        child: OutlinedButton(
                            key: const Key('askodoxOrderCancel'),
                            onPressed: _cancel,
                            child: Text(te ? 'ఆర్డర్ రద్దు' : 'Cancel the order')),
                      ),
                    if (o['can_cancel'] == true && '${o['business_phone'] ?? ''}'.isNotEmpty) const SizedBox(width: 8),
                    if ('${o['business_phone'] ?? ''}'.isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                            onPressed: () => launchUrl(Uri.parse('tel:${o['business_phone']}')),
                            icon: const Icon(Icons.call),
                            label: Text(te ? 'షాప్‌కి కాల్' : 'Call the shop')),
                      ),
                  ]),
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
          // Owner 2026-11-17: big coloured buttons (3 in a row), one tap = the waiter's phone rings and says it.
          LayoutBuilder(builder: (context, box) {
            final w = (box.maxWidth - 16) / 3;
            final quick = askodoxPosList(d['quick']);
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, q) in quick.indexed)
                SizedBox(
                  width: w,
                  child: Material(
                    color: AskodoxNavSection.palette[i % AskodoxNavSection.palette.length].$1,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: Key('askodoxTableAsk-${q['key']}'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: _busy ? null : () => _ask(kinds: ['${q['key']}']),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 80),
                        padding: const EdgeInsets.all(6),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(askodoxTableAskIcon('${q['key']}'),
                              size: 26, color: AskodoxNavSection.palette[i % AskodoxNavSection.palette.length].$2),
                          const SizedBox(height: 4),
                          Text(te ? '${q['te']}' : '${q['en']}',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]);
          }),
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
          if (askodoxPosList(d['requests']).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(te ? 'మీరు అడిగినవి' : 'What you asked for', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            Column(key: waiting.isEmpty ? null : const Key('askodoxTableWaiting'), children: [
              for (final r in askodoxPosList(d['requests']).take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(askodoxTableAskIcon('${r['kind']}'), size: 18, color: const Color(0xFF1E3FA0)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${r['text']}'.isNotEmpty ? '${r['text']}' : '${r['label']}')),
                    Text(
                        switch ('${r['status']}') {
                          'done' => '${'${r['done_by_name'] ?? ''}'.isNotEmpty ? '${r['done_by_name']} ' : ''}${te ? 'తెచ్చారు ✓' : 'brought it ✓'}',
                          'cancelled' => te ? 'రద్దు' : 'Cancelled',
                          _ => '${te ? 'పంపాం' : 'Sent'} · ${askodoxClockWords(r['created_at'], te)}',
                        },
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: r['status'] == 'done' ? const Color(0xFF17784C) : const Color(0xFFB45309))),
                  ]),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}
