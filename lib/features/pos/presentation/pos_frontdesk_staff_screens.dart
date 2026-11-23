import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/media_picker.dart';
import '../../../shared/widgets/askodox_fill_bar.dart';
import '../../shops/presentation/my_business_screens.dart' show askodoxBoxMic;
import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import '../domain/order_steps.dart' show askodoxClockWords;
import 'pos_common.dart';
import 'pos_frontdesk_screens.dart' show askodoxTableAskIcon;
import '../../../shared/widgets/qr_poster.dart';

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
  List<AskodoxJson> _asks = const [];

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
    try {
      final r = await ref.read(askodoxPosRepositoryProvider).deskRequests(widget.businessId);
      if (mounted) setState(() => _asks = askodoxPosList(r['requests']));
    } catch (_) {}
  }

  /// Table requests (water / extra gravy / onions / bill / call): the waiter's list, one tap = done.
  Future<void> _openAsks() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setLocal) {
          final te = askodoxPosTe(context);
          return SafeArea(
            child: ListView(key: const Key('askodoxDeskRequests'), shrinkWrap: true, padding: const EdgeInsets.all(14), children: [
              Text(te ? 'టేబుల్ అభ్యర్థనలు' : 'Table requests', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              if (_asks.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(te ? 'ఏమీ లేవు ✓' : 'Nothing waiting ✓')),
              // Owner 2026-11-17: a big card per request (table, what, how long ago) and one "Brought it ✓" tap.
              for (final r in _asks)
                Container(
                  key: Key('askodoxDeskRequest-${r['id']}'),
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E5),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Icon(askodoxTableAskIcon('${r['kind']}'), size: 30, color: const Color(0xFFB45309)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['table_name'] ?? ''}'.isEmpty ? (te ? 'టేబుల్' : 'Table') : '${r['table_name']}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        Text('${'${r['text']}'.isNotEmpty ? r['text'] : r['label']}${askodoxPosInt(r['qty']) > 1 ? ' × ${r['qty']}' : ''}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        Text(askodoxClockWords(r['created_at'], te), style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
                      ]),
                    ),
                    FilledButton(
                      key: Key('askodoxDeskRequestDone-${r['id']}'),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF17784C), minimumSize: const Size(0, 48)),
                      onPressed: () async {
                        try {
                          final out = await ref.read(askodoxPosRepositoryProvider).deskRequestDone(widget.businessId, '${r['id']}');
                          if (mounted) setState(() => _asks = askodoxPosList(out['requests']));
                          setLocal(() {});
                        } on AskodoxPosException catch (e) {
                          if (mounted) askodoxPosSnack(this.context, e.message(te));
                        }
                      },
                      child: Text(te ? 'తెచ్చాను ✓' : 'Brought it ✓'),
                    ),
                  ]),
                ),
            ]),
          );
        },
      ),
    );
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

  /// Pick the staff PERSON an order goes to (they get the alert on their own phone). Returns {id, label} or null.
  /// An empty staff list falls back to the typed name.
  Future<AskodoxJson?> _pickPerson(AskodoxJson order, {String? onlyRole}) async {
    final te = askodoxPosTe(context);
    List<AskodoxJson> people = const [];
    try {
      people = await ref.read(askodoxPosRepositoryProvider).deskPeople(widget.businessId);
    } on AskodoxPosException {
      people = const [];
    }
    if (!mounted) return null;
    if (onlyRole != null) {
      final narrowed = people.where((p) => p['role'] == onlyRole).toList();
      if (narrowed.isNotEmpty) people = narrowed;
    }
    final typed = TextEditingController(text: '${order['assignee'] ?? ''}');
    final picked = await showDialog<AskodoxJson?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(te ? 'ఎవరికి అసైన్ చేయాలి?' : 'Assign to whom?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final p in people)
              ListTile(
                key: Key('askodoxDeskPerson-${p['id']}'),
                contentPadding: EdgeInsets.zero,
                title: Text('${p['you'] == true ? (te ? 'నేను' : 'Me') : p['label']}'),
                subtitle: Text('${p['role']}'),
                selected: order['assignee_user'] == p['id'],
                onTap: () => Navigator.of(dialogContext).pop({'id': '${p['id']}', 'label': '${p['label']}'}),
              ),
            TextField(key: const Key('askodoxDeskAssignee'), controller: typed, decoration: InputDecoration(labelText: te ? 'లేదా పేరు రాయండి' : 'Or type a name')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(te ? 'వెనక్కి' : 'Back')),
          FilledButton(
              key: const Key('askodoxDeskAssignTyped'),
              onPressed: () => Navigator.of(dialogContext).pop({'id': '', 'label': typed.text.trim()}),
              child: Text(te ? 'సరే' : 'OK')),
        ],
      ),
    );
    typed.dispose();
    return picked;
  }

  Future<void> _assign(AskodoxJson order) async {
    final who = await _pickPerson(order);
    if (who == null) return;
    await _run(() => ref.read(askodoxPosRepositoryProvider).deskAssign(widget.businessId, '${order['id']}', '${who['label']}', userId: '${who['id']}'));
  }

  Future<void> _advance(AskodoxJson order, String stage) async {
    var who = '';
    var whoId = '';
    if (stage == 'out_for_delivery' && '${order['assignee'] ?? ''}'.isEmpty) {
      final picked = await _pickPerson(order, onlyRole: 'delivery');
      if (picked == null || '${picked['label']}'.isEmpty) return;
      who = '${picked['label']}';
      whoId = '${picked['id']}';
    }
    await _run(() => ref.read(askodoxPosRepositoryProvider).deskAdvance(widget.businessId, '${order['id']}', stage, assignee: who, assigneeUser: whoId));
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
            key: const Key('askodoxDeskSalesBtn'),
            tooltip: te ? 'అమ్మకాలు' : 'Sales',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.push('/desk/${widget.businessId}/sales')),
        IconButton(
            key: const Key('askodoxDeskSettingsBtn'),
            tooltip: te ? 'ఆర్డర్ అలర్ట్స్ & సిబ్బంది' : 'Order alerts & staff',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/desk/${widget.businessId}/settings')),
        IconButton(
            key: const Key('askodoxDeskQrBtn'),
            tooltip: 'QR',
            icon: const Icon(Icons.qr_code_2),
            onPressed: () => context.push('/desk/${widget.businessId}/qr')),
      ]),
      body: Column(children: [
        if (_asks.isNotEmpty)
          Material(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              key: const Key('askodoxDeskRequestsBanner'),
              dense: true,
              leading: const Icon(Icons.notifications_active),
              title: Text(te ? '${_asks.length} టేబుల్ అభ్యర్థనలు వేచి ఉన్నాయి' : '${_asks.length} table requests waiting',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(_asks.take(3).map((r) => '${r['table_name'] ?? ''} ${'${r['text']}'.isNotEmpty ? r['text'] : r['label']}').join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openAsks,
            ),
          ),
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
                    '${'${o['customer_name']}'.isEmpty ? '' : ' · ${o['customer_name']}'}'
                    // Owner 2026-11-23: an order from the public shop link (askodox.com/s/...) -- phone not OTP-checked.
                    '${o['source'] == 'shop_link' ? (te ? ' · 🔗 లింక్' : ' · 🔗 Link') : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            Chip(label: Text(_stageLabel(stage, te))),
          ]),
          if (o['escalated'] == true) Text(te ? '⚠ 1 నిమిషం దాటింది — ఓనర్‌కి చెప్పాం' : '⚠ Waiting over a minute — the owner was told', style: const TextStyle(color: Colors.deepOrange)),
          for (final i in askodoxPosList(o['items']))
            Text('${i['name']} × ${(i['qty'] as num).round()}${'${i['note']}'.isEmpty ? '' : ' (${i['note']})'}',
                style: TextStyle(decoration: i['status'] == 'unavailable' ? TextDecoration.lineThrough : null)),
          if ('${o['notes']}'.isNotEmpty) Text('📝 ${o['notes']}'),
          Text(askodoxPaise(askodoxPosInt(o['estimate_paise'])), style: const TextStyle(fontWeight: FontWeight.w700)),
          // Owner 2026-11-18: the customer's own choice -- cash at the counter / table, or online to the shop's UPI.
          if (o['pay_choice'] == 'cash' || o['pay_choice'] == 'online')
            Text(
                o['pay_choice'] == 'cash' ? (te ? '💵 క్యాష్ కడతారు' : '💵 Will pay cash') : (te ? '📱 ఆన్‌లైన్ (UPI) కడతారు' : '📱 Will pay online (UPI)'),
                key: ValueKey('askodoxDeskPayChoice-${o['id']}'),
                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF15803D))),
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
            if (!closed && stage != 'placed')
              OutlinedButton.icon(
                  key: Key('askodoxDeskAssign-${o['id']}'),
                  onPressed: _busy ? null : () => _assign(o),
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: Text('${'${o['assignee'] ?? ''}'.isEmpty ? (te ? 'అసైన్' : 'Assign') : o['assignee']}')),
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
  bool _sorting = false;
  AskodoxJson? _menu;
  List<AskodoxJson> _preview = const [];
  bool _reading = false;
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

  Future<void> _editItem(AskodoxJson m, bool te) async {
    final name = TextEditingController(text: '${m['name']}');
    final price = TextEditingController(text: (askodoxPosInt(m['price_paise']) / 100).toStringAsFixed(askodoxPosInt(m['price_paise']) % 100 == 0 ? 0 : 2));
    final group = TextEditingController(text: '${m['menu_group'] ?? ''}');
    var food = '${m['food_type'] ?? ''}';
    final sections = {
      for (final x in askodoxPosList(_menu?['items'])) '${x['menu_group'] ?? ''}'.trim(),
    }..remove('');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text(te ? 'ఐటమ్ మార్చండి' : 'Edit item'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(key: const Key('askodoxDeskEditName'), controller: name, decoration: InputDecoration(labelText: te ? 'పేరు' : 'Name')),
              TextField(
                  key: const Key('askodoxDeskEditPrice'),
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: te ? 'రేటు (₹)' : 'Price (₹)')),
              TextField(
                  key: const Key('askodoxDeskEditGroup'),
                  controller: group,
                  decoration: InputDecoration(labelText: te ? 'మెనూ వర్గం (బిర్యానీ, స్టార్టర్స్, డ్రింక్స్…)' : 'Menu section (Biryani, Starters, Drinks…)')),
              if (sections.isNotEmpty)
                Wrap(spacing: 6, children: [
                  for (final g in sections) ActionChip(label: Text(g), onPressed: () => setInner(() => group.text = g)),
                ]),
              const SizedBox(height: 10),
              Text(te ? 'వెజ్ / నాన్-వెజ్' : 'Veg / non-veg', style: const TextStyle(fontWeight: FontWeight.w700)),
              Wrap(spacing: 6, children: [
                for (final f in const ['veg', 'nonveg', 'egg', ''])
                  ChoiceChip(
                    key: Key('askodoxDeskEditFood-${f.isEmpty ? 'none' : f}'),
                    label: Text(switch (f) {
                      'veg' => te ? 'వెజ్' : 'Veg',
                      'nonveg' => te ? 'నాన్-వెజ్' : 'Non-veg',
                      'egg' => te ? 'ఎగ్' : 'Egg',
                      _ => te ? 'చెప్పను' : 'Not set',
                    }),
                    selected: food == f,
                    onSelected: (_) => setInner(() => food = f),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      ),
    );
    final newName = name.text.trim();
    final rupees = double.tryParse(price.text.trim());
    final newGroup = group.text.trim();
    name.dispose();
    price.dispose();
    group.dispose();
    if (ok != true || newName.isEmpty || rupees == null || rupees < 0) return;
    await _guard(() async {
      await ref.read(askodoxPosRepositoryProvider).updateProduct(widget.businessId, '${m['id']}',
          {'name': newName, 'price_paise': (rupees * 100).round(), 'menu_group': newGroup, 'food_type': food});
      await _load();
      return null;
    });
  }

  Future<void> _deleteItem(AskodoxJson m, bool te) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? '"${m['name']}" తీసేయాలా?' : 'Remove "${m['name']}"?'),
        content: Text(te ? 'మెనూ నుంచి తొలగిస్తుంది. పాత బిల్లులు మారవు.' : 'It leaves the menu. Old bills stay as they were.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(key: const Key('askodoxDeskDeleteYes'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'తీసేయి' : 'Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(() async {
      await ref.read(askodoxPosRepositoryProvider).updateProduct(widget.businessId, '${m['id']}', {'active': false});
      await _load();
      return null;
    });
    if (!mounted) return;
    // a removed item can be brought back (owner 2026-11-17: every list has undo)
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(te ? '"${m['name']}" తీసేశాం' : '"${m['name']}" removed'),
      action: SnackBarAction(
        label: te ? 'తిరిగి తెచ్చు' : 'Undo',
        onPressed: () => unawaited(_guard(() async {
          await ref.read(askodoxPosRepositoryProvider).updateProduct(widget.businessId, '${m['id']}', {'active': true});
          await _load();
          return null;
        })),
      ),
    ));
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

  /// Sections in menu order; items without one come last.
  List<String> _sections(List<AskodoxJson> items) {
    final out = <String>[for (final g in {for (final m in items) '${m['menu_group'] ?? ''}'.trim()}) if (g.isNotEmpty) g];
    if (items.any((m) => '${m['menu_group'] ?? ''}'.trim().isEmpty)) out.add('');
    return out;
  }

  /// One compact menu line: veg mark, number, name, price, ✏ edit, ⋮ more (today only / delete), on / off switch.
  Widget _itemRow(AskodoxJson m, bool te) {
    final on = m['available'] == true;
    final food = '${m['food_type'] ?? ''}';
    final foodColor = food == 'veg' ? const Color(0xFF17784C) : (food == 'egg' ? const Color(0xFFB45309) : const Color(0xFFB91C1C));
    return Container(
      key: Key('askodoxDeskItem-${m['id']}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF0F3)))),
      child: Row(children: [
        if (food.isNotEmpty)
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(border: Border.all(color: foodColor, width: 1.5), borderRadius: BorderRadius.circular(3)),
            alignment: Alignment.center,
            child: Container(width: 7, height: 7, decoration: BoxDecoration(color: foodColor, shape: BoxShape.circle)),
          ),
        if (askodoxPosInt(m['item_no']) > 0)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text('#${m['item_no']}',
                key: Key('askodoxDeskMenuNo-${m['id']}'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF5B6475))),
          ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m['name']}',
                style: TextStyle(fontWeight: FontWeight.w700, color: on ? null : const Color(0xFF9AA1AD), decoration: on ? null : TextDecoration.lineThrough)),
            if (m['today_only_flag'] == true || !on)
              Text(
                  [
                    if (m['today_only_flag'] == true) te ? 'ఈ రోజు మాత్రమే' : 'Today only',
                    if (!on) te ? 'ఈ రోజు లేదు' : 'Out today',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFFB45309))),
          ]),
        ),
        Text(askodoxPaise(askodoxPosInt(m['price_paise'])), style: const TextStyle(fontWeight: FontWeight.w800)),
        IconButton(
          key: Key('askodoxDeskEdit-${m['id']}'),
          tooltip: te ? 'మార్చు' : 'Edit',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.edit_outlined, size: 19),
          onPressed: () => _editItem(m, te),
        ),
        PopupMenuButton<String>(
          key: Key('askodoxDeskMore-${m['id']}'),
          tooltip: te ? 'ఇంకా' : 'More',
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_vert, size: 19),
          onSelected: (v) {
            if (v == 'delete') {
              unawaited(_deleteItem(m, te));
            } else {
              unawaited(_guard(() async {
                await ref.read(askodoxPosRepositoryProvider).deskTodayOnly(widget.businessId, '${m['id']}', m['today_only_flag'] != true);
                await _load();
                return null;
              }));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
                value: 'today',
                child: Text(m['today_only_flag'] == true ? (te ? 'రోజూ ఉంచు' : 'Keep daily') : (te ? 'ఈ రోజు మాత్రమే' : 'Today only'))),
            PopupMenuItem(key: Key('askodoxDeskDelete-${m['id']}'), value: 'delete', child: Text(te ? '🗑 తీసేయి' : '🗑 Delete')),
          ],
        ),
        Switch(
          key: Key('askodoxDeskAvailable-${m['id']}'),
          value: on,
          onChanged: (v) => _guard(() async {
            await ref.read(askodoxPosRepositoryProvider).deskAvailability(widget.businessId, '${m['id']}', v);
            await _load();
            return null;
          }),
        ),
      ]),
    );
  }

  Future<void> _aiSort(bool te) async {
    setState(() => _sorting = true);
    AskodoxJson? out;
    try {
      out = await ref.read(askodoxPosRepositoryProvider).menuSort(widget.businessId);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _sorting = false);
    }
    if (out == null || !mounted) return;
    final rows = [for (final r in askodoxPosList(out['items'])) Map<String, Object?>.of(r)];
    final groups = [for (final g in (out['groups'] as List? ?? const [])) '$g'];
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.8,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                    te
                        ? 'AI ఇలా సర్దింది — ${rows.where((r) => r['changed'] == true).length} మారాయి. తప్పు ఉంటే విభాగం నొక్కి మార్చండి.'
                        : 'AI suggests this — ${rows.where((r) => r['changed'] == true).length} change. Tap a section to fix it.',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.all(12), children: [
                  for (final g in [...groups, if (rows.any((r) => !groups.contains('${r['menu_group']}'))) ''])
                    if (rows.any((r) => '${r['menu_group']}' == g)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 4),
                        child: Text(g.isEmpty ? (te ? 'విభాగం లేనివి' : 'No section') : g,
                            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF5B21B6))),
                      ),
                      for (final r in rows.where((r) => '${r['menu_group']}' == g))
                        Row(children: [
                          Expanded(
                              child: Text('${r['name']}',
                                  style: TextStyle(fontWeight: r['changed'] == true ? FontWeight.w800 : FontWeight.w500))),
                          DropdownButton<String>(
                            value: const ['veg', 'nonveg', 'egg'].contains(r['food_type']) ? '${r['food_type']}' : '',
                            underline: const SizedBox.shrink(),
                            items: [
                              const DropdownMenuItem(value: '', child: Text('—')),
                              DropdownMenuItem(value: 'veg', child: Text(te ? 'వెజ్' : 'Veg')),
                              DropdownMenuItem(value: 'nonveg', child: Text(te ? 'నాన్-వెజ్' : 'Non-veg')),
                              DropdownMenuItem(value: 'egg', child: Text(te ? 'ఎగ్' : 'Egg')),
                            ],
                            onChanged: (v) => setSheet(() => r['food_type'] = v ?? ''),
                          ),
                          const SizedBox(width: 6),
                          DropdownButton<String>(
                            value: '${r['menu_group']}',
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final x in {...groups, '${r['menu_group']}'})
                                DropdownMenuItem(value: x, child: Text(x.isEmpty ? '—' : x, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => setSheet(() => r['menu_group'] = v ?? ''),
                          ),
                        ]),
                    ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel'))),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('askodoxDeskMenuAiSave'),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(te ? 'సేవ్ చేయి' : 'Save'),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
    if (save != true || !mounted) return;
    await _guard(() async {
      final res = await ref.read(askodoxPosRepositoryProvider).menuSortApply(widget.businessId, [
        for (final r in rows) {'id': r['id'], 'menu_group': r['menu_group'] ?? '', 'food_type': r['food_type'] ?? ''},
      ]);
      await _load();
      if (mounted) askodoxPosSnack(context, te ? '${res['saved']} ఐటమ్స్ సర్దాం ✓' : 'Sorted ${res['saved']} items ✓');
      return null;
    });
  }

  Future<void> _guard(Future<Object?> Function() action) async {
    final te = askodoxPosTe(context);
    try {
      await action();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  /// The photo path has its own words: a timeout / no answer is NOT "the bill is kept on this phone" (that text is the
  /// offline sale queue's).
  Future<void> _photoGuard(Future<Object?> Function() action) async {
    final te = askodoxPosTe(context);
    try {
      await action();
    } on AskodoxPosException catch (e) {
      if (!mounted) return;
      askodoxPosSnack(
          context,
          e.retryable
              ? (te
                  ? 'మెనూ చదవడం పూర్తి కాలేదు — నెట్ బాగున్నచోట మళ్ళీ ఫోటో పంపండి, లేదా ఐటమ్స్ చెప్పండి.'
                  : 'Could not finish reading the menu — try the photo again on a better network, or say the items.')
              : e.message(te));
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

  /// A photo (or several) of the menu board / price list -> items WITH the prices printed on it, as a preview the
  /// owner edits before anything is saved (owner 2026-11-16). A price the photo does not show stays empty.
  Future<void> _photo(String source) async {
    final te = askodoxPosTe(context);
    final picked = (await ref.read(askodoxMediaPickerProvider).pick(source)).where((a) => a.isImage).toList();
    if (picked.isEmpty || !mounted) return;
    if (picked.any((a) => a.bytes.length > 4400000)) {
      askodoxPosSnack(context, te ? 'ఫోటో చాలా పెద్దది. చిన్న ఫోటో వాడండి.' : 'That photo is too large. Use a smaller one.');
      return;
    }
    setState(() => _reading = true);
    await _photoGuard(() async {
      final out = await ref.read(askodoxPosRepositoryProvider).deskMenuPhoto(widget.businessId, [
        for (final a in picked.take(4)) {'data': base64Encode(a.bytes), 'mime': a.mimeType},
      ]);
      if (!mounted) return null;
      final items = askodoxPosList(out['items']);
      setState(() {
        _preview = items;
        _gst = out['gst'] == true;
      });
      if (items.isEmpty) {
        askodoxPosSnack(context, te ? 'ఫోటో నుంచి చదవలేకపోయాను. స్పష్టమైన ఫోటో తీయండి లేదా చెప్పండి.' : 'Could not read that photo. Take a clearer one, or say the items.');
      }
      return null;
    });
    if (mounted) setState(() => _reading = false);
  }

  /// Owner 2026-11-24: one photo of a shelf / counter -> every pack on it, each with its own photo, brand, pack and the
  /// MRP printed on it; nothing is typed one by one and nothing is saved until the owner checks the preview.
  Future<void> _shelf(String source) async {
    final te = askodoxPosTe(context);
    final picked = (await ref.read(askodoxMediaPickerProvider).pick(source)).where((a) => a.isImage).toList();
    if (picked.isEmpty || !mounted) return;
    if (picked.any((a) => a.bytes.length > 4400000)) {
      askodoxPosSnack(context, te ? 'ఫోటో చాలా పెద్దది. చిన్న ఫోటో వాడండి.' : 'That photo is too large. Use a smaller one.');
      return;
    }
    setState(() => _reading = true);
    await _photoGuard(() async {
      final out = await ref.read(askodoxPosRepositoryProvider).deskMenuShelf(widget.businessId, [
        for (final a in picked.take(4)) {'data': base64Encode(a.bytes), 'mime': a.mimeType},
      ]);
      if (!mounted) return null;
      final items = askodoxPosList(out['items']);
      setState(() {
        _preview = items;
        _gst = out['gst'] == true;
      });
      if (items.isEmpty) {
        askodoxPosSnack(context, te ? 'షెల్ఫ్ ఫోటో నుంచి ఏ ప్యాకెట్ చదవలేకపోయాను. దగ్గరగా, వెలుతురులో తీయండి.' : 'Could not read any pack. Take the photo closer, in good light.');
      }
      return null;
    });
    if (mounted) setState(() => _reading = false);
  }

  /// The pack photo of a previewed item: cut out of the shelf photo, or a pack photo ASKODOX already has.
  Widget? _previewThumb(AskodoxJson m) {
    final own = '${m['photo_b64'] ?? ''}';
    if (own.isNotEmpty) {
      try {
        return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(base64Decode(own), width: 44, height: 44, fit: BoxFit.cover, gaplessPlayback: true));
      } catch (_) {
        return null;
      }
    }
    final photoRef = '${m['photo'] ?? ''}';
    return photoRef.isEmpty ? null : AskodoxMasterThumb(photoRef: photoRef);
  }

  String _previewDetails(AskodoxJson m, bool te) => [
        for (final k in ['brand', 'pack'])
          if ('${m[k] ?? ''}'.isNotEmpty) '${m[k]}',
        if (m['price_from'] == 'mrp') te ? 'ధర = ప్యాక్ మీది MRP' : 'price = MRP on the pack',
        if ('${m['credit'] ?? ''}'.isNotEmpty) '${m['credit']}',
      ].join(' · ');

  /// Fix one previewed item (name / price) before saving.
  Future<void> _editPreview(int i, bool te) async {
    final m = _preview[i];
    final price = askodoxPosInt(m['price_paise']);
    final name = TextEditingController(text: '${m['name']}');
    final rate = TextEditingController(text: price <= 0 ? '' : (price / 100).toStringAsFixed(price % 100 == 0 ? 0 : 2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'ఐటమ్ సరిచేయండి' : 'Fix this item'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('askodoxDeskPreviewName'), controller: name, decoration: InputDecoration(labelText: te ? 'పేరు' : 'Name')),
          TextField(
              key: const Key('askodoxDeskPreviewPrice'),
              controller: rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: te ? 'రేటు (₹)' : 'Price (₹)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సరే' : 'OK')),
        ],
      ),
    );
    final newName = name.text.trim();
    final rupees = double.tryParse(rate.text.trim());
    name.dispose();
    rate.dispose();
    if (ok != true || newName.isEmpty || !mounted) return;
    setState(() {
      final next = [..._preview];
      final paise = rupees == null || rupees <= 0 ? 0 : (rupees * 100).round();
      next[i] = {...m, 'name': newName, 'price_paise': paise, 'needs_price': paise <= 0};
      _preview = next;
    });
  }

  Future<void> _import() => _guard(() async {
        final te = askodoxPosTe(context);
        final ready = [for (final m in _preview) if (askodoxPosInt(m['price_paise']) > 0) m];
        final skipped = _preview.length - ready.length;
        if (ready.isEmpty) {
          askodoxPosSnack(context, te ? 'ఏ ఐటమ్ కీ రేటు లేదు. రేట్లు రాయండి.' : 'No item has a price yet. Add the prices.');
          return null;
        }
        final out = await ref.read(askodoxPosRepositoryProvider).deskMenuImport(widget.businessId, ready, rateBp: _rateBp);
        if (skipped > 0 && mounted) {
          askodoxPosSnack(context, te ? '$skipped ఐటమ్‌లకు రేటు లేదు, వదిలేశాను.' : '$skipped items had no price and were left out.');
        }
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
      bottomNavigationBar: AskodoxFillBar(
        lang: te ? 'te' : 'en',
        onFilled: () => unawaited(_parse()),
        fields: () => [AskodoxFillField('menu', te ? 'మెనూ ఐటమ్స్ ధరలతో' : 'Menu items with prices', controller: _text)],
      ),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : ListView(key: const Key('askodoxDeskMenu'), padding: const EdgeInsets.all(14), children: [
              Text(te ? 'చెప్పండి లేదా రాయండి: "మటన్ బిర్యానీ 250 ఈ రోజు మాత్రమే, చికెన్ బిర్యానీ 170, టీ 10"' : 'Say or type: "mutton biryani 250 today only, chicken biryani 170, tea 10"'),
              // Owner 2026-11-19: bulk upload -- rows copied from Excel / Google Sheets / a CSV file are read as a table.
              Text(
                  te
                      ? 'ఎక్కువ ఐటమ్స్ ఉంటే: Excel / Google Sheets నుంచి వరుసలు (పేరు, ధర, యూనిట్, కేటగిరీ) కాపీ చేసి ఇక్కడ పేస్ట్ చేయండి — ఒకేసారి 200 వరకు.'
                      : 'Many items? Copy rows (name, price, unit, category) from Excel / Google Sheets and paste here — up to 200 at once.',
                  key: const Key('askodoxDeskMenuBulkHint'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
              const SizedBox(height: 8),
              TextField(
                key: const Key('askodoxDeskMenuText'),
                controller: _text,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(border: const OutlineInputBorder(), suffixIcon: askodoxBoxMic(context, _text)),
              ),
              const SizedBox(height: 8),
              FilledButton(key: const Key('askodoxDeskMenuParse'), onPressed: _parse, child: Text(te ? 'చూపించు (ఇంకా సేవ్ కాదు)' : 'Preview (not saved yet)')),
              const SizedBox(height: 8),
              Text(te ? 'లేదా మెనూ ఫోటో తీయండి — పేర్లు, రేట్లు అన్నీ చదివి చూపిస్తాను. మీరు సరిచూసి సేవ్ చేయండి.' : 'Or photograph the menu — I read every item with its price. You check, then save.',
                  style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        key: const Key('askodoxDeskMenuPhotoCamera'),
                        onPressed: _reading ? null : () => _photo('camera'),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(te ? 'ఫోటో తీయి' : 'Take photo'))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton.icon(
                        key: const Key('askodoxDeskMenuPhotoGallery'),
                        onPressed: _reading ? null : () => _photo('photos'),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(te ? 'గ్యాలరీ నుంచి' : 'From gallery'))),
              ]),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                  key: const Key('askodoxDeskMenuShelf'),
                  onPressed: _reading ? null : () => _shelf('camera'),
                  icon: const Icon(Icons.shelves),
                  label: Text(te ? 'షెల్ఫ్ / కౌంటర్ ఫోటో — ప్యాకెట్లు అన్నీ ఫోటోలతో' : 'Shelf / counter photo — every pack with its photo')),
              if (_reading) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(key: Key('askodoxDeskMenuReading'))),
              if (_reading)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        te ? 'మెనూ చదువుతున్నాను… 10–30 సెకన్లు పడుతుంది, ఆగండి.' : 'Reading the menu… this takes 10–30 seconds.',
                        key: const Key('askodoxDeskMenuReadingText'),
                        style: const TextStyle(fontSize: 12.5))),
              if (_preview.isNotEmpty) ...[
                const Divider(height: 24),
                for (var i = 0; i < _preview.length; i++)
                  ListTile(
                    key: Key('askodoxDeskPreview-$i'),
                    contentPadding: EdgeInsets.zero,
                    leading: _previewThumb(_preview[i]),
                    onTap: () => _editPreview(i, te),
                    title: Text(askodoxPosInt(_preview[i]['price_paise']) > 0 ? '${_preview[i]['name']} · ${askodoxPaise(askodoxPosInt(_preview[i]['price_paise']))}' : '${_preview[i]['name']} · ${te ? 'రేటు రాయండి' : 'add price'}',
                        style: TextStyle(color: askodoxPosInt(_preview[i]['price_paise']) > 0 ? null : const Color(0xFFB91C1C))),
                    subtitle: Text([
                      _preview[i]['exists'] == true ? (te ? 'ఉన్నదే — ధర మారుతుంది (పాతది ${askodoxPaise(askodoxPosInt(_preview[i]['old_price_paise']))})' : 'Exists — price changes (was ${askodoxPaise(askodoxPosInt(_preview[i]['old_price_paise']))})') : (te ? 'కొత్తది' : 'New'),
                      if (_preview[i]['today_only'] == true) te ? 'ఈ రోజు మాత్రమే' : 'Today only',
                      if (_previewDetails(_preview[i], te).isNotEmpty) _previewDetails(_preview[i], te),
                    ].join(' · ')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(key: Key('askodoxDeskPreviewEdit-$i'), tooltip: te ? 'మార్చు' : 'Edit', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _editPreview(i, te)),
                      IconButton(key: Key('askodoxDeskPreviewRemove-$i'), tooltip: te ? 'తీసేయి' : 'Delete', icon: const Icon(Icons.close), onPressed: () => setState(() => _preview = [..._preview]..removeAt(i))),
                    ]),
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
              // Owner 2026-11-17: one tap -> AI reads the item names and suggests sections + veg / non-veg; nothing is
              // saved until the owner checks the preview.
              if (items.length > 1)
                Material(
                  color: const Color(0xFFF3EEFF),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    key: const Key('askodoxDeskMenuAiSort'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: _sorting ? null : () => _aiSort(te),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        const Text('✨', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(te ? 'AI తో సర్దు' : 'Sort with AI', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF5B21B6))),
                            Text(
                                te
                                    ? 'బిర్యానీలు, స్టార్టర్స్, డ్రింక్స్… విభాగాలు + వెజ్ / నాన్-వెజ్ AI సూచిస్తుంది. మీరు చూసి సేవ్ చేయండి.'
                                    : 'AI suggests sections (biryanis, starters, drinks…) + veg / non-veg. You check, then save.',
                                style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                        if (_sorting)
                          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        else
                          const Icon(Icons.chevron_right, color: Color(0xFF5B21B6)),
                      ]),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(te ? 'ఈ రోజు ఏవి ఉన్నాయి?' : 'What is available today?', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                  te
                      ? 'ఏదైనా అయిపోతే దాని స్విచ్ ఆఫ్ చేయండి — కస్టమర్ కి కనపడదు, రేపు ఉదయం ఆటోగా మళ్ళీ ఆన్ అవుతుంది.'
                      : 'When something runs out, switch it off — customers will not see it, and it comes back on by itself tomorrow.',
                  key: const Key('askodoxDeskAvailableHelp'),
                  style: const TextStyle(fontSize: 12.5)),
              for (final g in _sections(items)) ...[
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Expanded(
                        child: Text(g.isEmpty ? (te ? 'విభాగం లేనివి' : 'No section') : g,
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1E3FA0)))),
                    Text('${items.where((m) => '${m['menu_group'] ?? ''}'.trim() == g).length}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E3FA0))),
                  ]),
                ),
                for (final m in items.where((m) => '${m['menu_group'] ?? ''}'.trim() == g)) _itemRow(m, te),
              ],
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

  String _shareText(AskodoxJson d, bool te) {
    final name = '${d['name'] ?? ''}'.trim();
    final shop = name.isEmpty ? (te ? 'మా షాప్' : 'our shop') : name;
    return te
        ? '$shop లో ఇప్పుడు ASKODOX తో ఆర్డర్ చేయవచ్చు. ASKODOX యాప్ తెరిచి Profile → "Order at a shop" లో ఈ కోడ్ రాయండి: ${d['shop']}'
        : 'You can now order from $shop on ASKODOX. Open the ASKODOX app, go to Profile → "Order at a shop" and enter this code: ${d['shop']}';
  }

  /// Owner 2026-11-18: "how do I make QR codes for dine-in tables?" -- say how many tables; T1..Tn are made (names
  /// already there are kept) and each gets its own QR below. Scanning a table's QR opens the menu as dine-in.
  Future<void> _addTables(bool te) async {
    final count = TextEditingController(text: '5');
    final n = await showDialog<int>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text(te ? 'ఎన్ని టేబుల్స్ ఉన్నాయి?' : 'How many tables?'),
              content: TextField(
                  key: const Key('askodoxDeskTablesCount'),
                  controller: count,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(helperText: te ? 'T1, T2 ... గా పేర్లు వస్తాయి' : 'Named T1, T2 ...')),
              actions: [
                TextButton(onPressed: () => Navigator.of(c).pop(), child: Text(te ? 'వద్దు' : 'Cancel')),
                FilledButton(
                    key: const Key('askodoxDeskTablesMake'),
                    onPressed: () => Navigator.of(c).pop(int.tryParse(count.text.trim())),
                    child: Text(te ? 'QR లు చేయి' : 'Make QRs')),
              ],
            ));
    if (n == null || n < 1) return;
    final repo = ref.read(askodoxPosRepositoryProvider);
    final have = {for (final t in askodoxPosList(_data?['tables'])) '${t['name']}'.trim().toLowerCase()};
    try {
      for (var i = 1; i <= n.clamp(1, 60); i++) {
        if (!have.contains('t$i')) await repo.addTable(widget.businessId, 'T$i');
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
    await _load();
  }

  Widget _qr(String title, String code) {
    final te = askodoxPosTe(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          AskodoxQrPoster(
            data: code,
            te: te,
            title: '${_data?['shop'] ?? _data?['name'] ?? ''}',
            label: title,
            size: 180,
            fileName: 'askodox-qr-${title.replaceAll(RegExp(r'\s+'), '-')}',
            instructionEn: 'Scan with ASKODOX to see the menu and order',
            instructionTe: 'ASKODOX తో స్కాన్ చేసి మెనూ చూడండి, ఆర్డర్ చేయండి',
          ),
          const SizedBox(height: 6),
          SelectableText(code, style: const TextStyle(fontSize: 11)),
        ]),
      ),
    );
  }

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
                  // A message the owner sends to customers (WhatsApp, SMS ...): they open ASKODOX and type this code,
                  // no QR needed (owner 2026-11-16).
                  Card(
                    key: const Key('askodoxDeskShare'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(te ? 'కస్టమర్లకు పంపండి' : 'Send to your customers', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(_shareText(d, te), style: const TextStyle(fontSize: 12.5)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          FilledButton.icon(
                              key: const Key('askodoxDeskShareWhatsApp'),
                              onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareText(d, te))}'), mode: LaunchMode.externalApplication),
                              icon: const Icon(Icons.send),
                              label: const Text('WhatsApp')),
                          OutlinedButton.icon(
                              key: const Key('askodoxDeskShareCopy'),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: _shareText(d, te)));
                                if (context.mounted) askodoxPosSnack(context, te ? 'కాపీ అయింది' : 'Copied');
                              },
                              icon: const Icon(Icons.copy),
                              label: Text(te ? 'కాపీ' : 'Copy')),
                        ]),
                      ]),
                    ),
                  ),
                  _qr(te ? 'షాప్ (పార్సిల్ / డెలివరీ)' : 'Shop (takeaway / delivery)', '${d['shop']}'),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(
                          te
                              ? 'టేబుల్ మీద కూర్చుని తినేవారికి (dine-in): ప్రతి టేబుల్‌కి వేరే QR. స్కాన్ చేస్తే ఆ టేబుల్ పేరుతో ఆర్డర్ వస్తుంది.'
                              : 'Dine-in: every table has its own QR. Scanning it orders for that table.',
                          style: const TextStyle(fontSize: 12.5)),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                          key: const Key('askodoxDeskAddTables'),
                          onPressed: () => _addTables(te),
                          icon: const Icon(Icons.table_restaurant_outlined),
                          label: Text(askodoxPosList(d['tables']).isEmpty
                              ? (te ? '+ టేబుల్ QR లు చేయి' : '+ Make table QRs')
                              : (te ? '+ ఇంకా టేబుల్స్' : '+ More tables'))),
                    ]),
                  ),
                  for (final t in askodoxPosList(d['tables'])) _qr(te ? 'టేబుల్ ${t['name']}' : 'Table ${t['name']}', '${t['code']}'),
                ]),
    );
  }
}


/// A shared pack photo (`p:<id>` / `m:<barcode>`) fetched once and kept for the screen's life.
class AskodoxMasterThumb extends ConsumerStatefulWidget {
  const AskodoxMasterThumb({super.key, required this.photoRef});
  final String photoRef;

  @override
  ConsumerState<AskodoxMasterThumb> createState() => _AskodoxMasterThumbState();
}

final Map<String, Future<Uint8List?>> _askodoxMasterPhotos = {};

class _AskodoxMasterThumbState extends ConsumerState<AskodoxMasterThumb> {
  late final Future<Uint8List?> _bytes = _askodoxMasterPhotos.putIfAbsent(widget.photoRef, () async {
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).masterPhoto(widget.photoRef);
      final data = '${out['image_base64'] ?? ''}';
      return data.isEmpty ? null : base64Decode(data);
    } catch (_) {
      return null;
    }
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: FutureBuilder<Uint8List?>(
          future: _bytes,
          builder: (context, snap) => snap.data == null
              ? const Icon(Icons.inventory_2_outlined, color: Color(0xFF94A3B8))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(snap.data!, width: 44, height: 44, fit: BoxFit.cover)),
        ),
      );
}
