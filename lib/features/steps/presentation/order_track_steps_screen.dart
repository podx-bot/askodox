import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/chat_pins.dart' show askodoxLiveOrdersProvider;
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/order_steps.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_frontdesk_screens.dart' show AskodoxTableRequestsPanel;
import '../../pos/presentation/shop_rating_screens.dart';
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 31): a customer's own order `/order-desk/track/:oid`.
/// Top = where the order is now (one big line), middle = ONE list (the steps with their times, then the items and the
/// bill), bottom = ONE big button (how will you pay: cash / online, or rate it once it is done, or call the shop).
/// Cancel (asks once), call, shop page and the old page live in ⋮. Refreshes every 8 s like before; the rating sheet
/// still opens by itself when the server asks. Old page stays at `?full=1`.
class AskodoxOrderTrackStepsScreen extends ConsumerStatefulWidget {
  const AskodoxOrderTrackStepsScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<AskodoxOrderTrackStepsScreen> createState() => _OrderTrackStepsState();
}

const _closed = {'done', 'rejected', 'cancelled'};

class _OrderTrackStepsState extends ConsumerState<AskodoxOrderTrackStepsScreen> {
  AskodoxJson? _order;
  Object? _error;
  bool _ratingAsked = false;
  Timer? _timer;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

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
      final o = await _repo.deskMineOne(widget.orderId);
      if (!mounted) return;
      final wasOpen = !_closed.contains('${_order?['stage']}');
      if (wasOpen && _closed.contains('${o['stage']}')) unawaited(ref.read(askodoxLiveOrdersProvider.notifier).refresh());
      setState(() {
        _order = o;
        _error = null;
      });
      if (o['can_rate'] == true && !_ratingAsked) {
        _ratingAsked = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _rate());
      }
    } catch (e) {
      if (mounted && _order == null) setState(() => _error = e);
    }
  }

  Future<void> _rate() async {
    if (!mounted) return;
    if (await askodoxAskRating(context, ref, widget.orderId) && mounted) {
      askodoxPosSnack(context, _te ? 'ధన్యవాదాలు! ⭐' : 'Thank you! ⭐');
      unawaited(_load());
    }
  }

  Future<void> _cancel() async {
    final te = _te;
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? 'ఆర్డర్ రద్దు చేయాలా?' : 'Cancel the order?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(te ? 'వద్దు' : 'No')),
          FilledButton(
              key: const Key('askodoxOrderTrackStepsCancelYes'),
              onPressed: () => Navigator.pop(d, true),
              child: Text(te ? 'రద్దు చేయి' : 'Cancel it')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      final o = await _repo.deskCancelMine(widget.orderId);
      if (mounted) setState(() => _order = o);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _call(String phone) async {
    try {
      await launchUrl(Uri.parse('tel:$phone'));
    } catch (_) {}
  }

  /// Cash or online is the customer's choice; the shop sees it on the order (owner 2026-11-18).
  Future<void> _payChoice(AskodoxJson o, int toPay, bool waiting, String? payLink) async {
    final te = _te;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(askodoxPaise(toPay), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            Text(waiting ? (te ? 'షాప్ ఒప్పుకున్నాక కట్టండి' : 'Pay after the shop accepts') : (te ? 'ఎలా కడతారు?' : 'How will you pay?'),
                style: const TextStyle(color: askodoxStepMuted)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('askodoxOrderTrackStepsCash'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: () => Navigator.pop(ctx, 'cash'),
              icon: const Icon(Icons.payments_outlined),
              label: Text(o['pay_choice'] == 'cash' ? (te ? '✓ క్యాష్' : '✓ Cash') : (te ? 'క్యాష్' : 'Cash')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('askodoxOrderTrackStepsOnline'),
              style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen, minimumSize: const Size.fromHeight(54)),
              onPressed: waiting || payLink == null ? null : () => Navigator.pop(ctx, 'online'),
              icon: const Icon(Icons.qr_code_2),
              label: Text(payLink == null && !waiting
                  ? (te ? 'బిల్లు రాగానే ఆన్‌లైన్' : 'Online once billed')
                  : (te ? 'ఆన్‌లైన్ (UPI)' : 'Online (UPI)')),
            ),
          ]),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      final out = await _repo.deskPayChoice(widget.orderId, choice);
      if (mounted) setState(() => _order = out);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (choice == 'online' && payLink != null) {
      final uri = Uri.tryParse(payLink);
      if (uri != null) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {}
      }
    } else if (choice == 'cash' && mounted) {
      askodoxPosSnack(context, te ? 'క్యాష్ కడతారని షాప్‌కి చెప్పాం' : 'The shop knows you will pay cash');
    }
  }

  String _kind(String kind, bool te) => switch (kind) {
        'dine_in' => te ? 'ఇక్కడ తింటాను' : 'Dine in',
        'delivery' => te ? 'డెలివరీ' : 'Delivery',
        _ => te ? 'పార్సిల్' : 'Takeaway',
      };

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final o = _order;
    final phone = '${o?['business_phone'] ?? ''}';
    final more = [
      if (o?['can_cancel'] == true)
        AskodoxStepMore('askodoxOrderTrackStepsCancel', te ? 'ఆర్డర్ రద్దు' : 'Cancel the order', Icons.cancel_outlined, _cancel),
      if (phone.isNotEmpty) AskodoxStepMore('askodoxOrderTrackStepsCall', te ? 'షాప్‌కి కాల్' : 'Call the shop', Icons.call, () => _call(phone)),
      if ('${o?['business_id'] ?? ''}'.isNotEmpty)
        AskodoxStepMore('askodoxOrderTrackStepsShop', te ? 'షాప్ పేజీ' : 'Shop page', Icons.storefront_outlined,
            () => context.push('/shops/${o!['business_id']}')),
      AskodoxStepMore('askodoxOrderTrackStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
          () => context.push('/order-desk/track/${widget.orderId}?full=1')),
    ];
    final title = o == null ? (te ? 'నా ఆర్డర్' : 'My order') : '${o['business_name'] ?? ''}';
    if (_error != null) return AskodoxStepScaffold(title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    if (o == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    final waiting = askodoxOrderAwaitsShop(o);
    final payLink = askodoxOrderPayLink(o);
    final invoice = o['invoice'] is Map ? askodoxPosMap(o['invoice']) : null;
    final balance = invoice == null ? 0 : askodoxPosInt(invoice['balance_paise']);
    final toPay = balance > 0 ? balance : askodoxPosInt(o['estimate_paise']);
    final closed = const ['rejected', 'cancelled'].contains('${o['stage']}');
    final canPay = !closed && !(invoice != null && balance == 0) && toPay > 0;
    final stageText = o['stage_text'] is Map ? '${(o['stage_text'] as Map)[te ? 'te' : 'en'] ?? ''}' : '${o['stage'] ?? ''}';
    final reason = '${o['reason'] ?? ''}';
    Widget? bottom;
    if (o['can_rate'] == true) {
      bottom = AskodoxStepBottom(
          buttonKey: const Key('askodoxOrderTrackStepsRate'), label: te ? 'రేటింగ్ ఇవ్వండి' : 'Rate it', icon: Icons.star_rounded, onPressed: _rate);
    } else if (canPay) {
      bottom = AskodoxStepBottom(
        buttonKey: const Key('askodoxOrderTrackStepsPay'),
        label: o['pay_choice'] == 'cash'
            ? (te ? '✓ క్యాష్ · ${askodoxPaise(toPay)}' : '✓ Cash · ${askodoxPaise(toPay)}')
            : (te ? '${askodoxPaise(toPay)} — ఎలా కడతారు?' : '${askodoxPaise(toPay)} — how will you pay?'),
        icon: Icons.payments_outlined,
        onPressed: () => _payChoice(o, toPay, waiting, payLink),
      );
    } else if (phone.isNotEmpty) {
      bottom = AskodoxStepBottom(
          buttonKey: const Key('askodoxOrderTrackStepsCallBig'),
          label: te ? 'షాప్‌కి కాల్' : 'Call the shop',
          icon: Icons.call,
          outline: true,
          onPressed: () => _call(phone));
    }
    return AskodoxStepScaffold(
      key: const Key('askodoxOrderTrackSteps'),
      title: title,
      sub: '${_kind('${o['kind']}', te)}${o['table_name'] != null ? ' · ${o['table_name']}' : ''}',
      question: waiting ? (te ? 'షాప్ ఒప్పుకోవడానికి వేచి ఉంది…' : 'Waiting for the shop to accept…') : stageText,
      hint: waiting
          ? (te ? 'ఒప్పుకోగానే మీకు చెప్తాం. ఇంకా డబ్బు కట్టకండి.' : 'You are told the moment they accept. Do not pay yet.')
          : (reason.isNotEmpty && reason != 'null' ? reason : null),
      more: more,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
          if ('${o['thanks'] ?? ''}'.isNotEmpty)
            Container(
              key: const Key('askodoxOrderTrackStepsThanks'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF382C14), borderRadius: BorderRadius.circular(14)),
              child: Text('🙏 ${o['thanks']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          for (final st in askodoxOrderSteps(o))
            Padding(
              key: Key('askodoxOrderTrackStepsStep-${st.stage}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(
                    switch (st.state) {
                      AskodoxStepState.done => Icons.check_circle,
                      AskodoxStepState.now => Icons.radio_button_checked,
                      AskodoxStepState.next => Icons.radio_button_unchecked,
                    },
                    size: 26,
                    color: switch (st.state) {
                      AskodoxStepState.done => askodoxStepDone,
                      AskodoxStepState.now => askodoxStepWarn,
                      AskodoxStepState.next => const Color(0xFF9099A8),
                    }),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(askodoxOrderStepName(st.stage, te),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: st.state == AskodoxStepState.next ? FontWeight.w500 : FontWeight.w800,
                            color: st.state == AskodoxStepState.next ? askodoxStepMuted : askodoxStepInk))),
                Text(askodoxClockWords(st.at, te), style: const TextStyle(fontSize: 13, color: askodoxStepMuted)),
              ]),
            ),
          const Divider(height: 24),
          for (final i in askodoxPosList(o['items']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${((i['qty'] as num?) ?? 0).round()} × ${i['name']}',
                        style: TextStyle(fontSize: 15, decoration: i['status'] == 'unavailable' ? TextDecoration.lineThrough : null)),
                    if (i['status'] == 'unavailable')
                      Text(te ? 'ఇది ఈ రోజు లేదు' : 'Not available today', style: const TextStyle(fontSize: 12, color: askodoxStepBad))
                    else if ('${i['note'] ?? ''}'.isNotEmpty)
                      Text('${i['note']}', style: const TextStyle(fontSize: 12, color: askodoxStepMuted)),
                  ]),
                ),
                Text(askodoxPaise(askodoxPosInt(i['price_paise']) * ((i['qty'] as num?) ?? 0).round()),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
                child: Text(invoice != null ? '${te ? 'బిల్లు' : 'Bill'} ${invoice['number']}' : (te ? 'మొత్తం (సుమారు)' : 'Total (about)'),
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(askodoxPaise(invoice != null ? askodoxPosInt(invoice['total_paise']) : askodoxPosInt(o['estimate_paise'])),
                key: const Key('askodoxOrderTrackStepsTotal'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ]),
          if (invoice != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                  balance > 0 ? '${te ? 'ఇంకా కట్టాల్సింది' : 'Still to pay'}: ${askodoxPaise(balance)}' : (te ? 'కట్టేశారు ✓' : 'Paid ✓'),
                  style: TextStyle(color: balance > 0 ? askodoxStepWarn : askodoxStepDone, fontWeight: FontWeight.w700)),
            ),
          if (o['kind'] == 'dine_in' && !const ['placed', 'accepting', 'done', 'rejected', 'cancelled'].contains('${o['stage']}'))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AskodoxTableRequestsPanel(key: const Key('askodoxOrderTrackStepsRequests'), orderId: widget.orderId),
            ),
        ]),
      ),
      bottom: bottom,
    );
  }
}
