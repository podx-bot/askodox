import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/qr_poster.dart';
import '../../home/application/conversation_archive.dart';
import '../../pos/data/pos_hardware.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_sale_screen.dart' show AskodoxPosPaymentSheet, AskodoxPosPayResult;
import 'step_kit.dart';

String _name(AskodoxJson item, bool te) =>
    te && '${item['name_te'] ?? ''}'.isNotEmpty ? '${item['name_te']}' : '${item['name'] ?? ''}';

String _qty(AskodoxJson item) => '${askodoxQty(askodoxPosInt(item['qty_milli']), '')} ${item['unit'] ?? ''}'.trim();

String _line(AskodoxJson item) => '${_qty(item)} × ${askodoxPaise(askodoxPosInt(item['unit_price_paise']))}';

/// Owner 2026-11-25 (3-step design, batch 37): the shop's self-shopping page `/pos/:id/selfshop`.
/// Top = ONE big number (today's entry code), middle = ONE list (the lists in the shop now, tap = exit check),
/// bottom = ONE big button (type the customer's exit code; "Turn on" while it is off). The entrance QR poster, turning
/// it off and the old page live in ⋮. Old page stays at `?full=1`.
class AskodoxSelfShopOwnerStepsScreen extends ConsumerStatefulWidget {
  const AskodoxSelfShopOwnerStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxSelfShopOwnerStepsScreen> createState() => _SelfShopOwnerStepsState();
}

class _SelfShopOwnerStepsState extends ConsumerState<AskodoxSelfShopOwnerStepsScreen> {
  AskodoxJson? _data;
  Object? _error;
  bool _busy = false;
  final _exit = TextEditingController();

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

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
      final data = await _repo.selfShopSettings(widget.businessId);
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggle(bool on) async {
    final te = _te;
    setState(() => _busy = true);
    try {
      final data = await _repo.setSelfShop(widget.businessId, enabled: on, minutes: askodoxPosInt(_data?['minutes'] ?? 90));
      if (mounted) setState(() => _data = data);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSession(String sid) async {
    await context.push('/pos/${widget.businessId}/selfshop/$sid');
    if (mounted) await _load();
  }

  Future<void> _askExit() async {
    final te = _te;
    _exit.clear();
    final code = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? 'ఎగ్జిట్ కోడ్' : 'Exit code'),
        content: TextField(
          key: const Key('askodoxSelfShopOwnerStepsExit'),
          controller: _exit,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 6),
          decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: te ? 'కస్టమర్ ఫోన్‌లో ఉన్న 4 అంకెలు' : "The 4 digits on the customer's phone"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxSelfShopOwnerStepsExitGo'),
              onPressed: () => Navigator.pop(d, _exit.text.trim()),
              child: Text(te ? 'తెరువు' : 'Open')),
        ],
      ),
    );
    if (code == null || !mounted) return;
    if (code.length != 4) {
      askodoxPosSnack(context, te ? 'కస్టమర్ ఫోన్‌లో ఉన్న 4 అంకెల ఎగ్జిట్ కోడ్ రాయండి.' : "Type the 4-digit exit code on the customer's phone.");
      return;
    }
    try {
      final session = await _repo.selfShopByExitCode(widget.businessId, code);
      if (mounted) await _openSession('${session['id']}');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  void _poster() {
    final te = _te;
    final d = _data ?? const <String, Object?>{};
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(te ? 'ద్వారం దగ్గర చూపించండి' : 'Show it at the entrance',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            AskodoxQrPoster(
              qrKey: const Key('askodoxSelfShopOwnerStepsQr'),
              data: '${d['qr']}',
              te: te,
              title: '${d['shop'] ?? d['name'] ?? ''}',
              size: 190,
              fileName: 'askodox-entry-code',
              instructionEn: 'Scan with ASKODOX to start self-shopping',
              instructionTe: 'ASKODOX తో స్కాన్ చేసి సెల్ఫ్ షాపింగ్ మొదలుపెట్టండి',
            ),
            Text(te ? 'రేపు కొత్త కోడ్ వస్తుంది.' : 'A new code comes every day.', style: const TextStyle(fontSize: 13)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final d = _data;
    final enabled = d?['enabled'] == true;
    final sessions = askodoxPosList(d?['sessions']);
    return AskodoxStepScaffold(
      key: const Key('askodoxSelfShopOwnerSteps'),
      title: te ? 'సెల్ఫ్ షాపింగ్' : 'Self-shopping',
      more: [
        if (enabled && d?['qr'] != null)
          AskodoxStepMore('askodoxSelfShopOwnerStepsPoster', te ? 'ద్వారం QR పోస్టర్' : 'Entrance QR poster', Icons.qr_code_2_rounded, _poster),
        if (enabled)
          AskodoxStepMore('askodoxSelfShopOwnerStepsOff', te ? 'సెల్ఫ్ షాపింగ్ ఆఫ్ చేయి' : 'Turn self-shopping off',
              Icons.power_settings_new_rounded, () => _toggle(false)),
        AskodoxStepMore('askodoxSelfShopOwnerStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/selfshop?full=1')),
      ],
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                    if (enabled && d['code'] != null)
                      AskodoxStepBigNumber('${d['code']}',
                          key: const Key('askodoxSelfShopOwnerStepsCode'),
                          label: te ? 'ఈ రోజు ప్రవేశ కోడ్ · ద్వారం దగ్గర చూపించండి' : "Today's entry code · show it at the entrance",
                          color: askodoxStepGreen)
                    else
                      AskodoxStepBigNumber(te ? 'ఆఫ్' : 'Off',
                          key: const Key('askodoxSelfShopOwnerStepsCode'),
                          label: te
                              ? 'ఆన్ చేస్తే కస్టమర్లు తమ ఫోన్‌తో స్కాన్ చేసి కొంటారు. డబ్బు కౌంటర్‌లోనే.'
                              : 'Turn it on and customers scan items with their own phone. Payment stays at the counter.',
                          color: askodoxStepMuted),
                    const SizedBox(height: 12),
                    if (enabled)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(te ? 'షాప్‌లో ఇప్పుడు ఉన్న లిస్టులు' : 'Lists in the shop now',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    if (enabled && sessions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(te ? 'ఇప్పుడు ఎవరూ స్కాన్ చేయడం లేదు.' : 'Nobody is scanning right now.',
                            style: const TextStyle(fontSize: 15, color: askodoxStepMuted)),
                      ),
                    for (final s in sessions)
                      AskodoxStepPersonRow(
                        key: ValueKey('askodoxSelfShopOwnerStepsSession-${s['id']}'),
                        name: '${te ? 'కస్టమర్' : 'Customer'} …${s['customer']}',
                        sub: s['status'] == 'CHECKOUT'
                            ? '${s['items']} ${te ? 'రకాలు · చెకౌట్ దగ్గర' : 'kinds · at checkout'}'
                            : '${s['items']} ${te ? 'రకాలు · ఇంకా షాపింగ్' : 'kinds · still shopping'}',
                        amount: s['status'] == 'CHECKOUT' ? '${s['exit_code']}' : '›',
                        amountColor: s['status'] == 'CHECKOUT' ? askodoxStepWarn : askodoxStepMuted,
                        onTap: () => _openSession('${s['id']}'),
                      ),
                  ]),
                ),
      bottom: d == null
          ? null
          : enabled
              ? AskodoxStepBottom(
                  buttonKey: const Key('askodoxSelfShopOwnerStepsOpen'),
                  label: te ? 'ఎగ్జిట్ కోడ్ రాయి' : 'Type the exit code',
                  icon: Icons.pin_rounded,
                  onPressed: _askExit,
                )
              : AskodoxStepBottom(
                  buttonKey: const Key('askodoxSelfShopOwnerStepsOn'),
                  label: te ? 'ఆన్ చేయి' : 'Turn on',
                  icon: Icons.power_settings_new_rounded,
                  busy: _busy,
                  onPressed: _busy ? null : () => _toggle(true),
                ),
    );
  }
}

/// Owner 2026-11-25 (3-step design, batch 37): the exit check `/pos/:id/selfshop/:sid`.
/// 1 the customer's list (ONE big total, ONE list; tap an item = take it off, asks once) -> 2 ONE photo of all the
/// items (what matched / was not seen / is not on the list shows in the same list) -> 3 Bill & take payment (the same
/// counter pay sheet and call). Billing without the photo, a second photo and the old page live in ⋮.
class AskodoxSelfShopCheckStepsScreen extends ConsumerStatefulWidget {
  const AskodoxSelfShopCheckStepsScreen({super.key, required this.businessId, required this.sessionId});
  final String businessId;
  final String sessionId;

  @override
  ConsumerState<AskodoxSelfShopCheckStepsScreen> createState() => _SelfShopCheckStepsState();
}

class _SelfShopCheckStepsState extends ConsumerState<AskodoxSelfShopCheckStepsScreen> {
  AskodoxJson? _session;
  AskodoxJson? _check;
  Object? _error;
  bool _busy = false;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.selfShopSession(widget.businessId, widget.sessionId);
      if (mounted) {
        setState(() {
          _session = s;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _photo() async {
    final te = _te;
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
      final check = await _repo.selfShopVerify(widget.businessId, widget.sessionId, codes);
      if (mounted) setState(() => _check = check);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Taking an item off the customer's list changes what they pay: ask once.
  Future<void> _remove(AskodoxJson item) async {
    final te = _te;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? 'లిస్ట్ నుండి తీసేయాలా?' : 'Take it off the list?'),
        content: Text('${_name(item, te)} · ${_line(item)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(te ? 'వద్దు' : 'No')),
          FilledButton(
              key: const Key('askodoxSelfShopCheckStepsRemoveYes'),
              onPressed: () => Navigator.pop(d, true),
              child: Text(te ? 'తీసేయి' : 'Take off')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      final s = await _repo.selfShopStaffQty(
          widget.businessId, widget.sessionId, '${item['product_id']}', '${item['pack'] ?? ''}', 0);
      if (mounted) {
        setState(() {
          _session = s;
          _check = null;
        });
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _bill() async {
    final te = _te;
    final total = askodoxPosInt(_session?['total_paise']);
    final result = await showModalBottomSheet<AskodoxPosPayResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AskodoxPosPaymentSheet(total: total, allowCredit: false, allowDue: false, te: te),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final out = await _repo.selfShopBill(widget.businessId, widget.sessionId, result.payments);
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title (${rows.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        for (final r in rows)
          Text(
              '• ${r['name'] ?? (te ? 'ఈ షాప్‌లో లేని బార్‌కోడ్' : 'barcode not in this shop')}'
              '${'${r['pack'] ?? ''}'.isEmpty ? '' : ' (${r['pack']})'}'
              '${r['qty_milli'] == null ? '' : ' × ${askodoxQty(askodoxPosInt(r['qty_milli']), '')}'}'
              '${r['barcode'] == null ? '' : ' · ${r['barcode']}'}',
              style: const TextStyle(fontSize: 14)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final s = _session;
    final items = askodoxPosList(s?['items']);
    final check = _check;
    final status = '${s?['status'] ?? ''}';
    final open = status == 'CHECKOUT' || status == 'OPEN';
    final canBill = status == 'CHECKOUT' && items.isNotEmpty;
    final billNext = canBill && check != null;
    return AskodoxStepScaffold(
      key: const Key('askodoxSelfShopCheckSteps'),
      title: te ? 'ఎగ్జిట్ చెక్' : 'Exit check',
      sub: s == null ? '' : '${te ? 'కస్టమర్' : 'Customer'} …${s['customer']}',
      step: s == null || !open ? 0 : (billNext ? 3 : 2),
      more: [
        if (canBill && !billNext)
          AskodoxStepMore('askodoxSelfShopCheckStepsBillNow', te ? 'ఫోటో లేకుండా బిల్లు' : 'Bill without the photo',
              Icons.payments_outlined, _bill),
        if (open && billNext)
          AskodoxStepMore('askodoxSelfShopCheckStepsPhotoAgain', te ? 'మళ్ళీ ఫోటో' : 'Photo again', Icons.photo_camera_outlined, _photo),
        AskodoxStepMore('askodoxSelfShopCheckStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/selfshop/${widget.sessionId}?full=1')),
      ],
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : s == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                  AskodoxStepBigNumber(askodoxPaise(askodoxPosInt(s['total_paise'])),
                      key: const Key('askodoxSelfShopCheckStepsTotal'),
                      label: status == 'OPEN'
                          ? (te ? 'కస్టమర్ ఇంకా "చెకౌట్" నొక్కలేదు' : 'The customer has not tapped Checkout yet')
                          : status == 'CHECKOUT'
                              ? (te ? 'మొత్తం (అంచనా) · ${items.length} రకాలు' : 'Total (preview) · ${items.length} kinds')
                              : (te ? 'ఈ లిస్ట్ ముగిసింది' : 'This list has ended')),
                  const SizedBox(height: 8),
                  if (check != null)
                    Container(
                      key: const Key('askodoxSelfShopCheckStepsResult'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: check['all_clear'] == true ? askodoxStepGreenSoft : const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(
                          check['all_clear'] == true
                              ? (te ? 'లిస్ట్‌లోని ప్రతి రకం ఫోటోలో కనబడింది.' : 'Every kind of item on the list was seen in the photo.')
                              : (te ? 'కొన్ని తేడాలు ఉన్నాయి — కింద చూడండి.' : 'Some differences — see below.'),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  if (check != null) ...[
                    _section('askodoxSelfShopCheckStepsNotSeen', te ? 'ఫోటోలో కనబడలేదు — చేతితో చూడండి' : 'Not seen — check by hand',
                        const Color(0xFFFEF3C7), askodoxPosList(check['not_seen']), te),
                    _section('askodoxSelfShopCheckStepsNotBilled', te ? 'లిస్ట్‌లో లేవు (బిల్ కాలేదు)' : 'Not on the list (not billed)',
                        const Color(0xFFFEE2E2), askodoxPosList(check['not_billed']), te),
                    _section('askodoxSelfShopCheckStepsCount', te ? 'ఒకటి కంటే ఎక్కువ — లెక్క చేతితో' : 'More than one — count by hand',
                        const Color(0xFFEFF6FF), askodoxPosList(check['count_by_hand']), te),
                    _section('askodoxSelfShopCheckStepsMatched', te ? 'సరిపోయాయి' : 'Matched', const Color(0xFFF0FDF4),
                        askodoxPosList(check['matched']), te),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      child: Text(
                          te
                              ? 'ఒక ఫోటోలో ఒకే బార్‌కోడ్ ఉన్న ప్యాకెట్లు ఒకటిగానే కనబడతాయి. లేని వాటిని కౌంటర్‌లో కొత్త బిల్లులో వేయండి.'
                              : 'Packets with the same barcode show once in a photo. Bill anything extra on a new counter bill.',
                          style: const TextStyle(fontSize: 13, color: askodoxStepMuted)),
                    ),
                  ],
                  for (final item in items)
                    AskodoxStepPersonRow(
                      key: ValueKey('askodoxSelfShopCheckStepsItem-${item['product_id']}-${item['pack']}'),
                      name: _name(item, te),
                      sub: _line(item),
                      amount: askodoxPaise(askodoxPosInt(item['total_paise'])),
                      amountColor: askodoxStepInk,
                      onTap: open ? () => _remove(item) : () {},
                    ),
                ]),
      bottom: s == null || !open
          ? null
          : billNext
              ? AskodoxStepBottom(
                  buttonKey: const Key('askodoxSelfShopCheckStepsBill'),
                  label: te ? 'బిల్లు & చెల్లింపు' : 'Bill & take payment',
                  icon: Icons.payments_outlined,
                  busy: _busy,
                  onPressed: _busy ? null : _bill,
                )
              : AskodoxStepBottom(
                  buttonKey: const Key('askodoxSelfShopCheckStepsPhoto'),
                  label: te ? 'అన్ని సరుకుల ఒకే ఫోటో' : 'One photo of all items',
                  icon: Icons.photo_camera_outlined,
                  busy: _busy,
                  onPressed: _busy ? null : _photo,
                ),
    );
  }
}

/// Owner 2026-11-25 (3-step design, batch 37): the customer's scan & shop page `/shop-scan`.
/// 1 which shop (ONE big button: photo of the entrance QR; typing the 6-digit code is in ⋮) -> 2 ONE big total + ONE
/// list (tap an item = less / more / what the shop says about it), ONE big button scans the next barcode, the last
/// row of the list is Checkout -> 3 ONE big exit code to show at the counter. Payment stays at the counter.
class AskodoxShopScanStepsScreen extends ConsumerStatefulWidget {
  const AskodoxShopScanStepsScreen({super.key});

  @override
  ConsumerState<AskodoxShopScanStepsScreen> createState() => _ShopScanStepsState();
}

class _ShopScanStepsState extends ConsumerState<AskodoxShopScanStepsScreen> {
  AskodoxJson? _session;
  bool _loading = true;
  bool _busy = false;
  final _code = TextEditingController();

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

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
      final mine = await _repo.selfShopMine();
      final live = askodoxPosList(mine['sessions']).where((s) => s['status'] == 'OPEN' || s['status'] == 'CHECKOUT');
      if (mounted) setState(() => _session = live.firstOrNull);
    } catch (_) {
      // Not signed in / offline: the first step explains what is needed.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<AskodoxJson> Function(AskodoxPosRepository repo) call) async {
    final te = _te;
    setState(() => _busy = true);
    try {
      final out = await call(_repo);
      if (mounted) setState(() => _session = out);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _scanOne() async {
    final te = _te;
    try {
      return await ref.read(askodoxBarcodeScannerProvider).scan(context);
    } on AskodoxScanException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return null;
    }
  }

  Future<void> _scanEntry() async {
    final code = await _scanOne();
    if (code != null && mounted) await _run((repo) => repo.selfShopJoin(code));
  }

  Future<void> _typeCode() async {
    final te = _te;
    _code.clear();
    final code = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? 'షాప్ కోడ్ (6 అంకెలు)' : 'Shop code (6 digits)'),
        content: TextField(
          key: const Key('askodoxShopScanStepsCode'),
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 4),
          decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: te ? 'ద్వారం దగ్గర / కౌంటర్‌పై ఉంటుంది. రోజూ మారుతుంది.' : 'Shown at the entrance / counter. It changes every day.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxShopScanStepsCodeGo'),
              onPressed: () => Navigator.pop(d, _code.text.trim()),
              child: Text(te ? 'మొదలుపెట్టు' : 'Start')),
        ],
      ),
    );
    if (code != null && code.isNotEmpty && mounted) await _run((repo) => repo.selfShopJoin(code));
  }

  Future<void> _scanItem() async {
    final te = _te;
    final sid = '${_session?['id']}';
    final code = await _scanOne();
    if (code == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final out = await _repo.selfShopScan(sid, code);
      if (!mounted) return;
      setState(() => _session = askodoxPosMap(out['session']));
      final item = askodoxPosMap(out['item']);
      if (out['added'] == true) {
        askodoxPosSnack(context, '${te ? 'జోడించాం' : 'Added'}: ${_name(item, te)} · ${askodoxPaise(askodoxPosInt(item['price_paise']))}');
      } else {
        _itemSheet(item,
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

  /// One item: what the shop itself says about it, less / more while the list is open, "Ask ASKODOX" for the rest.
  void _itemSheet(AskodoxJson item, {String? reason, AskodoxJson? row}) {
    final te = _te;
    final attributes = askodoxPosMap(item['attributes']);
    final name = _name(item, te);
    final facts = [
      for (final e in attributes.entries)
        if ('${e.value}'.isNotEmpty) '${e.key}: ${e.value}'
    ];
    final sid = '${_session?['id']}';
    void change(int by) {
      Navigator.pop(context);
      _run((repo) => repo.selfShopQty(sid, '${row!['product_id']}', '${row['pack'] ?? ''}', askodoxPosInt(row['qty_milli']) + by));
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          key: const Key('askodoxShopScanStepsItemInfo'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            if (item['price_paise'] != null)
              Text('${askodoxPaise(askodoxPosInt(item['price_paise']))} / ${item['unit'] ?? ''}', style: const TextStyle(fontSize: 15)),
            if (reason != null) ...[const SizedBox(height: 8), Text(reason, style: const TextStyle(color: askodoxStepWarn, fontSize: 15))],
            const SizedBox(height: 8),
            if (facts.isEmpty)
              Text(te ? 'షాప్ ఈ సరుకుకి ఇంకా వివరాలు పెట్టలేదు.' : 'The shop has not added details for this item yet.')
            else
              for (final f in facts) Text('• $f'),
            const SizedBox(height: 12),
            if (row != null)
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('askodoxShopScanStepsLess-${row['product_id']}-${row['pack']}'),
                    onPressed: () => change(-1000),
                    icon: const Icon(Icons.remove_rounded),
                    label: Text(te ? 'ఒకటి తగ్గించు' : 'One less'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: ValueKey('askodoxShopScanStepsMore-${row['product_id']}-${row['pack']}'),
                    onPressed: () => change(1000),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(te ? 'ఒకటి పెంచు' : 'One more'),
                  ),
                ),
              ]),
            TextButton.icon(
              key: const Key('askodoxShopScanStepsAsk'),
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
          ]),
        ),
      ),
    );
  }

  /// Cancelling throws the whole list away: ask once.
  Future<void> _cancel() async {
    final te = _te;
    final sid = '${_session?['id']}';
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? 'షాపింగ్ రద్దు చేయాలా?' : 'Cancel this list?'),
        content: Text(te ? 'మీ లిస్ట్ మొత్తం పోతుంది.' : 'Your whole list goes away.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(te ? 'వద్దు' : 'No')),
          FilledButton(
              key: const Key('askodoxShopScanStepsCancelYes'),
              onPressed: () => Navigator.pop(d, true),
              child: Text(te ? 'రద్దు చేయి' : 'Cancel it')),
        ],
      ),
    );
    if (yes == true && mounted) await _run((repo) => repo.selfShopCancel(sid));
  }

  AskodoxJson _details(AskodoxJson item) => {
        'name': item['name'],
        'name_te': item['name_te'],
        'price_paise': item['unit_price_paise'],
        'unit': item['unit'],
        'attributes': item['attributes'] ?? const <String, Object?>{},
      };

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final s = _session;
    final items = askodoxPosList(s?['items']);
    final status = '${s?['status'] ?? ''}';
    final live = status == 'OPEN' || status == 'CHECKOUT';
    final old = AskodoxStepMore('askodoxShopScanStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
        () => context.push('/shop-scan?full=1'));

    if (_loading) {
      return AskodoxStepScaffold(
          key: const Key('askodoxShopScanSteps'),
          title: te ? 'స్కాన్ చేసి కొనండి' : 'Scan & shop',
          body: const Center(child: CircularProgressIndicator()));
    }

    if (s == null) {
      return AskodoxStepScaffold(
        key: const Key('askodoxShopScanSteps'),
        title: te ? 'స్కాన్ చేసి కొనండి' : 'Scan & shop',
        step: 1,
        question: te ? 'ఏ షాప్‌లో ఉన్నారు?' : 'Which shop are you in?',
        hint: te ? 'షాప్ ద్వారం దగ్గర ఉన్న QR ఫోటో తీయండి' : 'Photograph the QR at the shop entrance',
        more: [
          AskodoxStepMore('askodoxShopScanStepsType', te ? '6 అంకెల కోడ్ రాయి' : 'Type the 6-digit code', Icons.keyboard_rounded, _typeCode),
          old,
        ],
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          AskodoxStepChoice(
            icon: Icons.qr_code_scanner_rounded,
            color: askodoxStepGreen,
            title: te ? 'మీ ఫోన్‌తో స్కాన్ చేసి కొనండి' : 'Shop by scanning with your phone',
            sub: te ? 'సరుకు బార్‌కోడ్ ఫోటో తీస్తే షాప్ ధరతో మీ లిస్ట్‌లో చేరుతుంది' : "Photograph an item's barcode and it joins your list at the shop's price",
            onTap: null,
          ),
          const SizedBox(height: 8),
          AskodoxStepChoice(
            icon: Icons.storefront_rounded,
            color: askodoxStepInfo,
            title: te ? 'డబ్బు కౌంటర్‌లోనే' : 'You pay at the counter',
            sub: te ? 'చివర్లో ఎగ్జిట్ కోడ్ చూపించి అక్కడే చెల్లించండి' : 'Show the exit code at the end and pay there',
            onTap: null,
          ),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxShopScanStepsEntry'),
          label: te ? 'QR ఫోటో తీయి' : 'Photograph the QR',
          icon: Icons.qr_code_scanner_rounded,
          busy: _busy,
          onPressed: _busy ? null : _scanEntry,
        ),
      );
    }

    return AskodoxStepScaffold(
      key: const Key('askodoxShopScanSteps'),
      title: '${s['shop'] ?? ''}',
      step: status == 'OPEN' ? 2 : (status == 'CHECKOUT' ? 3 : 0),
      more: [
        if (status == 'OPEN' && items.isNotEmpty)
          AskodoxStepMore('askodoxShopScanStepsCheckoutMore', te ? 'చెకౌట్' : 'Checkout', Icons.how_to_reg_outlined,
              () => _run((repo) => repo.selfShopCheckout('${s['id']}'))),
        if (live) AskodoxStepMore('askodoxShopScanStepsCancel', te ? 'షాపింగ్ రద్దు' : 'Cancel this list', Icons.close_rounded, _cancel),
        old,
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        if (status == 'CHECKOUT')
          AskodoxStepBigNumber('${s['exit_code']}',
              key: const Key('askodoxShopScanStepsExitCode'),
              label: te ? 'కౌంటర్‌లో ఈ కోడ్ చూపించండి · అక్కడే డబ్బు ఇవ్వండి' : 'Show this code at the counter · pay there',
              color: askodoxStepInfo)
        else if (status == 'OPEN')
          AskodoxStepBigNumber(askodoxPaise(askodoxPosInt(s['total_paise'])),
              key: const Key('askodoxShopScanStepsTotal'),
              label: te ? 'మొత్తం (అంచనా) · కౌంటర్ బిల్లే అంతిమం' : 'Total (preview) · the counter bill is final')
        else ...[
          const SizedBox(height: 16),
          if (status == 'BILLED') const Center(child: AskodoxStepDoneMark()),
          const SizedBox(height: 12),
          Center(
            child: Text(
                status == 'BILLED' ? (te ? 'బిల్లు అయింది. ధన్యవాదాలు!' : 'Billed. Thank you!') : (te ? 'ఈ లిస్ట్ ముగిసింది.' : 'This list has ended.'),
                key: const Key('askodoxShopScanStepsEnded'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ),
        ],
        const SizedBox(height: 8),
        if (status == 'CHECKOUT')
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
                te
                    ? 'సిబ్బంది మీ సరుకుల ఒక ఫోటో తీసి సరిచూస్తారు. మొత్తం (అంచనా) ${askodoxPaise(askodoxPosInt(s['total_paise']))}.'
                    : 'Staff take one photo of your items to check them. Total (preview) ${askodoxPaise(askodoxPosInt(s['total_paise']))}.',
                style: const TextStyle(fontSize: 14, color: askodoxStepMuted)),
          ),
        if (items.isEmpty && status == 'OPEN')
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
                te ? 'సరుకు తీసుకుని దాని బార్‌కోడ్ ఫోటో తీయండి.' : 'Pick an item and photograph its barcode.',
                style: const TextStyle(fontSize: 16, color: askodoxStepMuted)),
          ),
        if (live)
          for (final item in items)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxShopScanStepsItem-${item['product_id']}-${item['pack']}'),
              name: _name(item, te),
              sub: _line(item),
              amount: askodoxPaise(askodoxPosInt(item['total_paise'])),
              amountColor: askodoxStepInk,
              onTap: () => _itemSheet(_details(item), row: status == 'OPEN' ? item : null),
            ),
        if (status == 'OPEN' && items.isNotEmpty) ...[
          const SizedBox(height: 8),
          AskodoxStepChoice(
            key: const Key('askodoxShopScanStepsCheckout'),
            icon: Icons.how_to_reg_outlined,
            color: askodoxStepInfo,
            title: te ? 'అయిపోయిందా? చెకౌట్' : 'Finished? Checkout',
            sub: te ? 'కౌంటర్‌లో చూపించే ఎగ్జిట్ కోడ్ వస్తుంది' : 'You get the exit code to show at the counter',
            onTap: _busy ? null : () => _run((repo) => repo.selfShopCheckout('${s['id']}')),
          ),
        ],
      ]),
      bottom: status == 'OPEN'
          ? AskodoxStepBottom(
              buttonKey: const Key('askodoxShopScanStepsScan'),
              label: te ? 'బార్‌కోడ్ స్కాన్' : 'Scan barcode',
              icon: Icons.qr_code_scanner_rounded,
              busy: _busy,
              onPressed: _busy ? null : _scanItem,
            )
          : status == 'CHECKOUT'
              ? AskodoxStepBottom(
                  buttonKey: const Key('askodoxShopScanStepsReopen'),
                  label: te ? 'ఇంకా సరుకులు వేయాలి' : 'Add more items',
                  icon: Icons.add_shopping_cart_rounded,
                  outline: true,
                  busy: _busy,
                  onPressed: _busy ? null : () => _run((repo) => repo.selfShopReopen('${s['id']}')),
                )
              : AskodoxStepBottom(
                  buttonKey: const Key('askodoxShopScanStepsNew'),
                  label: te ? 'కొత్త షాపింగ్' : 'Start again',
                  icon: Icons.refresh_rounded,
                  onPressed: () => setState(() => _session = null),
                ),
    );
  }
}
