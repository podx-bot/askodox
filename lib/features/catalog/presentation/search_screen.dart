import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../deal_brain/application/universal_deal_controller.dart';
import '../../deal_brain/domain/universal_deal.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _answer = TextEditingController();
  final _focusNode = FocusNode();

  static const _explore = <(String, IconData, String)>[
    ('Buy & Sell', Icons.shopping_bag_outlined, 'I want to buy or sell something'),
    ('Jobs', Icons.work_outline_rounded, 'I am looking for a job or worker'),
    ('Services', Icons.handyman_outlined, 'I need or provide a service'),
    ('Rides & Travel', Icons.directions_car_outlined, 'I need or offer a ride or travel service'),
    ('Loans', Icons.account_balance_outlined, 'I want to compare loan options'),
    ('Insurance', Icons.health_and_safety_outlined, 'I want to compare insurance options'),
    ('Credit Cards', Icons.credit_card_outlined, 'I want to compare credit cards'),
    ('Utilities', Icons.bolt_outlined, 'I need a utility or bill service'),
  ];

  @override void dispose() { _answer.dispose(); _focusNode.dispose(); super.dispose(); }

  void _sendAnswer() {
    final text = _answer.text.trim();
    if (text.isEmpty) return;
    ref.read(universalDealControllerProvider.notifier).answer(text);
    _answer.clear();
    _focusNode.requestFocus();
  }

  void _start(String prompt) {
    ref.read(universalDealControllerProvider.notifier).start(prompt);
    _focusNode.requestFocus();
  }

  @override Widget build(BuildContext context) {
    final session = ref.watch(universalDealControllerProvider);
    final deal = session.deal;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ASKODOX'),
        actions: [
          IconButton(tooltip: 'New request', onPressed: () { ref.read(universalDealControllerProvider.notifier).reset(); context.go('/'); }, icon: const Icon(Icons.add_circle_outline)),
        ],
      ),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: deal == null ? _Explore(onStart: _start) : ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            _UserRequest(text: deal.rawText),
            const SizedBox(height: 14),
            _RequirementCard(deal: deal),
            const SizedBox(height: 14),
            if (!session.completed) ...[
              _AskodoxQuestion(text: session.lastQuestion ?? 'Tell me the missing detail.'),
              const SizedBox(height: 10),
              TextField(
                key: const Key('askodoxClarificationField'), controller: _answer, focusNode: _focusNode,
                autofocus: true, textInputAction: TextInputAction.send, onSubmitted: (_) => _sendAnswer(),
                decoration: InputDecoration(hintText: 'Answer only this detail', prefixIcon: const Icon(Icons.auto_awesome), suffixIcon: IconButton(onPressed: _sendAnswer, icon: const Icon(Icons.arrow_upward))),
              ),
              const SizedBox(height: 8),
              Text('ASKODOX remembers what you already said and asks only what is still needed.', style: Theme.of(context).textTheme.bodySmall),
            ] else ...[
              _ReadyToMatch(deal: deal),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => _focusNode.requestFocus(), icon: const Icon(Icons.edit_outlined), label: const Text('Change'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.icon(key: const Key('confirmRequirementButton'), onPressed: () => context.push('/deals'), icon: const Icon(Icons.check_circle_outline), label: const Text('Confirm & match'))),
              ]),
              const SizedBox(height: 18),
              _ComparisonEntry(onStart: _start),
            ],
            const SizedBox(height: 24),
            _ExploreCompact(onStart: _start),
          ],
        ),
      ))),
    );
  }
}

class _Explore extends StatelessWidget {
  const _Explore({required this.onStart}); final ValueChanged<String> onStart;
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(20, 28, 20, 28), children: [
    Text('Explore ASKODOX', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
    const SizedBox(height: 6),
    const Text('Choose a shortcut or go Home and ask naturally. Every shortcut enters the same AI Deal Brain.'),
    const SizedBox(height: 18),
    for (final item in _SearchScreenState._explore) Card(child: ListTile(leading: Icon(item.$2), title: Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w700)), trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16), onTap: () => onStart(item.$3))),
    const SizedBox(height: 14),
    FilledButton.icon(onPressed: () => context.go('/'), icon: const Icon(Icons.auto_awesome), label: const Text('Ask ASKODOX naturally')),
  ]);
}

class _ExploreCompact extends StatelessWidget {
  const _ExploreCompact({required this.onStart}); final ValueChanged<String> onStart;
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Explore more', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 10),
    Wrap(spacing: 8, runSpacing: 8, children: [for (final item in _SearchScreenState._explore) ActionChip(avatar: Icon(item.$2, size: 17), label: Text(item.$1), onPressed: () => onStart(item.$3))]),
  ]);
}

class _ComparisonEntry extends StatelessWidget {
  const _ComparisonEntry({required this.onStart}); final ValueChanged<String> onStart;
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Compare the best way to fulfil this', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 6), const Text('ASKODOX can widen the search instead of assuming nearest is always best.'), const SizedBox(height: 12),
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final scope in ['Near me', 'My city', 'State', 'India', 'Anywhere', 'Online'])
        ActionChip(label: Text(scope), onPressed: () => onStart('Find and compare this requirement in scope: $scope')),
    ]),
  ])));
}

class _UserRequest extends StatelessWidget {
  const _UserRequest({required this.text}); final String text;
  @override Widget build(BuildContext context) => Align(alignment: Alignment.centerRight, child: Container(constraints: const BoxConstraints(maxWidth: 560), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(18)), child: Text(text)));
}

class _RequirementCard extends StatelessWidget {
  const _RequirementCard({required this.deal}); final UniversalDeal deal;
  @override Widget build(BuildContext context) {
    final details = <String>[
      if (deal.subject != null && deal.subject!.trim().isNotEmpty) 'Need/offer: ${deal.subject}',
      if (deal.quantity != null) 'Quantity: ${deal.quantity} ${deal.unit ?? ''}',
      if (deal.price != null) 'Price/budget: ₹${deal.price}',
      if (deal.location.isKnown) 'Location: ${deal.location.label ?? '${deal.location.latitude}, ${deal.location.longitude}'}',
      if (deal.timing != null) 'Timing: ${deal.timing}', if (deal.fulfilment != null) 'Fulfilment: ${deal.fulfilment}',
      for (final entry in deal.dynamicFields.entries) if (entry.value != null && '${entry.value}'.trim().isNotEmpty) '${_title(entry.key)}: ${entry.value}',
    ];
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.psychology_alt_outlined), const SizedBox(width: 8), Expanded(child: Text('Here is what I understood', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))]),
      const SizedBox(height: 10), for (final item in details) Padding(padding: const EdgeInsets.only(bottom: 5), child: Text('• $item')),
      if (deal.missingForMatch.isNotEmpty) ...[const Divider(height: 22), Text('Still needed: ${deal.missingForMatch.map(_title).join(', ')}', style: Theme.of(context).textTheme.bodySmall)],
    ])));
  }
  static String _title(String value) => value.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

class _AskodoxQuestion extends StatelessWidget {
  const _AskodoxQuestion({required this.text}); final String text;
  @override Widget build(BuildContext context) => Align(alignment: Alignment.centerLeft, child: Container(constraints: const BoxConstraints(maxWidth: 560), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.auto_awesome, size: 20), const SizedBox(width: 8), Flexible(child: Text(text))])));
}

class _ReadyToMatch extends StatelessWidget {
  const _ReadyToMatch({required this.deal}); final UniversalDeal deal;
  @override Widget build(BuildContext context) => Card(color: Theme.of(context).colorScheme.secondaryContainer, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [const Icon(Icons.hub_rounded), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Requirement ready', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('Confirm it and ASKODOX will look for the matching side: ${deal.partyB.role}.')]))])));
}
