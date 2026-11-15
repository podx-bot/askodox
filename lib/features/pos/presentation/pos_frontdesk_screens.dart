import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../location/presentation/map_pin_picker.dart';
import '../../shops/presentation/my_business_screens.dart' show askodoxBoxMic;
import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
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
  List<AskodoxJson> _mine = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadMine());
  }

  @override
  void dispose() {
    _code.dispose();
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
        Text(te ? 'షాప్ లేదా టేబుల్ మీద ఉన్న QR కోడ్ రాయండి (ASKODOX-ORDER: తో మొదలవుతుంది).' : 'Type the code printed under the shop / table QR (it starts with ASKODOX-ORDER:).'),
        const SizedBox(height: 10),
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
  const AskodoxOrderDeskScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<AskodoxOrderDeskScreen> createState() => _AskodoxOrderDeskScreenState();
}

class _AskodoxOrderDeskScreenState extends ConsumerState<AskodoxOrderDeskScreen> {
  AskodoxJson? _data;
  Object? _error;
  final _qty = <String, double>{};
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
        'items': [for (final e in _qty.entries) {'product_id': e.key, 'qty': e.value}],
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

  Widget _menuRow(AskodoxJson m, bool te) {
    final id = '${m['id']}';
    final q = _qty[id] ?? 0;
    final available = m['available'] == true;
    return ListTile(
      key: Key('askodoxOrderItem-$id'),
      contentPadding: EdgeInsets.zero,
      enabled: available,
      title: Text(_itemName(m, te) + (m['today_only'] == true ? (te ? '  ⭐ ఈ రోజు' : '  ⭐ today') : '')),
      subtitle: Text(available ? '${askodoxPaise(askodoxPosInt(m['price_paise']))} / ${m['unit']}' : (te ? 'ఈ రోజు అయిపోయింది' : 'Finished for today')),
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
                      subtitle: i['status'] == 'unavailable' ? Text(te ? 'ఇది ఈ రోజు లేదు' : 'Not available today') : null,
                      trailing: Text(askodoxPaise(askodoxPosInt(i['price_paise']) * (i['qty'] as num).round())),
                    ),
                  Row(children: [
                    Expanded(child: Text(te ? 'సుమారు మొత్తం' : 'About')),
                    Text(askodoxPaise(askodoxPosInt(o['estimate_paise'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
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
