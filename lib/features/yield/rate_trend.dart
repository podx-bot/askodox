import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme/askodox_look.dart';
import '../../shared/widgets/estimate_note.dart';
import 'weekly_report.dart' show askodoxWeekDays, askodoxWeekdayName;
import 'yield_math.dart';
import 'yield_store.dart';

/// Rate trend (owner 2026-11-27, design "రేటు ట్రెండ్ · 7 రోజులు"): for one item, the real cost of a kg against the
/// selling rate over the last seven days, from the owner's OWN day ends on this phone, and the days the profit of a kg
/// fell under the minimum he set. Nothing is a sample and nothing is sent anywhere.

/// One day of the trend: cost, selling rate and the difference (all per kg, paise).
class AskodoxTrendDay {
  const AskodoxTrendDay(this.day, this.costPaise, this.sellPaise);
  final String day;
  final int costPaise, sellPaise;
  int get profitPaise => sellPaise - costPaise;
}

/// The days (of [days]) that have a day end with both a cost and a selling rate for [item], over every book. A day kept by
/// more than one shop is the average of their rates (halves away from zero).
List<AskodoxTrendDay> askodoxTrendDays(Iterable<AskodoxYieldBook> books, String item, Iterable<String> days) {
  final out = <AskodoxTrendDay>[];
  for (final day in days) {
    var cost = 0, sell = 0, n = 0;
    for (final b in books) {
      final d = b.dayOf(item, day);
      if (d == null || d.costPaise <= 0 || d.sellPaise <= 0) continue;
      cost += d.costPaise;
      sell += d.sellPaise;
      n++;
    }
    if (n > 0) out.add(AskodoxTrendDay(day, askodoxYieldRoundDiv(cost, n), askodoxYieldRoundDiv(sell, n)));
  }
  return out;
}

/// The smallest positive minimum profit the owner set for [item] in any book; 0 = none set.
int askodoxTrendMin(Iterable<AskodoxYieldBook> books, String item) {
  var m = 0;
  for (final b in books) {
    final v = b.minProfit[item] ?? 0;
    if (v > 0 && (m == 0 || v < m)) m = v;
  }
  return m;
}

/// The days whose profit of a kg is under [minPaise] (nothing when no minimum is set).
List<AskodoxTrendDay> askodoxTrendBelow(List<AskodoxTrendDay> days, int minPaise) =>
    minPaise <= 0 ? const [] : [for (final d in days) if (d.profitPaise < minPaise) d];

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.days, this.keys, this.cost, this.sell, this.grid);
  final List<AskodoxTrendDay> days;
  final List<String> keys;
  final Color cost, sell, grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    var lo = days.first.costPaise, hi = days.first.sellPaise;
    for (final d in days) {
      for (final v in [d.costPaise, d.sellPaise]) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    final span = (hi - lo) == 0 ? 1 : (hi - lo);
    const pad = 8.0;
    double x(String day) => keys.length == 1 ? size.width / 2 : pad + (size.width - 2 * pad) * keys.indexOf(day) / (keys.length - 1);
    double y(int v) => size.height - pad - (size.height - 2 * pad) * (v - lo) / span;
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), Paint()..color = grid);
    void line(int Function(AskodoxTrendDay) f, Color c) {
      final p = Paint()..color = c..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
      final path = Path();
      for (var i = 0; i < days.length; i++) {
        final o = Offset(x(days[i].day), y(f(days[i])));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        canvas.drawCircle(o, 3.5, Paint()..color = c);
      }
      canvas.drawPath(path, p);
    }

    line((d) => d.costPaise, cost);
    line((d) => d.sellPaise, sell);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.days != days;
}

class AskodoxRateTrendScreen extends ConsumerStatefulWidget {
  const AskodoxRateTrendScreen({super.key});

  @override
  ConsumerState<AskodoxRateTrendScreen> createState() => _AskodoxRateTrendScreenState();
}

class _AskodoxRateTrendScreenState extends ConsumerState<AskodoxRateTrendScreen> {
  String? _item;

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final state = ref.watch(askodoxYieldProvider);
    final books = state.books.values.toList();
    final items = <String>{for (final b in books) for (final d in b.days) d.item}.toList();
    final item = _item != null && items.contains(_item) ? _item! : (items.isEmpty ? '' : items.first);
    final keys = askodoxWeekDays(DateTime.now());
    final days = askodoxTrendDays(books, item, keys);
    final min = askodoxTrendMin(books, item);
    final below = askodoxTrendBelow(days, min);
    return Scaffold(
      key: const Key('askodoxRateTrend'),
      appBar: AppBar(title: Text(te ? 'రేటు ట్రెండ్ · 7 రోజులు' : 'Rate trend · 7 days')),
      body: SafeArea(
        child: !state.loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                if (items.isEmpty)
                  Text(
                      te
                          ? 'రోజు ముగింపు రాస్తే, కిలో అసలు ఖర్చు, అమ్మే రేటు ఇక్కడ గీతలుగా కనిపిస్తాయి. సంఖ్యలన్నీ మీవే.'
                          : 'Once you save day ends, the cost of a kg and your selling rate show here as lines. Every number is your own.',
                      key: const Key('askodoxTrendEmpty'))
                else ...[
                  Wrap(spacing: 8, children: [
                    for (final name in items)
                      ChoiceChip(
                          key: ValueKey('askodoxTrendItem-$name'),
                          label: Text(askodoxYieldItemName(name, te)),
                          selected: item == name,
                          onSelected: (_) => setState(() => _item = name)),
                  ]),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(te ? 'అసలు ఖర్చు vs అమ్మే రేటు (₹/kg)' : 'Cost vs selling rate (₹/kg)', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 150,
                          width: double.infinity,
                          child: days.isEmpty
                              ? Center(child: Text(te ? 'ఈ వారం రేట్లతో డే ఎండ్ రాలేదు.' : 'No day end with rates this week.', key: const Key('askodoxTrendNoDays')))
                              : CustomPaint(
                                  key: const Key('askodoxTrendChart'),
                                  painter: _TrendPainter(days, keys, AskodoxLook.accentText, AskodoxLook.good, AskodoxLook.line)),
                        ),
                        const SizedBox(height: 4),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          for (final k in keys) Text(askodoxWeekdayName(k, te), style: const TextStyle(fontSize: 11, color: AskodoxLook.muted)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          Text('━ ${te ? 'అమ్మే రేటు' : 'Selling rate'}', style: const TextStyle(color: AskodoxLook.good, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 16),
                          Text('━ ${te ? 'అసలు ఖర్చు' : 'Real cost'}', style: const TextStyle(color: AskodoxLook.accentText, fontWeight: FontWeight.w700)),
                        ]),
                      ]),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(children: [
                        Row(children: [
                          for (final h in te ? ['రోజు', 'ఖర్చు', 'అమ్మే', 'లాభం'] : ['Day', 'Cost', 'Sell', 'Profit'])
                            Expanded(child: Text(h, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AskodoxLook.muted))),
                        ]),
                        for (final d in days.reversed.take(5))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(key: ValueKey('askodoxTrendRow-${d.day}'), children: [
                              Expanded(child: Text(askodoxWeekdayName(d.day, te), style: const TextStyle(fontWeight: FontWeight.w800))),
                              Expanded(child: Text(askodoxYieldRupees(d.costPaise))),
                              Expanded(child: Text(askodoxYieldRupees(d.sellPaise))),
                              Expanded(
                                child: Text(askodoxYieldRupees(d.profitPaise),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: min > 0 && d.profitPaise < min ? AskodoxLook.accentText : AskodoxLook.good)),
                              ),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                  if (min > 0)
                    Card(
                      key: const Key('askodoxTrendMin'),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                            below.isEmpty
                                ? (te ? 'మీరు పెట్టిన కనిష్ట లాభం ${askodoxYieldRupees(min)} కంటే ఈ వారం ఏ రోజూ తగ్గలేదు.' : 'No day this week fell under your minimum profit of ${askodoxYieldRupees(min)}.')
                                : (te
                                    ? 'మీరు పెట్టిన కనిష్ట లాభం ${askodoxYieldRupees(min)} కంటే ${below.length} రోజులు తగ్గింది.'
                                    : '${below.length} day(s) fell under your minimum profit of ${askodoxYieldRupees(min)}.'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  if (min <= 0)
                    Text(te ? 'కనిష్ట లాభం యీల్డ్ పేజీలో మీరే పెట్టండి. అప్పుడు తగ్గిన రోజులు ఇక్కడ చెబుతాం.' : 'Set your minimum profit on the Yield page and the days under it show here.',
                        key: const Key('askodoxTrendNoMin'), style: const TextStyle(color: AskodoxLook.muted)),
                ],
                const SizedBox(height: 12),
                const AskodoxEstimateNote(),
              ]),
      ),
    );
  }
}
