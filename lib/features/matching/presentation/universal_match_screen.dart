import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../deal_brain/application/universal_deal_controller.dart';
import '../data/demo_natural_match_catalog.dart';
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
    final repository = ref.read(universalMatchRepositoryProvider);
    try {
      return await repository.createAndMatch(deal);
    } catch (_) {
      final demoMatches = DemoNaturalMatchCatalog.forDeal(deal)
        ..sort((a, b) => b.totalValueScore.compareTo(a.totalValueScore));
      return UniversalMatchResult(
        dealId: 'local-${DateTime.now().microsecondsSinceEpoch}',
        matches: demoMatches,
      );
    }
  }

  bool get _te {
    final raw = ref.read(universalDealControllerProvider).deal?.rawText ?? '';
    return RegExp(r'[\u0C00-\u0C7F]').hasMatch(raw);
  }

  void _select(UniversalMatch match) {
    setState(() {
      _selected = match;
      _stage = 0;
    });
  }

  void _askPrice() {
    setState(() => _stage = 1);
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

  void _refreshStatus() {
    setState(() => _stage = _stage == 2 ? 3 : 4);
  }

  void _retry() {
    final deal = ref.read(universalDealControllerProvider).deal;
    if (deal == null || !deal.readyToMatch) return;
    setState(() {
      _result = null;
      _selected = null;
      _stage = 0;
      _future = _loadMatches();
    });
  }

  @override
  Widget build(BuildContext context) {
    final deal = ref.watch(universalDealControllerProvider).deal;
    if (deal == null || !deal.readyToMatch) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFD),
        appBar: AppBar(backgroundColor: Colors.white, foregroundColor: _ink, title: const Text('ASKODOX')),
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
            return _MatchError(message: '${snapshot.error}', onRetry: _retry, te: _te);
          }
          final result = snapshot.data;
          if (result == null) {
            return _MatchError(message: 'Matching finished without a result.', onRetry: _retry, te: _te);
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
              ? 'మీ requirementకి ${result.matches.length} మంచి options దొరికాయి. ముందుగా దగ్గర, ధర, trust చూసి చూపిస్తున్నాను. మీకు నచ్చినదాని గురించి నన్ను అడగండి.'
              : 'I found ${result.matches.length} good options for your requirement. I have ranked them by fit, distance, price and trust. Ask me about any one of them.',
        ),
        const SizedBox(height: 16),
        for (final match in result.matches) ...[
          _MatchCard(match: match, te: _te, selected: selected?.id == match.id, onTap: () => _select(match)),
          const SizedBox(height: 10),
        ],
        if (selected != null) ...[
          const SizedBox(height: 8),
          _UserBubble(text: _te ? '${selected.title} గురించి చెప్పు' : 'Tell me about ${selected.title}'),
          const SizedBox(height: 12),
          _AssistantBubble(text: _selectedSummary(selected)),
          const SizedBox(height: 12),
          if (_stage == 0) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: Text(_te ? 'ధర / వివరాలు అడుగు' : 'Ask price / details'),
                  onPressed: _askPrice,
                ),
                ActionChip(
                  label: Text(_te ? 'ఈ షాప్‌ను ఎంచుకో' : 'Choose this seller'),
                  onPressed: _busy ? null : _confirm,
                ),
              ],
            ),
          ] else if (_stage == 1) ...[
            _SellerBubble(
              title: selected.title,
              text: selected.price == null
                  ? (_te ? 'అవును, మీ requirement ప్రస్తుతం available ఉంది. Final details chatలో confirm చేయవచ్చు.' : 'Yes, your requirement is currently available. Final details can be confirmed in chat.')
                  : (_te ? 'ప్రస్తుతం ధర ₹${selected.price!.toStringAsFixed(0)}. మీ cut / quantity / delivery preference ప్రకారం final amount confirm చేస్తాం.' : 'Current price is ₹${selected.price!.toStringAsFixed(0)}. Final amount can be confirmed based on cut, quantity and fulfilment.'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy ? null : _confirm,
              child: Text(_te ? 'సరే, ఈ sellerతో deal confirm చేయి' : 'Okay, confirm with this seller'),
            ),
          ] else if (_stage == 2) ...[
            _SellerBubble(
              title: selected.title,
              text: _te
                  ? 'మీ requirement confirm చేశాను. మీ కోసం reserve చేశాను.'
                  : 'Your requirement is confirmed and reserved for you.',
            ),
            const SizedBox(height: 10),
            _AssistantBubble(
              text: _te
                  ? 'Deal confirm అయింది. ఇక seller నుంచి ready / delivery status update వస్తుంది. మీరు seller-side buttons నొక్కాల్సిన అవసరం లేదు.'
                  : 'The deal is confirmed. From here, the seller will send ready or delivery status updates. You do not need seller-side controls.',
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _refreshStatus,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_te ? 'తాజా స్థితి చూడండి' : 'Check latest status'),
            ),
          ] else if (_stage == 3) ...[
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
            _AssistantBubble(
              text: _te
                  ? 'Deal completed ✅. ఈ conversation historyలో requirement, seller reaction, confirmation, status అన్నీ ఒకేచోట ఉంటాయి.'
                  : 'Deal completed ✅. Requirement, seller reaction, confirmation and status remain together in this conversation history.',
            ),
          ],
        ],
      ],
    );
  }

  String _selectedSummary(UniversalMatch match) {
    final parts = <String>[];
    if (match.distanceKm != null) parts.add('${match.distanceKm!.toStringAsFixed(1)} km');
    if (match.price != null) parts.add('₹${match.price!.toStringAsFixed(0)}');
    if (match.trustScore != null) parts.add('${_te ? 'Trust' : 'Trust'} ${match.trustScore!.round()}%');
    if (match.availabilityScore != null) parts.add('${_te ? 'Availability' : 'Availability'} ${match.availabilityScore!.round()}%');
    final detail = parts.join(' • ');
    return _te
        ? '${match.title} మీ requirementకి మంచి fit. $detail. కావాలంటే ధర, availability లేదా details అడగండి.'
        : '${match.title} is a good fit for your requirement. $detail. You can ask about price, availability or details.';
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
  const _MatchCard({required this.match, required this.te, required this.selected, required this.onTap});
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
            border: Border.all(color: selected ? _purple : const Color(0xFFE5EAF2), width: selected ? 1.6 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFEAF1FF),
                child: Icon(Icons.storefront_rounded, color: Color(0xFF1769FF)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(match.title, style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w900))),
              if (match.id.startsWith('demo-')) const Icon(Icons.verified_rounded, color: Color(0xFF1769FF), size: 20),
            ]),
            if (match.subtitle != null && match.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(match.subtitle!, style: const TextStyle(color: _mutedInk, height: 1.35)),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 7, runSpacing: 7, children: [
              if (match.score != null) _Pill('${te ? 'Fit' : 'Fit'} ${match.score!.clamp(0, 100).round()}%'),
              if (match.distanceKm != null) _Pill('${match.distanceKm!.toStringAsFixed(1)} km'),
              if (match.price != null) _Pill('₹${match.price!.toStringAsFixed(0)}'),
              if (match.trustScore != null) _Pill('Trust ${match.trustScore!.round()}%'),
            ]),
            const SizedBox(height: 10),
            Text(te ? 'దీని గురించి అడగండి →' : 'Ask about this option →', style: const TextStyle(color: _purple, fontWeight: FontWeight.w800)),
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
        decoration: BoxDecoration(color: const Color(0xFFF1F4F9), borderRadius: BorderRadius.circular(20)),
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
          decoration: BoxDecoration(color: const Color(0xFFEAF1FF), borderRadius: BorderRadius.circular(19)),
          child: Text(text, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, height: 1.4)),
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
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(19), border: Border.all(color: const Color(0xFFE5EAF2))),
                child: Text(text, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, height: 1.48)),
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
          decoration: BoxDecoration(color: const Color(0xFFF1FAF4), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFCDEED8))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.storefront_rounded, color: Color(0xFF10A53A), size: 19),
              const SizedBox(width: 7),
              Expanded(child: Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w900))),
            ]),
            const SizedBox(height: 7),
            Text(text, style: const TextStyle(color: _ink, fontWeight: FontWeight.w600, height: 1.45)),
          ]),
        ),
      );
}

class _ThinkingDots extends StatelessWidget {
  const _ThinkingDots();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: 48),
        child: Text('●  ●  ●', style: TextStyle(color: Color(0xFF9AA3B2), letterSpacing: 3, fontSize: 11)),
      );
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
            Text(te ? 'ఇప్పుడు match verify చేయలేకపోయాను.' : 'I could not verify matches right now.', style: const TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _mutedInk)),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(te ? 'మళ్లీ ప్రయత్నించు' : 'Retry')),
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
            Text(te ? 'ఇప్పటికి మంచి match దొరకలేదు.' : 'No strong match yet.', style: const TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            Text(te ? 'మీ requirementలో ఏదైనా మార్చి మళ్లీ చూడవచ్చు.' : 'You can adjust the requirement and try again.', textAlign: TextAlign.center, style: const TextStyle(color: _mutedInk)),
            const SizedBox(height: 14),
            FilledButton(onPressed: onBroaden, child: Text(te ? 'వివరాలు మార్చు' : 'Adjust details')),
          ]),
        ),
      );
}
