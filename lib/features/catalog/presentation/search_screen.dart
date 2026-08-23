import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../deal_brain/application/universal_deal_controller.dart';
import '../../deal_brain/domain/universal_deal.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _answer = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _answer.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendAnswer() {
    final text = _answer.text.trim();
    if (text.isEmpty) return;
    ref.read(universalDealControllerProvider.notifier).answer(text);
    _answer.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(universalDealControllerProvider);
    final deal = session.deal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ASKODOX'),
        actions: [
          IconButton(
            tooltip: 'Start a new request',
            onPressed: () {
              ref.read(universalDealControllerProvider.notifier).reset();
              context.go('/');
            },
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: deal == null
                ? _EmptyAsk(onAsk: () => context.go('/'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                    children: [
                      _UserRequest(text: deal.rawText),
                      const SizedBox(height: 14),
                      _PartyMatchCard(deal: deal),
                      const SizedBox(height: 14),
                      _RequirementCard(deal: deal),
                      const SizedBox(height: 18),
                      if (!session.completed) ...[
                        _AskodoxQuestion(text: session.lastQuestion ?? 'Tell me the missing detail.'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _answer,
                          focusNode: _focusNode,
                          autofocus: true,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendAnswer(),
                          decoration: InputDecoration(
                            hintText: 'Answer only this detail',
                            prefixIcon: const Icon(Icons.auto_awesome),
                            suffixIcon: IconButton(onPressed: _sendAnswer, icon: const Icon(Icons.arrow_upward)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ASKODOX asks only what is still required for a useful match.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ] else ...[
                        _ReadyToMatch(deal: deal),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => context.push('/deals'),
                          icon: const Icon(Icons.handshake_outlined),
                          label: Text('Open deals & matches'),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _EmptyAsk extends StatelessWidget {
  const _EmptyAsk({required this.onAsk});
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.hub_outlined, size: 68, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Tell ASKODOX what you need or what you can offer', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('One request is enough. ASKODOX identifies both sides and finds the opposite party.', textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton(onPressed: onAsk, child: const Text('Ask ASKODOX')),
          ]),
        ),
      );
}

class _UserRequest extends StatelessWidget {
  const _UserRequest({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(text),
        ),
      );
}

class _PartyMatchCard extends StatelessWidget {
  const _PartyMatchCard({required this.deal});
  final UniversalDeal deal;

  @override
  Widget build(BuildContext context) {
    final a = deal.partyA;
    final b = deal.partyB;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ASKODOX understood the exchange', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Party(side: 'Party A', role: a.role, action: a.action, icon: a.side == DealSide.demand ? Icons.search : Icons.inventory_2_outlined)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.compare_arrows_rounded)),
            Expanded(child: _Party(side: 'Party B', role: b.role, action: b.action, icon: b.side == DealSide.demand ? Icons.search : Icons.inventory_2_outlined)),
          ]),
        ]),
      ),
    );
  }
}

class _Party extends StatelessWidget {
  const _Party({required this.side, required this.role, required this.action, required this.icon});
  final String side;
  final String role;
  final String action;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon),
        const SizedBox(height: 6),
        Text(side, style: Theme.of(context).textTheme.labelMedium),
        Text(role, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(action, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _RequirementCard extends StatelessWidget {
  const _RequirementCard({required this.deal});
  final UniversalDeal deal;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (deal.subject != null && deal.subject!.trim().isNotEmpty) 'Need/offer: ${deal.subject}',
      if (deal.quantity != null) 'Quantity: ${deal.quantity} ${deal.unit ?? ''}',
      if (deal.price != null) 'Price/budget: ₹${deal.price}',
      if (deal.location.isKnown) 'Location: ${deal.location.label ?? '${deal.location.latitude}, ${deal.location.longitude}'}',
      if (deal.timing != null) 'Timing: ${deal.timing}',
      if (deal.fulfilment != null) 'Fulfilment: ${deal.fulfilment}',
      for (final entry in deal.dynamicFields.entries)
        if (entry.value != null && '${entry.value}'.trim().isNotEmpty) '${_title(entry.key)}: ${entry.value}',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Requirement', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final item in details) Padding(padding: const EdgeInsets.only(bottom: 5), child: Text('• $item')),
          if (deal.missingForMatch.isNotEmpty) ...[
            const Divider(height: 22),
            Text('Still needed: ${deal.missingForMatch.map(_title).join(', ')}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }

  static String _title(String value) => value.replaceAll('_', ' ').split(' ').map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}').join(' ');
}

class _AskodoxQuestion extends StatelessWidget {
  const _AskodoxQuestion({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.auto_awesome, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(text)),
          ]),
        ),
      );
}

class _ReadyToMatch extends StatelessWidget {
  const _ReadyToMatch({required this.deal});
  final UniversalDeal deal;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.hub_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Ready to match', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('ASKODOX should now search for the opposite side: ${deal.partyB.role} (${deal.oppositeIntent.name}).'),
              ]),
            ),
          ]),
        ),
      );
}
