import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme/askodox_look.dart';
import '../../shared/widgets/estimate_note.dart';
import '../kitchen/kitchen_logic.dart';
import '../kitchen/kitchen_store.dart';
import '../vault/vault_logic.dart';
import '../vault/vault_store.dart';

/// "My home" (owner 2026-11-27, design "నా ఇల్లు"): one page for the home -- the kitchen stock, bills & warranty, what
/// this month's groceries came to, and what to remember this week. It only READS what the person already keeps on
/// this phone (kitchen stock and papers); it keeps nothing of its own.

/// One thing to remember this week: [text], the words beside it, whether it is urgent, and where it opens.
class AskodoxHomeReminder {
  const AskodoxHomeReminder(this.text, this.note, this.urgent, this.route);
  final String text, note, route;
  final bool urgent;
}

/// The week's reminders: warranties ending (soonest first, only those the person left the reminder on) and kitchen
/// items that are low / finished. At most [max].
List<AskodoxHomeReminder> askodoxHomeReminders(
    List<AskodoxVaultPaper> papers, List<AskodoxKitchenItem> items, DateTime today, bool te,
    {int max = 6}) {
  final out = <AskodoxHomeReminder>[
    for (final p in askodoxVaultEnding(papers, today))
      AskodoxHomeReminder(
          te ? '${p.item} వారంటీ' : '${p.item} warranty', askodoxVaultStateText(p, today, te), true, '/me/vault'),
    for (final i in askodoxKitchenBuyList(items))
      AskodoxHomeReminder(te ? '${i.name} తక్కువ' : '${i.name} is low', te ? 'కొనాలి' : 'To buy', false, '/me/kitchen'),
  ];
  return out.length > max ? out.sublist(0, max) : out;
}

class AskodoxHomeHubScreen extends ConsumerWidget {
  const AskodoxHomeHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final today = ref.watch(askodoxVaultClockProvider)();
    final papers = ref.watch(askodoxVaultProvider).papers;
    final kitchen = ref.watch(askodoxKitchenProvider).book;
    final ending = askodoxVaultEnding(papers, today).length;
    final low = askodoxKitchenBuyList(kitchen.items).length;
    final spent = askodoxKitchenMonthSpend(kitchen.spends, today);
    final reminders = askodoxHomeReminders(papers, kitchen.items, today, te);
    return Scaffold(
      key: const Key('askodoxHomeHub'),
      appBar: AppBar(title: Text(te ? 'నా ఇల్లు' : 'My home')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          FilledButton.icon(
            key: const Key('askodoxHomeHubPhoto'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => context.push('/me/vault?photo=camera'),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(te ? 'బిల్ ఫోటో తీయండి' : 'Photograph a bill'),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: [
              _tile(context, 'askodoxHomeHubKitchen', te ? 'వంటగది స్టాక్' : 'Kitchen stock',
                  low > 0 ? (te ? '$low కొనాలి' : '$low to buy') : (te ? 'బియ్యం, పప్పులు, నూనె…' : 'Rice, dal, oil…'), low > 0, '/me/kitchen'),
              _tile(context, 'askodoxHomeHubVault', te ? 'బిల్స్ & వారంటీ' : 'Bills & warranty',
                  ending > 0 ? (te ? '$ending ముగుస్తున్నాయి' : '$ending ending') : (te ? 'మీ ఫోన్‌లోనే' : 'On your phone'), ending > 0, '/me/vault'),
              _tile(context, 'askodoxHomeHubSpend', te ? 'ఇంటి ఖర్చులు' : 'Home spending',
                  spent > 0 ? (te ? 'ఈ నెల కిరాణా ${askodoxKitchenRupees(spent)}' : 'Groceries this month ${askodoxKitchenRupees(spent)}')
                      : (te ? 'ఈ నెల కిరాణా రాయండి' : 'Note this month\'s groceries'), false, '/me/kitchen'),
              _tile(context, 'askodoxHomeHubFamily', te ? 'కుటుంబ లిస్ట్' : 'Family list',
                  te ? 'అందరూ కలిసి కొనుగోలు జాబితా' : 'One shopping list for the home', false, '/me/family-list'),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(te ? 'ఈ వారం గుర్తు చేయాల్సినవి' : 'To remember this week', style: const TextStyle(fontWeight: FontWeight.w800)),
                if (reminders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(te ? 'ఇప్పుడు ఏమీ ముగుస్తున్నది కనిపించడం లేదు.' : 'Nothing is running out or ending right now.',
                        key: const Key('askodoxHomeHubNothing'), style: const TextStyle(color: AskodoxLook.muted)),
                  ),
                for (var i = 0; i < reminders.length; i++)
                  ListTile(
                    key: ValueKey('askodoxHomeHubReminder-$i'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(reminders[i].text),
                    trailing: Text(reminders[i].note,
                        style: TextStyle(fontWeight: FontWeight.w800, color: reminders[i].urgent ? AskodoxLook.accentText : AskodoxLook.text)),
                    onTap: () => context.push(reminders[i].route),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text(
              te
                  ? 'మీ బిల్స్, ఫోటోలు ఈ ఫోన్‌లోనే ఉంటాయి. కుటుంబంతో ఏది పంచుకోవాలో మీరే ఎంచుకుంటారు.'
                  : 'Your bills and photos stay on this phone. You choose what to share with the family.',
              key: const Key('askodoxHomeHubPrivacy'),
              style: const TextStyle(color: AskodoxLook.muted)),
          const SizedBox(height: 12),
          const AskodoxEstimateNote(),
        ]),
      ),
    );
  }

  Widget _tile(BuildContext context, String keyName, String title, String note, bool hot, String route) => InkWell(
        key: Key(keyName),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(route),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AskodoxLook.sheet,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: hot ? AskodoxLook.accentText : AskodoxLook.line, width: hot ? 2 : 1.2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: hot ? AskodoxLook.accentText : AskodoxLook.muted)),
          ]),
        ),
      );
}
