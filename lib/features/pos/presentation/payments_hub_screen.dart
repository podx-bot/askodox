import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/pos_payment_alerts.dart' show askodoxPaymentAlertsBridgeProvider;
import '../../../shared/widgets/navigator_section.dart' show AskodoxNavSection;
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
      if (e['test'] == true || e['direction'] == 'out') continue; // money out is not "came in"
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

  /// 'me' = this phone's own payments (default for a normal person); otherwise a shop id the person belongs to.
  String _source = 'me';
  static const _sourceKey = 'askodox.payments.source.v1';
  bool get _mine => _source == 'me';
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
      final prefs = await SharedPreferences.getInstance();
      var source = prefs.getString(_sourceKey) ?? '';
      // Nobody's shop is picked for them: the owner of a shop starts on it, everyone else on their own phone.
      if (source != 'me' && !shops.any((s) => '${s['id']}' == source)) {
        source = shops.where((s) => '${s['role']}' == 'owner').map((s) => '${s['id']}').firstOrNull ?? 'me';
      }
      final events = await _eventsFor(repo, source);
      if (!mounted) return;
      setState(() {
        _shops = shops;
        _source = source;
        _events = events;
        _error = null;
      });
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// One week of events for [source]: this phone's own (kept on the phone) or one shop's (from the server).
  Future<List<AskodoxJson>> _eventsFor(AskodoxPosRepository repo, String source) async {
    if (source == 'me') {
      final local = await ref.read(askodoxPaymentAlertsBridgeProvider).localEvents();
      return [
        for (final e in local.reversed)
          if (e['test'] != true && e['direction'] != null)
            {
              ...e,
              'id': e['local_id'],
              'received_at': e['detected_at'],
              'acks': [if ('${e['spoken']}' == 'announced') {'state': 'announced'}],
            },
      ];
    }
    final since = _now.toUtc().subtract(const Duration(days: 7)).toIso8601String();
    try {
      return askodoxPosList((await repo.paymentEvents(source, since: since, limit: 500))['events']);
    } on AskodoxPosException {
      return const []; // The page still shows the doors; the list stays empty.
    }
  }

  Future<void> _pick(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceKey, source);
    final events = await _eventsFor(ref.read(askodoxPosRepositoryProvider), source);
    if (!mounted) return;
    setState(() {
      _source = source;
      _events = events;
    });
  }

  /// "My phone" + one chip per shop the person belongs to (owner, manager or staff) -- each is a separate history.
  Widget _sources(bool te, List<AskodoxJson> shops) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        ChoiceChip(
          key: const Key('askodoxPaymentsSource-me'),
          label: Text(te ? 'నా ఫోన్' : 'My phone'),
          selected: _mine,
          onSelected: (_) => _pick('me'),
        ),
        for (final s in shops)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ChoiceChip(
              key: ValueKey('askodoxPaymentsSource-${s['id']}'),
              label: Text('${s['name'] ?? ''}'),
              selected: _source == '${s['id']}',
              onSelected: (_) => _pick('${s['id']}'),
            ),
          ),
      ]));

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
                    Text(te ? 'మనీ' : 'Money',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _ink)),
                    const SizedBox(height: 2),
                    Text(te ? 'డబ్బు నేరుగా మీ ఖాతాకే వస్తుంది' : 'Money comes straight to your account',
                        style: const TextStyle(fontSize: 13, color: _muted)),
                    const SizedBox(height: 14),
                    if (shops.isNotEmpty) ...[_sources(te, shops), const SizedBox(height: 12)],
                    _qrCard(te),
                    const SizedBox(height: 12),
                    if (_mine && _events.isEmpty) ...[_start(te), const SizedBox(height: 12)],
                    _doors(te, shops),
                    const SizedBox(height: 16),
                    _recent(te, _source),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          te
                              ? 'ఫోన్ నోటిఫికేషన్ / బ్యాంక్ SMS లో "అందింది" అన్న లెక్క. ఖాతాలో పడిందో మీ బ్యాంక్ యాప్‌లో చూసుకోండి.'
                              : 'Counted from "received" phone notifications / bank SMS. Check your bank app for the money in your account.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11.5, color: _muted)),
                    ),
                    if (!_mine) ...[
                      const SizedBox(height: 14),
                      _advanced(te, _source),
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
          Text(te ? 'మీ ఫోన్‌కి డబ్బు వచ్చిన వెంటనే చెబుతుంది' : 'Your phone says it when money reaches it',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 6),
          Text(
              te
                  ? 'ఫోన్‌పే, గూగుల్ పే, సూపర్ మనీ, బ్యాంక్ SMS — మీకు కావలసిన యాప్‌లు ఎంచుకోండి. హిస్టరీ మీ ఫోన్‌లోనే.'
                  : 'PhonePe, Google Pay, super.money, bank SMS — choose the apps you want read. Your history stays on your phone.',
              style: const TextStyle(fontSize: 13, color: _muted, height: 1.4)),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('askodoxPaymentsHubStartButton'),
            style: FilledButton.styleFrom(backgroundColor: _ink, minimumSize: const Size.fromHeight(48)),
            onPressed: () => context.push('/me/payments/phone'),
            child: Text(te ? 'నా ఫోన్ అలర్ట్స్ ఆన్ చేయండి' : 'Switch my phone alerts on'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('askodoxPaymentsHubShopButton'),
            onPressed: () => context.push('/me/payment-alerts'),
            child: Text(te ? 'షాప్ కోసం అలర్ట్స్' : 'Alerts for my shop'),
          ),
        ]),
      );

  /// The one big action: show the QR the customer scans (money goes straight to the person's own account).
  Widget _qrCard(bool te) => Material(
        color: _ink,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: const Key('askodoxPaymentsHubQr'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.push('/me/payment-methods'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(te ? 'నా QR / ఖాతాలు' : 'My QR / accounts',
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  // Owner 2026-11-17: ONE place for the QR and the accounts (no separate "My accounts" button).
                  Text(te ? 'QR చూపించు · UPI / బ్యాంక్ చేర్చు, మార్చు' : 'Show the QR · add / change UPI and bank',
                      key: const Key('askodoxPaymentsHubAccounts'),
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
      );

  /// Six doors in a neat 2 x 3 grid (owner 2026-11-17: no stats card, no row of small buttons); each says its news.
  Widget _doors(bool te, List<AskodoxJson> shops) {
    final week = AskodoxPaymentWeek(_events, _now);
    final hasToday = _events.isNotEmpty;
    final alerts = _mine ? '/me/payments/phone' : '/me/payment-alerts/$_source';
    var n = 0;
    Widget door(String key, IconData icon, String title, String sub, String path, {Key? subKey, bool tint = false}) {
      final (bg, fg) = AskodoxNavSection.palette[n++ % AskodoxNavSection.palette.length];
      return Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key(key),
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(path),
          child: Container(
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: fg, size: 21),
              ),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 2),
              Text(sub, key: subKey, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563))),
            ]),
          ),
        ),
      );
    }

    final cells = [
      door('askodoxPaymentsHubMoney', Icons.account_balance_wallet_outlined, te ? 'నా డబ్బు' : 'My money',
          hasToday
              ? (te
                  ? 'ఈ రోజు ${askodoxRupees(week.todayPaise)} · ${week.todayCount} పేమెంట్లు'
                  : 'Today ${askodoxRupees(week.todayPaise)} · ${week.todayCount} payments')
              : (te ? 'అన్నీ ఒకే చోట: వచ్చినవి, ఖర్చులు, బిల్లులు' : 'All in one place: in, out, bills'),
          '/money',
          subKey: hasToday ? const Key('askodoxPaymentsHubToday') : null,
          tint: true),
      door('askodoxPaymentsHubBill', Icons.calculate_outlined, te ? 'బిల్ వేయి' : 'Make a bill',
          te ? 'నంబర్ / పేరుతో, WhatsApp కి' : 'By number / name, to WhatsApp', '/me/business/$_source/bill'),
      door('askodoxPaymentsHubDues', Icons.event_note_outlined, te ? 'రాబోయే చెల్లింపులు' : 'Coming up',
          te ? 'EMI, కరెంట్ బిల్, అద్దె' : 'EMI, current bill, rent', '/money'),
      door('askodoxPaymentsHubMyBills', Icons.receipt_long_outlined, te ? 'నా బిల్లులు' : 'My bills',
          te ? 'షాపుల నుంచి వచ్చినవి' : 'Bills shops sent you', '/me/bills'),
      door(
          'askodoxPaymentsHubAlerts',
          Icons.volume_up_rounded,
          te ? 'పేమెంట్ వాయిస్' : 'Payment voice',
          hasToday
              ? (te ? 'ఈ రోజు ${week.todaySpoken} సార్లు చెప్పింది' : 'spoke ${week.todaySpoken} times today')
              : (te ? 'డబ్బు రాగానే చెప్తుంది' : 'Says it when money comes'),
          alerts),
    ];
    // 2 x 2 + the voice door across the width (an odd one never sits alone in half a row)
    return Column(children: [
      for (var r = 0; r + 1 < cells.length; r += 2) ...[
        if (r > 0) const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: cells[r]),
          const SizedBox(width: 10),
          Expanded(child: cells[r + 1]),
        ]),
      ],
      if (cells.length.isOdd) ...[const SizedBox(height: 10), cells.last],
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
      Material(
        key: const Key('askodoxPaymentsHubRecent'),
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: _line)),
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
                  Text(latest[i]['amount_paise'] is int ? '${latest[i]['direction'] == 'out' ? '−' : ''}${askodoxRupees(latest[i]['amount_paise'] as int)}' : '—',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
                  if (askodoxPaymentWasSpoken(latest[i]))
                    Text(te ? '✓ మాట్లాడింది' : '✓ Spoke',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _green)),
                ]),
              ]),
            ),
          InkWell(
            key: const Key('askodoxPaymentsHubSeeAll'),
            onTap: () => context.push(shopId == 'me' ? '/me/payments/phone' : '/me/payment-alerts/$shopId/history'),
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
