import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/pos_repository.dart';
import 'pos_common.dart';

/// The Payments tab (redesign, owner 2026-11-13): one page for money that reaches the person's
/// OWN account -- today's alerts, the last week, the latest payments and one tap to the QR,
/// the alerts and the accounts. It only reads the existing payment-alert events
/// (`pos_payment_alerts.py`); phone notifications are never bank-verified, so the totals say
/// so. ASKODOX never holds the money.
class AskodoxPaymentsHubScreen extends ConsumerStatefulWidget {
  const AskodoxPaymentsHubScreen({super.key, this.now});

  /// Fixed clock for tests.
  final DateTime? now;

  @override
  ConsumerState<AskodoxPaymentsHubScreen> createState() => _AskodoxPaymentsHubScreenState();
}

const _ink = Color(0xFF10204A);
const _muted = Color(0xFF5A6478);
const _line = Color(0xFFE6E9EF);
const _blue = Color(0xFF2450C8);
const _green = Color(0xFF17784C);

/// "₹2,450" with Indian digit grouping (paise -> whole rupees).
String askodoxRupees(int paise) {
  final digits = (paise ~/ 100).abs().toString();
  if (digits.length <= 3) return '₹$digits';
  final last = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '₹${groups.join(',')},$last';
}

/// One week of payment alerts, by local day (oldest first, today last). Test payments are left out.
class AskodoxPaymentWeek {
  AskodoxPaymentWeek(List<AskodoxJson> events, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    days = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
    totals = List.filled(7, 0);
    for (final e in events) {
      if (e['test'] == true) continue;
      final at = DateTime.tryParse('${e['received_at'] ?? ''}')?.toLocal();
      if (at == null) continue;
      final day = DateTime(at.year, at.month, at.day);
      final index = days.indexOf(day);
      if (index < 0) continue;
      final paise = e['amount_paise'] is int ? e['amount_paise'] as int : 0;
      totals[index] += paise;
      if (index == 6) {
        todayCount++;
        if (askodoxPaymentWasSpoken(e)) todaySpoken++;
      }
    }
  }

  late final List<DateTime> days;
  late final List<int> totals;
  int todayCount = 0;
  int todaySpoken = 0;

  int get todayPaise => totals.last;
}

/// True when at least one phone said the payment out loud.
bool askodoxPaymentWasSpoken(AskodoxJson event) =>
    askodoxPosList(event['acks']).any((a) => '${a['state']}' == 'announced');

class _AskodoxPaymentsHubScreenState extends ConsumerState<AskodoxPaymentsHubScreen> {
  List<AskodoxJson>? _shops;
  List<AskodoxJson> _events = const [];
  AskodoxPosException? _error;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final shops = await repo.businesses();
      var events = const <AskodoxJson>[];
      if (shops.isNotEmpty) {
        final since = _now.toUtc().subtract(const Duration(days: 7)).toIso8601String();
        try {
          events = askodoxPosList((await repo.paymentEvents('${shops.first['id']}', since: since, limit: 500))['events']);
        } on AskodoxPosException {
          // The page still shows the doors; the list stays empty.
        }
      }
      if (!mounted) return;
      setState(() {
        _shops = shops;
        _events = events;
        _error = null;
      });
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final shops = _shops;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(backgroundColor: const Color(0xFFF4F5F7), elevation: 0, scrolledUnderElevation: 0, toolbarHeight: 44),
      body: SafeArea(
        top: false,
        child: shops == null
            ? (_error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  key: const Key('askodoxPaymentsHub'),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Text(te ? 'పేమెంట్లు' : 'Payments',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _ink)),
                    const SizedBox(height: 2),
                    Text(te ? 'డబ్బు నేరుగా మీ ఖాతాకే వస్తుంది' : 'Money comes straight to your account',
                        style: const TextStyle(fontSize: 13, color: _muted)),
                    const SizedBox(height: 14),
                    if (shops.isEmpty) _start(te) else _today(te),
                    const SizedBox(height: 12),
                    _doors(te, shops),
                    if (shops.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _recent(te, '${shops.first['id']}'),
                      const SizedBox(height: 14),
                      _advanced(te, '${shops.first['id']}'),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  BoxDecoration get _card => BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(20),
      );

  Widget _start(bool te) => Container(
        key: const Key('askodoxPaymentsHubStart'),
        decoration: _card,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(te ? 'డబ్బు వచ్చిన వెంటనే ఫోన్ చెబుతుంది' : 'Your phone says it when money arrives',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 6),
          Text(
              te
                  ? 'మీ షాప్ పేరు ఇచ్చి పేమెంట్ అలర్ట్స్ ఆన్ చేయండి. సిబ్బంది ఫోన్‌లలో కూడా వినిపిస్తుంది.'
                  : 'Name your shop and switch payment alerts on. Your staff can hear it on their phones too.',
              style: const TextStyle(fontSize: 13, color: _muted, height: 1.4)),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('askodoxPaymentsHubStartButton'),
            style: FilledButton.styleFrom(backgroundColor: _ink, minimumSize: const Size.fromHeight(48)),
            onPressed: () => context.push('/me/payment-alerts'),
            child: Text(te ? 'అలర్ట్స్ ఆన్ చేయండి' : 'Switch alerts on'),
          ),
        ]),
      );

  Widget _today(bool te) {
    final week = AskodoxPaymentWeek(_events, _now);
    final top = week.totals.fold<int>(0, (m, v) => v > m ? v : m);
    const teDays = ['సోమ', 'మంగళ', 'బుధ', 'గురు', 'శుక్ర', 'శని', 'ఆది'];
    const enDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const teMonths = ['జనవరి', 'ఫిబ్రవరి', 'మార్చి', 'ఏప్రిల్', 'మే', 'జూన్', 'జూలై', 'ఆగస్టు', 'సెప్టెంబర్', 'అక్టోబర్', 'నవంబర్', 'డిసెంబర్'];
    const enMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = _now;
    return Container(
      key: const Key('askodoxPaymentsHubToday'),
      decoration: _card,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(te ? 'ఈ రోజు వచ్చింది' : 'Came in today',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _muted)),
          ),
          Text('${now.day} ${(te ? teMonths : enMonths)[now.month - 1]}', style: const TextStyle(fontSize: 12, color: _muted)),
        ]),
        const SizedBox(height: 4),
        Text(askodoxRupees(week.todayPaise),
            key: const Key('askodoxPaymentsHubTodayTotal'),
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 4),
        Text(
            te
                ? '${week.todayCount} పేమెంట్లు · ${week.todaySpoken} సార్లు మాట్లాడింది'
                : '${week.todayCount} payments · spoke ${week.todaySpoken} times',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
        const SizedBox(height: 14),
        SizedBox(
          height: 72,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(
                      height: top == 0 ? 4 : 4 + 44 * week.totals[i] / top,
                      decoration: BoxDecoration(
                        color: i == 6 ? _green : const Color(0xFFCFE6D9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      i == 6 ? (te ? 'ఈ రోజు' : 'Today') : (te ? teDays : enDays)[week.days[i].weekday - 1],
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(fontSize: 10.5, fontWeight: i == 6 ? FontWeight.w800 : FontWeight.w500, color: _muted),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Text(
            te
                ? 'ఫోన్ నోటిఫికేషన్ల లెక్క — బ్యాంక్ నిర్ధారణ కాదు. బ్యాంక్ యాప్‌లో ఒకసారి చూసుకోండి.'
                : 'Counted from phone notifications — not bank-confirmed. Check your bank app once.',
            style: const TextStyle(fontSize: 11.5, color: _muted)),
      ]),
    );
  }

  Widget _doors(bool te, List<AskodoxJson> shops) {
    final alerts = shops.isEmpty ? '/me/payment-alerts' : '/me/payment-alerts/${shops.first['id']}';
    Widget door(String key, IconData icon, String label, String path, {bool primary = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: primary ? _ink : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: primary ? BorderSide.none : const BorderSide(color: _line),
              ),
              child: InkWell(
                key: Key(key),
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push(path),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: primary ? Colors.white : _blue),
                    const SizedBox(height: 6),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: primary ? Colors.white : _ink)),
                  ]),
                ),
              ),
            ),
          ),
        );
    return Row(children: [
      door('askodoxPaymentsHubQr', Icons.qr_code_2_rounded, te ? 'నా QR చూపించు' : 'Show my QR', '/me/payment-methods', primary: true),
      door('askodoxPaymentsHubAlerts', Icons.volume_up_rounded, te ? 'అలర్ట్స్' : 'Alerts', alerts),
      door('askodoxPaymentsHubAccounts', Icons.account_balance_outlined, te ? 'నా ఖాతాలు' : 'My accounts', '/me/payment-methods'),
    ]);
  }

  Widget _recent(bool te, String shopId) {
    final latest = _events.where((e) => e['test'] != true).take(3).toList();
    String initials(String label) {
      final l = label.trim();
      if (l.isEmpty) return '₹';
      if (l.startsWith('PhonePe')) return 'Pe';
      if (l.startsWith('Google')) return 'G';
      if (l.startsWith('Paytm')) return 'Pa';
      return l.length <= 2 ? l : l.substring(0, 2);
    }

    String time(Object? at) {
      final t = DateTime.tryParse('${at ?? ''}')?.toLocal();
      if (t == null) return '';
      final clock = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      final now = _now;
      final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
      if (days <= 0) return clock;
      if (days == 1) return te ? 'నిన్న · $clock' : 'Yesterday · $clock';
      return '${t.day}/${t.month} · $clock';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(te ? 'ఇప్పుడే వచ్చినవి' : 'Just came in',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _muted, letterSpacing: .4)),
      const SizedBox(height: 8),
      Container(
        key: const Key('askodoxPaymentsHubRecent'),
        decoration: _card,
        child: Column(children: [
          if (latest.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(te ? 'ఈ వారం ఇంకా పేమెంట్ అలర్ట్ రాలేదు.' : 'No payment alerts this week yet.',
                  style: const TextStyle(fontSize: 13, color: _muted)),
            ),
          for (var i = 0; i < latest.length; i++)
            Container(
              key: ValueKey('askodoxPaymentsHubEvent-${latest[i]['id']}'),
              decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF0F4)))),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: const Color(0xFFE8EEFC),
                  child: Text(initials('${latest[i]['source_label'] ?? ''}'),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _blue)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${latest[i]['source_label'] ?? ''}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                    Text(time(latest[i]['received_at']), style: const TextStyle(fontSize: 12, color: _muted)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(latest[i]['amount_paise'] is int ? askodoxRupees(latest[i]['amount_paise'] as int) : '—',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
                  if (askodoxPaymentWasSpoken(latest[i]))
                    Text(te ? '✓ మాట్లాడింది' : '✓ Spoke',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _green)),
                ]),
              ]),
            ),
          InkWell(
            key: const Key('askodoxPaymentsHubSeeAll'),
            onTap: () => context.push('/me/payment-alerts/$shopId'),
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF0F4)))),
              padding: const EdgeInsets.all(14),
              child: Text(te ? 'అన్నీ చూడండి' : 'See all',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _blue)),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _advanced(bool te, String shopId) => InkWell(
        key: const Key('askodoxPaymentsHubAdvanced'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/me/payment-alerts/$shopId'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            te ? 'ASKODOX పేమెంట్ ప్రొఫైల్, సిబ్బంది ఫోన్లు — అధునాతనం ›' : 'ASKODOX payment profile, staff phones — Advanced ›',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _muted),
          ),
        ),
      );
}
