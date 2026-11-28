import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme/askodox_look.dart';
import '../../shared/widgets/estimate_note.dart';
import '../money_home/money_home_store.dart';
import 'yield_math.dart';
import 'yield_store.dart';

/// This week's report (owner 2026-11-27, design "వారం రిపోర్ట్"): for one item across the owner's shops, the stock that
/// was not accounted for, the leak day by day, the cost share per shop and the supplier's rate (last lot against the
/// lot before). Everything is read from the owner's own day ends and lots kept on this phone; nothing is sent anywhere.

/// The last [count] day keys, oldest first, ending with [today].
List<String> askodoxWeekDays(DateTime today, {int count = 7}) => [
      for (var i = count - 1; i >= 0; i--) askodoxYieldDayKey(DateTime(today.year, today.month, today.day - i)),
    ];

/// What was missing at the day ends of one day (grams short against the books), over every book given; stock that was
/// MORE than the books is not a leak and is not counted.
int askodoxMissingGrams(Iterable<AskodoxYieldBook> books, String item, String day) {
  var sum = 0;
  for (final b in books) {
    final d = b.dayOf(item, day);
    if (d != null && d.diff < 0) sum += -d.diff;
  }
  return sum;
}

/// Money value of the grams missing, each day at that day's own cost of a kg.
int askodoxMissingPaise(Iterable<AskodoxYieldBook> books, String item, Iterable<String> days) {
  var sum = 0;
  for (final b in books) {
    for (final day in days) {
      final d = b.dayOf(item, day);
      if (d != null && d.diff < 0) sum += askodoxYieldDiffValue(d.diff, d.costPaise);
    }
  }
  return sum;
}

/// What a kg cost against what it sold for over the days, in basis points; null when nothing was sold at a rate.
int? askodoxCostShareBp(AskodoxYieldBook book, String item, Iterable<String> days) {
  var cost = 0, sales = 0;
  for (final day in days) {
    final d = book.dayOf(item, day);
    if (d == null || d.soldGrams <= 0 || d.sellPaise <= 0) continue;
    cost += d.soldGrams * d.costPaise;
    sales += d.soldGrams * d.sellPaise;
  }
  return sales <= 0 ? null : askodoxYieldRoundDiv(cost * 10000, sales);
}

/// The buying rate of the last two lots of [item] over all the books (older first); null with fewer than two.
(int, int)? askodoxSupplierRates(Iterable<AskodoxYieldBook> books, String item) {
  final lots = [for (final b in books) ...b.of(item)]..sort((a, b) => a.day.compareTo(b.day));
  if (lots.length < 2) return null;
  return (lots[lots.length - 2].ratePaise, lots.last.ratePaise);
}

const _teDays = ['సోమ', 'మంగ', 'బుధ', 'గురు', 'శుక్ర', 'శని', 'ఆది'];
const _enDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String askodoxWeekdayName(String dayKey, bool te) {
  final d = DateTime.tryParse(dayKey);
  if (d == null) return '';
  return (te ? _teDays : _enDays)[d.weekday - 1];
}

class AskodoxWeeklyReportScreen extends ConsumerStatefulWidget {
  const AskodoxWeeklyReportScreen({super.key});

  @override
  ConsumerState<AskodoxWeeklyReportScreen> createState() => _AskodoxWeeklyReportScreenState();
}

class _AskodoxWeeklyReportScreenState extends ConsumerState<AskodoxWeeklyReportScreen> {
  String? _item;

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final state = ref.watch(askodoxYieldProvider);
    final shops = ref.watch(askodoxMyShopsProvider).valueOrNull ?? const [];
    final names = {for (final s in shops) '${s['id']}': '${s['name'] ?? ''}'};
    final books = {for (final e in state.books.entries) e.key: e.value};
    final items = <String>{
      for (final b in books.values) ...[for (final d in b.days) d.item, for (final l in b.batches) l.item],
    }.toList();
    final item = _item != null && items.contains(_item) ? _item! : (items.isEmpty ? '' : items.first);
    final days = askodoxWeekDays(DateTime.now());
    final all = books.values.toList();
    final missing = [for (final day in days) askodoxMissingGrams(all, item, day)];
    final total = missing.fold(0, (a, b) => a + b);
    final worth = askodoxMissingPaise(all, item, days);
    final peak = missing.fold(0, (a, b) => a > b ? a : b);
    final rates = askodoxSupplierRates(all, item);
    return Scaffold(
      key: const Key('askodoxWeekly'),
      appBar: AppBar(title: Text(te ? 'ఈ వారం రిపోర్ట్' : 'This week')),
      body: SafeArea(
        child: !state.loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                if (items.isEmpty)
                  Text(
                      te
                          ? 'యీల్డ్ & రేట్లు పేజీలో సరుకు, రోజు ముగింపు రాస్తే ఇక్కడ వారం రిపోర్ట్ కనిపిస్తుంది. సంఖ్యలన్నీ మీవే.'
                          : 'Once you enter lots and day ends on the Yield & rates page, the week shows here. Every number is your own.',
                      key: const Key('askodoxWeeklyEmpty'))
                else ...[
                  Wrap(spacing: 8, children: [
                    for (final name in items)
                      ChoiceChip(
                          key: ValueKey('askodoxWeeklyItem-$name'),
                          label: Text(askodoxYieldItemName(name, te)),
                          selected: item == name,
                          onSelected: (_) => setState(() => _item = name)),
                  ]),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(te ? 'ఈ వారం లెక్కలో లేనిది' : 'Not accounted for this week',
                            style: const TextStyle(color: AskodoxLook.muted)),
                        Text('${askodoxYieldKg(total)} kg ≈ ${askodoxYieldRupees(worth)}',
                            key: const Key('askodoxWeeklyTotal'),
                            style: TextStyle(
                                fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: AskodoxLook.figures,
                                color: total == 0 ? AskodoxLook.good : AskodoxLook.accentText)),
                      ]),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(te ? 'రోజు వారీ లీక్ (kg)' : 'Leak by day (kg)', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 120,
                          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            for (var i = 0; i < days.length; i++)
                              Expanded(
                                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  Text(missing[i] == 0 ? '' : askodoxYieldKg(missing[i]),
                                      style: const TextStyle(fontSize: 10, color: AskodoxLook.muted)),
                                  Container(
                                    key: ValueKey('askodoxWeeklyBar-${days[i]}'),
                                    width: 20,
                                    height: peak == 0 ? 2 : 2 + 72.0 * missing[i] / peak,
                                    decoration: BoxDecoration(
                                        color: missing[i] == 0 ? AskodoxLook.line : AskodoxLook.accentText,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(askodoxWeekdayName(days[i], te), style: const TextStyle(fontSize: 11, color: AskodoxLook.muted)),
                                ]),
                              ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(te ? 'షాప్ వారీగా కాస్ట్ %' : 'Cost share by shop', style: const TextStyle(fontWeight: FontWeight.w800)),
                        for (final e in books.entries)
                          Builder(builder: (context) {
                            final bp = askodoxCostShareBp(e.value, item, days);
                            if (bp == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(children: [
                                SizedBox(width: 90, child: Text(names[e.key] ?? (te ? 'షాప్' : 'Shop'), overflow: TextOverflow.ellipsis)),
                                Expanded(
                                  child: LinearProgressIndicator(
                                      value: (bp / 10000).clamp(0.0, 1.0), minHeight: 10, borderRadius: BorderRadius.circular(6)),
                                ),
                                const SizedBox(width: 8),
                                Text(askodoxYieldPercent(bp),
                                    key: ValueKey('askodoxWeeklyShare-${e.key}'), style: const TextStyle(fontWeight: FontWeight.w800)),
                              ]),
                            );
                          }),
                      ]),
                    ),
                  ),
                  if (rates != null)
                    Card(
                      child: ListTile(
                        title: Text(te ? 'సప్లయర్ రేటు' : "Supplier's rate", style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(te ? 'క్రితం సరుకు vs ఈ సరుకు' : 'Last lot vs this lot'),
                        trailing: Text(
                            '${askodoxYieldRupees(rates.$1)} → ${askodoxYieldRupees(rates.$2)}${rates.$2 > rates.$1 ? ' ▲' : rates.$2 < rates.$1 ? ' ▼' : ''}',
                            key: const Key('askodoxWeeklyRates'),
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800,
                                color: rates.$2 > rates.$1 ? AskodoxLook.accentText : AskodoxLook.text)),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                const AskodoxEstimateNote(),
              ]),
      ),
    );
  }
}
