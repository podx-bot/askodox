import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../growth/data/benefits.dart';
import '../../growth/presentation/benefits_widgets.dart';
import '../../orders/data/order_repository.dart';
import '../domain/conversation_language.dart';

/// The live deal inside the conversation: request → seller/provider reply →
/// negotiation → accept/decline → payment state → delivery/service →
/// customer confirmation → problem/support → review → closed.
///
/// Every action shown is one the server's universal lifecycle allows for
/// this viewer right now (backend deal_lifecycle.py); nothing is assumed
/// locally, and payment/delivery are never marked done by the app itself.
class AskodoxDealPanel extends ConsumerStatefulWidget {
  const AskodoxDealPanel({
    super.key,
    required this.orderId,
    required this.te,
    this.onAlternatives,
    this.onSupport,
    this.showAcceptDecline = false,
  });

  final String orderId;
  /// The seller order card already has its own Accept/Decline buttons.
  final bool showAcceptDecline;
  final bool te;
  final void Function(List<Map<String, Object?>> rows)? onAlternatives;
  final Future<void> Function()? onSupport;

  @override
  ConsumerState<AskodoxDealPanel> createState() => _AskodoxDealPanelState();
}

class _AskodoxDealPanelState extends ConsumerState<AskodoxDealPanel> {
  OrderDetail? _detail;
  String? _error;
  bool _busy = false;

  bool get _te => widget.te;
  OrderLifecycleRepository get _repo => ref.read(orderLifecycleRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => _run(() => _repo.detail(widget.orderId));

  Future<void> _run(Future<OrderDetail> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final detail = await action();
      if (mounted) setState(() => _detail = detail);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message
            : (_te ? 'డీల్ స్థితి ఇప్పుడు అందుబాటులో లేదు.' : 'Deal status is unavailable right now.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _ask(String title, String label, {bool number = false}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('askodoxDealInput'),
          controller: controller,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(_te ? 'రద్దు' : 'Cancel')),
          FilledButton(
            key: const Key('askodoxDealSubmit'),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(_te ? 'పంపండి' : 'Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _askSeller() async {
    final text = await _ask(_te ? 'విక్రేతను అడగండి' : 'Ask the seller', _te ? 'మీ ప్రశ్న' : 'Your question');
    if (text == null || text.isEmpty) return;
    await _run(() => _repo.message(widget.orderId, 'QUESTION', text: text));
  }

  Future<void> _offer() async {
    final text = await _ask(_te ? 'మీ ధర ప్రతిపాదన' : 'Propose a price', '₹', number: true);
    final amount = double.tryParse((text ?? '').replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    await _run(() => _repo.message(widget.orderId, 'OFFER', amount: amount));
  }

  Future<void> _payment() async {
    final reference = await _ask(
        _te ? 'చెల్లింపు రిఫరెన్స్' : 'Payment reference', _te ? 'UPI UTR నంబర్' : 'UPI UTR number');
    if (reference == null || reference.isEmpty) return;
    await _run(() => _repo.payment(widget.orderId, 'submit_reference', reference: reference));
  }

  Future<void> _problem() async {
    final issue = await _ask(
        _te ? 'సమస్యను తెలపండి' : 'Report a problem',
        _te ? 'ఏమి జరిగింది?' : 'What went wrong? (not received, damaged, not completed...)');
    if (issue == null || issue.length < 3) return;
    final lower = issue.toLowerCase();
    final category = lower.contains('pay') || lower.contains('refund') || issue.contains('డబ్బు') ? 'PAYMENT' : 'DELIVERY';
    await _run(() => _repo.problem(widget.orderId, issue: issue, category: category));
  }

  Future<void> _confirm() async {
    final service = _detail?.order.isService == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(service
            ? (_te ? 'సేవ సరిగ్గా పూర్తయిందా?' : 'Was the service completed properly?')
            : (_te ? 'మీకు ప్రొడక్ట్ అందిందా?' : 'Did you receive the product?')),
        actions: [
          TextButton(
            key: const Key('askodoxDealConfirmNo'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(_te ? 'సమస్య ఉంది' : 'Report a problem'),
          ),
          FilledButton(
            key: const Key('askodoxDealConfirmYes'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_te ? 'అవును, పూర్తయింది' : 'Yes, confirm'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _repo.confirm(widget.orderId));
      await _revealReward();
    } else if (ok == false) {
      await _problem();
    }
  }

  /// After a confirmed completion the server may issue a Scratch & Reveal
  /// reward for THIS order (decided server-side, once per order).
  Future<void> _revealReward() async {
    if (_error != null || !mounted) return;
    AskodoxClaimResult? reward;
    try {
      reward = await ref.read(askodoxBenefitsRepositoryProvider).scratch(widget.orderId);
    } catch (_) {
      reward = null;
    }
    if (reward == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AskodoxScratchCard(reward: reward!, lang: ref.read(askodoxReplyLanguageProvider)),
    );
  }

  Future<void> _review() async {
    final text = await _ask(_te ? 'రేటింగ్ (1-5)' : 'Rate this deal (1-5)', '5', number: true);
    final rating = int.tryParse(text ?? '');
    if (rating == null || rating < 1 || rating > 5) return;
    try {
      await _repo.review(widget.orderId, rating);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_te ? 'ధన్యవాదాలు!' : 'Thanks for the review!')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error is StateError ? error.message : '$error');
    }
  }

  Future<void> _answer() async {
    final text = await _ask(_te ? 'కస్టమర్‌కు సమాధానం' : 'Answer the customer', _te ? 'సమాధానం' : 'Answer');
    if (text == null || text.isEmpty) return;
    await _run(() => _repo.message(widget.orderId, 'ANSWER', text: text));
  }

  Future<void> _counter() async {
    final text = await _ask(_te ? 'కౌంటర్ ఆఫర్' : 'Counter-offer', '₹', number: true);
    final amount = double.tryParse((text ?? '').replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    await _run(() => _repo.message(widget.orderId, 'COUNTER_OFFER', amount: amount));
  }

  Future<void> _sellerStatus(String status) async {
    setState(() => _busy = true);
    final result = await ref.read(orderRepositoryProvider).respondToOrder(orderId: widget.orderId, status: status);
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _busy = false;
        _error = result.message;
      });
      return;
    }
    await _load();
  }

  String _stepLabel(String status) => switch (status) {
        'PREPARING' => _te ? 'సిద్ధం చేస్తున్నాం' : 'Preparing',
        'READY' => _te ? 'సిద్ధంగా ఉంది' : 'Ready',
        'DISPATCHED' => _te ? 'పంపించాం' : 'Dispatched',
        'DELIVERED' => _te ? 'డెలివర్ చేశాం' : 'Delivered',
        'SCHEDULED' => _te ? 'షెడ్యూల్ చేశాం' : 'Scheduled',
        'PROVIDER_ASSIGNED' => _te ? 'ప్రొవైడర్ కేటాయింపు' : 'Provider assigned',
        'ARRIVED' => _te ? 'చేరుకున్నాం' : 'Arrived',
        'IN_PROGRESS' => _te ? 'పని ప్రారంభం' : 'Started',
        'SERVICE_COMPLETED' => _te ? 'సేవ పూర్తి' : 'Service completed',
        'ACCEPTED' => _te ? 'అంగీకరించు' : 'Accept',
        'REJECTED' => _te ? 'తిరస్కరించు' : 'Decline',
        _ => status,
      };

  Future<void> _alternatives() async {
    final rows = await _repo.alternatives(widget.orderId);
    widget.onAlternatives?.call(rows);
  }

  String _statusLabel(OrderDetail d) {
    final te = _te;
    return switch (d.order.status) {
      'PLACED' => te ? 'అభ్యర్థన పంపబడింది — విక్రేత/ప్రొవైడర్ స్పందన కోసం వేచి ఉంది' : 'Request sent — waiting for the seller/provider',
      'ACCEPTED' => te ? 'అంగీకరించారు' : 'Accepted',
      'REJECTED' => te ? 'విక్రేత అంగీకరించలేదు' : 'Declined by the seller/provider',
      'CANCELLED' => te ? 'రద్దు చేశారు' : 'Cancelled',
      'PREPARING' => te ? 'సిద్ధం చేస్తున్నారు' : 'Preparing',
      'READY' => te ? 'సిద్ధంగా ఉంది' : 'Ready',
      'DISPATCHED' => te ? 'పంపించారు' : 'Dispatched',
      'DELIVERED' => te ? 'డెలివర్ అయిందని విక్రేత తెలిపారు — దయచేసి నిర్ధారించండి' : 'Seller marked delivered — please confirm',
      'SCHEDULED' => te ? 'షెడ్యూల్ అయింది' : 'Scheduled',
      'PROVIDER_ASSIGNED' => te ? 'ప్రొవైడర్ కేటాయించబడ్డారు' : 'Provider assigned',
      'ARRIVED' => te ? 'ప్రొవైడర్ వచ్చారు' : 'Provider arrived',
      'IN_PROGRESS' => te ? 'సేవ జరుగుతోంది' : 'Service in progress',
      'SERVICE_COMPLETED' => te ? 'సేవ పూర్తయిందని ప్రొవైడర్ తెలిపారు — దయచేసి నిర్ధారించండి' : 'Provider marked completed — please confirm',
      'FULFILLED' => te ? 'పూర్తయిందని తెలిపారు — దయచేసి నిర్ధారించండి' : 'Marked done — please confirm',
      'DISPUTED' => te ? 'సమస్య నమోదైంది — కస్టమర్ కేర్ చూస్తోంది' : 'Problem reported — Customer Care is handling it',
      'RESOLVED' => te ? 'సపోర్ట్ పరిష్కరించింది — దయచేసి నిర్ధారించండి' : 'Support resolved it — please confirm',
      'CLOSED' => te ? 'డీల్ పూర్తయింది' : 'Deal closed',
      final other => other,
    };
  }

  String? _paymentLabel(String state) => switch (state) {
        'AWAITING_PAYMENT' => _te ? 'చెల్లింపు: నేరుగా విక్రేతకు; ఇంకా జరగలేదు' : 'Payment: direct to the seller — not made yet',
        'PROOF_SUBMITTED' => _te ? 'చెల్లింపు రిఫరెన్స్ పంపారు — నిర్ధారణ కోసం వేచి ఉంది' : 'Payment reference sent — awaiting confirmation',
        'VERIFIED' => _te ? 'చెల్లింపు నిర్ధారించబడింది' : 'Payment confirmed',
        'FAILED' => _te ? 'చెల్లింపు అందలేదని తెలిపారు' : 'Payment not received',
        'DISPUTED' => _te ? 'చెల్లింపు వివాదంలో ఉంది' : 'Payment under review',
        _ => null,
      };

  String _messageLabel(OrderMessage m) {
    final who = m.fromRole == 'seller' ? (_te ? 'విక్రేత' : 'Seller') : (_te ? 'మీరు' : 'You');
    final amount = m.amount == null ? '' : ' ₹${m.amount!.toStringAsFixed(0)}';
    final what = switch (m.kind) {
      'OFFER' => _te ? 'ధర ప్రతిపాదన' : 'offered',
      'COUNTER_OFFER' => _te ? 'కౌంటర్ ఆఫర్' : 'counter-offer',
      'ACCEPT_OFFER' => _te ? 'ఆఫర్ అంగీకరించారు' : 'accepted the offer',
      'DECLINE_OFFER' => _te ? 'ఆఫర్ తిరస్కరించారు' : 'declined the offer',
      _ => '',
    };
    final text = m.text?.trim().isNotEmpty == true ? m.text!.trim() : '';
    return '$who: ${[what, amount.trim(), text].where((x) => x.isNotEmpty).join(' ')}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final te = _te;
    final buttons = <Widget>[
      if (d != null) ...[
        if (d.can('ask_seller'))
          OutlinedButton(key: const Key('askodoxDealAsk'), onPressed: _busy ? null : _askSeller, child: Text(te ? 'విక్రేతను అడగండి' : 'Ask seller')),
        if (d.can('offer_price'))
          OutlinedButton(key: const Key('askodoxDealOffer'), onPressed: _busy ? null : _offer, child: Text(te ? 'ధర ప్రతిపాదించండి' : 'Propose price')),
        if (d.can('accept_offer'))
          FilledButton(
            key: const Key('askodoxDealAcceptOffer'),
            onPressed: _busy ? null : () => _run(() => _repo.message(widget.orderId, 'ACCEPT_OFFER')),
            child: Text(te ? 'ఆఫర్ అంగీకరించండి' : 'Accept offer'),
          ),
        if (d.can('decline_offer'))
          OutlinedButton(
            onPressed: _busy ? null : () => _run(() => _repo.message(widget.orderId, 'DECLINE_OFFER')),
            child: Text(te ? 'వద్దు' : 'Decline offer'),
          ),
        if (d.can('submit_payment_reference'))
          OutlinedButton(key: const Key('askodoxDealPay'), onPressed: _busy ? null : _payment, child: Text(te ? 'చెల్లింపు రిఫరెన్స్' : 'Payment reference')),
        if (d.can('confirm_completion'))
          FilledButton(key: const Key('askodoxDealConfirm'), onPressed: _busy ? null : _confirm, child: Text(te ? 'నిర్ధారించండి' : 'Confirm completion')),
        if (d.can('report_problem'))
          OutlinedButton(key: const Key('askodoxDealProblem'), onPressed: _busy ? null : _problem, child: Text(te ? 'సమస్య తెలపండి' : 'Report problem')),
        if (d.can('see_alternatives') && widget.onAlternatives != null)
          FilledButton(key: const Key('askodoxDealAlternatives'), onPressed: _busy ? null : _alternatives, child: Text(te ? 'ఇతర ఎంపికలు' : 'See other options')),
        if (d.can('contact_support') && widget.onSupport != null)
          OutlinedButton(key: const Key('askodoxDealSupport'), onPressed: _busy ? null : widget.onSupport, child: Text(te ? 'కస్టమర్ కేర్' : 'Contact Customer Care')),
        if (d.can('review'))
          OutlinedButton(key: const Key('askodoxDealReview'), onPressed: _busy ? null : _review, child: Text(te ? 'రివ్యూ ఇవ్వండి' : 'Review')),
        // Seller / provider side (same server-decided action list).
        if (d.can('answer'))
          OutlinedButton(key: const Key('askodoxDealAnswer'), onPressed: _busy ? null : _answer, child: Text(te ? 'సమాధానం' : 'Answer')),
        if (d.can('counter_offer'))
          OutlinedButton(key: const Key('askodoxDealCounter'), onPressed: _busy ? null : _counter, child: Text(te ? 'కౌంటర్ ఆఫర్' : 'Counter-offer')),
        for (final action in d.actions.where((a) => a.startsWith('status:')))
          if (widget.showAcceptDecline || !const {'status:ACCEPTED', 'status:REJECTED'}.contains(action))
            OutlinedButton(
              key: Key('askodoxDeal-$action'),
              onPressed: _busy ? null : () => _sellerStatus(action.substring(7)),
              child: Text(_stepLabel(action.substring(7))),
            ),
        if (d.can('confirm_payment_received'))
          FilledButton(
            key: const Key('askodoxDealPaymentReceived'),
            onPressed: _busy ? null : () => _run(() => _repo.payment(widget.orderId, 'confirm_received')),
            child: Text(te ? 'చెల్లింపు అందింది' : 'Payment received'),
          ),
        if (d.can('payment_not_received'))
          OutlinedButton(
            onPressed: _busy ? null : () => _run(() => _repo.payment(widget.orderId, 'not_received')),
            child: Text(te ? 'చెల్లింపు అందలేదు' : 'Not received'),
          ),
        if (d.can('cancel'))
          TextButton(
            onPressed: _busy ? null : () => _run(() => _repo.cancel(widget.orderId)),
            child: Text(te ? 'అభ్యర్థన రద్దు' : 'Cancel request'),
          ),
      ],
    ];
    return Container(
      key: const Key('askodoxDealPanel'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F5FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2DEFF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.handshake_outlined, size: 18, color: Color(0xFF5B4BFF)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              d == null ? (te ? 'డీల్ స్థితి' : 'Deal status') : _statusLabel(d),
              key: const Key('askodoxDealStatus'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: te ? 'రిఫ్రెష్' : 'Refresh',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
        ]),
        if (_busy && d == null) const LinearProgressIndicator(minHeight: 2),
        if (d != null && _paymentLabel(d.order.paymentState) != null)
          Text(_paymentLabel(d.order.paymentState)!,
              key: const Key('askodoxDealPayment'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF5E6472))),
        if (d != null && d.order.price != null)
          Text('${te ? 'ధర' : 'Price'}: ₹${d.order.price!.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF5E6472))),
        if (d != null)
          for (final m in d.messages.reversed.take(4).toList().reversed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_messageLabel(m), style: const TextStyle(fontSize: 13)),
            ),
        if (d?.sellerUnresponsive == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              te ? 'విక్రేత ఇంకా స్పందించలేదు.' : 'The seller has not responded yet.',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E)),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E))),
          ),
        if (buttons.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: buttons),
        ],
      ]),
    );
  }
}
