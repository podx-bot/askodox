import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../deal_brain/application/universal_deal_controller.dart';
import '../../deals/services/deal_invoice_service.dart';
import '../data/universal_match_repository.dart';

const _ink = Color(0xFF14213D);
const _mutedInk = Color(0xFF667085);
const _purple = Color(0xFF6A3FD6);

class UniversalMatchScreen extends ConsumerStatefulWidget {
  const UniversalMatchScreen({super.key});

  @override
  ConsumerState<UniversalMatchScreen> createState() => _UniversalMatchScreenState();
}

class _UniversalMatchScreenState extends ConsumerState<UniversalMatchScreen> {
  Future<UniversalMatchResult>? _future;
  UniversalMatchResult? _result;
  UniversalMatch? _selected;
  int _stage = 0;
  bool _busy = false;
  String? _paymentMode;
  String? _invoicePath;
  final _questionController = TextEditingController();
  final List<MapEntry<String, String>> _clarifications = [];

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deal = ref.read(universalDealControllerProvider).deal;
    if (_future == null && deal != null && deal.readyToMatch) {
      _future = _loadMatches();
    }
  }

  Future<UniversalMatchResult> _loadMatches() async {
    final deal = ref.read(universalDealControllerProvider).deal;
    if (deal == null || !deal.readyToMatch) {
      throw StateError('Complete the requirement before matching.');
    }
    return ref.read(universalMatchRepositoryProvider).createAndMatch(deal);
  }

  bool get _te => RegExp(r'[\u0C00-\u0C7F]').hasMatch(
        ref.read(universalDealControllerProvider).deal?.rawText ?? '',
      );

  void _select(UniversalMatch match) {
    setState(() {
      _selected = match;
      _stage = 0;
      _paymentMode = null;
      _invoicePath = null;
      _clarifications.clear();
      _questionController.clear();
    });
  }

  String _sellerAnswer(String question, UniversalMatch match) {
    final q = question.toLowerCase();
    if (q.contains('rate') ||
        q.contains('price') ||
        q.contains('ధర') ||
        q.contains('రేట్')) {
      return match.price == null
          ? (_te
              ? 'ఈ ధరను sellerతో confirm చేయాలి. Seller response వచ్చిన తర్వాత ఇక్కడే చూపిస్తాను.'
              : 'I need the seller to confirm the price. I will show the response here.')
          : (_te
              ? 'Seller ప్రస్తుతం ₹${match.price!.toStringAsFixed(0)} అని తెలిపాడు. Final quantity/specification ఆధారంగా final amount confirm చేయాలి.'
              : 'The seller currently quotes ₹${match.price!.toStringAsFixed(0)}. Final amount depends on quantity and specifications.');
    }
    if (q.contains('available') ||
        q.contains('stock') ||
        q.contains('ఉందా') ||
        q.contains('దొరుక')) {
      return _te
          ? 'Seller profile ప్రకారం ప్రస్తుతం availableగా ఉంది. Exact stock/requirementని confirmation ముందు sellerతో verify చేస్తాను.'
          : 'The seller profile shows it as available. Exact stock will be verified before confirmation.';
    }
    if (q.contains('delivery') ||
        q.contains('pickup') ||
        q.contains('డెలివరీ') ||
        q.contains('పికప్')) {
      return _te
          ? 'Pickup/delivery preferenceని order summaryలో note చేస్తాను. Seller fulfilmentని confirmation ముందు verify చేస్తాను.'
          : 'I will note your pickup/delivery preference and verify fulfilment before confirmation.';
    }
    if (q.contains('discount') ||
        q.contains('less') ||
        q.contains('తగ్గ') ||
        q.contains('బేరం')) {
      return _te
          ? 'ఈ rate తగ్గించగలరా అని sellerకి negotiation requestగా పంపాలి. Seller limit/approval వచ్చిన తర్వాతే final rateగా చూపిస్తాను.'
          : 'I will treat that as a negotiation request. A lower rate becomes final only after seller approval.';
    }
    return _te
        ? 'ఈ విషయానికి నాకు verified answer లేదు. Guess చేసి confirm చేయను. Sellerని అడిగి clarity తీసుకుని ఇదే conversationలో update చేస్తాను.'
        : 'I do not have a verified answer for that. I will not guess or confirm it; I will ask the seller and update this conversation.';
  }

  void _askQuestion([String? preset]) {
    final selected = _selected;
    if (selected == null) return;
    final question = (preset ?? _questionController.text).trim();
    if (question.isEmpty) return;
    setState(() {
      _clarifications.add(MapEntry(question, _sellerAnswer(question, selected)));
      _questionController.clear();
      _stage = 1;
    });
  }

  Future<void> _confirm() async {
    final result = _result;
    final match = _selected;
    if (result == null || match == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(universalMatchRepositoryProvider).acceptMatch(
            dealId: result.dealId,
            matchId: match.id,
          );
      if (!mounted) return;
      if (result.dealId.startsWith('local-') || match.id.startsWith('demo-')) {
        setState(() => _stage = 2);
      } else {
        context.go('/deals');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createInvoice({
    required String paymentMode,
    required String paymentStatus,
  }) async {
    final selected = _selected;
    final result = _result;
    if (selected == null || result == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await const DealInvoiceService().generate(
        DealInvoiceData(
          orderId: result.dealId,
          shopName: selected.title,
          buyerName: 'ASKODOX Buyer',
          sellerName: selected.title,
          amount: selected.price,
          paymentMode: paymentMode,
          paymentStatus: paymentStatus,
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _paymentMode = paymentMode;
        _invoicePath = file.path;
        _stage = 3;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_te ? 'Invoice create కాలేదు: $error' : 'Could not create invoice: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showDemoUpi() => setState(() => _paymentMode = 'DEMO UPI');

  void _refreshStatus() {
    setState(() {
      if (_stage == 3) {
        _stage = 4;
      } else if (_stage == 4) {
        _stage = 5;
      }
    });
  }

  void _retry() {
    final deal = ref.read(universalDealControllerProvider).deal;
    if (deal == null || !deal.readyToMatch) return;
    setState(() {
      _result = null;
      _selected = null;
      _stage = 0;
      _paymentMode = null;
      _invoicePath = null;
      _future = _loadMatches();
    });
  }

  @override
  Widget build(BuildContext context) {
    final deal = ref.watch(universalDealControllerProvider).deal;
    if (deal == null || !deal.readyToMatch) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFD),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _ink,
          title: const Text('ASKODOX'),
        ),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/search'),
            child: Text(_te ? 'ముందు వివరాలు పూర్తి చేయండి' : 'Complete requirement first'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        title: const Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFE8F8ED),
            child: Icon(Icons.smart_toy_rounded, color: Color(0xFF10A53A), size: 19),
          ),
          SizedBox(width: 8),
          Text('ASKODOX', style: TextStyle(fontWeight: FontWeight.w900)),
        ]),
      ),
      body: FutureBuilder<UniversalMatchResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _LoadingConversation(te: _te);
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            if (error is DealNeedsDetailsException) {
              return _NeedsDetails(
                exception: error,
                onComplete: () => context.go('/search'),
                te: _te,
              );
            }
            return _MatchError(message: '$error', onRetry: _retry, te: _te);
          }
          final result = snapshot.data;
          if (result == null) {
            return _MatchError(
              message: 'Matching finished without a result.',
              onRetry: _retry,
              te: _te,
            );
          }
          _result ??= result;
          if (result.matches.isEmpty) {
            return _NoMatches(onBroaden: () => context.go('/search'), te: _te);
          }
          return _conversation(result);
        },
      ),
    );
  }

  Widget _conversation(UniversalMatchResult result) {
    final selected = _selected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        _AssistantBubble(
          text: _te
              ? 'మీ requirementకి ${result.matches.length} మంచి options దొరికాయి. Shop ఎంచుకున్న వెంటనే దాని కింద details, doubts, bargaining, confirmation కొనసాగుతాయి.'
              : 'I found ${result.matches.length} good options. Choose one; details, questions, negotiation and confirmation continue directly below it.',
        ),
        const SizedBox(height: 16),
        for (final match in result.matches) ...[
          _MatchCard(
            match: match,
            te: _te,
            selected: selected?.id == match.id,
            onTap: () => _select(match),
          ),
          if (selected?.id == match.id) ...[
            const SizedBox(height: 10),
            _selectedConversation(match),
          ],
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _selectedConversation(UniversalMatch selected) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AssistantBubble(text: _selectedSummary(selected)),
          for (final entry in _clarifications) ...[
            const SizedBox(height: 9),
            _UserBubble(text: entry.key),
            const SizedBox(height: 9),
            _SellerBubble(title: selected.title, text: entry.value),
          ],
          if (_stage < 2) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _questionController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _askQuestion(),
              decoration: InputDecoration(
                hintText: _te
                    ? 'Rate, stock, quality, delivery, bargaining… ఏదైనా అడగండి'
                    : 'Ask about rate, stock, quality, delivery or negotiate…',
                filled: true,
                fillColor: Colors.white,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: _askQuestion,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                label: Text(_te ? 'Final rate ఎంత?' : 'What is the final rate?'),
                onPressed: () => _askQuestion(_te ? 'Final rate ఎంత?' : 'What is the final rate?'),
              ),
              ActionChip(
                label: Text(_te ? 'Stock ఉందా?' : 'Is it in stock?'),
                onPressed: () => _askQuestion(_te ? 'Stock ఉందా?' : 'Is it in stock?'),
              ),
              ActionChip(
                label: Text(_te ? 'Rate తగ్గుతుందా?' : 'Can the price be lower?'),
                onPressed: () => _askQuestion(_te ? 'Rate తగ్గుతుందా?' : 'Can the price be lower?'),
              ),
              ActionChip(
                label: Text(_te ? 'Delivery / pickup?' : 'Delivery / pickup?'),
                onPressed: () => _askQuestion(_te ? 'Delivery / pickup?' : 'Delivery / pickup?'),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => FocusScope.of(context).requestFocus(FocusNode()),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(_te ? 'ఇంకా వివరాలు అడగాలి' : 'Ask more details'),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _confirm,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(_te ? 'అన్నీ సరే — Confirm' : 'All clear — Confirm'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              _te
                  ? 'ASKODOXకి clarity లేని విషయం ఉంటే guess చేయదు; sellerతో verify చేసిన తర్వాతే confirmationకి తీసుకెళ్తుంది.'
                  : 'ASKODOX will not guess an unclear detail; it will verify with the seller before confirmation.',
              style: const TextStyle(color: _mutedInk, fontSize: 12.5),
            ),
          ] else if (_stage == 2) ...[
            const SizedBox(height: 10),
            _SellerBubble(
              title: selected.title,
              text: _te
                  ? 'మీ requirement confirm చేశాను. మీ కోసం reserve చేశాను.'
                  : 'Your requirement is confirmed and reserved for you.',
            ),
            const SizedBox(height: 10),
            _AssistantBubble(
              text: _te
                  ? 'Deal confirm అయింది. ఇప్పుడు payment mode ఎంచుకోండి. ASKODOX మీ paymentని collect చేయదు.'
                  : 'The deal is confirmed. Choose a payment mode. ASKODOX does not collect the seller payment.',
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _createInvoice(
                        paymentMode: 'PAY ON DELIVERY / PICKUP',
                        paymentStatus: 'PENDING - PAY SELLER DIRECTLY',
                      ),
              icon: const Icon(Icons.payments_outlined),
              label: Text(_te ? 'Delivery/Pickup వద్ద sellerకి pay చేస్తాను' : 'Pay seller on delivery/pickup'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _showDemoUpi,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: Text(_te ? 'Demo UPI QR చూడండి' : 'Show demo UPI QR'),
            ),
            if (_paymentMode == 'DEMO UPI') ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5EAF2)),
                ),
                child: Column(children: [
                  const Text('DEMO UPI — NO REAL PAYMENT', style: TextStyle(color: _ink, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  QrImageView(
                    data: 'upi://pay?pa=demo@askodox&pn=ASKODOX%20DEMO&am=${selected.price?.toStringAsFixed(2) ?? '0.00'}&cu=INR',
                    size: 180,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _te ? 'ఇది test QR మాత్రమే. నిజమైన డబ్బు పంపదు.' : 'This QR is for testing only and does not transfer real money.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _mutedInk),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _createInvoice(
                              paymentMode: 'DEMO UPI',
                              paymentStatus: 'DEMO PAID - NO REAL MONEY TRANSFERRED',
                            ),
                    child: Text(_te ? 'Demo payment completeగా mark చేయి' : 'Mark demo payment complete'),
                  ),
                ]),
              ),
            ],
          ] else if (_stage == 3) ...[
            const SizedBox(height: 10),
            _AssistantBubble(
              text: _te
                  ? 'Payment choice save అయింది. Order invoice PDF create చేశాను.'
                  : 'Payment choice saved. I created the order invoice PDF.',
            ),
            if (_invoicePath != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                _te ? 'Invoice file: $_invoicePath' : 'Invoice file: $_invoicePath',
                style: const TextStyle(color: _mutedInk, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _refreshStatus,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_te ? 'తాజా order స్థితి చూడండి' : 'Check latest order status'),
            ),
          ] else if (_stage == 4) ...[
            const SizedBox(height: 10),
            _SellerBubble(
              title: selected.title,
              text: _te
                  ? 'మీ order readyగా ఉంది. Pickup / deliveryకి సిద్ధం.'
                  : 'Your order is ready for pickup or delivery.',
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _refreshStatus,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_te ? 'మళ్లీ స్థితి చూడండి' : 'Check status again'),
            ),
          ] else ...[
            const SizedBox(height: 10),
            _AssistantBubble(
              text: _te
                  ? 'Deal completed ✅. Requirement, seller clarification, bargaining, payment choice, invoice, status అన్నీ ఈ conversationలోనే ఉంటాయి.'
                  : 'Deal completed ✅. Requirement, seller clarification, negotiation, payment choice, invoice and status remain in this conversation.',
            ),
          ],
        ],
      );

  String _selectedSummary(UniversalMatch match) {
    final parts = <String>[];
    if (match.distanceKm != null) parts.add('${match.distanceKm!.toStringAsFixed(1)} km');
    if (match.price != null) parts.add('₹${match.price!.toStringAsFixed(0)}');
    if (match.trustScore != null) parts.add('Trust ${match.trustScore!.round()}%');
    if (match.availabilityScore != null) {
      parts.add('Availability ${match.availabilityScore!.round()}%');
    }
    return _te
        ? '${match.title} మీ requirementకి మంచి fit. ${parts.join(' • ')}. Deal confirm చేసే ముందు మీకు కావాల్సిన ఏ detail అయినా ఇక్కడే అడగండి.'
        : '${match.title} is a good fit. ${parts.join(' • ')}. Ask anything you need before confirming the deal.';
  }
}

class _LoadingConversation extends StatelessWidget {
  const _LoadingConversation({required this.te});
  final bool te;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
        children: [
          _AssistantBubble(
            text: te
                ? 'సరే. మీ వివరాలను బట్టి దగ్గరలో సరైన options చూస్తున్నాను…'
                : 'Got it. I am checking the best nearby options for your requirement…',
          ),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft, child: _ThinkingDots()),
        ],
      );
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.te,
    required this.selected,
    required this.onTap,
  });

  final UniversalMatch match;
  final bool te;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _purple : const Color(0xFFE5EAF2),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFEAF1FF),
                child: Icon(Icons.storefront_rounded, color: Color(0xFF1769FF)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  match.title,
                  style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
              if (match.id.startsWith('demo-'))
                const Icon(Icons.verified_rounded, color: Color(0xFF1769FF), size: 20),
            ]),
            if (match.subtitle != null && match.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(match.subtitle!, style: const TextStyle(color: _mutedInk, height: 1.35)),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 7, runSpacing: 7, children: [
              if (match.score != null) _Pill('Fit ${match.score!.clamp(0, 100).round()}%'),
              if (match.distanceKm != null) _Pill('${match.distanceKm!.toStringAsFixed(1)} km'),
              if (match.price != null) _Pill('₹${match.price!.toStringAsFixed(0)}'),
              if (match.trustScore != null) _Pill('Trust ${match.trustScore!.round()}%'),
            ]),
            const SizedBox(height: 10),
            Text(
              te ? 'దీని గురించి అడగండి →' : 'Ask about this option →',
              style: const TextStyle(color: _purple, fontWeight: FontWeight.w800),
            ),
          ]),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F4F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
      );
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1FF),
            borderRadius: BorderRadius.circular(19),
          ),
          child: Text(
            text,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, height: 1.4),
          ),
        ),
      );
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CircleAvatar(
            radius: 19,
            backgroundColor: Color(0xFFE8F8ED),
            child: Icon(Icons.smart_toy_rounded, color: Color(0xFF10A53A), size: 22),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 320),
              builder: (context, value, child) => Opacity(opacity: value, child: child),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: const Color(0xFFE5EAF2)),
                ),
                child: Text(
                  text,
                  style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, height: 1.48),
                ),
              ),
            ),
          ),
        ]),
      );
}

class _SellerBubble extends StatelessWidget {
  const _SellerBubble({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF1FAF4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFCDEED8)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.storefront_rounded, color: Color(0xFF10A53A), size: 19),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: _ink, fontWeight: FontWeight.w900),
                ),
              ),
            ]),
            const SizedBox(height: 7),
            Text(
              text,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w600, height: 1.45),
            ),
          ]),
        ),
      );
}

class _ThinkingDots extends StatelessWidget {
  const _ThinkingDots();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: 48),
        child: Text(
          '●  ●  ●',
          style: TextStyle(color: Color(0xFF9AA3B2), letterSpacing: 3, fontSize: 11),
        ),
      );
}

class _NeedsDetails extends StatelessWidget {
  const _NeedsDetails({
    required this.exception,
    required this.onComplete,
    required this.te,
  });

  final DealNeedsDetailsException exception;
  final VoidCallback onComplete;
  final bool te;

  static const _englishLabels = <String, String>{
    'subject': 'what you need',
    'location': 'location',
    'timing': 'timing',
    'from_location': 'pickup / from location',
    'to_location': 'destination / to location',
    'issue': 'issue details',
    'applicant_context': 'applicant details',
    'question': 'your question',
  };

  static const _teluguLabels = <String, String>{
    'subject': 'ఏది కావాలో',
    'location': 'లొకేషన్',
    'timing': 'ఎప్పుడు కావాలో',
    'from_location': 'ఎక్కడి నుంచి',
    'to_location': 'ఎక్కడికి',
    'issue': 'సమస్య వివరాలు',
    'applicant_context': 'అప్లికెంట్ వివరాలు',
    'question': 'మీ ప్రశ్న',
  };

  String _label(String field) {
    final labels = te ? _teluguLabels : _englishLabels;
    return labels[field] ?? field.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final labels = exception.missingFields.map(_label).toList(growable: false);
    final details = labels.isEmpty
        ? (te ? 'కొన్ని వివరాలు ఇంకా కావాలి.' : 'A few more details are required.')
        : (te
            ? 'ఇంకా కావాల్సింది: ${labels.join(', ')}.'
            : 'Still needed: ${labels.join(', ')}.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.edit_note_rounded, size: 52, color: _ink),
          const SizedBox(height: 12),
          Text(
            te ? 'Match చేసే ముందు ఈ వివరాలు పూర్తి చేయండి' : 'Complete these details before matching',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(details, textAlign: TextAlign.center, style: const TextStyle(color: _mutedInk)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onComplete,
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(te ? 'వివరాలు పూర్తి చేయండి' : 'Complete details'),
          ),
        ]),
      ),
    );
  }
}

class _MatchError extends StatelessWidget {
  const _MatchError({required this.message, required this.onRetry, required this.te});
  final String message;
  final VoidCallback onRetry;
  final bool te;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: _ink),
            const SizedBox(height: 12),
            Text(
              te ? 'ఇప్పుడు match verify చేయలేకపోయాను.' : 'I could not verify matches right now.',
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _mutedInk)),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(te ? 'మళ్లీ ప్రయత్నించు' : 'Retry'),
            ),
          ]),
        ),
      );
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.onBroaden, required this.te});
  final VoidCallback onBroaden;
  final bool te;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.search_off_rounded, size: 52, color: _ink),
            const SizedBox(height: 12),
            Text(
              te ? 'ఇప్పటికి మంచి match దొరకలేదు.' : 'No strong match yet.',
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              te ? 'మీ requirementలో ఏదైనా మార్చి మళ్లీ చూడవచ్చు.' : 'You can adjust the requirement and try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _mutedInk),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onBroaden, child: Text(te ? 'వివరాలు మార్చు' : 'Adjust details')),
          ]),
        ),
      );
}
