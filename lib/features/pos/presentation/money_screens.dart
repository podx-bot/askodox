import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/backend_providers.dart';
import '../data/pos_payment_alerts.dart';
import '../data/pos_repository.dart';
import '../domain/money_accounts.dart';
import '../domain/money_ledger.dart';
import '../domain/pos_money.dart';
import 'pos_common.dart';
import 'pay_alert_disclaimer.dart';

/// ONE money history (owner 2026-11-17, design "ASKODOX డబ్బు హిస్టరీ — అన్నీ ఒకే చోట"): the phone's payments, the bills
/// the person got, a shop's bills and Razorpay alerts, upcoming dues -- one list, with "which bill did this pay", "what
/// was it for" and "what is coming". The person's own money and each shop's money are separate views (never mixed).
class AskodoxMoneyScreen extends ConsumerStatefulWidget {
  const AskodoxMoneyScreen({super.key});

  @override
  ConsumerState<AskodoxMoneyScreen> createState() => _AskodoxMoneyScreenState();
}

const _accent = Color(0xFF1E3FA0);
const _green = Color(0xFF17784C);
const _red = Color(0xFFB91C1C);
const _amber = Color(0xFF92400E);

String _rs(int paise) => askodoxPaise(paise);

/// The native "My phone" settings with the ElevenLabs voice address (same as the My phone screen).
Map<String, Object?> _nativeOf(WidgetRef ref, AskodoxMyPhoneAlerts m) {
  var base = '';
  var token = '';
  try {
    base = ref.read(appConfigProvider).apiBaseUrl?.toString() ?? '';
    final session = ref.read(authSessionProvider);
    token = session.user == null ? '' : (session.tokenPlaceholder ?? '');
  } catch (_) {}
  return m.nativeConfig(baseUrl: base, token: token);
}

/// The money data of one view, loaded once and shared by the screens.
class _MoneyData {
  AskodoxMyPhoneAlerts? mine;
  List<AskodoxJson> phoneEvents = const [];
  List<AskodoxJson> myBills = const [];
  List<AskodoxJson> businesses = const [];
  List<AskodoxJson> shopAlerts = const [];
  List<AskodoxJson> shopBills = const [];
  String? error;
}

class _AskodoxMoneyScreenState extends ConsumerState<AskodoxMoneyScreen> with WidgetsBindingObserver {
  final _data = _MoneyData();
  String _owner = 'me'; // 'me' or a business id
  String _kind = 'all'; // all | in | out | bills | pending
  String _period = 'month'; // today | week | month | all
  String _how = ''; // '' = every way
  String? _account;
  String _q = '';
  bool _searching = false;
  bool _loading = true;
  bool _listMode = false; // false = the one-page summary, true = every row with filters
  late final AskodoxPaymentAlertsBridge _bridge = ref.read(askodoxPaymentAlertsBridgeProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bridge.onEvent((_) => unawaited(_load(quiet: true)));
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bridge.onEvent(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load(quiet: true));
  }

  bool get _signedIn {
    try {
      return ref.read(authSessionProvider).user != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      _data.mine = await AskodoxMyPhoneAlerts.load();
      _data.phoneEvents = await _bridge.localEvents();
      unawaited(_bridge.checkDues());
    } catch (_) {}
    if (_signedIn) {
      try {
        _data.myBills = await repo.myBills();
      } catch (_) {}
      try {
        _data.businesses = await repo.businesses();
      } catch (_) {}
      if (_owner != 'me') await _loadShop(_owner);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadShop(String biz) async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      _data.shopAlerts = askodoxPosList((await repo.paymentEvents(biz, limit: 200))['events']);
    } catch (_) {
      _data.shopAlerts = const [];
    }
    try {
      _data.shopBills = askodoxPosList((await repo.billHistory(biz))['bills']);
    } catch (_) {
      _data.shopBills = const [];
    }
  }

  Future<void> _saveMine(void Function(AskodoxMyPhoneAlerts m) edit) async {
    final m = _data.mine;
    if (m == null) return;
    edit(m);
    await m.save();
    try {
      await _bridge.configurePersonal(_nativeOf(ref, m));
    } catch (_) {}
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------ the rows of this view

  List<AskodoxMoneyItem> _items() {
    final m = _data.mine;
    if (_owner != 'me') {
      return [...askodoxItemsFromShopAlerts(_data.shopAlerts), ...askodoxItemsFromShopBills(_data.shopBills)]
        ..sort((a, b) => b.at.compareTo(a.at));
    }
    final labelToPkg = m == null ? <String, String>{} : {for (final e in m.apps.entries) e.value: e.key};
    return [
      ...askodoxItemsFromPhone(_data.phoneEvents, m?.places ?? const [], m?.assigned ?? const {}, m?.links ?? const {},
          labelToPackage: labelToPkg),
      ...askodoxItemsFromMyBills(_data.myBills, m?.links ?? const {}),
    ]..sort((a, b) => b.at.compareTo(a.at));
  }

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      'today' => (today, today.add(const Duration(days: 1))),
      'week' => (today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1))),
      'month' => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
      _ => (DateTime(2000), DateTime(2100)),
    };
  }

  String _cat(AskodoxMoneyItem i) =>
      askodoxCategoryOf(i, rowCategory: _data.mine?.rowCategory ?? const {}, payeeCategory: _data.mine?.payeeCategory ?? const {});

  String _accountName(String key, bool te) {
    if (key.isEmpty) return '';
    for (final p in _data.mine?.places ?? const <AskodoxMoneyPlace>[]) {
      if (p.key == key) return p.name;
    }
    return key.startsWith('bank:') ? 'A/c ••${key.substring(5)}' : key;
  }

  // ------------------------------------------------------------------ joins

  Future<void> _join(AskodoxPairSuggestion s, bool te) async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      if (s.bill.id.startsWith('mybill:')) {
        // the shop is TOLD the customer paid (it never marks the bill paid by itself; the shop confirms)
        await repo.myBillPaid(s.bill.id.substring(7), s.payment.how);
        await _saveMine((m) => m.links = {...m.links, s.payment.id: s.bill.id});
      } else if (s.bill.id.startsWith('shopbill:')) {
        final pay = switch (s.payment.how) { 'phonepe' || 'gpay' || 'paytm' => s.payment.how, 'cash' => 'cash', _ => 'other_upi' };
        await repo.billSettle(_owner, s.bill.id.substring(9), pay, askodoxNewTxnId());
        await _loadShop(_owner);
      }
      if (mounted) askodoxPosSnack(context, te ? 'జత చేశాం ✓' : 'Joined ✓');
      await _load(quiet: true);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _dismiss(String key) => _saveMine((m) => m.dismissed = {...m.dismissed, key});

  Future<void> _duePaid(AskodoxMoneyItem payment, AskodoxDue due, DateTime date) => _saveMine((m) {
        m.dues = [
          for (final d in m.dues) d.id == due.id ? d.copyWith(paidDates: [...d.paidDates, askodoxDay(date)]) : d,
        ];
        m.links = {...m.links, payment.id: 'due:${due.id}'};
        if (due.category.isNotEmpty) m.rowCategory = {...m.rowCategory, payment.id: due.category};
      });

  Future<void> _pickCategory(AskodoxMoneyItem item, bool te) async {
    var always = true;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(te ? 'దేనికి?' : 'What was it for?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final c in askodoxMoneyCategories)
                  ChoiceChip(
                    key: ValueKey('askodoxMoneyCat-${c.$1}'),
                    label: Text(te ? c.$3 : c.$2),
                    selected: _cat(item) == c.$1,
                    onSelected: (_) => Navigator.pop(ctx, c.$1),
                  ),
              ]),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: always,
                onChanged: (v) => setLocal(() => always = v ?? true),
                title: Text(te ? '"${item.title}" కి కట్టేవి ఎప్పుడూ ఇదే వర్గం' : 'Always this for "${item.title}"'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (picked == null) return;
    await _saveMine((m) {
      m.rowCategory = {...m.rowCategory, item.id: picked};
      if (always && item.title.trim().isNotEmpty) m.payeeCategory = {...m.payeeCategory, askodoxNormPayee(item.title): picked};
    });
  }

  // ------------------------------------------------------------------ detail

  Future<void> _open(AskodoxMoneyItem i, List<AskodoxMoneyItem> all, bool te) async {
    final cat = _cat(i);
    final linked = i.linkedTo.isEmpty ? null : all.where((x) => x.id == i.linkedTo).firstOrNull;
    final billLines = (linked ?? i).raw['lines'];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: _Badge(how: i.how, kind: i.kind, size: 52)),
            const SizedBox(height: 8),
            Text('${i.direction == 'out' ? '− ' : '+ '}${_rs(i.amountPaise)}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: i.direction == 'out' ? _red : _green)),
            Text(i.title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(_when(i.at, te), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF5B6475))),
            if (_proof(i, te) case final p?) Center(child: Padding(padding: const EdgeInsets.only(top: 6), child: _Pill(p.$1, p.$2))),
            const Divider(height: 24),
            if (i.how.isNotEmpty) _kv(te ? 'ఎలా' : 'How', te ? askodoxHowLabel(i.how).$2 : askodoxHowLabel(i.how).$1),
            if (i.account.isNotEmpty) _kv(te ? 'ఖాతా' : 'Account', _accountName(i.account, te)),
            if ('${i.raw['reference'] ?? i.raw['reference_tail'] ?? ''}'.isNotEmpty)
              _kv(te ? 'రిఫరెన్స్' : 'Reference', '${i.raw['reference'] ?? '••${i.raw['reference_tail']}'}'),
            if (i.sub.isNotEmpty) _kv(te ? 'ఎక్కడ నుంచి' : 'From', i.sub),
            if (i.raw['balance_paise'] is num) _kv(te ? 'బ్యాలెన్స్ (SMS)' : 'Balance (SMS)', _rs((i.raw['balance_paise'] as num).toInt())),
            if (i.direction == 'out' && _owner == 'me')
              _kv(te ? 'దేనికి' : 'For', cat.isEmpty ? (te ? 'వర్గం లేదు' : 'Not set') : (te ? askodoxCategoryLabel(cat).$2 : askodoxCategoryLabel(cat).$1)),
            if (linked != null) ...[
              const SizedBox(height: 10),
              Text(te ? 'జత అయింది' : 'Joined with', style: const TextStyle(fontWeight: FontWeight.w800)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _Badge(how: linked.how, kind: linked.kind),
                title: Text(linked.title),
                subtitle: Text('${linked.sub} · ${_when(linked.at, te)}'),
                trailing: Text(_rs(linked.amountPaise), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
            if (billLines is List && billLines.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final l in billLines.whereType<Map>())
                Row(children: [
                  Expanded(child: Text('${l['name'] ?? ''}')),
                  if (l['amount_paise'] is num) Text(_rs((l['amount_paise'] as num).toInt())),
                ]),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (i.direction == 'out' && _owner == 'me' && i.kind == 'payment')
                OutlinedButton(
                  key: const Key('askodoxMoneyDetailCategory'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(_pickCategory(i, te));
                  },
                  child: Text(te ? 'వర్గం మార్చు' : 'Change category'),
                ),
              if (i.kind == 'bill' && i.id.startsWith('mybill:') && i.pending)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/me/bills');
                  },
                  child: Text(te ? 'కట్టు' : 'Pay'),
                ),
              if (i.linkedTo.isNotEmpty && _owner == 'me' && i.kind == 'payment')
                OutlinedButton(
                  key: const Key('askodoxMoneyDetailUnlink'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _saveMine((m) => m.links = {...m.links}..remove(i.id));
                  },
                  child: Text(te ? 'జత తీసేయి' : 'Remove the join'),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(k, style: const TextStyle(color: Color(0xFF5B6475)))),
          Flexible(flex: 2, child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  (String, Color)? _proof(AskodoxMoneyItem i, bool te) {
    if (i.kind == 'bill') {
      if (i.pending) return (te ? '⏳ ఇంకా కట్టలేదు' : '⏳ Not paid yet', _amber);
      if (i.linkedTo.isNotEmpty) return (te ? '✓ పేమెంట్‌తో జత' : '✓ Joined to a payment', _green);
      return (te ? '✓ కట్టారు' : '✓ Paid', _green);
    }
    return switch (i.confirmed) {
      'bank_sms' => (te ? '✓ బ్యాంక్ SMS లో అందింది' : '✓ Received (bank SMS)', _green),
      'provider' => (te ? '✓ Razorpay లో అందింది' : '✓ Received (Razorpay)', _green),
      'cashier' => (te ? '✓ క్యాషియర్ నమోదు చేశారు' : '✓ Entered by the cashier', _green),
      _ => i.kind == 'payment' ? (te ? '⏳ బ్యాంక్ SMS ఇంకా రాలేదు' : '⏳ Bank SMS not seen yet', const Color(0xFF6B7280)) : null,
    };
  }

  String _when(DateTime d, bool te) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final t = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (day == today) return t;
    if (day == today.subtract(const Duration(days: 1))) return '${te ? 'నిన్న' : 'Yesterday'} $t';
    return '${d.day}/${d.month} $t';
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    if (!_listMode) return _summary(te);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _listMode = false);
      },
      child: _list(te),
    );
  }

  /// Unconfirmed money (only a notification saw it): a small ⏳ after the name; the meaning is in ONE note below.
  bool _unconfirmed(AskodoxMoneyItem i) => i.kind == 'payment' && i.confirmed.isEmpty;

  Widget _footNote(bool te) => Padding(
        key: const Key('askodoxMoneyFootNote'),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(children: [
          Text(
              te
                  ? '⏳ = యాప్ నోటిఫికేషన్‌లో మాత్రమే అందింది, బ్యాంక్ SMS ఇంకా రాలేదు.'
                  : '⏳ = received in an app notification only; no bank SMS yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B6475))),
          const SizedBox(height: 8),
          AskodoxPayAlertDisclaimer(te: te),
        ]),
      );

  // ------------------------------------------------------------------ the one page (owner 2026-11-17)

  String _periodLabel(bool te) {
    const monthsTe = ['జనవరి', 'ఫిబ్రవరి', 'మార్చి', 'ఏప్రిల్', 'మే', 'జూన్', 'జూలై', 'ఆగస్టు', 'సెప్టెంబర్', 'అక్టోబర్', 'నవంబర్', 'డిసెంబర్'];
    const monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return switch (_period) {
      'today' => te ? 'ఈ రోజు' : 'Today',
      'week' => te ? 'ఈ వారం' : 'This week',
      'all' => te ? 'అన్నీ' : 'All time',
      _ => te ? monthsTe[DateTime.now().month - 1] : monthsEn[DateTime.now().month - 1],
    };
  }

  void _openList({String kind = 'all', String? account, bool search = false}) => setState(() {
        _listMode = true;
        _kind = kind;
        _account = account;
        _searching = search;
        if (!search) _q = '';
      });

  /// Everything at a glance on ONE screen: what came in / went out, what is due, what to join, the latest few rows.
  /// Every tile opens the full list already filtered.
  Widget _summary(bool te) {
    final all = _items();
    final range = _range();
    final m = _data.mine;
    final personal = _owner == 'me';
    final totals = askodoxTotals(all, range.$1, range.$2,
        rowCategory: m?.rowCategory ?? const {}, payeeCategory: m?.payeeCategory ?? const {});
    final payments = all.where((i) => i.kind == 'payment').toList();
    final bills = all.where((i) => i.kind == 'bill').toList();
    final pairs = askodoxPairSuggestions(payments, bills, dismissed: m?.dismissed ?? const <String>{});
    final pending = bills.where((b) => b.pending).toList();
    final pendingSum = pending.fold<int>(0, (a, b) => a + b.amountPaise);
    final balances = askodoxLatestBalances(all);
    final sales = bills.where((b) => !b.at.isBefore(range.$1) && b.at.isBefore(range.$2)).toList();
    final salesSum = sales.fold<int>(0, (a, b) => a + b.amountPaise);
    final topCat = (totals.byCategory.entries.where((e) => e.key.isNotEmpty).toList()..sort((a, b) => b.value.compareTo(a.value)))
        .firstOrNull;
    final cash = totals.inByHow['cash'] ?? 0;
    final now = DateTime.now();
    final upcoming = <(AskodoxDue, DateTime)>[
      if (personal && m != null)
        for (final d in m.dues)
          if (askodoxNextDue(d, now) case final next?) (d, next),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final recent = all.where((i) => !i.at.isBefore(range.$1) && i.at.isBefore(range.$2)).take(4).toList();
    final today = DateTime(now.year, now.month, now.day);

    Widget stat(String label, String value, {String sub = ''}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
              if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
            ]),
          ),
        );

    Widget tile(String key, String label, String value, String sub, Color color, Color bg, VoidCallback onTap) => Expanded(
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: ValueKey('askodoxMoneyTile-$key'),
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 74),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
                  if (sub.isNotEmpty)
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B6475))),
                ]),
              ),
            ),
          ),
        );

    final tiles = personal
        ? [
            tile('pending', te ? 'కట్టాల్సిన బిల్లులు' : 'Bills to pay', _rs(pendingSum),
                te ? '${pending.length} బిల్' : '${pending.length} bills', _amber, const Color(0xFFFFF4E5), () => _openList(kind: 'pending')),
            const SizedBox(width: 8),
            tile('top', te ? 'ఎక్కువ ఖర్చు' : 'Spent most on',
                topCat == null ? '—' : (te ? askodoxCategoryLabel(topCat.key).$2 : askodoxCategoryLabel(topCat.key).$1),
                topCat == null ? '' : _rs(topCat.value), const Color(0xFF1B2333), Colors.white,
                () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => AskodoxMoneyMonthScreen(items: all, mine: _data.mine, personal: personal)))),
            const SizedBox(width: 8),
            tile('pairs', te ? 'జత చేయాలి' : 'To join', '${pairs.length}', te ? 'బిల్ ↔ పేమెంట్' : 'bill ↔ payment', _accent,
                const Color(0xFFE8EEFB), () => _openList()),
          ]
        : [
            tile('pending', te ? 'రావాల్సిన బాకీ' : 'Customers owe', _rs(pendingSum),
                te ? '${pending.length} బిల్లులు' : '${pending.length} bills', _amber, const Color(0xFFFFF4E5), () => _openList(kind: 'pending')),
            const SizedBox(width: 8),
            tile('cash', te ? 'క్యాష్ / UPI' : 'Cash / UPI', '${_rs(cash)} / ${_rs(totals.inPaise - cash)}', '', const Color(0xFF1B2333),
                Colors.white, () => _openList(kind: 'in')),
            const SizedBox(width: 8),
            tile('pairs', te ? 'జత చేయాలి' : 'To join', '${pairs.length}', te ? 'పేమెంట్ ↔ బిల్' : 'payment ↔ bill', _accent,
                const Color(0xFFE8EEFB), () => _openList()),
          ];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(key: const Key('askodoxMoney'), padding: EdgeInsets.zero, children: [
          Container(
            key: const Key('askodoxMoneySummary'),
            padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top + 6, 14, 14),
            decoration: const BoxDecoration(color: _accent, borderRadius: BorderRadius.vertical(bottom: Radius.circular(22))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                IconButton(
                    tooltip: te ? 'వెనక్కి' : 'Back',
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop()),
                Expanded(
                    child: Text(personal ? (te ? 'నా డబ్బు' : 'My money') : (te ? 'షాప్ డబ్బు' : 'Shop money'),
                        style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800))),
                IconButton(
                  key: const Key('askodoxMoneySearchToggle'),
                  tooltip: te ? 'వెతుకు' : 'Search',
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: () => _openList(search: true),
                ),
                PopupMenuButton<String>(
                  key: const Key('askodoxMoneyPeriod'),
                  initialValue: _period,
                  onSelected: (p) => setState(() => _period = p),
                  itemBuilder: (_) => [
                    for (final p in const ['today', 'week', 'month', 'all'])
                      PopupMenuItem(value: p, child: Text(switch (p) {
                        'today' => te ? 'ఈ రోజు' : 'Today',
                        'week' => te ? 'ఈ వారం' : 'This week',
                        'month' => te ? 'ఈ నెల' : 'This month',
                        _ => te ? 'అన్నీ' : 'All time',
                      })),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                    child: Text('${_periodLabel(te)} ▾', style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ),
              ]),
              if (_data.businesses.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _segment('me', te ? 'నా సొంతం' : 'My own'),
                      for (final b in _data.businesses) _segment('${b['id']}', '${b['name'] ?? ''}'),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(children: personal
                  ? [
                      stat(te ? 'వచ్చింది' : 'Came in', _rs(totals.inPaise)),
                      const SizedBox(width: 8),
                      stat(te ? 'ఖర్చు' : 'Went out', _rs(totals.outPaise)),
                    ]
                  : [
                      stat(te ? 'అమ్మకాలు (బిల్లులు)' : 'Sales (bills)', _rs(salesSum), sub: te ? '${sales.length} బిల్లులు' : '${sales.length} bills'),
                      const SizedBox(width: 8),
                      stat(te ? 'వచ్చిన డబ్బు' : 'Money in', _rs(totals.inPaise),
                          sub: te ? '${payments.where((p) => !p.at.isBefore(range.$1) && p.at.isBefore(range.$2)).length} పేమెంట్లు' : ''),
                    ]),
              if (personal && balances.isNotEmpty)
                InkWell(
                  key: const Key('askodoxMoneyBalances'),
                  onTap: () => _openList(),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        '${te ? 'బ్యాలెన్స్' : 'Balance'}: ${[
                          for (final e in balances.entries.take(2)) '${_accountName(e.key, te)} ${_rs(e.value.$1)}',
                        ].join(' · ')} ›',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                  ),
                ),
            ]),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: tiles)),
          if (pairs.isNotEmpty) _pairCard(te, pairs.first),
          if (personal) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(children: [
                Expanded(child: Text(te ? 'రాబోయే చెల్లింపులు' : 'Coming up', style: const TextStyle(fontWeight: FontWeight.w800))),
                TextButton(
                  key: const Key('askodoxMoneyDues'),
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => AskodoxDuesScreen(phoneEvents: _data.phoneEvents, items: all)));
                    await _load(quiet: true);
                  },
                  child: Text(upcoming.isEmpty ? (te ? '+ చేర్చు' : '+ Add') : (te ? 'అన్నీ ›' : 'All ›')),
                ),
              ]),
            ),
            SizedBox(
              height: 72,
              child: upcoming.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(te ? 'EMI, కరెంట్ బిల్, అద్దె చేర్చండి — గడువుకు 2 రోజుల ముందు, ఆ రోజు వాయిస్‌తో చెప్తుంది.'
                          : 'Add EMI, current bill, rent — said aloud 2 days before and on the day.',
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
                    )
                  : ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14), children: [
                      for (final u in upcoming.take(8))
                        Container(
                          key: ValueKey('askodoxMoneyDue-${u.$1.id}'),
                          width: 132,
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E7EB))),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(u.$1.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text(_rs(u.$1.amountPaise), style: const TextStyle(fontWeight: FontWeight.w800)),
                            Builder(builder: (_) {
                              final days = DateTime(u.$2.year, u.$2.month, u.$2.day).difference(today).inDays;
                              return Text(
                                  days <= 0 ? (te ? 'ఈ రోజే' : 'Today') : days == 1 ? (te ? 'రేపు' : 'Tomorrow') : days <= 7 ? (te ? '$days రోజుల్లో' : 'in $days days') : '${u.$2.day}/${u.$2.month}',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: days <= 3 ? const Color(0xFFB45309) : const Color(0xFF374151)));
                            }),
                          ]),
                        ),
                    ]),
            ),
          ],
          Container(
            margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(te ? 'ఇటీవల' : 'Latest', style: const TextStyle(fontWeight: FontWeight.w800))),
                TextButton(key: const Key('askodoxMoneyAll'), onPressed: () => _openList(), child: Text(te ? 'అన్నీ చూడు ›' : 'See all ›')),
              ]),
              if (recent.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(_loading ? (te ? 'లోడ్ అవుతోంది…' : 'Loading…') : (te ? 'ఇంకా ఏమీ లేదు.' : 'Nothing yet.'),
                        textAlign: TextAlign.center)),
              for (final i in recent) _row(te, i, all),
            ]),
          ),
          _footNote(te),
        ]),
      ),
    );
  }

  Widget _segment(String id, String label) {
    final sel = _owner == id;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: sel ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          key: ValueKey('askodoxMoneyOwner-$id'),
          borderRadius: BorderRadius.circular(9),
          onTap: () async {
            setState(() {
              _owner = id;
              _account = null;
              _how = '';
              _loading = id != 'me';
            });
            if (id != 'me') {
              await _loadShop(id);
              if (mounted) setState(() => _loading = false);
            }
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 38, minWidth: 96),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label,
                style: TextStyle(color: sel ? _accent : Colors.white, fontWeight: sel ? FontWeight.w800 : FontWeight.w500, fontSize: 13)),
          ),
        ),
      ),
    );
  }

  Widget _list(bool te) {
    final all = _items();
    final range = _range();
    final m = _data.mine;
    final personal = _owner == 'me';
    final dismissed = m?.dismissed ?? const <String>{};
    var shown = all.where((i) => !i.at.isBefore(range.$1) && i.at.isBefore(range.$2)).toList();
    if (_account != null) shown = shown.where((i) => i.account == _account).toList();
    if (_how.isNotEmpty) shown = shown.where((i) => i.how == _how).toList();
    shown = switch (_kind) {
      'in' => shown.where((i) => i.direction == 'in').toList(),
      'out' => shown.where((i) => i.direction == 'out').toList(),
      'bills' => shown.where((i) => i.kind == 'bill').toList(),
      'pending' => shown.where((i) => i.pending).toList(),
      _ => shown,
    };
    if (_q.trim().isNotEmpty) {
      final q = _q.trim().toLowerCase();
      shown = shown
          .where((i) => '${i.title} ${i.sub} ${i.amountPaise ~/ 100} ${_accountName(i.account, te)}'.toLowerCase().contains(q))
          .toList();
    }
    final totals = askodoxTotals(
        _account == null ? all : all.where((i) => i.account == _account), range.$1, range.$2,
        rowCategory: m?.rowCategory ?? const {}, payeeCategory: m?.payeeCategory ?? const {});
    final payments = all.where((i) => i.kind == 'payment').toList();
    final bills = all.where((i) => i.kind == 'bill').toList();
    final pairs = askodoxPairSuggestions(payments, bills, dismissed: dismissed);
    final duePairs = <(AskodoxMoneyItem, AskodoxDue, DateTime)>[];
    if (personal && m != null) {
      for (final p in payments.take(60)) {
        if (p.linkedTo.isNotEmpty || dismissed.contains('due|${p.id}')) continue;
        if (askodoxDuePaidBy(p, m.dues) case final hit?) duePairs.add((p, hit.$1, hit.$2));
      }
    }
    final pendingBills = bills.where((b) => b.pending).toList();
    final hows = <String>{for (final i in all) if (i.how.isNotEmpty) i.how}.toList();
    final balances = askodoxLatestBalances(all);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(key: const Key('askodoxMoney'), padding: EdgeInsets.zero, children: [
          _header(te, balances, personal),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          _totalsBox(te, totals),
          if (personal && m != null) _duesCard(te, m),
          if (pendingBills.isNotEmpty) _pendingCard(te, pendingBills, personal),
          for (final s in pairs.take(3)) _pairCard(te, s),
          for (final d in duePairs.take(2)) _duePairCard(te, d.$1, d.$2, d.$3),
          _filters(te, hows),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                      _loading ? (te ? 'లోడ్ అవుతోంది…' : 'Loading…') : (te ? 'ఈ ఫిల్టర్‌లో ఏమీ లేదు.' : 'Nothing for this filter.'),
                      textAlign: TextAlign.center),
                ),
              for (final i in shown.take(300)) _row(te, i, all),
            ]),
          ),
          _footNote(te),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              OutlinedButton.icon(
                key: const Key('askodoxMoneyMonth'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => AskodoxMoneyMonthScreen(items: all, mine: _data.mine, personal: personal))),
                icon: const Icon(Icons.pie_chart_outline),
                label: Text(te ? 'ఈ నెల ఎక్కడ ఖర్చు' : 'Where the money went'),
              ),
              if (personal)
                OutlinedButton.icon(
                  key: const Key('askodoxMoneyAccounts'),
                  onPressed: () async {
                    await context.push('/me/payments/phone');
                    await _load(quiet: true);
                  },
                  icon: const Icon(Icons.account_balance_outlined),
                  label: Text(te ? 'ఖాతాలు / సెట్టింగ్స్' : 'Accounts / settings'),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _header(bool te, Map<String, (int, DateTime)> balances, bool personal) {
    final keys = _accountKeys(balances);
    final total = balances.values.fold<int>(0, (a, b) => a + b.$1);
    return Container(
      padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top + 8, 8, 16),
      decoration: const BoxDecoration(color: _accent, borderRadius: BorderRadius.vertical(bottom: Radius.circular(22))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(
              tooltip: te ? 'వెనక్కి' : 'Back',
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => _listMode ? setState(() => _listMode = false) : Navigator.of(context).maybePop()),
          Expanded(
            child: _searching
                ? TextField(
                    key: const Key('askodoxMoneySearch'),
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: te ? 'పేరు / మొత్తం / ఖాతా' : 'Name / amount / account',
                        hintStyle: const TextStyle(color: Colors.white70)),
                    onChanged: (v) => setState(() => _q = v),
                  )
                : Text(personal ? (te ? 'నా డబ్బు' : 'My money') : (te ? 'షాప్ డబ్బు' : 'Shop money'),
                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            key: const Key('askodoxMoneySearchToggle'),
            tooltip: te ? 'వెతుకు' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search, color: Colors.white),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _q = '';
            }),
          ),
        ]),
        if (_data.businesses.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _ownerChip('me', te ? 'నా సొంతం' : 'My own', te),
                for (final b in _data.businesses) _ownerChip('${b['id']}', '${b['name'] ?? ''}', te),
              ]),
            ),
          ),
        if (personal && balances.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(te ? 'చివరిగా తెలిసిన బ్యాలెన్స్ (బ్యాంక్ SMS)' : 'Last known balance (bank SMS)',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(_rs(total), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
        ],
        if (personal && keys.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 74,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
              _accountCard(null, te ? 'అన్ని ఖాతాలు' : 'All accounts', null, te),
              for (final k in keys) _accountCard(k, _accountName(k, te), balances[k], te),
            ]),
          ),
        ],
      ]),
    );
  }

  /// Accounts worth a card: ones with money seen in them or a known balance, ONE card per name (two saved places
  /// both called "PhonePe" with nothing in them are not shown twice -- owner 2026-11-17).
  List<String> _accountKeys(Map<String, (int, DateTime)> balances) {
    final used = <String>{for (final i in _items()) if (i.account.isNotEmpty) i.account, ...balances.keys};
    final names = <String>{};
    final out = <String>[];
    for (final k in used) {
      final name = _accountName(k, true).trim().toLowerCase();
      if (names.add(name)) out.add(k);
    }
    return out;
  }

  Widget _ownerChip(String id, String label, bool te) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          key: ValueKey('askodoxMoneyOwner-$id'),
          label: Text(label),
          selected: _owner == id,
          onSelected: (_) async {
            setState(() {
              _owner = id;
              _account = null;
              _how = '';
              _loading = id != 'me';
            });
            if (id != 'me') {
              await _loadShop(id);
              if (mounted) setState(() => _loading = false);
            }
          },
        ),
      );

  Widget _accountCard(String? key, String name, (int, DateTime)? bal, bool te) {
    final sel = _account == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: sel ? Colors.white : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('askodoxMoneyAccount-${key ?? 'all'}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _account = key),
          child: Container(
            constraints: const BoxConstraints(minWidth: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: sel ? const Color(0xFF1B2333) : Colors.white)),
              if (bal != null)
                Text('${_rs(bal.$1)} · ${_when(bal.$2, te)}',
                    style: TextStyle(fontSize: 12, color: sel ? const Color(0xFF5B6475) : Colors.white70)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _totalsBox(bool te, AskodoxMoneyTotals t) => Container(
        key: const Key('askodoxMoneyTotals'),
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(
            child: Column(children: [
              Text(te ? 'వచ్చింది' : 'Came in', style: const TextStyle(color: Color(0xFF5B6475), fontSize: 13)),
              Text(_rs(t.inPaise), style: const TextStyle(color: _green, fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
          ),
          Container(width: 1, height: 40, color: const Color(0xFFE5E7EB)),
          Expanded(
            child: Column(children: [
              Text(te ? 'ఖర్చు' : 'Went out', style: const TextStyle(color: Color(0xFF5B6475), fontSize: 13)),
              Text(_rs(t.outPaise), style: const TextStyle(color: _red, fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      );

  Widget _duesCard(bool te, AskodoxMyPhoneAlerts m) {
    final now = DateTime.now();
    final week = <(AskodoxDue, DateTime)>[];
    for (final d in m.dues) {
      final next = askodoxNextDue(d, now);
      if (next != null && next.difference(DateTime(now.year, now.month, now.day)).inDays <= 7) week.add((d, next));
    }
    week.sort((a, b) => a.$2.compareTo(b.$2));
    final suggestions = askodoxDueSuggestions(_data.phoneEvents, m.dues, m.dismissed, now).length +
        askodoxEmiSuggestions(_items(), m.dues, m.dismissed).length;
    final sum = week.fold<int>(0, (a, b) => a + b.$1.amountPaise);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        key: const Key('askodoxMoneyDues'),
        leading: const Icon(Icons.event_note_outlined, color: _accent),
        title: Text(
            week.isEmpty
                ? (te ? 'రాబోయే చెల్లింపులు (EMI, కరెంట్ బిల్, అద్దె…)' : 'Upcoming payments (EMI, current bill, rent…)')
                : (te ? 'ఈ వారం కట్టాల్సింది ${_rs(sum)}' : 'Due this week ${_rs(sum)}'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          for (final w in week.take(2)) '${w.$1.name} ${_rs(w.$1.amountPaise)} · ${w.$2.day}/${w.$2.month}',
          if (suggestions > 0) te ? '$suggestions కొత్తవి కనిపించాయి' : '$suggestions new found',
          if (week.isEmpty && suggestions == 0) te ? 'జోడించండి — గడువుకు ముందు వాయిస్‌తో చెప్తుంది' : 'Add them — said aloud before the date',
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AskodoxDuesScreen(phoneEvents: _data.phoneEvents, items: _items())));
          await _load(quiet: true);
        },
      ),
    );
  }

  Widget _pendingCard(bool te, List<AskodoxMoneyItem> pending, bool personal) {
    final sum = pending.fold<int>(0, (a, b) => a + b.amountPaise);
    return Container(
      key: const Key('askodoxMoneyPending'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                personal
                    ? (te ? 'కట్టాల్సిన బిల్లులు ${pending.length} · ${_rs(sum)}' : 'Bills to pay ${pending.length} · ${_rs(sum)}')
                    : (te ? 'కస్టమర్ల బాకీ ${pending.length} · ${_rs(sum)}' : 'Customers owe ${pending.length} · ${_rs(sum)}'),
                style: const TextStyle(fontWeight: FontWeight.w800, color: _amber)),
            Text(pending.take(2).map((p) => '${p.title} ${p.sub}').join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _amber)),
          ]),
        ),
        TextButton(
          onPressed: () => setState(() => _kind = 'pending'),
          child: Text(te ? 'చూడు' : 'Show'),
        ),
      ]),
    );
  }

  Widget _pairCard(bool te, AskodoxPairSuggestion s) => Container(
        key: ValueKey('askodoxMoneyPair-${s.payment.id}'),
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'ఈ బిల్‌కి కట్టారా?' : 'Was this for that bill?', style: const TextStyle(fontWeight: FontWeight.w800, color: _amber)),
          Text(
              te
                  ? '${_rs(s.payment.amountPaise)} ${s.payment.direction == 'out' ? 'పోయింది' : 'వచ్చింది'} (${s.payment.title}, ${_when(s.payment.at, te)}) — బిల్ ${s.bill.sub} · ${s.bill.title}'
                  : '${_rs(s.payment.amountPaise)} ${s.payment.direction == 'out' ? 'paid' : 'came'} (${s.payment.title}, ${_when(s.payment.at, te)}) — bill ${s.bill.sub} · ${s.bill.title}',
              style: const TextStyle(fontSize: 13, color: _amber)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton(
                key: ValueKey('askodoxMoneyPairYes-${s.payment.id}'),
                style: FilledButton.styleFrom(backgroundColor: _amber),
                onPressed: () => _join(s, te),
                child: Text(te ? 'అవును, జత చేయి' : 'Yes, join'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: ValueKey('askodoxMoneyPairNo-${s.payment.id}'),
                onPressed: () => _dismiss('${s.payment.id}|${s.bill.id}'),
                child: Text(te ? 'కాదు' : 'No'),
              ),
            ),
          ]),
        ]),
      );

  Widget _duePairCard(bool te, AskodoxMoneyItem p, AskodoxDue d, DateTime date) => Container(
        key: ValueKey('askodoxMoneyDuePair-${p.id}'),
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFE8EEFB), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(
            child: Text(
                te
                    ? '${d.name} (${date.day}/${date.month}) ${_rs(p.amountPaise)} కట్టారా? — ${p.title}, ${_when(p.at, te)}'
                    : 'Did you pay ${d.name} (${date.day}/${date.month}) ${_rs(p.amountPaise)}? — ${p.title}, ${_when(p.at, te)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          TextButton(onPressed: () => _duePaid(p, d, date), child: Text(te ? 'అవును' : 'Yes')),
          TextButton(onPressed: () => _dismiss('due|${p.id}'), child: Text(te ? 'కాదు' : 'No')),
        ]),
      );

  Widget _filters(bool te, List<String> hows) {
    Widget chip(String key, String label, bool sel, VoidCallback tap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(key: ValueKey('askodoxMoneyFilter-$key'), label: Text(label), selected: sel, onSelected: (_) => tap()),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final p in const ['today', 'week', 'month', 'all'])
              chip('period-$p', switch (p) {
                'today' => te ? 'ఈ రోజు' : 'Today',
                'week' => te ? 'ఈ వారం' : 'This week',
                'month' => te ? 'ఈ నెల' : 'This month',
                _ => te ? 'అన్నీ' : 'All time',
              }, _period == p, () => setState(() => _period = p)),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final k in const ['all', 'in', 'out', 'bills', 'pending'])
              chip('kind-$k', switch (k) {
                'in' => te ? 'వచ్చినవి' : 'In',
                'out' => te ? 'ఖర్చులు' : 'Out',
                'bills' => te ? 'బిల్లులు' : 'Bills',
                'pending' => te ? 'బాకీ' : 'Pending',
                _ => te ? 'అన్నీ' : 'All',
              }, _kind == k, () => setState(() => _kind = k)),
          ]),
        ),
        if (hows.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip('how-all', te ? 'ఏ విధంగానైనా' : 'Any way', _how.isEmpty, () => setState(() => _how = '')),
              for (final h in hows)
                chip('how-$h', te ? askodoxHowLabel(h).$2 : askodoxHowLabel(h).$1, _how == h, () => setState(() => _how = h)),
            ]),
          ),
      ]),
    );
  }

  Widget _row(bool te, AskodoxMoneyItem i, List<AskodoxMoneyItem> all) {
    final cat = i.direction == 'out' && _owner == 'me' ? _cat(i) : '';
    final linked = i.linkedTo.isEmpty ? null : all.where((x) => x.id == i.linkedTo).firstOrNull;
    final linkText = linked != null
        ? (te ? 'బిల్ ${linked.sub} · ${linked.title}' : 'Bill ${linked.sub} · ${linked.title}')
        : i.linkedTo.startsWith('due:')
            ? (te ? 'రాబోయే చెల్లింపు కట్టారు' : 'Upcoming payment paid')
            : '';
    return InkWell(
      key: ValueKey('askodoxMoneyRow-${i.id}'),
      onTap: () => _open(i, all, te),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Badge(how: i.how, kind: i.kind),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${i.title.isEmpty ? (te ? 'పేమెంట్' : 'Payment') : i.title}${_unconfirmed(i) ? ' ⏳' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                  [
                    if (i.kind == 'bill') i.sub,
                    if (i.how.isNotEmpty) te ? askodoxHowLabel(i.how).$2 : askodoxHowLabel(i.how).$1,
                    if (i.account.isNotEmpty) _accountName(i.account, te),
                    _when(i.at, te),
                  ].where((x) => x.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
              if (i.kind == 'bill' && i.pending)
                Text(te ? 'ఇంకా కట్టలేదు' : 'Not paid yet', style: const TextStyle(fontSize: 11.5, color: _amber, fontWeight: FontWeight.w600)),
              if (linkText.isNotEmpty || cat.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: _Pill(
                      [if (linkText.isNotEmpty) linkText, if (cat.isNotEmpty) te ? askodoxCategoryLabel(cat).$2 : askodoxCategoryLabel(cat).$1]
                          .join(' · '),
                      _amber),
                ),
            ]),
          ),
          Text('${i.direction == 'out' ? '− ' : '+ '}${_rs(i.amountPaise)}',
              style: TextStyle(fontWeight: FontWeight.w800, color: i.kind == 'bill' && i.pending ? _amber : (i.direction == 'out' ? _red : _green))),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
      );
}

/// A round letter badge for how the money moved (never another company's logo).
class _Badge extends StatelessWidget {
  const _Badge({required this.how, required this.kind, this.size = 40});
  final String how;
  final String kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (text, bg, fg) = kind == 'bill'
        ? ('₹', const Color(0xFFFFF4E5), _amber)
        : switch (how) {
            'phonepe' => ('Pe', const Color(0xFFEFE7FB), const Color(0xFF5B2A9E)),
            'gpay' => ('GP', const Color(0xFFE6F4EA), _green),
            'paytm' => ('Pt', const Color(0xFFE6F4F8), const Color(0xFF0E6A84)),
            'razorpay' => ('Rz', const Color(0xFFE8EEFB), _accent),
            'sms' || 'bank' => ('Bk', const Color(0xFFF1F2F4), const Color(0xFF374151)),
            'cash' => ('₹', const Color(0xFFE6F4EA), _green),
            'wallet' => ('W', const Color(0xFFFFF4E5), _amber),
            'qr' => ('QR', const Color(0xFFE8EEFB), _accent),
            _ => ('UPI', const Color(0xFFF1F2F4), const Color(0xFF374151)),
          };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: size * 0.3)),
    );
  }
}

// ======================================================================== where the money went (a month)

class AskodoxMoneyMonthScreen extends StatefulWidget {
  const AskodoxMoneyMonthScreen({super.key, required this.items, required this.mine, required this.personal});
  final List<AskodoxMoneyItem> items;
  final AskodoxMyPhoneAlerts? mine;
  final bool personal;

  @override
  State<AskodoxMoneyMonthScreen> createState() => _AskodoxMoneyMonthScreenState();
}

class _AskodoxMoneyMonthScreenState extends State<AskodoxMoneyMonthScreen> {
  int _back = 0; // 0 = this month

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - _back);
    final to = DateTime(now.year, now.month - _back + 1);
    AskodoxMoneyTotals tot(DateTime a, DateTime b) => askodoxTotals(widget.items, a, b,
        rowCategory: widget.mine?.rowCategory ?? const {}, payeeCategory: widget.mine?.payeeCategory ?? const {});
    final t = tot(from, to);
    final prev = tot(DateTime(from.year, from.month - 1), from);
    final cats = t.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final hows = t.inByHow.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    const months = ['జనవరి', 'ఫిబ్రవరి', 'మార్చి', 'ఏప్రిల్', 'మే', 'జూన్', 'జూలై', 'ఆగస్టు', 'సెప్టెంబర్', 'అక్టోబర్', 'నవంబర్', 'డిసెంబర్'];
    const monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    Widget bar(String label, int value, int max, Color c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(_rs(value), style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(value: max == 0 ? 0 : value / max, minHeight: 10, color: c, backgroundColor: const Color(0xFFE5E7EB)),
            ),
          ]),
        );
    final diff = t.outPaise - prev.outPaise;
    return Scaffold(
      key: const Key('askodoxMoneyMonthScreen'),
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: Text(te ? 'ఎక్కడ ఖర్చు / ఎక్కడ నుంచి వచ్చింది' : 'Where it went / came from')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, children: [
          for (var b = 0; b < 3; b++)
            ChoiceChip(
              label: Text(te ? months[DateTime(now.year, now.month - b).month - 1] : monthsEn[DateTime(now.year, now.month - b).month - 1]),
              selected: _back == b,
              onSelected: (_) => setState(() => _back = b),
            ),
        ]),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(children: [
                Expanded(child: Column(children: [Text(te ? 'వచ్చింది' : 'In'), Text(_rs(t.inPaise), style: const TextStyle(color: _green, fontSize: 22, fontWeight: FontWeight.w800))])),
                Expanded(child: Column(children: [Text(te ? 'ఖర్చు' : 'Out'), Text(_rs(t.outPaise), style: const TextStyle(color: _red, fontSize: 22, fontWeight: FontWeight.w800))])),
              ]),
              const SizedBox(height: 6),
              Text(
                  '${te ? 'మిగిలింది' : 'Left'} ${_rs(t.inPaise - t.outPaise)}'
                  '${prev.outPaise > 0 ? (te ? ' · గత నెల కంటే ఖర్చు ${_rs(diff.abs())} ${diff > 0 ? 'ఎక్కువ' : 'తక్కువ'}' : ' · spent ${_rs(diff.abs())} ${diff > 0 ? 'more' : 'less'} than last month') : ''}',
                  textAlign: TextAlign.center),
            ]),
          ),
        ),
        if (widget.personal && cats.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(te ? 'ఎక్కడ ఖర్చు' : 'Where it went', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                for (final c in cats)
                  bar(c.key.isEmpty ? (te ? 'వర్గం లేనివి (వరుస నొక్కి పెట్టండి)' : 'Not set (tap a row to set)') : (te ? askodoxCategoryLabel(c.key).$2 : askodoxCategoryLabel(c.key).$1),
                      c.value, cats.first.value, c.key.isEmpty ? const Color(0xFF9CA3AF) : const Color(0xFFB45309)),
              ]),
            ),
          ),
        if (hows.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(te ? 'ఎలా వచ్చింది' : 'How it came in', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                for (final h in hows) bar(te ? askodoxHowLabel(h.key).$2 : askodoxHowLabel(h.key).$1, h.value, hows.first.value, _green),
              ]),
            ),
          ),
        if (cats.isEmpty && hows.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text(te ? 'ఈ నెల ఇంకా ఏమీ లేదు.' : 'Nothing this month yet.', textAlign: TextAlign.center)),
      ]),
    );
  }
}

// ======================================================================== upcoming payments

class AskodoxDuesScreen extends ConsumerStatefulWidget {
  const AskodoxDuesScreen({super.key, this.phoneEvents = const [], this.items = const []});
  final List<AskodoxJson> phoneEvents;
  final List<AskodoxMoneyItem> items;

  @override
  ConsumerState<AskodoxDuesScreen> createState() => _AskodoxDuesScreenState();
}

class _AskodoxDuesScreenState extends ConsumerState<AskodoxDuesScreen> {
  AskodoxMyPhoneAlerts? _mine;

  @override
  void initState() {
    super.initState();
    unawaited(AskodoxMyPhoneAlerts.load().then((m) {
      if (mounted) setState(() => _mine = m);
    }));
  }

  Future<void> _save(void Function(AskodoxMyPhoneAlerts m) edit) async {
    final m = _mine;
    if (m == null) return;
    edit(m);
    await m.save();
    try {
      final bridge = ref.read(askodoxPaymentAlertsBridgeProvider);
      await bridge.configurePersonal(_nativeOf(ref, m));
      unawaited(bridge.checkDues());
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _edit({AskodoxDue? due, String name = '', int amount = 0, DateTime? date, String repeat = 'monthly', String category = '', String dismiss = ''}) async {
    final out = await showModalBottomSheet<AskodoxDue>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DueSheet(due: due, name: name, amount: amount, date: date, repeat: repeat, category: category),
    );
    if (out == null) return;
    await _save((m) {
      m.dues = [for (final d in m.dues) if (d.id != out.id) d, out];
      if (dismiss.isNotEmpty) m.dismissed = {...m.dismissed, dismiss};
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final m = _mine;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rows = <(AskodoxDue, DateTime?)>[for (final d in m?.dues ?? const <AskodoxDue>[]) (d, askodoxNextDue(d, now))]
      ..sort((a, b) => (a.$2 ?? DateTime(2100)).compareTo(b.$2 ?? DateTime(2100)));
    final week = rows.where((r) => r.$2 != null && r.$2!.difference(today).inDays <= 7).fold<int>(0, (a, r) => a + r.$1.amountPaise);
    final month = rows.where((r) => r.$2 != null && r.$2!.month == now.month && r.$2!.year == now.year).fold<int>(0, (a, r) => a + r.$1.amountPaise);
    final found = m == null ? const <AskodoxJson>[] : askodoxDueSuggestions(widget.phoneEvents, m.dues, m.dismissed, now);
    final emis = m == null ? const <AskodoxMoneyItem>[] : askodoxEmiSuggestions(widget.items, m.dues, m.dismissed);
    return Scaffold(
      key: const Key('askodoxDuesScreen'),
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: Text(te ? 'రాబోయే చెల్లింపులు' : 'Upcoming payments')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('askodoxDueAdd'),
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(te ? 'EMI / బిల్ / అద్దె జోడించు' : 'Add EMI / bill / rent'),
      ),
      body: m == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
              Row(children: [
                Expanded(child: _box(te ? 'ఈ వారం' : 'This week', _rs(week), _amber)),
                const SizedBox(width: 8),
                Expanded(child: _box(te ? 'ఈ నెల మొత్తం' : 'This month', _rs(month), const Color(0xFF1B2333))),
              ]),
              for (final e in found)
                _suggest(
                  key: 'askodoxDueFound-${e['local_id']}',
                  text: te
                      ? 'కొత్తది కనిపించింది: ${e['party']} ${_rs(askodoxPosInt(e['amount_paise']))} · ${e['due_date']}'
                      : 'Found: ${e['party']} ${_rs(askodoxPosInt(e['amount_paise']))} · due ${e['due_date']}',
                  sub: '${e['source_label'] ?? ''}',
                  add: () => _edit(
                      name: '${e['party'] ?? ''}',
                      amount: askodoxPosInt(e['amount_paise']),
                      date: DateTime.tryParse('${e['due_date']}'),
                      category: askodoxCategoryOf(AskodoxMoneyItem(
                          id: '', kind: 'due', direction: 'out', amountPaise: 0, at: now, title: '${e['party'] ?? ''}')),
                      dismiss: '${e['local_id']}'),
                  no: () => _save((x) => x.dismissed = {...x.dismissed, '${e['local_id']}'}),
                  te: te,
                ),
              for (final e in emis)
                _suggest(
                  key: 'askodoxDueEmi-${e.id}',
                  text: te ? 'EMI లా ఉంది: ${e.title} ${_rs(e.amountPaise)} · ${e.at.day}/${e.at.month}' : 'Looks like an EMI: ${e.title} ${_rs(e.amountPaise)} · ${e.at.day}/${e.at.month}',
                  sub: te ? 'ప్రతి నెల అదే రోజు అని జోడించాలా?' : 'Add as monthly on the same day?',
                  add: () => _edit(
                      name: e.title.isEmpty ? 'EMI' : '${e.title} EMI',
                      amount: e.amountPaise,
                      date: DateTime(e.at.year, e.at.month + 1, e.at.day),
                      category: 'emi',
                      dismiss: e.id),
                  no: () => _save((x) => x.dismissed = {...x.dismissed, e.id}),
                  te: te,
                ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                      te
                          ? 'EMI, కరెంట్ బిల్, అద్దె, రీఛార్జ్, LIC… జోడించండి. గడువుకు 2 రోజుల ముందు, ఆ రోజు వాయిస్‌తో చెప్తుంది.'
                          : 'Add EMI, current bill, rent, recharge, insurance… It is said aloud 2 days before and on the day.',
                      textAlign: TextAlign.center),
                ),
              for (final r in rows) _dueRow(te, r.$1, r.$2, today),
            ]),
    );
  }

  Widget _box(String label, String value, Color c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(label, style: const TextStyle(color: Color(0xFF5B6475), fontSize: 12.5)),
          Text(value, style: TextStyle(color: c, fontSize: 21, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _suggest({required String key, required String text, required String sub, required VoidCallback add, required VoidCallback no, required bool te}) =>
      Container(
        key: ValueKey(key),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFE8EEFB), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
            ]),
          ),
          TextButton(onPressed: add, child: Text(te ? 'జోడించు' : 'Add')),
          IconButton(tooltip: te ? 'వద్దు' : 'No', onPressed: no, icon: const Icon(Icons.close)),
        ]),
      );

  Widget _dueRow(bool te, AskodoxDue d, DateTime? next, DateTime today) {
    final left = next?.difference(today).inDays;
    final whenText = next == null
        ? (te ? 'అన్నీ కట్టారు ✓' : 'All paid ✓')
        : left! < 0
            ? (te ? '${next.day}/${next.month} · ${-left} రోజులు దాటింది' : '${next.day}/${next.month} · ${-left} days late')
            : left == 0
                ? (te ? 'ఈ రోజు' : 'Today')
                : (te ? '${next.day}/${next.month} · $left రోజుల్లో' : '${next.day}/${next.month} · in $left days');
    final color = next == null ? _green : (left! <= 2 ? _amber : const Color(0xFF374151));
    final repeat = switch (d.repeat) {
      'once' => te ? 'ఒక్కసారి' : 'once',
      'quarterly' => te ? 'ప్రతి 3 నెలలకు' : 'every 3 months',
      'yearly' => te ? 'ప్రతి సంవత్సరం' : 'yearly',
      'monthly' => te ? 'ప్రతి నెల' : 'monthly',
      _ => te ? 'ప్రతి ${d.repeat.substring(5)} రోజులకు' : 'every ${d.repeat.substring(5)} days',
    };
    return Container(
      key: ValueKey('askodoxDue-${d.id}'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text([repeat, if (d.category.isNotEmpty) te ? askodoxCategoryLabel(d.category).$2 : askodoxCategoryLabel(d.category).$1].join(' · '),
                style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
            Text(whenText, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_rs(d.amountPaise), style: const TextStyle(fontWeight: FontWeight.w800)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (next != null)
              TextButton(
                key: ValueKey('askodoxDuePaid-${d.id}'),
                onPressed: () => _save((m) => m.dues = [
                      for (final x in m.dues) x.id == d.id ? x.copyWith(paidDates: [...x.paidDates, askodoxDay(next)]) : x,
                    ]),
                child: Text(te ? 'కట్టాను' : 'Paid'),
              ),
            PopupMenuButton<String>(
              key: ValueKey('askodoxDueMenu-${d.id}'),
              onSelected: (v) async {
                if (v == 'edit') {
                  await _edit(due: d);
                } else {
                  await _save((m) => m.dues = [for (final x in m.dues) if (x.id != d.id) x]);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(te ? 'మార్చు' : 'Edit')),
                PopupMenuItem(value: 'delete', child: Text(te ? 'తొలగించు' : 'Delete')),
              ],
            ),
          ]),
        ]),
      ]),
    );
  }
}

class _DueSheet extends StatefulWidget {
  const _DueSheet({this.due, this.name = '', this.amount = 0, this.date, this.repeat = 'monthly', this.category = ''});
  final AskodoxDue? due;
  final String name;
  final int amount;
  final DateTime? date;
  final String repeat;
  final String category;

  @override
  State<_DueSheet> createState() => _DueSheetState();
}

class _DueSheetState extends State<_DueSheet> {
  late final _name = TextEditingController(text: widget.due?.name ?? widget.name);
  late final _amount = TextEditingController(
      text: (widget.due?.amountPaise ?? widget.amount) > 0 ? '${(widget.due?.amountPaise ?? widget.amount) / 100}'.replaceAll(RegExp(r'\.0$'), '') : '');
  late final _days = TextEditingController(text: (widget.due?.repeat ?? widget.repeat).startsWith('days:') ? (widget.due?.repeat ?? widget.repeat).substring(5) : '84');
  late DateTime _date = widget.due?.date ?? widget.date ?? DateTime.now().add(const Duration(days: 7));
  late String _repeat = () {
    final r = widget.due?.repeat ?? widget.repeat;
    return r.startsWith('days:') ? 'days' : r;
  }();
  late String _category = widget.due?.category ?? widget.category;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _days.dispose();
    super.dispose();
  }

  void _save() {
    final te = askodoxPosTe(context);
    final rupees = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (_name.text.trim().isEmpty || rupees == null || rupees <= 0) {
      setState(() => _error = te ? 'పేరు, మొత్తం ఇవ్వండి.' : 'Give a name and the amount.');
      return;
    }
    final days = int.tryParse(_days.text.trim()) ?? 0;
    if (_repeat == 'days' && days < 1) {
      setState(() => _error = te ? 'ఎన్ని రోజులకోసారి?' : 'Every how many days?');
      return;
    }
    Navigator.pop(
        context,
        AskodoxDue(
          id: widget.due?.id ?? 'd${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
          name: _name.text.trim(),
          amountPaise: (rupees * 100).round(),
          date: _date,
          repeat: _repeat == 'days' ? 'days:$days' : _repeat,
          category: _category,
          paidDates: widget.due?.paidDates ?? const [],
          match: widget.due?.match ?? '',
        ));
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.due == null ? (te ? 'చెల్లింపు జోడించు' : 'Add a payment') : (te ? 'మార్చు' : 'Edit'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
              key: const Key('askodoxDueName'),
              controller: _name,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'పేరు (ఉదా. బైక్ EMI, కరెంట్ బిల్)' : 'Name (e.g. bike EMI, current bill)')),
          const SizedBox(height: 10),
          TextField(
              key: const Key('askodoxDueAmount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'మొత్తం ₹' : 'Amount ₹')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('askodoxDueDate'),
            onPressed: () async {
              final d = await showDatePicker(
                  context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(DateTime.now().year + 5));
              if (d != null) setState(() => _date = d);
            },
            icon: const Icon(Icons.event),
            label: Text('${te ? 'గడువు తేదీ' : 'Due date'}: ${_date.day}/${_date.month}/${_date.year}'),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in const ['monthly', 'quarterly', 'yearly', 'days', 'once'])
              ChoiceChip(
                key: ValueKey('askodoxDueRepeat-$r'),
                label: Text(switch (r) {
                  'monthly' => te ? 'ప్రతి నెల' : 'Monthly',
                  'quarterly' => te ? '3 నెలలకు' : 'Every 3 months',
                  'yearly' => te ? 'సంవత్సరానికి' : 'Yearly',
                  'days' => te ? 'కొన్ని రోజులకు' : 'Every N days',
                  _ => te ? 'ఒక్కసారి' : 'Once',
                }),
                selected: _repeat == r,
                onSelected: (_) => setState(() => _repeat = r),
              ),
          ]),
          if (_repeat == 'days')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                  controller: _days,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'ఎన్ని రోజులకోసారి (రీఛార్జ్ 28 / 84)' : 'Every how many days (recharge 28 / 84)')),
            ),
          const SizedBox(height: 10),
          Text(te ? 'వర్గం' : 'Category', style: const TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in askodoxMoneyCategories.where((c) => const ['emi', 'power', 'rent', 'phone', 'insurance', 'education', 'medical', 'other'].contains(c.$1)))
              ChoiceChip(label: Text(te ? c.$3 : c.$2), selected: _category == c.$1, onSelected: (_) => setState(() => _category = c.$1)),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: _red))),
          const SizedBox(height: 12),
          FilledButton(key: const Key('askodoxDueSave'), onPressed: _save, child: Text(te ? 'సేవ్' : 'Save')),
        ]),
      ),
    );
  }
}
