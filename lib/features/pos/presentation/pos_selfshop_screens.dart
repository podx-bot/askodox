import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../home/application/conversation_archive.dart';
import '../data/pos_hardware.dart';
import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import 'pos_common.dart';
import 'pos_sale_screen.dart' show AskodoxPosPaymentSheet;

String _itemName(AskodoxJson item, bool te) =>
    te && '${item['name_te'] ?? ''}'.isNotEmpty ? '${item['name_te']}' : '${item['name'] ?? ''}';

String _qtyText(AskodoxJson item) => '${askodoxQty(askodoxPosInt(item['qty_milli']), '')} ${item['unit'] ?? ''}'.trim();

// =============================================================== staff: settings + entry code
class AskodoxPosSelfShopScreen extends ConsumerStatefulWidget {
  const AskodoxPosSelfShopScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosSelfShopScreen> createState() => _AskodoxPosSelfShopScreenState();
}

class _AskodoxPosSelfShopScreenState extends ConsumerState<AskodoxPosSelfShopScreen> {
  AskodoxJson? _data;
  Object? _error;
  bool _busy = false;
  final _exit = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(askodoxPosRepositoryProvider).selfShopSettings(widget.businessId);
      if (mounted) setState(() => (_data, _error) = (data, null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggle(bool on) async {
    final te = askodoxPosTe(context);
    setState(() => _busy = true);
    try {
      final data = await ref
          .read(askodoxPosRepositoryProvider)
          .setSelfShop(widget.businessId, enabled: on, minutes: askodoxPosInt(_data?['minutes'] ?? 90));
      if (mounted) setState(() => _data = data);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openExit() async {
    final te = askodoxPosTe(context);
    final code = _exit.text.trim();
    if (code.length != 4) {
      askodoxPosSnack(context, te ? 'కస్టమర్ ఫోన్‌లో ఉన్న 4 అంకెల ఎగ్జిట్ కోడ్ రాయండి.' : "Type the 4-digit exit code on the customer's phone.");
      return;
    }
    try {
      final session = await ref.read(askodoxPosRepositoryProvider).selfShopByExitCode(widget.businessId, code);
      if (!mounted) return;
      _exit.clear();
      await context.push('/pos/${widget.businessId}/selfshop/${session['id']}');
      if (mounted) await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final d = _data;
    final enabled = d?['enabled'] == true;
    final sessions = askodoxPosList(d?['sessions']);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'సెల్ఫ్ షాపింగ్' : 'Self-shopping')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(key: const Key('askodoxPosSelfShop'), padding: const EdgeInsets.all(14), children: [
                    SwitchListTile(
                      key: const Key('askodoxPosSelfShopEnabled'),
                      contentPadding: EdgeInsets.zero,
                      value: enabled,
                      onChanged: _busy ? null : _toggle,
                      title: Text(te ? 'కస్టమర్లు తమ ఫోన్‌తో స్కాన్ చేసి కొనొచ్చు' : 'Customers scan items with their own phone'),
                      subtitle: Text(te
                          ? 'బరువుతో అమ్మేవి, IMEI / సీరియల్ ఉన్నవి కౌంటర్‌లోనే. డబ్బు కౌంటర్‌లోనే తీసుకుంటారు.'
                          : 'Items sold by weight or with an IMEI / serial stay at the counter. Payment is taken at the counter.'),
                    ),
                    if (enabled && d['code'] != null) ...[
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(children: [
                            Text(te ? 'ఈ రోజు ప్రవేశ కోడ్ (ద్వారం దగ్గర చూపించండి)' : "Today's entry code (show it at the entrance)",
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            QrImageView(key: const Key('askodoxPosSelfShopQr'), data: '${d['qr']}', size: 190),
                            Text('${d['code']}',
                                key: const Key('askodoxPosSelfShopCode'),
                                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 6)),
                            Text(te ? 'రేపు కొత్త కోడ్ వస్తుంది.' : 'A new code comes every day.', style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: AskodoxPosField(
                          key: const Key('askodoxPosSelfShopExit'),
                          controller: _exit,
                          number: true,
                          decimal: false,
                          maxLength: 4,
                          label: te ? 'ఎగ్జిట్ కోడ్ (కస్టమర్ ఫోన్‌లో)' : "Exit code (on the customer's phone)",
                          guideEn: 'When a customer taps Checkout, their phone shows a 4-digit exit code. Type it to open their list.',
                          guideTe: 'కస్టమర్ "చెకౌట్" నొక్కితే వారి ఫోన్‌లో 4 అంకెల ఎగ్జిట్ కోడ్ వస్తుంది. వారి లిస్ట్ తెరవడానికి అది రాయండి.',
                          exampleEn: '4821',
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(key: const Key('askodoxPosSelfShopExitGo'), onPressed: _openExit, child: Text(te ? 'తెరువు' : 'Open')),
                    ]),
                    const SizedBox(height: 8),
                    Text(te ? 'షాప్‌లో ఇప్పుడు ఉన్న లిస్టులు' : 'Lists in the shop now', style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (sessions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(te ? 'ఇప్పుడు ఎవరూ స్కాన్ చేయడం లేదు.' : 'Nobody is scanning right now.'),
                      ),
                    for (final s in sessions)
                      ListTile(
                        key: ValueKey('askodoxPosSelfShopSession-${s['id']}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(s['status'] == 'CHECKOUT' ? Icons.how_to_reg_outlined : Icons.shopping_cart_outlined),
                        title: Text('${te ? 'కస్టమర్' : 'Customer'} …${s['customer']} · ${s['items']} ${te ? 'రకాలు' : 'kinds'}'),
                        subtitle: Text(s['status'] == 'CHECKOUT'
                            ? '${te ? 'చెకౌట్ — ఎగ్జిట్ కోడ్' : 'At checkout — exit code'} ${s['exit_code']}'
                            : (te ? 'ఇంకా షాపింగ్ చేస్తున్నారు' : 'Still shopping')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await context.push('/pos/${widget.businessId}/selfshop/${s['id']}');
                          if (mounted) await _load();
                        },
                      ),
                  ]),
                ),
    );
  }
}

// =============================================================== staff: exit check + bill
class AskodoxPosSelfShopCheckScreen extends ConsumerStatefulWidget {
  const AskodoxPosSelfShopCheckScreen({super.key, required this.businessId, required this.sessionId});
  final String businessId;
  final String sessionId;

  @override
  ConsumerState<AskodoxPosSelfShopCheckScreen> createState() => _AskodoxPosSelfShopCheckScreenState();
}

class _AskodoxPosSelfShopCheckScreenState extends ConsumerState<AskodoxPosSelfShopCheckScreen> {
  AskodoxJson? _session;
  AskodoxJson? _check;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(askodoxPosRepositoryProvider).selfShopSession(widget.businessId, widget.sessionId);
      if (mounted) setState(() => (_session, _error) = (s, null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _photo() async {
    final te = askodoxPosTe(context);
    List<String>? codes;
    try {
      codes = await ref.read(askodoxMultiBarcodeScannerProvider).scanAll(context);
    } on AskodoxScanException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (codes == null || !mounted) return;
    if (codes.isEmpty) {
      askodoxPosSnack(
          context,
          te
              ? 'ఫోటోలో ఒక్క బార్‌కోడ్ కూడా కనబడలేదు. బార్‌కోడ్‌లు పైకి కనిపించేలా పెట్టి, వెలుతురులో మళ్ళీ తీయండి.'
              : 'No barcode was found. Lay the items with barcodes facing up and take it again in good light.');
      return;
    }
    setState(() => _busy = true);
    try {
      final check = await ref.read(askodoxPosRepositoryProvider).selfShopVerify(widget.businessId, widget.sessionId, codes);
      if (mounted) setState(() => _check = check);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(AskodoxJson item) async {
    final te = askodoxPosTe(context);
    try {
      final s = await ref
          .read(askodoxPosRepositoryProvider)
          .selfShopStaffQty(widget.businessId, widget.sessionId, '${item['product_id']}', '${item['pack'] ?? ''}', 0);
      if (mounted) setState(() => (_session, _check) = (s, null));
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _bill() async {
    final te = askodoxPosTe(context);
    final total = askodoxPosInt(_session?['total_paise']);
    final payments = await showModalBottomSheet<List<AskodoxJson>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AskodoxPosPaymentSheet(total: total, allowCredit: false, te: te),
    );
    if (payments == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).selfShopBill(widget.businessId, widget.sessionId, payments);
      if (!mounted) return;
      final invoice = askodoxPosMap(out['invoice']);
      context.go('/pos/${widget.businessId}/invoice/${invoice['id']}');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _section(String key, String title, Color color, List<AskodoxJson> rows, bool te) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      key: Key(key),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title (${rows.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
        for (final r in rows)
          Text('• ${r['name'] ?? (te ? 'ఈ షాప్‌లో లేని బార్‌కోడ్' : 'barcode not in this shop')}'
              '${'${r['pack'] ?? ''}'.isEmpty ? '' : ' (${r['pack']})'}'
              '${r['qty_milli'] == null ? '' : ' × ${askodoxQty(askodoxPosInt(r['qty_milli']), '')}'}'
              '${r['barcode'] == null ? '' : ' · ${r['barcode']}'}'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final s = _session;
    final items = askodoxPosList(s?['items']);
    final check = _check;
    final open = s != null && (s['status'] == 'CHECKOUT' || s['status'] == 'OPEN');
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఎగ్జిట్ చెక్' : 'Exit check')),
      bottomNavigationBar: s == null || s['status'] != 'CHECKOUT'
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  key: const Key('askodoxPosSelfShopBill'),
                  onPressed: _busy || items.isEmpty ? null : _bill,
                  icon: const Icon(Icons.payments_outlined),
                  label: Text('${te ? 'బిల్లు & చెల్లింపు' : 'Bill & take payment'} ${askodoxPaise(askodoxPosInt(s['total_paise']))}'),
                ),
              ),
            ),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : s == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(key: const Key('askodoxPosSelfShopCheck'), padding: const EdgeInsets.all(14), children: [
                  Text('${te ? 'కస్టమర్' : 'Customer'} …${s['customer']} · ${s['status']}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (s['status'] == 'OPEN')
                    Text(te ? 'కస్టమర్ ఇంకా "చెకౌట్" నొక్కలేదు.' : 'The customer has not tapped Checkout yet.'),
                  const SizedBox(height: 8),
                  for (final item in items)
                    ListTile(
                      key: ValueKey('askodoxPosSelfShopItem-${item['product_id']}-${item['pack']}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_itemName(item, te)),
                      subtitle: Text('${_qtyText(item)} × ${askodoxPaise(askodoxPosInt(item['unit_price_paise']))}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(askodoxPaise(askodoxPosInt(item['total_paise']))),
                        if (open)
                          IconButton(
                            key: ValueKey('askodoxPosSelfShopRemove-${item['product_id']}-${item['pack']}'),
                            tooltip: te ? 'లిస్ట్ నుండి తీసేయి' : 'Remove from the list',
                            onPressed: () => _remove(item),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                      ]),
                    ),
                  const Divider(),
                  Text('${te ? 'మొత్తం (అంచనా)' : 'Total (preview)'} ${askodoxPaise(askodoxPosInt(s['total_paise']))}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  if (open)
                    OutlinedButton.icon(
                      key: const Key('askodoxPosSelfShopPhoto'),
                      onPressed: _busy ? null : _photo,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(te ? 'అన్ని సరుకుల ఒకే ఫోటో (బార్‌కోడ్‌లు పైకి)' : 'One photo of all items (barcodes up)'),
                    ),
                  if (check != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      key: const Key('askodoxPosSelfShopResult'),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: check['all_clear'] == true ? const Color(0xFFDCFCE7) : const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(check['all_clear'] == true
                          ? (te ? 'లిస్ట్‌లోని ప్రతి రకం ఫోటోలో కనబడింది.' : 'Every kind of item on the list was seen in the photo.')
                          : (te ? 'కొన్ని తేడాలు ఉన్నాయి — కింద చూడండి.' : 'Some differences — see below.')),
                    ),
                    _section('askodoxPosSelfShopMatched', te ? 'సరిపోయాయి' : 'Matched', const Color(0xFFF0FDF4),
                        askodoxPosList(check['matched']), te),
                    _section('askodoxPosSelfShopNotSeen', te ? 'ఫోటోలో కనబడలేదు — చేతితో చూడండి' : 'Not seen — check by hand',
                        const Color(0xFFFEF3C7), askodoxPosList(check['not_seen']), te),
                    _section('askodoxPosSelfShopNotBilled', te ? 'లిస్ట్‌లో లేవు (బిల్ కాలేదు)' : 'Not on the list (not billed)',
                        const Color(0xFFFEE2E2), askodoxPosList(check['not_billed']), te),
                    _section('askodoxPosSelfShopCount', te ? 'ఒకటి కంటే ఎక్కువ — లెక్క చేతితో' : 'More than one — count by hand',
                        const Color(0xFFEFF6FF), askodoxPosList(check['count_by_hand']), te),
                    const SizedBox(height: 6),
                    Text(
                        te
                            ? 'ఒక ఫోటోలో ఒకే బార్‌కోడ్ ఉన్న ప్యాకెట్లు ఒకటిగానే కనబడతాయి. లేని వాటిని కౌంటర్‌లో కొత్త బిల్లులో వేయండి.'
                            : 'Packets with the same barcode show once in a photo. Bill anything extra on a new counter bill.',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ]),
    );
  }
}

// =============================================================== customer: scan & go
class AskodoxSelfShopScreen extends ConsumerStatefulWidget {
  const AskodoxSelfShopScreen({super.key});

  @override
  ConsumerState<AskodoxSelfShopScreen> createState() => _AskodoxSelfShopScreenState();
}

class _AskodoxSelfShopScreenState extends ConsumerState<AskodoxSelfShopScreen> {
  AskodoxJson? _session;
  bool _loading = true;
  bool _busy = false;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _resume();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    try {
      final mine = await ref.read(askodoxPosRepositoryProvider).selfShopMine();
      final live = askodoxPosList(mine['sessions']).where((s) => s['status'] == 'OPEN' || s['status'] == 'CHECKOUT');
      if (mounted) setState(() => _session = live.firstOrNull);
    } catch (_) {
      // Not signed in / offline: the join form explains what is needed.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<AskodoxJson> Function(AskodoxPosRepository repo) call) async {
    final te = askodoxPosTe(context);
    setState(() => _busy = true);
    try {
      final out = await call(ref.read(askodoxPosRepositoryProvider));
      if (mounted) setState(() => _session = out);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join([String? text]) => _run((repo) => repo.selfShopJoin(text ?? _code.text.trim()));

  Future<String?> _scanOne() async {
    final te = askodoxPosTe(context);
    try {
      return await ref.read(askodoxBarcodeScannerProvider).scan(context);
    } on AskodoxScanException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return null;
    }
  }

  Future<void> _scanEntry() async {
    final code = await _scanOne();
    if (code != null && mounted) await _join(code);
  }

  Future<void> _scanItem() async {
    final te = askodoxPosTe(context);
    final sid = '${_session?['id']}';
    final code = await _scanOne();
    if (code == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).selfShopScan(sid, code);
      if (!mounted) return;
      setState(() => _session = askodoxPosMap(out['session']));
      final item = askodoxPosMap(out['item']);
      if (out['added'] == true) {
        askodoxPosSnack(context, '${te ? 'జోడించాం' : 'Added'}: ${_itemName(item, te)} · ${askodoxPaise(askodoxPosInt(item['price_paise']))}');
      } else {
        await _explain(item,
            reason: out['reason'] == 'weigh_at_counter'
                ? (te ? 'ఇది బరువుతో అమ్మేది — కౌంటర్‌లో తూకం వేసి బిల్ చేస్తారు.' : 'This is sold by weight — the counter weighs and bills it.')
                : (te ? 'దీనికి IMEI / సీరియల్ ఉంది — కౌంటర్‌లో బిల్ చేస్తారు.' : 'This has an IMEI / serial — the counter bills it.'));
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// What the shop itself says about an item (its own details), plus "Ask ASKODOX" for anything more.
  Future<void> _explain(AskodoxJson item, {String? reason}) async {
    final te = askodoxPosTe(context);
    final attributes = askodoxPosMap(item['attributes']);
    final name = _itemName(item, te);
    final facts = [for (final e in attributes.entries) if ('${e.value}'.isNotEmpty) '${e.key}: ${e.value}'];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          key: const Key('askodoxSelfShopItemInfo'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (item['price_paise'] != null) Text('${askodoxPaise(askodoxPosInt(item['price_paise']))} / ${item['unit'] ?? ''}'),
            if (reason != null) ...[const SizedBox(height: 8), Text(reason, style: const TextStyle(color: Color(0xFFB45309)))],
            const SizedBox(height: 8),
            if (facts.isEmpty)
              Text(te ? 'షాప్ ఈ సరుకుకి ఇంకా వివరాలు పెట్టలేదు.' : 'The shop has not added details for this item yet.')
            else
              for (final f in facts) Text('• $f'),
            const SizedBox(height: 10),
            Row(children: [
              TextButton.icon(
                key: const Key('askodoxSelfShopAsk'),
                onPressed: () {
                  Navigator.pop(ctx);
                  ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(te
                      ? '$name గురించి చెప్పండి${facts.isEmpty ? '' : ' (షాప్ వివరాలు: ${facts.join('; ')})'}. ఇది నాకు సరిపోతుందా?'
                      : 'Tell me about $name${facts.isEmpty ? '' : ' (shop details: ${facts.join('; ')})'}. Is it right for me?');
                  context.go('/');
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(te ? 'ASKODOX ని అడగండి' : 'Ask ASKODOX'),
              ),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'సరే' : 'OK')),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _joinForm(bool te) => ListView(key: const Key('askodoxSelfShopJoin'), padding: const EdgeInsets.all(16), children: [
        Text(te ? 'షాప్‌లో మీ ఫోన్‌తో స్కాన్ చేసి కొనండి' : 'Shop by scanning with your phone',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(te
            ? 'షాప్ ద్వారం దగ్గర ఉన్న QR ఫోటో తీయండి, లేదా 6 అంకెల కోడ్ రాయండి. డబ్బు కౌంటర్‌లోనే ఇస్తారు.'
            : 'Take a photo of the QR at the shop entrance, or type its 6-digit code. You pay at the counter.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('askodoxSelfShopScanQr'),
          onPressed: _busy ? null : _scanEntry,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(te ? 'QR ఫోటో తీయండి' : 'Photo of the QR'),
        ),
        const SizedBox(height: 10),
        AskodoxPosField(
          key: const Key('askodoxSelfShopCode'),
          controller: _code,
          number: true,
          decimal: false,
          maxLength: 6,
          label: te ? 'షాప్ కోడ్ (6 అంకెలు)' : 'Shop code (6 digits)',
          guideEn: 'The 6-digit code shown at the shop entrance or on the counter screen. It changes every day.',
          guideTe: 'షాప్ ద్వారం దగ్గర / కౌంటర్ స్క్రీన్‌పై ఉండే 6 అంకెల కోడ్. రోజూ మారుతుంది.',
          exampleEn: '483920',
        ),
        FilledButton(key: const Key('askodoxSelfShopJoinGo'), onPressed: _busy ? null : () => _join(), child: Text(te ? 'మొదలుపెట్టు' : 'Start')),
      ]);

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final s = _session;
    final items = askodoxPosList(s?['items']);
    final status = '${s?['status'] ?? ''}';
    return Scaffold(
      appBar: AppBar(title: Text(s == null ? (te ? 'స్కాన్ చేసి కొనండి' : 'Scan & shop') : '${s['shop']}')),
      bottomNavigationBar: s == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: status == 'CHECKOUT'
                    ? OutlinedButton(
                        key: const Key('askodoxSelfShopReopen'),
                        onPressed: _busy ? null : () => _run((repo) => repo.selfShopReopen('${s['id']}')),
                        child: Text(te ? 'ఇంకా సరుకులు వేయాలి' : 'Add more items'),
                      )
                    : Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('askodoxSelfShopScanItem'),
                            onPressed: _busy || status != 'OPEN' ? null : _scanItem,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: Text(te ? 'బార్‌కోడ్ స్కాన్' : 'Scan barcode'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          key: const Key('askodoxSelfShopCheckout'),
                          onPressed: _busy || items.isEmpty || status != 'OPEN'
                              ? null
                              : () => _run((repo) => repo.selfShopCheckout('${s['id']}')),
                          child: Text(te ? 'చెకౌట్' : 'Checkout'),
                        ),
                      ]),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : s == null
              ? _joinForm(te)
              : ListView(key: const Key('askodoxSelfShopList'), padding: const EdgeInsets.all(14), children: [
                  if (status == 'CHECKOUT')
                    Container(
                      key: const Key('askodoxSelfShopExitCode'),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12)),
                      child: Column(children: [
                        Text(te ? 'కౌంటర్‌లో ఈ కోడ్ చూపించండి' : 'Show this code at the counter'),
                        Text('${s['exit_code']}', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 8)),
                        Text(te
                            ? 'సిబ్బంది మీ సరుకుల ఒక ఫోటో తీసి సరిచూస్తారు. తర్వాత కౌంటర్‌లో డబ్బు ఇవ్వండి.'
                            : 'Staff take one photo of your items to check them. Then pay at the counter.'),
                      ]),
                    ),
                  if (status == 'EXPIRED' || status == 'CANCELLED' || status == 'BILLED')
                    Text(status == 'BILLED'
                        ? (te ? 'బిల్లు అయింది. ధన్యవాదాలు!' : 'Billed. Thank you!')
                        : (te ? 'ఈ లిస్ట్ ముగిసింది.' : 'This list has ended.')),
                  if (items.isEmpty && status == 'OPEN')
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(te
                          ? 'సరుకు తీసుకుని దాని బార్‌కోడ్ ఫోటో తీయండి ("బార్‌కోడ్ స్కాన్").'
                          : 'Pick an item and photograph its barcode ("Scan barcode").'),
                    ),
                  for (final item in items)
                    ListTile(
                      key: ValueKey('askodoxSelfShopItem-${item['product_id']}-${item['pack']}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(_itemName(item, te)),
                      subtitle: Text('${_qtyText(item)} × ${askodoxPaise(askodoxPosInt(item['unit_price_paise']))}'),
                      onTap: () => _explain(_itemDetails(item)),
                      trailing: status != 'OPEN'
                          ? Text(askodoxPaise(askodoxPosInt(item['total_paise'])))
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                key: ValueKey('askodoxSelfShopLess-${item['product_id']}-${item['pack']}'),
                                onPressed: _busy
                                    ? null
                                    : () => _run((repo) => repo.selfShopQty('${s['id']}', '${item['product_id']}',
                                        '${item['pack'] ?? ''}', askodoxPosInt(item['qty_milli']) - 1000)),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              IconButton(
                                key: ValueKey('askodoxSelfShopMore-${item['product_id']}-${item['pack']}'),
                                onPressed: _busy
                                    ? null
                                    : () => _run((repo) => repo.selfShopQty('${s['id']}', '${item['product_id']}',
                                        '${item['pack'] ?? ''}', askodoxPosInt(item['qty_milli']) + 1000)),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ]),
                    ),
                  if (items.isNotEmpty) ...[
                    const Divider(),
                    Text('${te ? 'మొత్తం' : 'Total'} ${askodoxPaise(askodoxPosInt(s['total_paise']))}',
                        key: const Key('askodoxSelfShopTotal'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    Text(te
                        ? 'ఇది అంచనా. కౌంటర్‌లో వచ్చే బిల్లే అంతిమం. డబ్బు కౌంటర్‌లోనే.'
                        : 'A preview. The counter bill is final. You pay at the counter.',
                        style: const TextStyle(fontSize: 12)),
                  ],
                  if (status == 'OPEN' || status == 'CHECKOUT')
                    TextButton(
                      key: const Key('askodoxSelfShopCancel'),
                      onPressed: _busy ? null : () => _run((repo) => repo.selfShopCancel('${s['id']}')),
                      child: Text(te ? 'షాపింగ్ రద్దు' : 'Cancel this list'),
                    ),
                  if (status == 'EXPIRED' || status == 'CANCELLED' || status == 'BILLED')
                    FilledButton(
                      key: const Key('askodoxSelfShopNew'),
                      onPressed: () => setState(() => _session = null),
                      child: Text(te ? 'కొత్త షాపింగ్' : 'Start again'),
                    ),
                ]),
    );
  }

  /// The list row carries the shop's own details for the item.
  AskodoxJson _itemDetails(AskodoxJson item) => {
        'name': item['name'],
        'name_te': item['name_te'],
        'price_paise': item['unit_price_paise'],
        'unit': item['unit'],
        'attributes': item['attributes'] ?? const <String, Object?>{},
      };
}
