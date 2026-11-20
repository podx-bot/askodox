import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import 'pos_common.dart';

/// Owner 2026-11-20: "Baaki reminders" -- from 3 days before each bill's pay date up to the date, ONE tap per person
/// opens WhatsApp with the message and the pay link already written (the owner's own WhatsApp: free, no setup). After
/// the date the bill shows as overdue with a one-tap new date. Customers on ASKODOX also get the app push by themselves.
class AskodoxPosDuesScreen extends ConsumerStatefulWidget {
  const AskodoxPosDuesScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosDuesScreen> createState() => _AskodoxPosDuesScreenState();
}

/// One-tap pay dates: tomorrow, 3 days, 1 week, end of this month (or next month when it is near).
List<(String, String, DateTime)> askodoxDueDateChoices(DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  var monthEnd = DateTime(day.year, day.month + 1, 0);
  if (monthEnd.difference(day).inDays < 3) monthEnd = DateTime(day.year, day.month + 2, 0);
  return [
    ('Tomorrow', 'రేపు', day.add(const Duration(days: 1))),
    ('3 days', '3 రోజులు', day.add(const Duration(days: 3))),
    ('1 week', '1 వారం', day.add(const Duration(days: 7))),
    ('Month end', 'నెలాఖరు', monthEnd),
  ];
}

String askodoxIsoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _AskodoxPosDuesScreenState extends ConsumerState<AskodoxPosDuesScreen> {
  AskodoxJson? _data;
  Object? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).dueReminders(widget.businessId);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _whatsApp(AskodoxJson r, bool te) async {
    final to = '${r['whatsapp_to'] ?? ''}';
    final uri = Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent('${r['text'] ?? ''}')}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!mounted) return;
    if (!ok) {
      askodoxPosSnack(context, te ? 'WhatsApp తెరవలేకపోయాను.' : 'Could not open WhatsApp.');
      return;
    }
    try {
      await ref.read(askodoxPosRepositoryProvider).markDueReminded(widget.businessId, '${r['invoice_id']}');
    } catch (_) {}
    await _load();
  }

  Future<void> _setDate(AskodoxJson r, DateTime date, bool te) async {
    final id = '${r['invoice_id']}';
    setState(() => _busy.add(id));
    try {
      await ref.read(askodoxPosRepositoryProvider).setDueDate(widget.businessId, id, askodoxIsoDay(date));
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Widget _dateChips(AskodoxJson r, bool te) => Wrap(spacing: 6, runSpacing: 4, children: [
        for (final c in askodoxDueDateChoices(DateTime.now()))
          ActionChip(
            key: ValueKey('askodoxDueDate-${r['invoice_id']}-${c.$1}'),
            visualDensity: VisualDensity.compact,
            label: Text(te ? c.$2 : c.$1),
            onPressed: _busy.contains('${r['invoice_id']}') ? null : () => _setDate(r, c.$3, te),
          ),
      ]);

  String _when(AskodoxJson r, bool te) {
    final left = askodoxPosInt(r['days_left']);
    if (left < 0) return te ? '${-left} రోజులు దాటింది' : '${-left} days late';
    if (left == 0) return te ? 'ఈరోజే' : 'today';
    if (left == 1) return te ? 'రేపు' : 'tomorrow';
    return te ? '$left రోజుల్లో' : 'in $left days';
  }

  Widget _row(AskodoxJson r, bool te) {
    final state = '${r['state']}';
    final sent = r['sent_today'] == true;
    final hasPhone = '${r['whatsapp_to'] ?? ''}'.isNotEmpty;
    final color = state == 'overdue' ? const Color(0xFFB91C1C) : state == 'remind' ? const Color(0xFF17784C) : const Color(0xFF5B6475);
    return Card(
      key: ValueKey('askodoxDue-${r['invoice_id']}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${'${r['customer'] ?? ''}'.isEmpty ? (te ? 'కస్టమర్' : 'Customer') : r['customer']} · ${askodoxPaise(askodoxPosInt(r['due_paise']))}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
            ),
            if (state == 'remind' && hasPhone)
              sent
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle, color: Color(0xFF17784C), size: 20),
                      const SizedBox(width: 4),
                      Text(te ? 'పంపాం' : 'Sent', style: const TextStyle(color: Color(0xFF17784C), fontWeight: FontWeight.w700)),
                    ])
                  : FilledButton.icon(
                      key: ValueKey('askodoxDueWhatsApp-${r['invoice_id']}'),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF128C7E)),
                      onPressed: () => _whatsApp(r, te),
                      icon: const Icon(Icons.chat, size: 18),
                      label: const Text('WhatsApp'),
                    ),
          ]),
          const SizedBox(height: 2),
          Text(
              '${r['number']} · ${te ? 'కట్టాల్సిన తేదీ' : 'Pay by'} ${r['pay_date']} (${_when(r, te)})'
              '${r['date_by'] == 'customer' ? (te ? ' · కస్టమర్ చెప్పారు' : ' · customer said') : ''}',
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5)),
          if (state == 'remind' && !hasPhone)
            Text(te ? 'ఫోన్ నంబర్ లేదు — కస్టమర్ వివరాల్లో నంబర్ చేర్చండి.' : 'No phone number — add it to the customer.',
                style: const TextStyle(fontSize: 12)),
          if (state != 'remind') ...[
            const SizedBox(height: 6),
            Text(state == 'overdue' ? (te ? 'కొత్త తేదీ:' : 'New date:') : (te ? 'తేదీ మార్చాలంటే:' : 'Change the date:'),
                style: const TextStyle(fontSize: 12)),
            _dateChips(r, te),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final items = askodoxPosList(_data?['items']);
    final remind = [for (final r in items) if (r['state'] == 'remind') r];
    final overdue = [for (final r in items) if (r['state'] == 'overdue') r];
    final later = [for (final r in items) if (r['state'] == 'later') r];
    Widget head(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        );
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బాకీ గుర్తులు' : 'Baaki reminders')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(key: const Key('askodoxPosDues'), padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
                    Text(
                        te
                            ? 'కట్టాల్సిన తేదీకి 3 రోజుల ముందు నుంచి ఆ రోజు వరకు రోజుకి ఒకసారి గుర్తు చేస్తాం. ASKODOX ఉన్న కస్టమర్‌కి యాప్‌లో తానే వెళ్తుంది; మిగతా వారికి WhatsApp ఒక్క టాప్.'
                            : 'From 3 days before the pay date up to the date, once a day. Customers on ASKODOX get it in the app by itself; others: one tap on WhatsApp.',
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Center(child: Text(te ? 'బాకీ బిల్లులు లేవు 🎉' : 'No baaki bills 🎉', style: const TextStyle(fontSize: 16))),
                      ),
                    if (remind.isNotEmpty) ...[head(te ? 'ఈరోజు గుర్తు చేయాలి (${remind.length})' : 'Remind today (${remind.length})'), ...remind.map((r) => _row(r, te))],
                    if (overdue.isNotEmpty) ...[head(te ? 'తేదీ దాటింది (${overdue.length})' : 'Overdue (${overdue.length})'), ...overdue.map((r) => _row(r, te))],
                    if (later.isNotEmpty) ...[head(te ? 'తర్వాత (${later.length})' : 'Later (${later.length})'), ...later.map((r) => _row(r, te))],
                  ]),
                ),
    );
  }
}
