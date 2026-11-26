import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/backend_providers.dart';
import '../../../shared/widgets/chat_pins.dart' show askodoxLiveOrdersProvider;
import '../../location/presentation/map_pin_picker.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_item_icons.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 38): the customer's menu & order page `/order-desk`.
/// 1 what would you like (ONE list of the shop's menu: tap = one more, hold = less / note; the mic is the same
/// receptionist) -> 2 how do you want it (eat here / takeaway / delivery; delivery asks the address or a map pin) ->
/// 3 ONE big total + the chosen items, ONE big Send order. Same calls as the old page; the old page stays at
/// `?full=1`. You pay the shop directly.
class AskodoxOrderDeskStepsScreen extends ConsumerStatefulWidget {
  const AskodoxOrderDeskStepsScreen({super.key, required this.code, this.kind = '', this.cart = ''});
  final String code;

  /// From the chat's menu card: the way chosen there and the cart ("productId:qty,productId:qty").
  final String kind;
  final String cart;

  @override
  ConsumerState<AskodoxOrderDeskStepsScreen> createState() => _OrderDeskStepsState();
}

class _OrderDeskStepsState extends ConsumerState<AskodoxOrderDeskStepsScreen> {
  AskodoxJson? _data;
  Object? _error;
  final _qty = <String, double>{};
  final _itemNote = <String, String>{};
  final _search = TextEditingController();
  final _note = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _landmark = TextEditingController();
  final _notes = TextEditingController();
  int _step = 1;
  String _kind = 'takeaway';
  String _reply = '';
  bool _vegOnly = false;
  double? _lat;
  double? _lng;
  bool _busy = false;
  String _txn = askodoxNewTxnId();

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [_search, _note, _name, _phone, _address, _landmark, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// "Try it" (owner 2026-11-26): how this shop's items can be shown -- from its Business Kit: on_me / in_home / '' (none).
  String get _tryOn => '${_data?['try_on'] ?? ''}';

  /// The item's own photo (public, like the shop page photos); '' when it has none.
  String _photoUrl(AskodoxJson m) {
    if (m['has_photo'] != true) return '';
    final shop = '${(_data?['business'] as Map?)?['id'] ?? ''}';
    if (shop.isEmpty) return '';
    final base = ref.read(appConfigProvider).apiBaseUrl;
    final path = '/api/pos/shops/$shop/photo/product/${m['id']}';
    return base == null ? path : base.resolve(path).toString();
  }

  /// The small "Try it" button on an item with a photo, only in a shop whose kit offers it.
  Widget? _tryButton(AskodoxJson m, bool te) {
    final url = _photoUrl(m);
    if (_tryOn.isEmpty || !url.startsWith('https://')) return null;
    return IconButton(
      key: Key('askodoxOrderDeskStepsTry-${m['id']}'),
      tooltip: te ? 'ట్రై చేసి చూడు' : 'Try it',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.checkroom_rounded, size: 22),
      onPressed: () => context.push(Uri(path: '/try-on', queryParameters: {
        'image': url,
        'name': _itemName(m),
        'mode': _tryOn,
      }).toString()),
    );
  }

  List<String> get _modes => ((_data?['modes'] as List?) ?? const []).map((e) => '$e').toList();
  List<AskodoxJson> get _menu => askodoxPosList(_data?['menu']);
  List<String> get _groups => [for (final g in {for (final m in _menu) '${m['menu_group'] ?? ''}'.trim()}) g];
  bool get _hasFoodMarks => _menu.any((m) => '${m['food_type'] ?? ''}'.isNotEmpty);

  Future<void> _load() async {
    try {
      final data = await _repo.deskResolve(widget.code);
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        final modes = _modes;
        _kind = modes.contains('dine_in') ? 'dine_in' : (modes.contains('takeaway') || modes.isEmpty ? 'takeaway' : modes.first);
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
          // The chat's menu card already chose the items: go on to the next question.
          if (_qty.isNotEmpty) _step = modes.contains(widget.kind) && widget.kind != 'delivery' ? 3 : 2;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  AskodoxJson? _item(String id) {
    for (final m in _menu) {
      if ('${m['id']}' == id) return m;
    }
    return null;
  }

  String _itemName(AskodoxJson item) =>
      _te && '${item['name_te'] ?? ''}'.isNotEmpty ? '${item['name_te']}' : '${item['name'] ?? ''}';

  String _kindLabel(String kind, bool te) => switch (kind) {
        'dine_in' => te ? 'ఇక్కడ తింటాను' : 'Dine in',
        'delivery' => te ? 'డెలివరీ' : 'Delivery',
        _ => te ? 'పార్సిల్' : 'Takeaway',
      };

  int get _total {
    var sum = 0;
    _qty.forEach((id, q) {
      final item = _item(id);
      if (item != null) sum += (askodoxPosInt(item['price_paise']) * q).round();
    });
    return sum;
  }

  int get _count => _qty.values.fold<double>(0, (a, b) => a + b).round();

  void _change(String id, double by) {
    setState(() {
      final next = (_qty[id] ?? 0) + by;
      if (next <= 0) {
        _qty.remove(id);
        _itemNote.remove(id);
      } else {
        _qty[id] = next > 50 ? 50 : next;
      }
      _txn = askodoxNewTxnId();
    });
  }

  bool _shows(AskodoxJson m) {
    if (_vegOnly && m['food_type'] != 'veg') return false;
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${m['name'] ?? ''}'.toLowerCase().contains(q) ||
        '${m['name_te'] ?? ''}'.contains(q) ||
        '${m['item_no'] ?? ''}' == q ||
        '${m['menu_group'] ?? ''}'.toLowerCase().contains(q);
  }

  List<AskodoxJson> _cartJson() => [
        for (final e in _qty.entries)
          {'product_id': e.key, 'qty': e.value.round(), 'price_paise': askodoxPosInt(_item(e.key)?['price_paise'])}
      ];

  /// The receptionist: the same call as the old page. It fills the list; only "that's all" sends the order.
  Future<void> _ask(String text) async {
    final te = _te;
    final said = text.trim();
    if (said.isEmpty) return;
    try {
      final out = await _repo.deskAssist(widget.code, said, _cartJson(), te: te);
      if (!mounted) return;
      setState(() {
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
    final te = _te;
    final place = await AskodoxMapPinPicker.open(context, title: te ? 'డెలివరీ చోటు' : 'Delivery spot');
    if (place == null || !mounted) return;
    setState(() {
      _lat = place.latitude;
      _lng = place.longitude;
      if (_address.text.trim().isEmpty) _address.text = place.label;
    });
  }

  Future<void> _place() async {
    final te = _te;
    if (_qty.isEmpty) {
      askodoxPosSnack(context, te ? 'ముందు ఐటమ్స్ ఎంచుకోండి.' : 'Choose items first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final order = await _repo.deskPlace({
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
      if (mounted) await ref.read(askodoxLiveOrdersProvider.notifier).refresh();
      if (mounted) context.pushReplacement('/order-desk/track/${order['id']}');
    } on AskodoxPosException catch (e) {
      if (!mounted) return;
      if (e.code == 'address') {
        setState(() => _step = 2);
        askodoxPosSnack(context, te ? 'డెలివరీకి అడ్రస్ రాయండి (లేదా మ్యాప్‌లో పిన్ పెట్టండి).' : 'Delivery needs an address (or a map pin).');
      } else {
        askodoxPosSnack(context, e.message(te));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One chosen item: one less / one more and a note for the kitchen (a common one or your own).
  void _itemSheet(String id) {
    final te = _te;
    final item = _item(id);
    if (item == null) return;
    _note.text = _itemNote[id] ?? '';
    final quick = te
        ? ['తక్కువ కారం', 'ఎక్కువ కారం', 'ఉల్లిపాయ వద్దు', 'తక్కువ నూనె', 'ముందు ఇవ్వండి']
        : ['Less spicy', 'More spicy', 'No onion', 'Less oil', 'Serve first'];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: StatefulBuilder(
            builder: (ctx, setSheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_itemName(item), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text('${askodoxPaise(askodoxPosInt(item['price_paise']))} / ${item['unit'] ?? ''} · ×${(_qty[id] ?? 0).round()}',
                  key: const Key('askodoxOrderDeskStepsSheetQty'), style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('askodoxOrderDeskStepsLess-$id'),
                    onPressed: () {
                      _change(id, -1);
                      if ((_qty[id] ?? 0) <= 0) {
                        Navigator.pop(ctx);
                      } else {
                        setSheet(() {});
                      }
                    },
                    icon: const Icon(Icons.remove_rounded),
                    label: Text(te ? 'ఒకటి తగ్గించు' : 'One less'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: Key('askodoxOrderDeskStepsMore-$id'),
                    onPressed: () {
                      _change(id, 1);
                      setSheet(() {});
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: Text(te ? 'ఒకటి పెంచు' : 'One more'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final q in quick) ActionChip(label: Text(q), onPressed: () => _note.text = q),
              ]),
              const SizedBox(height: 8),
              TextField(
                key: const Key('askodoxOrderDeskStepsNoteBox'),
                controller: _note,
                maxLength: 120,
                decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'వంటగదికి నోట్' : 'Note for the kitchen'),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('askodoxOrderDeskStepsNoteOk'),
                  onPressed: () {
                    final text = _note.text.trim();
                    setState(() {
                      if (text.isEmpty || !_qty.containsKey(id)) {
                        _itemNote.remove(id);
                      } else {
                        _itemNote[id] = text;
                      }
                      _txn = askodoxNewTxnId();
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text(te ? 'సరే' : 'Done'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Optional: who it is for and one line for the kitchen.
  void _whoSheet() {
    final te = _te;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                key: const Key('askodoxOrderDeskStepsName'),
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
                decoration:
                    InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'షాప్‌కి నోట్ (కారం తక్కువ…)' : 'Note for the kitchen')),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {});
                  },
                  child: Text(te ? 'సరే' : 'Done')),
            ),
          ]),
        ),
      ),
    );
  }

  void _repeatLast() {
    final last = askodoxPosList(_data?['last_items']);
    setState(() {
      for (final l in last) {
        final id = '${l['product_id']}';
        if (_item(id) != null) _qty[id] = (l['qty'] as num).toDouble();
      }
      _txn = askodoxNewTxnId();
    });
  }

  void _next() {
    final te = _te;
    if (_step == 1) {
      if (_qty.isEmpty) {
        askodoxPosSnack(context, te ? 'ముందు ఐటమ్స్ ఎంచుకోండి.' : 'Choose items first.');
        return;
      }
      // One way only and it is not delivery: nothing to ask.
      final modes = _modes;
      setState(() => _step = modes.length <= 1 && _kind != 'delivery' ? 3 : 2);
    } else if (_step == 2) {
      if (_kind == 'delivery' && _address.text.trim().isEmpty && _lat == null) {
        askodoxPosSnack(context, te ? 'డెలివరీకి అడ్రస్ రాయండి (లేదా మ్యాప్‌లో పిన్ పెట్టండి).' : 'Delivery needs an address (or a map pin).');
        return;
      }
      setState(() => _step = 3);
    }
  }

  void _back() {
    if (_step == 3) {
      setState(() => _step = _modes.length <= 1 && _kind != 'delivery' ? 1 : 2);
    } else {
      setState(() => _step = 1);
    }
  }

  Widget _menuRow(AskodoxJson m, bool te) {
    final id = '${m['id']}';
    final q = (_qty[id] ?? 0).round();
    final available = m['available'] == true;
    final mark = '${m['food_type'] ?? ''}';
    return Opacity(
      opacity: available ? 1 : 0.5,
      child: GestureDetector(
        onLongPress: available && q > 0 ? () => _itemSheet(id) : null,
        child: AskodoxStepPersonRow(
          key: Key('askodoxOrderDeskStepsItem-$id'),
          photoUrl: _photoUrl(m),
          action: _tryButton(m, te),
          name: '${askodoxItemIcon('${m['name'] ?? ''}', nameTe: '${m['name_te'] ?? ''}')} '
              '${m['item_no'] != null ? '#${m['item_no']} ' : ''}${_itemName(m)}',
          sub: available
              ? '${askodoxPaise(askodoxPosInt(m['price_paise']))} / ${m['unit']}'
                  '${mark.isEmpty ? '' : (mark == 'veg' ? (te ? ' · వెజ్' : ' · veg') : (te ? ' · నాన్-వెజ్' : ' · non-veg'))}'
                  '${m['today_only'] == true ? (te ? ' · ⭐ ఈ రోజు' : ' · ⭐ today') : ''}'
              : (te ? 'ఈ రోజు అయిపోయింది' : 'Finished for today'),
          amount: q > 0 ? '×$q' : '+',
          amountColor: q > 0 ? askodoxStepGreen : askodoxStepMuted,
          onTap: available ? () => _change(id, 1) : () {},
        ),
      ),
    );
  }

  Widget _stepOne(AskodoxJson d, bool te) {
    final last = askodoxPosList(d['last_items']);
    final table = d['table'] as Map?;
    final groups = _groups;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      AskodoxStepSearch(
        fieldKey: const Key('askodoxOrderDeskStepsSearch'),
        controller: _search,
        hint: te ? 'ఐటమ్ పేరు / నంబర్' : 'Item name / number',
        onChanged: (_) => setState(() {}),
      ),
      if (table != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AskodoxStepPill(te ? 'టేబుల్ ${table['name']}' : 'Table ${table['name']}'),
        ),
      if (_reply.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_reply, key: const Key('askodoxOrderDeskStepsReply'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      const SizedBox(height: 8),
      if (last.isNotEmpty && _search.text.trim().isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AskodoxStepChoice(
            key: const Key('askodoxOrderDeskStepsRepeat'),
            icon: Icons.history_rounded,
            color: askodoxStepInfo,
            title: te ? 'మునుపటిలాగే' : 'Same as last time',
            sub: te ? 'గత ఆర్డర్‌లోని ఐటమ్స్ లిస్ట్‌లో చేరతాయి' : 'The items of your last order join the list',
            onTap: _repeatLast,
          ),
        ),
      for (final g in groups)
        if (_menu.any((m) => '${m['menu_group'] ?? ''}'.trim() == g && _shows(m))) ...[
          if (g.isNotEmpty && groups.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text(g, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          for (final m in _menu)
            if ('${m['menu_group'] ?? ''}'.trim() == g && _shows(m)) _menuRow(m, te),
        ],
    ]);
  }

  Widget _stepTwo(bool te) {
    final modes = _modes.isEmpty ? const ['takeaway'] : _modes;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
      for (final m in modes)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AskodoxStepChoice(
            key: Key('askodoxOrderDeskStepsKind-$m'),
            icon: m == 'dine_in' ? Icons.restaurant_rounded : (m == 'delivery' ? Icons.delivery_dining_rounded : Icons.shopping_bag_rounded),
            color: m == 'dine_in' ? askodoxStepGreen : (m == 'delivery' ? askodoxStepInfo : askodoxStepWarn),
            title: _kindLabel(m, te),
            sub: m == 'dine_in'
                ? (te ? 'టేబుల్ దగ్గరికి తెస్తారు' : 'Served at the table')
                : (m == 'delivery' ? (te ? 'మీ అడ్రస్‌కి తెస్తారు' : 'Brought to your address') : (te ? 'సిద్ధమైతే వచ్చి తీసుకోండి' : 'Collect it when it is ready')),
            selected: _kind == m,
            onTap: () => setState(() => _kind = m),
          ),
        ),
      if (_kind == 'delivery') ...[
        TextField(
            key: const Key('askodoxOrderDeskStepsAddress'),
            controller: _address,
            maxLines: 2,
            decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'డెలివరీ అడ్రస్' : 'Delivery address')),
        const SizedBox(height: 8),
        TextField(
            controller: _landmark,
            decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'ల్యాండ్‌మార్క్' : 'Landmark')),
        const SizedBox(height: 8),
        AskodoxStepChoice(
          key: const Key('askodoxOrderDeskStepsPin'),
          icon: Icons.place_rounded,
          color: askodoxStepInfo,
          title: _lat == null ? (te ? 'మ్యాప్‌లో పిన్' : 'Pin on the map') : (te ? 'పిన్ పెట్టాం ✓' : 'Pin set ✓'),
          sub: te ? 'డెలివరీ వ్యక్తికి సరిగ్గా చోటు తెలుస్తుంది' : 'The delivery person finds the exact spot',
          onTap: _pin,
        ),
      ],
    ]);
  }

  Widget _stepThree(AskodoxJson d, bool te) {
    final gst = (d['business'] as Map?)?['gst'] == true;
    final who = [_name.text.trim(), _phone.text.trim(), _notes.text.trim()].where((t) => t.isNotEmpty).join(' · ');
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      AskodoxStepBigNumber(askodoxPaise(_total),
          key: const Key('askodoxOrderDeskStepsTotal'), label: '$_count ${te ? 'ఐటమ్స్' : 'items'} · ${_kindLabel(_kind, te)}'),
      const SizedBox(height: 8),
      for (final e in _qty.entries)
        if (_item(e.key) != null)
          AskodoxStepPersonRow(
            key: Key('askodoxOrderDeskStepsLine-${e.key}'),
            photoUrl: _photoUrl(_item(e.key)!),
            action: _tryButton(_item(e.key)!, te),
            name: '${_itemName(_item(e.key)!)} ×${e.value.round()}',
            sub: (_itemNote[e.key] ?? '').isEmpty ? (te ? 'నొక్కితే: తగ్గించు / పెంచు / నోట్' : 'Tap: less / more / note') : '✏️ ${_itemNote[e.key]}',
            amount: askodoxPaise((askodoxPosInt(_item(e.key)!['price_paise']) * e.value).round()),
            amountColor: askodoxStepInk,
            onTap: () => _itemSheet(e.key),
          ),
      const SizedBox(height: 8),
      AskodoxStepPersonRow(
        key: const Key('askodoxOrderDeskStepsWho'),
        name: te ? 'పేరు / ఫోన్ / నోట్' : 'Name / phone / note',
        sub: who.isEmpty ? (te ? 'ఇష్టమైతే' : 'Optional') : who,
        amount: '›',
        amountColor: askodoxStepMuted,
        onTap: _whoSheet,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
            gst
                ? (te ? 'GST బిల్లులో చూపిస్తారు. డబ్బు నేరుగా షాప్ UPI కి.' : 'GST is shown on the bill. You pay the shop directly.')
                : (te ? 'ఈ షాప్‌కి GST లేదు. డబ్బు నేరుగా షాప్ UPI కి.' : 'This shop has no GST. You pay the shop directly.'),
            style: const TextStyle(fontSize: 13, color: askodoxStepMuted)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final d = _data;
    final biz = askodoxPosMap(d?['business']);
    final title = '${biz['name'] ?? (te ? 'ఆర్డర్' : 'Order')}';
    final full = '/order-desk?code=${Uri.encodeQueryComponent(widget.code)}&full=1';
    final old = AskodoxStepMore('askodoxOrderDeskStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded, () => context.push(full));

    if (_error != null || d == null || d['open'] != true) {
      return AskodoxStepScaffold(
        key: const Key('askodoxOrderDeskSteps'),
        title: title,
        more: [old],
        body: _error != null
            ? AskodoxPosError(error: _error!, onRetry: _load)
            : d == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('${d['message']}',
                            key: const Key('askodoxOrderDeskStepsClosed'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)))),
      );
    }

    final welcome = '${askodoxPosMap(d['welcome'])['text'] ?? ''}';
    return AskodoxStepScaffold(
      key: const Key('askodoxOrderDeskSteps'),
      title: title,
      step: _step,
      onBack: _step > 1 ? _back : null,
      question: _step == 1
          ? (te ? 'ఏం కావాలి?' : 'What would you like?')
          : _step == 2
              ? (te ? 'ఎలా కావాలి?' : 'How do you want it?')
              : null,
      hint: _step == 1
          ? (welcome.isNotEmpty ? welcome : (te ? 'నొక్కితే ఒకటి · నొక్కి పట్టుకుంటే తగ్గించు / నోట్ · మైక్‌తో చెప్పొచ్చు' : 'Tap = one more · hold = less / note · or say it'))
          : null,
      more: [
        if (_step == 1 && _hasFoodMarks)
          AskodoxStepMore('askodoxOrderDeskStepsVeg', _vegOnly ? (te ? 'అన్నీ చూపించు' : 'Show everything') : (te ? 'వెజ్ మాత్రమే' : 'Veg only'),
              Icons.eco_rounded, () => setState(() => _vegOnly = !_vegOnly)),
        if ('${biz['id'] ?? ''}'.isNotEmpty)
          AskodoxStepMore('askodoxOrderDeskStepsShop', te ? 'షాప్ పేజీ' : 'Shop page', Icons.storefront_outlined,
              () => context.push('/shops/${biz['id']}')),
        old,
      ],
      body: _step == 1 ? _stepOne(d, te) : (_step == 2 ? _stepTwo(te) : _stepThree(d, te)),
      bottom: _step == 3
          ? AskodoxStepBottom(
              buttonKey: const Key('askodoxOrderDeskStepsSend'),
              label: te ? 'ఆర్డర్ పంపు' : 'Send order',
              icon: Icons.send_rounded,
              busy: _busy,
              onPressed: _busy ? null : _place,
            )
          : AskodoxStepBottom(
              buttonKey: const Key('askodoxOrderDeskStepsNext'),
              label: _step == 1
                  ? (_count == 0 ? (te ? 'ఐటమ్స్ ఎంచుకోండి' : 'Choose items') : '$_count ${te ? 'ఐటమ్స్' : 'items'} · ${askodoxPaise(_total)}')
                  : (te ? 'తర్వాత' : 'Next'),
              icon: Icons.arrow_forward_rounded,
              onSpoken: _step == 1 ? (text) => unawaited(_ask(text)) : null,
              onPressed: _next,
            ),
    );
  }
}
