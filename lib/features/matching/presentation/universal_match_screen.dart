import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../deal_brain/application/universal_deal_controller.dart';
import '../data/universal_match_repository.dart';

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
    if (_future == null && deal != null && deal.readyToMatch) {
      _future = _loadMatches();
    }
  }

  Future<UniversalMatchResult> _loadMatches() async {
    final deal = ref.read(universalDealControllerProvider).deal;
    if (deal == null || !deal.readyToMatch) {
      throw StateError('Complete the requirement before matching.');
    }

    // Keep provider creation and the first repository call inside an async
    // boundary. In release builds a synchronous provider/configuration error
    // previously escaped didChangeDependencies and could leave a blank grey
    // branch screen instead of a recoverable error state.
    final repository = ref.read(universalMatchRepositoryProvider);
    return repository.createAndMatch(deal);
  }

  Future<void> _accept(UniversalMatchResult result, UniversalMatch match) async {
    if (_acceptingId != null) return;
    setState(() => _acceptingId = match.id);
    try {
      await ref.read(universalMatchRepositoryProvider).acceptMatch(
            dealId: result.dealId,
            matchId: match.id,
          );
      if (mounted) context.go('/deals');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _acceptingId = null);
    }
  }

  void _retry() {
    final deal = ref.read(universalDealControllerProvider).deal;
    if (deal == null || !deal.readyToMatch) return;
    setState(() {
      _future = _loadMatches();
    });
  }

  @override
  Widget build(BuildContext context) {
    final deal = ref.watch(universalDealControllerProvider).deal;
    if (deal == null || !deal.readyToMatch) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        appBar: AppBar(title: const Text('Matches')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/search'),
            child: const Text('Complete requirement first'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Best matches'),
      ),
      body: FutureBuilder<UniversalMatchResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('ASKODOX is finding the best matches…'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return _MatchError(message: '${snapshot.error}', onRetry: _retry);
          }
          final result = snapshot.data;
          if (result == null) {
            return _MatchError(
              message: 'Matching finished without a result. Please retry.',
              onRetry: _retry,
            );
          }
          if (result.matches.isEmpty) {
            return _NoMatches(
              onBroaden: () => context.go('/search'),
              onDeals: () => context.go('/deals'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'ASKODOX found ${result.matches.length} match${result.matches.length == 1 ? '' : 'es'}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text('Choose the best fit. Matching is based on your confirmed requirement, not on commission.'),
              const SizedBox(height: 16),
              for (final match in result.matches)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(match.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        if (match.subtitle != null && match.subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(match.subtitle!),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (match.score != null) Chip(label: Text('Fit ${(match.score! * 100).round()}%')),
                            if (match.distanceKm != null) Chip(label: Text('${match.distanceKm!.toStringAsFixed(1)} km')),
                            if (match.price != null) Chip(label: Text('₹${match.price!.toStringAsFixed(0)}')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _acceptingId == null ? () => _accept(result, match) : null,
                          icon: _acceptingId == match.id
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.handshake_outlined),
                          label: const Text('Accept & connect'),
                        ),
                      ],
                    ),
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
            const Icon(Icons.cloud_off_outlined, size: 52),
            const SizedBox(height: 12),
            const Text('Live matching is not available yet.', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
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
            const Icon(Icons.search_off_rounded, size: 58),
            const SizedBox(height: 12),
            const Text('No strong match found yet', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Broaden the search scope or keep the requirement active so ASKODOX can connect the opposite side when available.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onBroaden, child: const Text('Broaden search')),
            TextButton(onPressed: onDeals, child: const Text('Open deals')),
          ]),
        ),
      );
}
