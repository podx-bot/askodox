import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import '../domain/step_logic.dart';
import 'step_kit.dart';

/// `/biz/:id/money/dues` (owner 2026-11-22, "3 steps"): ① who paid? (the total owed on top, contacts-style list)
/// ② how much? (dialer keypad, "all" suggested, cash | online) ③ ✓ with a WhatsApp receipt. One payment is spread
/// over the person's bills oldest first. The old page stays at `?full=1`; reminders live on `/pos/:id/dues`.
class AskodoxDuesStepsScreen extends ConsumerStatefulWidget {
  const AskodoxDuesStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxDuesStepsScreen> createState() => _AskodoxDuesStepsScreenState();
}

class _AskodoxDuesStepsScreenState extends ConsumerState<AskodoxDuesStepsScreen> {
  int _step = 1;
  AskodoxJson? _data;
  Object? _error;
  final _search = TextEditingController();
  String _q = '';
  AskodoxJson? _person;
  String _typed = '';
  /// The amount on the pad is our suggestion (the whole due): the first digit typed REPLACES it, never joins it
  /// (₹360 shown + "100" typed used to read ₹3,60,100).
  bool _suggested = false;
  String _pay = 'cash';
  bool _busy = false;
  String _txn = askodoxNewTxnId();
  int _received = 0;
  int _left = 0;
  String _shopName = '';

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(ref.read(askodoxPosRepositoryProvider).shopState(widget.businessId).then((shop) {
      if (mounted) setState(() => _shopName = '${shop['name'] ?? ''}');
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).dues(widget.businessId);
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

  String _nameOf(AskodoxJson p) => '${p['name']}'.trim().isEmpty ? (_te ? 'పేరు లేదు' : 'No name') : '${p['name']}';

  List<AskodoxJson> get _people {
    final q = _q.trim().toLowerCase();
    final all = askodoxPosList(_data?['people']);
    if (q.isEmpty) return all;
    return all.where((p) => '${p['name']}'.toLowerCase().contains(q) || '${p['last4']}'.contains(q)).toList();
  }

  void _open(AskodoxJson p) {
    setState(() {
      _person = p;
      _typed = '${askodoxPosInt(p['due_paise']) ~/ 100}';
      _suggested = true;
      _pay = 'cash';
      _txn = askodoxNewTxnId();
      _step = 2;
    });
  }

  /// The money in: spread over the bills oldest first (each settle is idempotent on its own txn id).
  Future<void> _collect() async {
    final te = _te;
    final person = _person;
    if (person == null || _busy) return;
    final due = askodoxPosInt(person['due_paise']);
    final amount = askodoxKeypadPaise(_typed);
    if (amount <= 0) {
      askodoxPosSnack(context, te ? 'ఎంత ఇచ్చారో రాయండి.' : 'Type how much they paid.');
      return;
    }
    if (amount > due) {
      askodoxPosSnack(context, te ? 'బాకీ ${askodoxStepRupees(due)} కంటే ఎక్కువ రాయలేం.' : 'Cannot be more than the due ${askodoxStepRupees(due)}.');
      return;
    }
    final bills = askodoxPosList(person['bills'])
      ..sort((a, b) => '${a['local_date']} ${a['number']}'.compareTo('${b['local_date']} ${b['number']}'));
    final parts = askodoxSplitDuePayment([for (final b in bills) ('${b['id']}', askodoxPosInt(b['due_paise']))], amount);
    setState(() => _busy = true);
    var done = 0;
    try {
      final repo = ref.read(askodoxPosRepositoryProvider);
      for (var i = 0; i < parts.length; i++) {
        final (id, paise) = parts[i];
        await repo.billSettle(widget.businessId, id, _pay, '$_txn-$i', amountPaise: paise);
        done += paise;
      }
      if (!mounted) return;
      setState(() {
        _received = done;
        _left = due - done;
        _step = 3;
      });
      unawaited(_load());
    } on AskodoxPosException catch (e) {
      if (!mounted) return;
      askodoxPosSnack(
          context,
          done > 0
              ? (te ? '${askodoxStepRupees(done)} రాశాం, మిగతాది రాలేదు: ${e.message(te)}' : 'Saved ${askodoxStepRupees(done)}; the rest failed: ${e.message(te)}')
              : e.message(te));
      unawaited(_load());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receipt() async {
    final te = _te;
    final person = _person;
    if (person == null) return;
    final shop = _shopName.isEmpty ? 'ASKODOX' : _shopName;
    final text = te
        ? '$shop: ${_nameOf(person)} గారు, ${askodoxStepRupees(_received)} అందింది. మిగిలిన బాకీ ${askodoxStepRupees(_left)}. ధన్యవాదాలు 🙏'
        : '$shop: ${_nameOf(person)}, we received ${askodoxStepRupees(_received)}. Balance due ${askodoxStepRupees(_left)}. Thank you 🙏';
    final opened = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) askodoxPosSnack(context, te ? 'WhatsApp తెరుచుకోలేదు — మెసేజ్ కాపీ చేశాను.' : 'WhatsApp did not open — message copied.');
    }
  }

  void _heardName(String words) {
    final w = words.trim().replaceAll(RegExp(r'[.,!?]'), '');
    if (w.isEmpty) return;
    final all = askodoxPosList(_data?['people']);
    final hit = all.where((p) {
      final n = '${p['name']}'.toLowerCase();
      return n.isNotEmpty && w.toLowerCase().split(RegExp(r'\s+')).any((part) => part.length > 1 && n.contains(part));
    }).toList();
    if (hit.length == 1) {
      _open(hit.single);
      final paise = askodoxSpokenRupees(w);
      if (paise != null && paise > 0 && paise <= askodoxPosInt(hit.single['due_paise'])) setState(() => _typed = '${paise ~/ 100}');
      return;
    }
    setState(() {
      _search.text = w;
      _q = w;
    });
  }

  void _heardAmount(String words) {
    final paise = askodoxSpokenRupees(words);
    if (paise == null) {
      askodoxPosSnack(context, _te ? 'మొత్తం అర్థం కాలేదు: "$words"' : 'No amount in "$words"');
      return;
    }
    final w = words.toLowerCase();
    setState(() {
      _typed = '${paise ~/ 100}';
      if (w.contains('online') || w.contains('ఆన్‌లైన్') || w.contains('upi') || w.contains('phonepe') || w.contains('ఫోన్ పే')) {
        _pay = 'online';
      }
    });
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    final id = widget.businessId;
    return [
      AskodoxStepMore('askodoxDuesStepsRemind', te ? 'గుర్తులు పంపు (WhatsApp)' : 'Send reminders (WhatsApp)', Icons.notifications_active_rounded,
          () => context.push('/pos/$id/dues')),
      AskodoxStepMore('askodoxDuesStepsFull', te ? 'పాత బాకీల పేజీ (బిల్లు వారీగా)' : 'Old dues page (bill by bill)', Icons.menu_book_rounded,
          () => context.push('/biz/$id/money/dues?full=1')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'బాకీలు' : 'Dues';
    final person = _person;
    return switch (_step) {
      2 when person != null => AskodoxStepScaffold(
          key: const Key('askodoxDuesSteps2'),
          title: title,
          sub: _shopName,
          step: 2,
          question: te ? 'ఎంత ఇచ్చారు?' : 'How much did they pay?',
          onBack: () => setState(() => _step = 1),
          more: _more(),
          body: _amountStep(te, person),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxDuesStepsGot'),
            label: te ? 'వచ్చింది' : 'Received',
            icon: Icons.check_rounded,
            busy: _busy,
            onPressed: askodoxKeypadPaise(_typed) > 0 ? _collect : null,
            onSpoken: _heardAmount,
          ),
        ),
      3 when person != null => AskodoxStepScaffold(
          key: const Key('askodoxDuesSteps3'),
          title: title,
          sub: _shopName,
          step: 3,
          more: _more(),
          body: _doneStep(te, person),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxDuesStepsNext'),
            label: te ? 'ఇంకొకరు' : 'Someone else',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => setState(() {
              _person = null;
              _typed = '';
              _step = 1;
            }),
          ),
        ),
      _ => AskodoxStepScaffold(
          key: const Key('askodoxDuesSteps1'),
          title: title,
          sub: _shopName,
          step: 1,
          question: te ? 'ఎవరు కట్టారు?' : 'Who paid?',
          more: _more(),
          body: _peopleStep(te),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxDuesStepsRemindAll'),
            label: te ? 'గుర్తులు పంపు' : 'Send reminders',
            icon: Icons.send_rounded,
            outline: true,
            onPressed: () => context.push('/pos/${widget.businessId}/dues'),
            onSpoken: _heardName,
          ),
        ),
    };
  }

  Widget _peopleStep(bool te) {
    if (_error != null && _data == null) return AskodoxPosError(error: _error!, onRetry: _load);
    if (_data == null) return const Center(child: CircularProgressIndicator());
    final all = askodoxPosList(_data?['people']);
    final people = _people;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        AskodoxStepBigNumber(askodoxStepRupees(askodoxPosInt(_data?['total_paise'])),
            label: te ? '${all.length} మంది బాకీ' : (all.length == 1 ? '1 person owes' : '${all.length} people owe'), color: askodoxStepWarn, size: 40),
        const SizedBox(height: 12),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(te ? 'ఎవరూ బాకీ లేరు 👍' : 'Nobody owes anything 👍',
                key: const Key('askodoxDuesStepsNone'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          )
        else ...[
          AskodoxStepSearch(
            fieldKey: const Key('askodoxDuesStepsSearch'),
            controller: _search,
            hint: te ? 'పేరు చెప్పండి / టైప్' : 'Say / type a name',
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 4),
          for (final p in people)
            AskodoxStepPersonRow(
              key: Key('askodoxDuesStepsPerson-${p['name']}-${p['last4']}'),
              name: _nameOf(p),
              sub: [
                te ? '${askodoxPosList(p['bills']).length} బిల్లులు' : '${askodoxPosList(p['bills']).length} bills',
                if ('${p['last4'] ?? ''}'.isNotEmpty) '••${p['last4']}',
                if ('${p['oldest'] ?? ''}'.length >= 10)
                  te
                      ? '${'${p['oldest']}'.substring(8, 10)}/${'${p['oldest']}'.substring(5, 7)} నుంచి'
                      : 'since ${'${p['oldest']}'.substring(8, 10)}/${'${p['oldest']}'.substring(5, 7)}',
              ].join(' · '),
              amount: askodoxStepRupees(askodoxPosInt(p['due_paise'])),
              onTap: () => _open(p),
            ),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(te ? '"$_q" పేరుతో ఎవరూ లేరు' : 'No one called "$_q"', textAlign: TextAlign.center),
            ),
        ],
      ]),
    );
  }

  Widget _amountStep(bool te, AskodoxJson person) {
    final due = askodoxPosInt(person['due_paise']);
    final rupees = due ~/ 100;
    final quick = <(String, String)>[
      (te ? 'మొత్తం ${askodoxStepRupees(due)}' : 'All ${askodoxStepRupees(due)}', '$rupees'),
      if (rupees > 1000) ('₹1,000', '1000'),
      if (rupees > 500) ('₹500', '500'),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 2, 16, 12), children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFF1F2432), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF222C4A),
            child: Text(_nameOf(person).characters.first.toUpperCase(),
                style: const TextStyle(color: askodoxStepInfo, fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nameOf(person), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: askodoxStepInk)),
              Text(te ? 'బాకీ ${askodoxStepRupees(due)}' : 'Due ${askodoxStepRupees(due)}',
                  style: const TextStyle(fontSize: 12.5, color: askodoxStepMuted)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      AskodoxStepToggle(
        options: [('cash', te ? 'క్యాష్' : 'Cash'), ('online', te ? 'ఆన్‌లైన్' : 'Online')],
        value: _pay,
        onChanged: (v) => setState(() => _pay = v),
      ),
      const SizedBox(height: 10),
      AskodoxStepAmountPad(
          value: _typed,
          quick: quick,
          onChanged: (v) => setState(() {
                if (_suggested && v.length > _typed.length && v.startsWith(_typed)) {
                  v = v.substring(_typed.length).replaceFirst(RegExp(r'^0+'), '');
                }
                _suggested = false;
                _typed = v;
              })),
    ]);
  }

  Widget _doneStep(bool te, AskodoxJson person) => ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
        const Center(child: AskodoxStepDoneMark()),
        const SizedBox(height: 26),
        AskodoxStepBigNumber(te ? '${askodoxStepRupees(_received)} వచ్చింది' : '${askodoxStepRupees(_received)} received',
            label: '${_nameOf(person)} · ${_pay == 'online' ? (te ? 'ఆన్‌లైన్' : 'online') : (te ? 'క్యాష్' : 'cash')}', size: 32),
        const SizedBox(height: 10),
        Center(
          child: AskodoxStepPill(
              _left > 0
                  ? (te ? 'ఇంకా బాకీ ${askodoxStepRupees(_left)}' : 'Still due ${askodoxStepRupees(_left)}')
                  : (te ? 'బాకీ పూర్తిగా తీరింది ✓' : 'All dues cleared ✓'),
              kind: _left > 0 ? 'warn' : 'good'),
        ),
        const SizedBox(height: 22),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          AskodoxStepRoundAction(
              key: const Key('askodoxDuesStepsReceipt'),
              icon: Icons.send_rounded,
              label: te ? 'రసీదు పంపు' : 'Send receipt',
              color: const Color(0xFF75D48B),
              onTap: _receipt),
        ]),
      ]);
}
