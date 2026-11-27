import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme/askodox_look.dart';
import '../../core/providers/backend_providers.dart';
import '../../shared/widgets/estimate_note.dart';
import '../home/domain/shopping_mode.dart';
import '../money_home/money_home_store.dart';
import '../pos/data/pos_repository.dart';
import 'morning_brief_logic.dart';

/// The chip above the Home chat. On only in `main()`; tests keep it off.
bool askodoxMorningBriefChip = false;

/// The brief of one side: '' = the person's own, else that shop. Signed out = nothing to show.
final askodoxMorningBriefProvider = FutureProvider.autoDispose.family<AskodoxJson, String>((ref, shop) async {
  if (ref.watch(authSessionProvider).user == null) return const {};
  final repo = ref.watch(askodoxPosRepositoryProvider);
  return shop.isEmpty ? repo.myBrief() : repo.shopBrief(shop);
});

void _open(BuildContext context, String route) {
  if (route == '/mode') {
    context.go(route); // a tab of the bottom bar
  } else {
    context.push(route);
  }
}

/// "ఈ రోజు 3 పనులు" above the chat: shown only when something waits; a tap opens the brief.
class AskodoxMorningBriefChipStrip extends ConsumerWidget {
  const AskodoxMorningBriefChipStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!askodoxMorningBriefChip) return const SizedBox.shrink();
    var shop = '';
    if (ref.watch(askodoxSellerModeProvider)) {
      final picked = askodoxPickShop(ref.watch(askodoxMyShopsProvider).valueOrNull ?? const [], ref.watch(askodoxMoneyShopProvider));
      if (picked == null) return const SizedBox.shrink();
      shop = '${picked['id']}';
    }
    final tasks = askodoxBriefTasks(ref.watch(askodoxMorningBriefProvider(shop)).valueOrNull?['tasks']);
    if (tasks.isEmpty) return const SizedBox.shrink();
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ActionChip(
          key: const Key('askodoxMorningBriefChip'),
          avatar: const Icon(Icons.wb_sunny_outlined, size: 16, color: AskodoxLook.accentText),
          label: Text(askodoxBriefHeadline(tasks.length, te), style: const TextStyle(fontWeight: FontWeight.w700)),
          onPressed: () => context.push(shop.isEmpty ? '/brief' : '/pos/$shop/brief'),
        ),
      ),
    );
  }
}

/// The brief itself: a greeting, at most three things with ONE button each, and what was done yesterday.
class AskodoxMorningBriefScreen extends ConsumerWidget {
  const AskodoxMorningBriefScreen({super.key, this.businessId = ''});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final brief = ref.watch(askodoxMorningBriefProvider(businessId));
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఈ రోజు' : 'Today')),
      body: SafeArea(
        child: brief.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(te ? 'ఇప్పుడు చూపలేకపోయాం. మళ్ళీ ప్రయత్నించండి.' : 'Could not show this now. Please try again.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('askodoxBriefRetry'),
                onPressed: () => ref.invalidate(askodoxMorningBriefProvider(businessId)),
                child: Text(te ? 'మళ్ళీ' : 'Try again'),
              ),
            ]),
          ),
          data: (data) => _body(context, data, te),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AskodoxJson data, bool te) {
    final tasks = askodoxBriefTasks(data['tasks']);
    final handled = askodoxBriefHandled(data['handled'], te);
    final weekday = data['weekday'] is num ? (data['weekday'] as num).toInt() : DateTime.now().weekday - 1;
    return ListView(
      key: const Key('askodoxMorningBrief'),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
      children: [
        Text(askodoxBriefGreeting(weekday, DateTime.now().hour, te),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AskodoxLook.muted)),
        Text(askodoxBriefHeadline(tasks.length, te),
            key: const Key('askodoxBriefHeadline'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        for (var i = 0; i < tasks.length; i++) _task(context, i + 1, tasks[i], te),
        if (handled.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(te ? 'నిన్న ASKODOX చూసుకున్నవి' : 'What ASKODOX took care of yesterday',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AskodoxLook.muted)),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < handled.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _count(handled[i].$1, handled[i].$2)),
            ],
          ]),
        ],
        const SizedBox(height: 20),
        Text(
            te
                ? 'ASKODOX డ్రాఫ్ట్ చేస్తుంది · మీరు ఆమోదిస్తేనే పంపుతుంది'
                : 'ASKODOX drafts · it is sent only when you approve',
            key: const Key('askodoxBriefApproveNote'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted)),
        if (askodoxBriefShowsMoney(tasks)) ...[
          const SizedBox(height: 8),
          const AskodoxEstimateNote(),
        ],
      ],
    );
  }

  Widget _task(BuildContext context, int number, AskodoxBriefTask task, bool te) {
    return Card(
      key: ValueKey('askodoxBriefTask-${task.key}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: AskodoxLook.bg, border: Border.all(color: AskodoxLook.accent, width: 1.5)),
            child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w800, color: AskodoxLook.accentText)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(askodoxBriefTitle(task, te), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text(askodoxBriefSub(task, te), style: const TextStyle(fontSize: 13, color: AskodoxLook.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: ValueKey('askodoxBriefGo-${task.key}'),
            onPressed: () => _open(context, task.route),
            child: Text(askodoxBriefButton(task, te)),
          ),
        ]),
      ),
    );
  }

  Widget _count(String label, int value) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Text('$value',
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: AskodoxLook.good, fontFeatures: AskodoxLook.figures)),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AskodoxLook.muted)),
        ]),
      ),
    );
  }
}
