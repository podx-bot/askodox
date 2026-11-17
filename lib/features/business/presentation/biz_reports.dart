import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../guide/in_app_guide.dart' show askodoxGuideSpeakerProvider;
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart' show askodoxPaise;
import '../../pos/presentation/pos_common.dart';
import 'biz_hub.dart';

/// Reports & analytics (owner 2026-11-18): made for a person who may not read -- a big face for the day, big numbers,
/// colours, bars instead of tables, and "వినండి" reads it out. Every problem shows WHY (from the shop's own rows) and
/// one thing to do, with a button that opens the page where it is fixed.

const _green = Color(0xFF17784C);
const _red = Color(0xFFB91C1C);
const _orange = Color(0xFFB45309);
const _blue = Color(0xFF1E3FA0);
const _purple = Color(0xFF5B2A9E);
const _muted = Color(0xFF4B5563);

final askodoxReportDayProvider = FutureProvider.autoDispose.family<AskodoxJson, (String, String)>(
    (ref, k) => ref.watch(askodoxPosRepositoryProvider).reportDay(k.$1, date: k.$2));
final askodoxReportRangeProvider = FutureProvider.autoDispose.family<AskodoxJson, (String, int)>(
    (ref, k) => ref.watch(askodoxPosRepositoryProvider).reportRange(k.$1, days: k.$2));

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _rs(Object? p) => askodoxPaise(askodoxPosInt(p));
String _hour(int h) => '${h % 12 == 0 ? 12 : h % 12}${h < 12 ? 'AM' : 'PM'}';

(String, String, Color) _mood(String mood, bool te) => switch (mood) {
      'good' => ('😊', te ? 'ఈ రోజు బాగుంది' : 'A good day', _green),
      'bad' => ('😟', te ? 'సమస్యలు ఉన్నాయి' : 'Some problems', _red),
      _ => ('😐', te ? 'పర్వాలేదు' : 'Okay', _orange),
    };

/// `/biz/:id/reports` -- today / yesterday / 7 days / 30 days.
class AskodoxBizReportsScreen extends ConsumerStatefulWidget {
  const AskodoxBizReportsScreen({super.key, required this.businessId, this.date = ''});
  final String businessId;

  /// A date from the night push (`/reports/day?date=`); empty = today.
  final String date;

  @override
  ConsumerState<AskodoxBizReportsScreen> createState() => _AskodoxBizReportsScreenState();
}

class _AskodoxBizReportsScreenState extends ConsumerState<AskodoxBizReportsScreen> {
  late String _tab = widget.date.isEmpty ? 'today' : 'date';

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final now = DateTime.now();
    final tabs = <(String, String)>[
      if (widget.date.isNotEmpty) ('date', widget.date.substring(5).split('-').reversed.join('/')),
      ('today', te ? 'ఈ రోజు' : 'Today'),
      ('yesterday', te ? 'నిన్న' : 'Yesterday'),
      ('7', te ? '7 రోజులు' : '7 days'),
      ('30', te ? '30 రోజులు' : '30 days'),
    ];
    final date = switch (_tab) {
      'date' => widget.date,
      'yesterday' => _ymd(now.subtract(const Duration(days: 1))),
      _ => _ymd(now),
    };
    final range = _tab == '7' || _tab == '30';
    final AsyncValue<AskodoxJson> data = range
        ? ref.watch(askodoxReportRangeProvider((widget.businessId, int.parse(_tab))))
        : ref.watch(askodoxReportDayProvider((widget.businessId, date)));
    return AskodoxBizScaffold(
      key: const Key('askodoxBizReports'),
      businessId: widget.businessId,
      tone: askodoxBizTones['reports']!,
      icon: Icons.insights_outlined,
      title: te ? 'రిపోర్ట్స్' : 'Reports',
      trail: [te ? 'రిపోర్ట్స్' : 'Reports'],
      page: 'reports',
      onRefresh: () async {
        ref.invalidate(askodoxReportDayProvider);
        ref.invalidate(askodoxReportRangeProvider);
      },
      actions: [
        IconButton(
          key: const Key('askodoxReportSettings'),
          tooltip: te ? 'రాత్రి రిపోర్ట్' : 'Night report',
          onPressed: () => context.push('/biz/${widget.businessId}/reports/settings'),
          icon: const Icon(Icons.nightlight_round),
        ),
      ],
      askHint: te ? '"ఈ రోజు ఎంత అమ్మింది?" "ఎక్కువ అమ్మిన ఐటమ్?"' : '"How much today?" "Top item?"',
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (k, label) in tabs)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  key: Key('askodoxReportTab-$k'),
                  label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                  selected: _tab == k,
                  selectedColor: const Color(0xFFE4D8F8),
                  onSelected: (_) => setState(() => _tab = k),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        ...data.when(
          loading: () => [const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))],
          error: (e, _) => [
            AskodoxPosError(
                error: e,
                onRetry: () {
                  ref.invalidate(askodoxReportDayProvider);
                  ref.invalidate(askodoxReportRangeProvider);
                })
          ],
          data: (r) => range ? _rangeView(context, r, te) : _dayView(context, r, te),
        ),
      ],
    );
  }

  Future<void> _listen(String text, bool te) async {
    try {
      await ref.read(askodoxGuideSpeakerProvider)(text, te ? 'te' : 'en');
    } catch (_) {}
  }

  List<Widget> _dayView(BuildContext context, AskodoxJson r, bool te) {
    final sales = askodoxPosMap(r['sales']);
    final (face, moodText, moodColor) = _mood('${r['mood']}', te);
    final change = sales['change_pct'];
    final money = askodoxPosMap(r['money']);
    final items = askodoxPosMap(r['items']);
    final orders = askodoxPosMap(r['orders']);
    final staff = askodoxPosMap(r['staff']);
    final customers = askodoxPosMap(r['customers']);
    final problems = askodoxPosList(r['problems']);
    final hours = askodoxPosList(r['hours']).where((h) => askodoxPosInt(h['bills']) > 0).toList();
    return [
      // 1. the face + the big number
      Container(
        key: const Key('askodoxReportFace'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: moodColor.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: moodColor.withValues(alpha: .35), width: 1.5)),
        child: Column(children: [
          Row(children: [
            Text(face, style: const TextStyle(fontSize: 58)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(moodText, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: moodColor)),
                FittedBox(
                  child: Text(_rs(sales['paise']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 34)),
                ),
                Text(te ? '${sales['bills']} బిల్లులు · సగటు ${_rs(sales['avg_bill_paise'])}' : '${sales['bills']} bills · avg ${_rs(sales['avg_bill_paise'])}',
                    style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
          if (change != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(askodoxPosInt(change) >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  color: askodoxPosInt(change) >= 0 ? _green : _red),
              Expanded(
                child: Text(
                    te
                        ? 'గత వారం ఇదే రోజు కంటే ${askodoxPosInt(change).abs()}% ${askodoxPosInt(change) >= 0 ? 'ఎక్కువ' : 'తక్కువ'} (${_rs(sales['last_week_paise'])})'
                        : '${askodoxPosInt(change).abs()}% ${askodoxPosInt(change) >= 0 ? 'more' : 'less'} than last week (${_rs(sales['last_week_paise'])})',
                    style: TextStyle(fontWeight: FontWeight.w800, color: askodoxPosInt(change) >= 0 ? _green : _red)),
              ),
            ]),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('askodoxReportListen'),
            style: FilledButton.styleFrom(backgroundColor: moodColor, minimumSize: const Size.fromHeight(46)),
            onPressed: () => _listen('${te ? r['say_te'] : r['say_en']}', te),
            icon: const Icon(Icons.volume_up_rounded),
            label: Text(te ? 'వినండి' : 'Listen', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ]),
      ),
      // 2. problems: what, why, what to do, open the page
      AskodoxBizSection(problems.isEmpty
          ? (te ? 'సమస్యలు లేవు ✓' : 'No problems ✓')
          : (te ? 'గమనించాల్సినవి (${problems.length}) — కారణం + ఏం చేయాలి' : 'Look at these (${problems.length}) — why + what to do')),
      for (final p in problems) _ProblemCard(businessId: widget.businessId, p: p, te: te),
      // 3. money
      AskodoxBizSection(te ? 'డబ్బు — వచ్చింది, వెళ్ళింది' : 'Money — in and out'),
      _Bars(rows: [
        (te ? '💵 క్యాష్' : '💵 Cash', askodoxPosInt(money['cash_paise']), _green),
        (te ? '📱 ఆన్‌లైన్' : '📱 Online', askodoxPosInt(money['online_paise']), _blue),
        if (askodoxPosInt(money['other_in_paise']) > 0) (te ? '➕ ఇతర ఆదాయం' : '➕ Other in', askodoxPosInt(money['other_in_paise']), _green),
        (te ? '🧾 ఖర్చు' : '🧾 Spent', askodoxPosInt(money['expense_paise']), _red),
        if (askodoxPosInt(money['new_dues_paise']) > 0) (te ? '📕 కొత్త బాకీ' : '📕 New dues', askodoxPosInt(money['new_dues_paise']), _orange),
      ]),
      _bigLine(te ? 'చేతిలో మిగిలింది' : 'Left in hand', _rs(money['left_paise']),
          askodoxPosInt(money['left_paise']) >= 0 ? _green : _red),
      // 4. busy hours
      if (hours.isNotEmpty) ...[
        AskodoxBizSection(te ? 'రద్దీ టైం' : 'Busy hours'),
        _HourChart(hours: askodoxPosList(r['hours']), peak: r['peak_hour'] == null ? null : askodoxPosInt(r['peak_hour']), te: te),
      ],
      // 5. items
      AskodoxBizSection(te ? 'ఎక్కువ అమ్ముడైనవి' : 'Top items'),
      if (askodoxPosList(items['top']).isEmpty) Text(te ? 'ఇంకా అమ్మకాలు లేవు.' : 'No sales yet.'),
      _Bars(rows: [
        for (final (i, it) in askodoxPosList(items['top']).indexed)
          ('${i == 0 ? '🥇 ' : i == 1 ? '🥈 ' : i == 2 ? '🥉 ' : ''}${it['name']} × ${(it['qty'] as num?)?.toStringAsFixed((it['qty'] as num? ?? 0) % 1 == 0 ? 0 : 1)}',
              askodoxPosInt(it['paise']), _purple),
      ]),
      if (askodoxPosList(items['not_selling']).isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(te ? '🐢 ఈ వారం అమ్ముడు కానివి' : '🐢 Not sold this week', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final it in askodoxPosList(items['not_selling'])) Chip(label: Text('${it['name']}'), visualDensity: VisualDensity.compact),
        ]),
      ],
      // 6. orders & tables
      if (askodoxPosInt(orders['count']) > 0 || askodoxPosInt(orders['calls']) > 0) ...[
        AskodoxBizSection(te ? 'ఆర్డర్లు & టేబుల్స్' : 'Orders & tables'),
        Row(children: [
          _stat(te ? 'ఆర్డర్లు' : 'Orders', '${orders['count']}', _blue),
          _stat(te ? 'ఒప్పుకోడానికి' : 'To accept', orders['avg_accept_min'] == null ? '—' : '${orders['avg_accept_min']} ని.', _orange),
          _stat(te ? 'రెడీ అవడానికి' : 'To ready', orders['avg_ready_min'] == null ? '—' : '${orders['avg_ready_min']} ని.', _purple),
          _stat(te ? 'పిలుపులు' : 'Calls', '${orders['calls']}', _red),
        ]),
      ],
      // 7. customers
      AskodoxBizSection(te ? 'కస్టమర్లు' : 'Customers'),
      Row(children: [
        _stat(te ? 'కొత్తవారు' : 'New', '${customers['new']}', _green),
        _stat(te ? 'మళ్ళీ వచ్చినవారు' : 'Came back', '${customers['returning']}', _blue),
        _stat(te ? 'పేరు లేనివారు' : 'Walk-in', '${customers['walk_in']}', _muted),
      ]),
      for (final c in askodoxPosList(customers['top']))
        ListTile(
          dense: true,
          leading: Text(c['new'] == true ? '🆕' : '🔁', style: const TextStyle(fontSize: 20)),
          title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          trailing: Text(_rs(c['paise']), style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      // 8. staff
      if (askodoxPosList(staff['people']).isNotEmpty || askodoxPosList(staff['by_person']).isNotEmpty) ...[
        AskodoxBizSection(te ? 'సిబ్బంది & పని' : 'Staff & work'),
        Row(children: [
          _stat(te ? 'వచ్చారు' : 'Present', '${staff['present']}', _green),
          _stat(te ? 'ఆలస్యం' : 'Late', '${staff['late']}', _orange),
          _stat(te ? 'రాలేదు' : 'Absent', '${staff['absent']}', _red),
          _stat(te ? 'పనులు' : 'Tasks', '${staff['tasks_done']}/${staff['tasks']}', _purple),
        ]),
        const SizedBox(height: 6),
        if (askodoxPosList(staff['by_person']).isNotEmpty) ...[
          Text(te ? 'ఎవరు ఎన్ని బిల్లులు చేశారు' : 'Bills made by each person', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          _Bars(rows: [
            for (final p in askodoxPosList(staff['by_person']))
              ('${p['name'] == 'Owner' ? (te ? 'ఓనర్' : 'Owner') : p['name']} · ${p['bills']}', askodoxPosInt(p['paise']), _blue),
          ]),
        ],
      ],
    ];
  }

  List<Widget> _rangeView(BuildContext context, AskodoxJson r, bool te) {
    final series = askodoxPosList(r['series']);
    final best = askodoxPosMap(r['best_day']);
    const wd = ['సోమ', 'మంగళ', 'బుధ', 'గురు', 'శుక్ర', 'శని', 'ఆది'];
    const wdEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final spent = askodoxPosMap(r['expense_by_category']);
    return [
      Row(children: [
        _stat(te ? 'మొత్తం అమ్మకం' : 'Total sales', _rs(r['total_paise']), _green),
        _stat(te ? 'రోజుకు సగటు' : 'Per day', _rs(r['avg_day_paise']), _blue),
        _stat(te ? 'బిల్లులు' : 'Bills', '${r['bills']}', _purple),
      ]),
      if (best.isNotEmpty) ...[
        const SizedBox(height: 8),
        _bigLine(te ? '🏆 ఎక్కువ అమ్మిన రోజు ${best['date']}' : '🏆 Best day ${best['date']}', _rs(best['paise']), _green),
      ],
      AskodoxBizSection(te ? 'రోజూ అమ్మకం' : 'Sales each day'),
      _DayChart(series: series),
      AskodoxBizSection(te ? 'ఏ రోజు ఎక్కువ అమ్ముతుంది (సగటు)' : 'Which weekday sells most (average)'),
      _Bars(rows: [
        for (final w in askodoxPosList(r['weekdays']))
          ((te ? wd : wdEn)[askodoxPosInt(w['weekday']).clamp(0, 6)], askodoxPosInt(w['avg_paise']), _blue),
      ]),
      AskodoxBizSection(te ? 'రద్దీ టైం' : 'Busy hours'),
      _HourChart(hours: askodoxPosList(r['hours']), te: te),
      AskodoxBizSection(te ? 'ఎక్కువ అమ్ముడైనవి' : 'Top items'),
      _Bars(rows: [
        for (final it in askodoxPosList(r['items_top'])) ('${it['name']}', askodoxPosInt(it['paise']), _purple),
      ]),
      if (askodoxPosList(r['items_low']).isNotEmpty) ...[
        AskodoxBizSection(te ? '🐢 తక్కువ అమ్ముడైనవి' : '🐢 Slow items'),
        _Bars(rows: [for (final it in askodoxPosList(r['items_low'])) ('${it['name']}', askodoxPosInt(it['paise']), _orange)]),
      ],
      if (spent.isNotEmpty) ...[
        AskodoxBizSection(te ? 'ఖర్చులు — ${_rs(r['expense_paise'])}' : 'Spending — ${_rs(r['expense_paise'])}'),
        _Bars(rows: [for (final e in spent.entries) (_category(e.key, te), askodoxPosInt(e.value), _red)]),
      ],
      if (askodoxPosList(r['staff']).isNotEmpty) ...[
        AskodoxBizSection(te ? 'సిబ్బంది హాజరు' : 'Staff attendance'),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: [
            for (final p in askodoxPosList(r['staff']))
              ListTile(
                dense: true,
                title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: Text('✅ ${p['present']}  ⏰ ${p['late']}  🌴 ${p['leave']}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
        Text(te ? '✅ వచ్చిన రోజులు  ⏰ ఆలస్యం  🌴 సెలవు' : '✅ days present  ⏰ late  🌴 leave',
            style: const TextStyle(fontSize: 11.5, color: _muted)),
      ],
      if (askodoxPosList(r['customers_top']).isNotEmpty) ...[
        AskodoxBizSection(te ? 'ఎక్కువ కొన్న కస్టమర్లు (${r['customers_count']})' : 'Top customers (${r['customers_count']})'),
        _Bars(rows: [
          for (final c in askodoxPosList(r['customers_top'])) ('${c['name']} · ${c['bills']}', askodoxPosInt(c['paise']), _green),
        ]),
      ],
    ];
  }

  static String _category(String key, bool te) => te
      ? const {
            'stock': 'సరుకులు',
            'salary': 'జీతాలు',
            'rent': 'అద్దె',
            'power': 'కరెంట్',
            'gas': 'గ్యాస్',
            'transport': 'రవాణా',
            'repair': 'రిపేర్',
            'other': 'ఇతరాలు',
          }[key] ??
          key
      : key;

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            FittedBox(child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: color))),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: _muted)),
          ]),
        ),
      );

  Widget _bigLine(String label, String value, Color color) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color)),
        ]),
      );
}

class _ProblemCard extends StatelessWidget {
  const _ProblemCard({required this.businessId, required this.p, required this.te});
  final String businessId;
  final AskodoxJson p;
  final bool te;

  @override
  Widget build(BuildContext context) {
    final color = switch ('${p['level']}') { 'high' => _red, 'mid' => _orange, _ => _muted };
    final why = '${te ? p['why_te'] : p['why_en']}';
    final route = askodoxBizRoute(businessId, '${p['page']}');
    return Container(
      key: Key('askodoxReportProblem-${p['key']}'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 6))),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(p['level'] == 'high' ? Icons.error_rounded : Icons.warning_amber_rounded, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text('${te ? p['text_te'] : p['text_en']}', style: TextStyle(fontWeight: FontWeight.w900, color: color))),
        ]),
        if (why.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${te ? 'కారణం' : 'Why'}: $why', style: const TextStyle(color: _muted)),
        ],
        const SizedBox(height: 4),
        Text('💡 ${te ? p['do_te'] : p['do_en']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (askodoxRouteShownNow(route))
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => context.push(route), child: Text(te ? 'అక్కడికి వెళ్ళు ›' : 'Go there ›')),
          ),
      ]),
    );
  }
}

/// Horizontal bars: a label, a coloured bar as long as its share, the amount.
class _Bars extends StatelessWidget {
  const _Bars({required this.rows});
  final List<(String, int, Color)> rows;

  @override
  Widget build(BuildContext context) {
    final top = rows.fold<int>(0, (m, r) => r.$2 > m ? r.$2 : m);
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
                width: 118,
                child: Text(r.$1, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
            Expanded(
              child: Container(
                height: 22,
                decoration: BoxDecoration(color: const Color(0xFFEFF1F5), borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: top == 0 ? 0 : (r.$2 / top).clamp(0.02, 1.0),
                  child: Container(decoration: BoxDecoration(color: r.$3, borderRadius: BorderRadius.circular(8))),
                ),
              ),
            ),
            SizedBox(
                width: 76,
                child: Text(askodoxPaise(r.$2), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5))),
          ]),
        ),
    ]);
  }
}

/// Bills per hour as standing bars; the busiest hour is coloured.
class _HourChart extends StatelessWidget {
  const _HourChart({required this.hours, required this.te, this.peak});
  final List<AskodoxJson> hours;
  final bool te;
  final int? peak;

  @override
  Widget build(BuildContext context) {
    final open = hours.where((h) => askodoxPosInt(h['bills']) > 0).map((h) => askodoxPosInt(h['hour'])).toList();
    if (open.isEmpty) return Text(te ? 'ఇంకా బిల్లులు లేవు.' : 'No bills yet.');
    final from = open.reduce((a, b) => a < b ? a : b), to = open.reduce((a, b) => a > b ? a : b);
    final shown = [for (final h in hours) if (askodoxPosInt(h['hour']) >= from && askodoxPosInt(h['hour']) <= to) h];
    final top = shown.fold<int>(1, (m, h) => askodoxPosInt(h['bills']) > m ? askodoxPosInt(h['bills']) : m);
    final busiest = peak ?? shown.reduce((a, b) => askodoxPosInt(a['bills']) >= askodoxPosInt(b['bills']) ? a : b)['hour'];
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        SizedBox(
          height: 110,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final h in shown)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (askodoxPosInt(h['bills']) > 0)
                      Text('${h['bills']}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
                    Container(
                      height: 86 * askodoxPosInt(h['bills']) / top,
                      decoration: BoxDecoration(
                          color: askodoxPosInt(h['hour']) == askodoxPosInt(busiest) ? _red : const Color(0xFF9DB0E8),
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
        Row(children: [
          for (final h in shown)
            Expanded(
                child: Text(askodoxPosInt(h['hour']) % 2 == from % 2 ? _hour(askodoxPosInt(h['hour'])) : '',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 8.5, color: _muted))),
        ]),
        const SizedBox(height: 4),
        Text(te ? '🔴 ఎక్కువ రద్దీ ${_hour(askodoxPosInt(busiest))} — అప్పుడు ఎక్కువ మంది ఉండాలి' : '🔴 Busiest ${_hour(askodoxPosInt(busiest))} — have more hands then',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
      ]),
    );
  }
}

/// Sales per day as standing bars (7 or 30).
class _DayChart extends StatelessWidget {
  const _DayChart({required this.series});
  final List<AskodoxJson> series;

  @override
  Widget build(BuildContext context) {
    final top = series.fold<int>(1, (m, d) => askodoxPosInt(d['paise']) > m ? askodoxPosInt(d['paise']) : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        SizedBox(
          height: 120,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final d in series)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.2),
                  child: Container(
                    height: 116 * askodoxPosInt(d['paise']) / top,
                    decoration: BoxDecoration(
                        color: askodoxPosInt(d['paise']) == top ? _green : const Color(0xFF8FCFB0),
                        borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
          ]),
        ),
        Row(children: [
          Text('${series.first['date']}'.substring(5), style: const TextStyle(fontSize: 10, color: _muted)),
          const Spacer(),
          Text('${series.last['date']}'.substring(5), style: const TextStyle(fontSize: 10, color: _muted)),
        ]),
      ]),
    );
  }
}

/// `/biz/:id/reports/settings` -- the night report: on / off and when.
class AskodoxBizReportSettingsScreen extends ConsumerStatefulWidget {
  const AskodoxBizReportSettingsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizReportSettingsScreen> createState() => _AskodoxBizReportSettingsScreenState();
}

class _AskodoxBizReportSettingsScreenState extends ConsumerState<AskodoxBizReportSettingsScreen> {
  AskodoxJson? _s;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final s = await ref.read(askodoxPosRepositoryProvider).reportSettings(widget.businessId);
        if (mounted) setState(() => _s = s);
      } catch (_) {}
    }());
  }

  Future<void> _save(AskodoxJson change) async {
    final te = askodoxPosTe(context);
    try {
      final s = await ref.read(askodoxPosRepositoryProvider).saveReportSettings(widget.businessId, change);
      if (mounted) {
        setState(() => _s = s);
        askodoxPosSnack(context, te ? 'సేవ్ అయింది ✓' : 'Saved ✓');
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final s = _s;
    return AskodoxBizScaffold(
      key: const Key('askodoxBizReportSettings'),
      businessId: widget.businessId,
      tone: askodoxBizTones['reports']!,
      icon: Icons.nightlight_round,
      title: te ? 'రాత్రి రిపోర్ట్' : 'Night report',
      trail: [te ? 'రిపోర్ట్స్' : 'Reports', te ? 'రాత్రి రిపోర్ట్' : 'Night report'],
      page: 'reports',
      askHint: te ? '"రాత్రి 11కి రిపోర్ట్ పంపు"' : '"Send the report at 11 pm"',
      children: s == null
          ? [const Center(child: CircularProgressIndicator())]
          : [
              SwitchListTile(
                key: const Key('askodoxReportNightPush'),
                tileColor: Colors.white,
                value: s['night_push'] == true,
                onChanged: (v) => _save({'night_push': v}),
                title: Text(te ? 'ప్రతి రాత్రి రిపోర్ట్ పంపు' : 'Send the report every night'),
                subtitle: Text(te
                    ? 'మీకు, రిపోర్ట్స్ చూడగలిగే మేనేజర్ / అకౌంటెంట్‌కి ఒక నోటిఫికేషన్'
                    : 'One notification to you and the manager / accountant who can see reports'),
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const Key('askodoxReportTime'),
                tileColor: Colors.white,
                leading: const Icon(Icons.schedule),
                title: Text(te ? 'ఎప్పుడు?' : 'When?'),
                trailing: Text('${s['send_time']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                onTap: () async {
                  final cur = '${s['send_time']}'.split(':');
                  final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: int.tryParse(cur.first) ?? 0, minute: int.tryParse(cur.last) ?? 0));
                  if (t != null) {
                    await _save({'send_time': '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'});
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                  te
                      ? 'రాత్రి 12 (00:00) = అయిపోయిన రోజు రిపోర్ట్. మధ్యాహ్నం 12 తర్వాత టైం = ఆ రోజు రిపోర్ట్ అప్పటివరకు.'
                      : '12 midnight (00:00) = the day that just ended. A time after noon = that day so far.',
                  style: const TextStyle(color: _muted, fontSize: 12.5)),
            ],
    );
  }
}
