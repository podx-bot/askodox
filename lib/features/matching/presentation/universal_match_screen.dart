import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../deal_brain/application/universal_deal_controller.dart';
import '../data/demo_natural_match_catalog.dart';
import '../data/universal_match_repository.dart';

const _ink = Color(0xFF14213D);
const _mutedInk = Color(0xFF475467);

class UniversalMatchScreen extends ConsumerStatefulWidget {
  const UniversalMatchScreen({super.key});

  @override
  ConsumerState<UniversalMatchScreen> createState() => _UniversalMatchScreenState();
}

class _UniversalMatchScreenState extends ConsumerState<UniversalMatchScreen> {
  Future<UniversalMatchResult>? _future;
  String? _acceptingId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deal = ref.read(universalDealControllerProvider).deal;
    if (_future == null && deal != null && deal.readyToMatch) _future = _loadMatches();
  }

  Future<UniversalMatchResult> _loadMatches() async {
    final deal = ref.read(universalDealControllerProvider).deal;
    if (deal == null || !deal.readyToMatch) throw StateError('Complete the requirement before matching.');
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

  Future<void> _accept(UniversalMatchResult result, UniversalMatch match) async {
    if (_acceptingId != null) return;
    setState(() => _acceptingId = match.id);
    try {
      await ref.read(universalMatchRepositoryProvider).acceptMatch(dealId: result.dealId, matchId: match.id);
      if (!mounted) return;
      if (result.dealId.startsWith('local-') || match.id.startsWith('demo-')) {
        await _showDemoReaction(match);
      } else {
        context.go('/deals');
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _acceptingId = null);
    }
  }

  Future<void> _showDemoReaction(UniversalMatch match) async {
    var stage = 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final reaction = switch (stage) {
            0 => 'Yes, your requirement is available now. I can serve you immediately.',
            1 => match.price == null
                ? 'I have confirmed availability. We can continue with the deal.'
                : 'Current demo price is ₹${match.price!.toStringAsFixed(0)}. Final price can be confirmed in chat.',
            2 => 'Confirmed. I have reserved this requirement for you. The deal is now confirmed.',
            3 => 'Ready for pickup / delivery. The provider has marked your requirement ready.',
            _ => 'Completed. The demo deal has successfully moved through the full action and reaction flow.',
          };
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFFE8F7EC),
                      child: const Icon(Icons.storefront_rounded, color: Color(0xFF16A34A), size: 30),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(match.title, style: const TextStyle(color: _ink, fontSize: 19, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text('Demo verified profile • ${(match.distanceKm ?? 0).toStringAsFixed(1)} km away', style: const TextStyle(color: _mutedInk)),
                      ]),
                    ),
                    const Icon(Icons.verified_rounded, color: Color(0xFF2563EB)),
                  ]),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (match.trustScore != null) Chip(label: Text('Trust ${match.trustScore!.round()}%')),
                    if (match.availabilityScore != null) Chip(label: Text('Available ${match.availabilityScore!.round()}%')),
                    if (match.price != null) Chip(label: Text('₹${match.price!.toStringAsFixed(0)}')),
                  ]),
                  const SizedBox(height: 18),
                  Text(
                    switch (stage) {
                      0 => 'Opposite party reaction',
                      1 => 'Price / details',
                      2 => 'Deal confirmed',
                      3 => 'Ready for fulfilment',
                      _ => 'Deal completed',
                    },
                    style: const TextStyle(color: _ink, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(16)),
                    child: Text(reaction, style: const TextStyle(color: _ink, height: 1.4, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 16),
                  if (stage == 0)
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSheetState(() => stage = 1),
                          child: const Text('Ask price / details'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => setSheetState(() => stage = 2),
                          child: const Text('Confirm deal'),
                        ),
                      ),
                    ])
                  else if (stage == 1)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => setSheetState(() => stage = 2),
                        child: const Text('Confirm deal'),
                      ),
                    )
                  else if (stage == 2)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => setSheetState(() => stage = 3),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Mark ready for pickup / delivery'),
                      ),
                    )
                  else if (stage == 3)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => setSheetState(() => stage = 4),
                        icon: const Icon(Icons.done_all_rounded),
                        label: const Text('Complete demo deal'),
                      ),
                    )
                  else
                    Column(children: [
                      const Row(children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
                        SizedBox(width: 8),
                        Expanded(child: Text('Action → Reaction → Confirmed → Ready → Completed', style: TextStyle(color: _ink, fontWeight: FontWeight.w800))),
                      ]),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Done'),
                        ),
                      ),
                    ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _retry() {
    final deal = ref.read(universalDealControllerProvider).deal;
    if (deal == null || !deal.readyToMatch) return;
    setState(() => _future = _loadMatches());
  }

  @override
  Widget build(BuildContext context) {
    final deal = ref.watch(universalDealControllerProvider).deal;
    if (deal == null || !deal.readyToMatch) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        appBar: AppBar(backgroundColor: Colors.white, foregroundColor: _ink, title: const Text('Matches')),
        body: Center(
          child: FilledButton(onPressed: () => context.go('/search'), child: const Text('Complete requirement first')),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(backgroundColor: Colors.white, surfaceTintColor: Colors.white, foregroundColor: _ink, title: const Text('Best matches')),
      body: FutureBuilder<UniversalMatchResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(), SizedBox(height: 14),
              Text('ASKODOX is finding the best matches…', style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            ]));
          }
          if (snapshot.hasError) return _MatchError(message: '${snapshot.error}', onRetry: _retry);
          final result = snapshot.data;
          if (result == null) return _MatchError(message: 'Matching finished without a result. Please retry.', onRetry: _retry);
          if (result.matches.isEmpty) {
            return _NoMatches(onBroaden: () => context.go('/search'), onDeals: () => context.go('/deals'));
          }
          final isDemo = result.dealId.startsWith('local-') || result.matches.any((m) => m.id.startsWith('demo-'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('ASKODOX found ${result.matches.length} match${result.matches.length == 1 ? '' : 'es'}',
                  style: const TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                isDemo
                    ? 'Demo profiles are active so you can test the complete action and reaction flow even when live matching is unavailable.'
                    : 'Choose the best fit. Matching is based on your confirmed requirement, not on commission.',
                style: const TextStyle(color: _mutedInk),
              ),
              const SizedBox(height: 16),
              for (final match in result.matches)
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFFEFF6FF),
                          child: Icon(match.id.startsWith('demo-') ? Icons.storefront_rounded : Icons.person_rounded, color: const Color(0xFF2563EB)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(match.title, style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800))),
                        if (match.id.startsWith('demo-')) const Icon(Icons.verified_rounded, color: Color(0xFF2563EB), size: 20),
                      ]),
                      if (match.subtitle != null && match.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 8), Text(match.subtitle!, style: const TextStyle(color: _mutedInk)),
                      ],
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (match.score != null) Chip(label: Text('Fit ${match.score!.clamp(0, 100).round()}%')),
                        if (match.distanceKm != null) Chip(label: Text('${match.distanceKm!.toStringAsFixed(1)} km')),
                        if (match.price != null) Chip(label: Text('₹${match.price!.toStringAsFixed(0)}')),
                        if (match.trustScore != null) Chip(label: Text('Trust ${match.trustScore!.round()}%')),
                      ]),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _acceptingId == null ? () => _accept(result, match) : null,
                        icon: _acceptingId == match.id
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.handshake_outlined),
                        label: Text(match.id.startsWith('demo-') ? 'Test action & reaction' : 'Accept & connect'),
                      ),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MatchError extends StatelessWidget {
  const _MatchError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 52, color: _ink),
        const SizedBox(height: 12),
        const Text('Live matching is not available yet.', textAlign: TextAlign.center, style: TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _mutedInk, height: 1.4)),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]),
    ),
  );
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.onBroaden, required this.onDeals});
  final VoidCallback onBroaden;
  final VoidCallback onDeals;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search_off_rounded, size: 58, color: _ink),
        const SizedBox(height: 12),
        const Text('No strong match found yet', textAlign: TextAlign.center, style: TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 19)),
        const SizedBox(height: 8),
        const Text('Broaden the search scope or keep the requirement active so ASKODOX can connect the opposite side when available.', textAlign: TextAlign.center, style: TextStyle(color: _mutedInk, height: 1.45)),
        const SizedBox(height: 16),
        FilledButton(onPressed: onBroaden, child: const Text('Broaden search')),
        TextButton(style: TextButton.styleFrom(foregroundColor: const Color(0xFF5B45D6)), onPressed: onDeals, child: const Text('Open deals', style: TextStyle(fontWeight: FontWeight.w800))),
      ]),
    ),
  );
}
