import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shops/presentation/my_business_screens.dart' show askodoxBoxMic;
import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import 'pos_common.dart';

/// Front desk, shop side (owner 2026-11-15): ONE orders desk for table / shop-QR / counter / reception orders,
/// the spoken menu, and the QR page. Cooks accept + move the stages, a cashier bills; every rule is the server's.

String _stageLabel(String stage, bool te) => const {
      'placed': ('Waiting', 'కొత్త'),
      'accepted': ('Accepted', 'అంగీకరించారు'),
      'preparing': ('Preparing', 'తయారవుతోంది'),
      'ready': ('Ready', 'సిద్ధం'),
      'packed': ('Packed', 'ప్యాక్'),
      'served': ('Served', 'వడ్డించారు'),
      'handed': ('Handed over', 'అందజేశారు'),
      'out_for_delivery': ('On the way', 'డెలివరీకి వెళ్ళింది'),
      'delivered': ('Delivered', 'డెలివరీ అయింది'),
      'done': ('Done', 'పూర్తి'),
      'rejected': ('Rejected', 'వద్దన్నారు'),
      'cancelled': ('Cancelled', 'రద్దు'),
    }[stage]
        ?.let((p) => te ? p.$2 : p.$1) ??
    stage;

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

// =============================================================== orders desk
class AskodoxDeskOrdersScreen extends ConsumerStatefulWidget {
  const AskodoxDeskOrdersScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxDeskOrdersScreen> createState() => _AskodoxDeskOrdersScreenState();
}

class _AskodoxDeskOrdersScreenState extends ConsumerState<AskodoxDeskOrdersScreen> {
  static const _lanes = ['new', 'kitchen', 'ready', 'delivery', 'done'];
  String _lane = 'new';
  AskodoxJson? _data;
  Object? _error;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).deskOrders(widget.businessId, lane: _lane);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _data == null) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<Object?> Function() action) async {
    final te = askodoxPosTe(context);
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(AskodoxJson order) async {
    final te = askodoxPosTe(context);
    final items = askodoxPosList(order['items']);
    final decisions = <String, bool>{for (final i in items) '${i['product_id']}': true};
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(te ? 'ఏవి ఉన్నాయి?' : 'What is available?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final i in items)
              SwitchListTile(
                key: Key('askodoxDeskAvail-${i['product_id']}'),
                contentPadding: EdgeInsets.zero,
                value: decisions['${i['product_id']}'] ?? true,
                onChanged: (v) => setLocal(() => decisions['${i['product_id']}'] = v),
                title: Text('${i['name']} × ${(i['qty'] as num).round()}'),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(te ? 'వద్దు' : 'Back')),
            FilledButton(
                key: const Key('askodoxDeskAcceptGo'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(te ? 'అంగీకరించు' : 'Accept')),
          ],
        ),
      ),
    );
    if (go == true) {
      await _run(() => ref.read(askodoxPosRepositoryProvider).deskConfirm(widget.businessId, '${order['id']}', decisions));
    }
  }

  Future<void> _reject(AskodoxJson order) async {
    final te = askodoxPosTe(context);
    final reason = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(te ? 'ఎందుకు వద్దు?' : 'Why not?'),
        content: TextField(controller: reason, decoration: InputDecoration(hintText: te ? 'కారణం (కస్టమర్‌కి కనిపిస్తుంది)' : 'Reason (the customer sees it)')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(te ? 'వెనక్కి' : 'Back')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(te ? 'తిరస్కరించు' : 'Reject')),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (go == true) await _run(() => ref.read(askodoxPosRepositoryProvider).deskReject(widget.businessId, '${order['id']}', text));
  }

  Future<void> _advance(AskodoxJson order, String stage) async {
    final te = askodoxPosTe(context);
    var who = '';
    if (stage == 'out_for_delivery') {
      final box = TextEditingController(text: '${order['assignee'] ?? ''}');
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(te ? 'డెలివరీ ఎవరు తీసుకెళ్తున్నారు?' : 'Who is delivering?'),
          content: TextField(key: const Key('askodoxDeskAssignee'), controller: box, decoration: InputDecoration(labelText: te ? 'పేరు' : 'Name')),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(te ? 'వెనక్కి' : 'Back')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(te ? 'సరే' : 'OK')),
          ],
        ),
      );
      who = box.text.trim();
      box.dispose();
      if (go != true) return;
    }
    await _run(() => ref.read(askodoxPosRepositoryProvider).deskAdvance(widget.businessId, '${order['id']}', stage, assignee: who));
  }

  Future<void> _bill(AskodoxJson order) async {
    final te = askodoxPosTe(context);
    final estimate = askodoxPosInt(order['estimate_paise']);
    var method = 'cash';
    final paid = TextEditingController(text: (estimate / 100).toStringAsFixed(estimate % 100 == 0 ? 0 : 2));
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(te ? 'బిల్లు చేయండి' : 'Make the bill'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(order['gst'] == true ? (te ? 'GST బిల్లులో కలుస్తుంది.' : 'GST is added on the bill.') : (te ? 'GST లేని బిల్లు.' : 'Bill without GST.')),
            const SizedBox(height: 8),
            TextField(
                key: const Key('askodoxDeskBillPaid'),
                controller: paid,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: te ? 'ఇప్పటి వరకు కట్టినది ₹ (0 = కట్టలేదు)' : 'Paid so far ₹ (0 = not paid)')),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'cash', label: Text(te ? 'క్యాష్' : 'Cash')),
                ButtonSegment(value: 'upi', label: const Text('UPI')),
                ButtonSegment(value: 'card', label: Text(te ? 'కార్డ్' : 'Card')),
              ],
              selected: {method},
              onSelectionChanged: (s) => setLocal(() => method = s.first),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(te ? 'వెనక్కి' : 'Back')),
            FilledButton(key: const Key('askodoxDeskBillGo'), onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(te ? 'బిల్లు' : 'Bill')),
          ],
        ),
      ),
    );
    final amount = askodoxParsePaise(paid.text) ?? 0;
    paid.dispose();
    if (go != true) return;
    await _run(() => ref.read(askodoxPosRepositoryProvider).deskBill(
          widget.businessId,
          '${order['id']}',
          amount > 0 ? [{'method': method, 'amount_paise': amount}] : const [],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final counts = askodoxPosMap(_data?['counts']);
    final orders = askodoxPosList(_data?['orders']);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఆర్డర్స్ డెస్క్' : 'Orders desk'), actions: [
        IconButton(
            key: const Key('askodoxDeskMenuBtn'),
            tooltip: te ? 'మెనూ' : 'Menu',
            icon: const Icon(Icons.restaurant_menu),
            onPressed: () => context.push('/desk/${widget.businessId}/menu')),
        IconButton(
            key: const Key('askodoxDeskQrBtn'),
            tooltip: 'QR',
            icon: const Icon(Icons.qr_code_2),
            onPressed: () => context.push('/desk/${widget.businessId}/qr')),
      ]),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            for (final lane in _lanes)
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(
                  key: Key('askodoxDeskLane-$lane'),
                  selected: _lane == lane,
                  label: Text('${const {
                    'new': ('New', 'కొత్త'),
                    'kitchen': ('Kitchen', 'వంటగది'),
                    'ready': ('Ready', 'సిద్ధం'),
                    'delivery': ('Delivery', 'డెలివరీ'),
                    'done': ('Done', 'పూర్తి'),
                  }[lane]!.let((p) => te ? p.$2 : p.$1)} ${counts[lane] ?? 0}'),
                  onSelected: (_) {
                    setState(() => _lane = lane);
                    unawaited(_load());
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: _error != null
              ? AskodoxPosError(error: _error!, onRetry: _load)
              : _data == null
                  ? const Center(child: CircularProgressIndicator())
                  : orders.isEmpty
                      ? Center(child: Text(te ? 'ఇక్కడ ఆర్డర్లు లేవు.' : 'No orders here.'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(padding: const EdgeInsets.all(10), children: [for (final o in orders) _card(o, te)])),
        ),
      ]),
    );
  }

  Widget _card(AskodoxJson o, bool te) {
    final stage = '${o['stage']}';
    final next = o['next_stage'] as String?;
    final closed = ['done', 'rejected', 'cancelled'].contains(stage);
    final billed = o['invoice'] is Map;
    final isDelivery = o['kind'] == 'delivery';
    return Card(
      key: Key('askodoxDeskOrder-${o['id']}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(
                    '${o['table_name'] != null ? (te ? 'టేబుల్ ${o['table_name']}' : 'Table ${o['table_name']}') : {'dine_in': te ? 'టేబుల్' : 'Dine in', 'takeaway': te ? 'పార్సిల్' : 'Takeaway', 'delivery': te ? 'డెలివరీ' : 'Delivery'}[o['kind']]}'
                    '${'${o['customer_name']}'.isEmpty ? '' : ' · ${o['customer_name']}'}',
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            Chip(label: Text(_stageLabel(stage, te))),
          ]),
          if (o['escalated'] == true) Text(te ? '⚠ 1 నిమిషం దాటింది — ఓనర్‌కి చెప్పాం' : '⚠ Waiting over a minute — the owner was told', style: const TextStyle(color: Colors.deepOrange)),
          for (final i in askodoxPosList(o['items']))
            Text('${i['name']} × ${(i['qty'] as num).round()}${'${i['note']}'.isEmpty ? '' : ' (${i['note']})'}',
                style: TextStyle(decoration: i['status'] == 'unavailable' ? TextDecoration.lineThrough : null)),
          if ('${o['notes']}'.isNotEmpty) Text('📝 ${o['notes']}'),
          Text(askodoxPaise(askodoxPosInt(o['estimate_paise'])), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (isDelivery) ...[
            Text('${o['address']}${'${o['landmark']}'.isEmpty ? '' : ' · ${o['landmark']}'}'),
            if ('${o['maps_url']}'.isNotEmpty)
              TextButton.icon(
                  key: Key('askodoxDeskMap-${o['id']}'),
                  onPressed: () => launchUrl(Uri.parse('${o['maps_url']}'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.map_outlined),
                  label: Text(te ? 'మ్యాప్‌లో చూడండి' : 'Open in Maps')),
            if ('${o['customer_phone'] ?? ''}'.isNotEmpty)
              TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('tel:${o['customer_phone']}')),
                  icon: const Icon(Icons.call),
                  label: Text('${o['customer_phone']}')),
          ],
          if (billed) Text('${te ? 'బిల్లు' : 'Bill'} ${(o['invoice'] as Map)['number']} · ${te ? 'బాకీ' : 'Balance'} ${askodoxPaise(askodoxPosInt((o['invoice'] as Map)['balance_paise']))}'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (stage == 'placed') ...[
              FilledButton(key: Key('askodoxDeskAccept-${o['id']}'), onPressed: _busy ? null : () => _accept(o), child: Text(te ? 'అంగీకరించు' : 'Accept')),
              OutlinedButton(onPressed: _busy ? null : () => _reject(o), child: Text(te ? 'వద్దు' : 'Reject')),
            ] else if (!closed && next != null && !(next == 'done' && !billed))
              FilledButton(
                  key: Key('askodoxDeskNext-${o['id']}'),
                  onPressed: _busy ? null : () => _advance(o, next),
                  child: Text('→ ${_stageLabel(next, te)}')),
            if (!closed && stage != 'placed' && !billed)
              OutlinedButton(key: Key('askodoxDeskBill-${o['id']}'), onPressed: _busy ? null : () => _bill(o), child: Text(te ? 'బిల్లు' : 'Bill')),
          ]),
        ]),
      ),
    );
  }
}

// =============================================================== menu: speak / type, review, then save
class AskodoxDeskMenuScreen extends ConsumerStatefulWidget {
  const AskodoxDeskMenuScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxDeskMenuScreen> createState() => _AskodoxDeskMenuScreenState();
}

class _AskodoxDeskMenuScreenState extends ConsumerState<AskodoxDeskMenuScreen> {
  final _text = TextEditingController();
  AskodoxJson? _menu;
  List<AskodoxJson> _preview = const [];
  bool _gst = false;
  int _rateBp = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await ref.read(askodoxPosRepositoryProvider).deskMenu(widget.businessId);
      if (mounted) {
        setState(() {
          _menu = m;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _guard(Future<Object?> Function() action) async {
    final te = askodoxPosTe(context);
    try {
      await action();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _parse() => _guard(() async {
        final out = await ref.read(askodoxPosRepositoryProvider).deskMenuParse(widget.businessId, _text.text);
        if (!mounted) return null;
        setState(() {
          _preview = askodoxPosList(out['items']);
          _gst = out['gst'] == true;
        });
        return null;
      });

  Future<void> _import() => _guard(() async {
        final te = askodoxPosTe(context);
        final out = await ref.read(askodoxPosRepositoryProvider).deskMenuImport(widget.businessId, _preview, rateBp: _rateBp);
        if (!mounted) return null;
        setState(() {
          _preview = const [];
          _text.clear();
        });
        askodoxPosSnack(context, te ? 'సేవ్ అయింది: ${out['created']} కొత్త, ${out['updated']} మార్పు' : 'Saved: ${out['created']} new, ${out['updated']} updated');
        await _load();
        return null;
      });

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final items = askodoxPosList(_menu?['items']);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'మెనూ' : 'Menu')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : ListView(key: const Key('askodoxDeskMenu'), padding: const EdgeInsets.all(14), children: [
              Text(te ? 'చెప్పండి లేదా రాయండి: "మటన్ బిర్యానీ 250 ఈ రోజు మాత్రమే, చికెన్ బిర్యానీ 170, టీ 10"' : 'Say or type: "mutton biryani 250 today only, chicken biryani 170, tea 10"'),
              const SizedBox(height: 8),
              TextField(
                key: const Key('askodoxDeskMenuText'),
                controller: _text,
                maxLines: 3,
                decoration: InputDecoration(border: const OutlineInputBorder(), suffixIcon: askodoxBoxMic(context, _text)),
              ),
              const SizedBox(height: 8),
              FilledButton(key: const Key('askodoxDeskMenuParse'), onPressed: _parse, child: Text(te ? 'చూపించు (ఇంకా సేవ్ కాదు)' : 'Preview (not saved yet)')),
              if (_preview.isNotEmpty) ...[
                const Divider(height: 24),
                for (var i = 0; i < _preview.length; i++)
                  ListTile(
                    key: Key('askodoxDeskPreview-$i'),
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_preview[i]['name']} · ${askodoxPaise(askodoxPosInt(_preview[i]['price_paise']))}'),
                    subtitle: Text([
                      _preview[i]['exists'] == true ? (te ? 'ఉన్నదే — ధర మారుతుంది (పాతది ${askodoxPaise(askodoxPosInt(_preview[i]['old_price_paise']))})' : 'Exists — price changes (was ${askodoxPaise(askodoxPosInt(_preview[i]['old_price_paise']))})') : (te ? 'కొత్తది' : 'New'),
                      if (_preview[i]['today_only'] == true) te ? 'ఈ రోజు మాత్రమే' : 'Today only',
                    ].join(' · ')),
                    trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _preview = [..._preview]..removeAt(i))),
                  ),
                if (_gst)
                  DropdownButtonFormField<int>(
                    key: const Key('askodoxDeskMenuGst'),
                    initialValue: _rateBp,
                    decoration: InputDecoration(labelText: te ? 'ఈ ఐటమ్స్‌కి GST % (మీరే ఎంచుకోండి)' : 'GST % for these items (your choice)'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('0%')),
                      DropdownMenuItem(value: 500, child: Text('5%')),
                      DropdownMenuItem(value: 1200, child: Text('12%')),
                      DropdownMenuItem(value: 1800, child: Text('18%')),
                    ],
                    onChanged: (v) => setState(() => _rateBp = v ?? 0),
                  ),
                const SizedBox(height: 8),
                FilledButton(key: const Key('askodoxDeskMenuSave'), onPressed: _import, child: Text(te ? 'మెనూలో సేవ్ చేయండి' : 'Save to the menu')),
              ],
              const Divider(height: 28),
              Text(te ? 'ఈ రోజు ఏవి ఉన్నాయి?' : 'What is available today?', style: const TextStyle(fontWeight: FontWeight.w800)),
              for (final m in items)
                SwitchListTile(
                  key: Key('askodoxDeskAvailable-${m['id']}'),
                  contentPadding: EdgeInsets.zero,
                  value: m['available'] == true,
                  title: Text('${m['name']} · ${askodoxPaise(askodoxPosInt(m['price_paise']))}'),
                  subtitle: Row(children: [
                    Text(m['today_only_flag'] == true ? (te ? 'ఈ రోజు మాత్రమే ✓' : 'Today only ✓') : ''),
                    TextButton(
                      onPressed: () => _guard(() async {
                        await ref.read(askodoxPosRepositoryProvider).deskTodayOnly(widget.businessId, '${m['id']}', m['today_only_flag'] != true);
                        await _load();
                        return null;
                      }),
                      child: Text(m['today_only_flag'] == true ? (te ? 'రోజూ ఉంచు' : 'Keep daily') : (te ? 'ఈ రోజు మాత్రమే' : 'Today only')),
                    ),
                  ]),
                  onChanged: (v) => _guard(() async {
                    await ref.read(askodoxPosRepositoryProvider).deskAvailability(widget.businessId, '${m['id']}', v);
                    await _load();
                    return null;
                  }),
                ),
            ]),
    );
  }
}

// =============================================================== QR page (shop + each table)
class AskodoxDeskQrScreen extends ConsumerStatefulWidget {
  const AskodoxDeskQrScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxDeskQrScreen> createState() => _AskodoxDeskQrScreenState();
}

class _AskodoxDeskQrScreenState extends ConsumerState<AskodoxDeskQrScreen> {
  AskodoxJson? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).deskQr(widget.businessId);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Widget _qr(String title, String code) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            QrImageView(data: code, size: 180),
            SelectableText(code, style: const TextStyle(fontSize: 11)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'షాప్ / టేబుల్ QR' : 'Shop / table QR')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(key: const Key('askodoxDeskQr'), padding: const EdgeInsets.all(14), children: [
                  Text(te ? 'ఈ QR ని ప్రింట్ చేసి టేబుల్ / షాప్ మీద అతికించండి. కస్టమర్ ASKODOX లో "ఆర్డర్ కోడ్" లో ఈ కోడ్ వేస్తే మెనూ తెరుచుకుంటుంది.' : 'Print this QR and stick it on the shop / each table. The customer enters the code in ASKODOX "Order code" to open the menu.'),
                  const SizedBox(height: 8),
                  _qr(te ? 'షాప్ (పార్సిల్ / డెలివరీ)' : 'Shop (takeaway / delivery)', '${d['shop']}'),
                  for (final t in askodoxPosList(d['tables'])) _qr(te ? 'టేబుల్ ${t['name']}' : 'Table ${t['name']}', '${t['code']}'),
                ]),
    );
  }
}
