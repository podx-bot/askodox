import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart' show askodoxPaise, askodoxParsePaise;
import '../../pos/presentation/pos_common.dart';
import 'biz_hub.dart';

/// Bills & money inner pages (owner 2026-11-18): cashbook, dues, bill history -- the same page shape as the groups.

const _months = ['జనవరి', 'ఫిబ్రవరి', 'మార్చి', 'ఏప్రిల్', 'మే', 'జూన్', 'జూలై', 'ఆగస్టు', 'సెప్టెంబర్', 'అక్టోబర్', 'నవంబర్', 'డిసెంబర్'];
const _monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
  'November', 'December'];

String _monthLabel(DateTime m, bool te) => '${te ? _months[m.month - 1] : _monthsEn[m.month - 1]} ${m.year}';
String _ym(DateTime m) => '${m.year}-${m.month.toString().padLeft(2, '0')}';

String askodoxCashCategory(String c, bool te) {
  const inTe = {'stock': 'సరుకులు', 'salary': 'జీతాలు', 'rent': 'అద్దె', 'power': 'కరెంట్', 'gas': 'గ్యాస్',
    'transport': 'రవాణా', 'repair': 'రిపేర్', 'other': 'ఇతరాలు', 'sale': 'అమ్మకం', 'advance': 'అడ్వాన్స్',
    'catering': 'క్యాటరింగ్'};
  const en = {'stock': 'Stock', 'salary': 'Salary', 'rent': 'Rent', 'power': 'Power', 'gas': 'Gas',
    'transport': 'Transport', 'repair': 'Repair', 'other': 'Other', 'sale': 'Sales', 'advance': 'Advance',
    'catering': 'Catering'};
  return (te ? inTe[c] : en[c]) ?? c;
}

/// `/biz/:id/money/cashbook` -- money in (bills read automatically) and money out, month by month.
class AskodoxBizCashbookScreen extends ConsumerStatefulWidget {
  const AskodoxBizCashbookScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizCashbookScreen> createState() => _AskodoxBizCashbookScreenState();
}

class _AskodoxBizCashbookScreenState extends ConsumerState<AskodoxBizCashbookScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  AskodoxJson? _data;
  Object? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).cashbook(widget.businessId, month: _ym(_month));
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

  void _shift(int by) {
    setState(() {
      _month = DateTime(_month.year, _month.month + by);
      _data = null;
    });
    unawaited(_load());
  }

  Future<void> _add(String kind) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AskodoxCashEntrySheet(businessId: widget.businessId, kind: kind),
    );
    if (saved == true) await _load();
  }

  Future<void> _remove(AskodoxJson e) async {
    final te = askodoxPosTe(context);
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      await repo.cashbookRemove(widget.businessId, '${e['id']}');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(te ? 'తీసేశాం' : 'Removed'),
        action: SnackBarAction(
          label: te ? 'వెనక్కి' : 'Undo',
          onPressed: () async {
            await repo.cashbookRemove(widget.businessId, '${e['id']}', undo: true);
            await _load();
          },
        ),
      ));
    } on AskodoxPosException catch (err) {
      if (mounted) askodoxPosSnack(context, err.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final d = _data;
    final entries = askodoxPosList(d?['entries']).where((e) => switch (_filter) {
          'income' => e['kind'] == 'income',
          'expense' => e['kind'] == 'expense',
          'salary' => e['category'] == 'salary',
          'stock' => e['category'] == 'stock',
          _ => true,
        });
    return AskodoxBizScaffold(
      key: const Key('askodoxBizCashbook'),
      businessId: widget.businessId,
      tone: askodoxBizTones['money']!,
      icon: Icons.import_contacts_outlined,
      title: te ? 'క్యాష్‌బుక్' : 'Cashbook',
      trail: [te ? 'బిల్లులు & డబ్బు' : 'Bills & money', te ? 'క్యాష్‌బుక్' : 'Cashbook'],
      page: 'money',
      onRefresh: _load,
      askHint: te ? '"గ్యాస్ సిలిండర్ 1100 ఖర్చు" అని చెప్పండి' : '"Gas cylinder 1100 expense"',
      bottom: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          child: Row(children: [
            Expanded(
              child: FilledButton(
                key: const Key('askodoxCashIn'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF17784C), minimumSize: const Size.fromHeight(50)),
                onPressed: () => _add('income'),
                child: Text(te ? '+ ఆదాయం' : '+ Money in', style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const Key('askodoxCashOut'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C), minimumSize: const Size.fromHeight(50)),
                onPressed: () => _add('expense'),
                child: Text(te ? '− ఖర్చు' : '− Money out', style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ),
      ),
      children: [
        if (_error != null) AskodoxPosError(error: _error!, onRetry: _load),
        AskodoxBizStrip(cells: [
          (te ? 'ఆదాయం' : 'In', askodoxPaise(askodoxPosInt(d?['income_paise'])), const Color(0xFF17784C)),
          (te ? 'ఖర్చు' : 'Out', askodoxPaise(askodoxPosInt(d?['expense_paise'])), const Color(0xFFB91C1C)),
          (te ? 'మిగిలింది' : 'Left', askodoxPaise(askodoxPosInt(d?['balance_paise'])), const Color(0xFF1E3FA0)),
        ]),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            IconButton(key: const Key('askodoxCashPrevMonth'), onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(_monthLabel(_month, te),
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E3FA0))),
            ),
            IconButton(key: const Key('askodoxCashNextMonth'), onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (k, en, tel) in [
              ('all', 'All', 'అన్నీ'),
              ('income', 'In', 'ఆదాయం'),
              ('expense', 'Out', 'ఖర్చు'),
              ('salary', 'Salary', 'జీతాలు'),
              ('stock', 'Stock', 'సరుకులు'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                    label: Text(te ? tel : en), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        if (d == null && _error == null) const Center(child: CircularProgressIndicator()),
        if (d != null && entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(te ? 'ఈ నెల ఇంకా ఏమీ లేదు.' : 'Nothing this month yet.', textAlign: TextAlign.center),
          ),
        if (entries.isNotEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final e in entries)
                ListTile(
                  key: Key('askodoxCashEntry-${e['id']}'),
                  leading: SizedBox(
                    width: 40,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('${e['local_date']}'.length >= 10 ? '${e['local_date']}'.substring(8, 10) : '',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ]),
                  ),
                  title: Text(
                      e['auto'] == true
                          ? (te ? 'బిల్లుల అమ్మకం (ఆటో)' : 'Bill sales (automatic)')
                          : ('${e['note'] ?? ''}'.isNotEmpty ? '${e['note']}' : askodoxCashCategory('${e['category']}', te)),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                      '${e['kind'] == 'income' ? (te ? 'ఆదాయం' : 'In') : (te ? 'ఖర్చు' : 'Out')} · ${askodoxCashCategory('${e['category']}', te)}',
                      style: TextStyle(
                          color: e['kind'] == 'income' ? const Color(0xFF17784C) : const Color(0xFFB91C1C),
                          fontWeight: FontWeight.w700)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${e['kind'] == 'income' ? '+' : '−'}${askodoxPaise(askodoxPosInt(e['amount_paise']))}',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: e['kind'] == 'income' ? const Color(0xFF17784C) : const Color(0xFFB91C1C))),
                    if (e['auto'] != true)
                      IconButton(
                        tooltip: te ? 'తీసేయి' : 'Remove',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _remove(e),
                      ),
                  ]),
                ),
            ]),
          ),
      ],
    );
  }
}

class AskodoxCashEntrySheet extends ConsumerStatefulWidget {
  const AskodoxCashEntrySheet({super.key, required this.businessId, required this.kind});
  final String businessId;
  final String kind;

  @override
  ConsumerState<AskodoxCashEntrySheet> createState() => AskodoxCashEntrySheetState();
}

class AskodoxCashEntrySheetState extends ConsumerState<AskodoxCashEntrySheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String _category = widget.kind == 'expense' ? 'stock' : 'advance';
  final _txn = askodoxNewTxnId();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final te = askodoxPosTe(context);
    final paise = askodoxParsePaise(_amount.text.trim());
    if (paise == null || paise <= 0) {
      askodoxPosSnack(context, te ? 'మొత్తం రాయండి.' : 'Write the amount.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).cashbookAdd(widget.businessId, {
        'kind': widget.kind,
        'amount_paise': paise,
        'category': _category,
        'note': _note.text.trim(),
        'client_txn_id': _txn,
      });
      if (mounted) Navigator.pop(context, true);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final out = widget.kind == 'expense';
    final cats = out
        ? const ['stock', 'salary', 'rent', 'power', 'gas', 'transport', 'repair', 'other']
        : const ['advance', 'catering', 'other'];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(out ? (te ? '− ఖర్చు రాయండి' : '− Money out') : (te ? '+ ఆదాయం రాయండి' : '+ Money in'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          TextField(
            key: const Key('askodoxCashAmount'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            decoration: const InputDecoration(prefixText: '₹ ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in cats)
              ChoiceChip(
                key: Key('askodoxCashCat-$c'),
                label: Text(askodoxCashCategory(c, te)),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
          ]),
          const SizedBox(height: 10),
          TextField(
            key: const Key('askodoxCashNote'),
            controller: _note,
            maxLength: 120,
            decoration: InputDecoration(
                labelText: te ? 'ఏమిటి? (ఉదా: కూరగాయలు, గ్యాస్)' : 'What for? (e.g. vegetables, gas)',
                border: const OutlineInputBorder()),
          ),
          FilledButton(
            key: const Key('askodoxCashSave'),
            style: FilledButton.styleFrom(
                backgroundColor: out ? const Color(0xFFB91C1C) : const Color(0xFF17784C),
                minimumSize: const Size.fromHeight(50)),
            onPressed: _busy ? null : _save,
            child: Text(te ? 'సేవ్' : 'Save'),
          ),
        ]),
      ),
    );
  }
}

/// `/biz/:id/money/dues` -- who still owes money, biggest first; open a person to see their bills, mark one paid,
/// or send the bill again as a reminder.
class AskodoxBizDuesScreen extends ConsumerStatefulWidget {
  const AskodoxBizDuesScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizDuesScreen> createState() => _AskodoxBizDuesScreenState();
}

class _AskodoxBizDuesScreenState extends ConsumerState<AskodoxBizDuesScreen> {
  AskodoxJson? _data;
  Object? _error;
  String? _open;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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

  Future<void> _paid(AskodoxJson bill) async {
    final te = askodoxPosTe(context);
    final pay = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(te ? '${askodoxPaise(askodoxPosInt(bill['due_paise']))} ఎలా కట్టారు?' : 'How was ${askodoxPaise(askodoxPosInt(bill['due_paise']))} paid?',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          ListTile(leading: const Icon(Icons.payments_outlined), title: Text(te ? 'క్యాష్' : 'Cash'), onTap: () => Navigator.pop(ctx, 'cash')),
          ListTile(leading: const Icon(Icons.phone_android), title: Text(te ? 'ఆన్‌లైన్' : 'Online'), onTap: () => Navigator.pop(ctx, 'online')),
        ]),
      ),
    );
    if (pay == null || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).billSettle(widget.businessId, '${bill['id']}', pay, askodoxNewTxnId());
      await _load();
      if (mounted) askodoxPosSnack(context, te ? 'కట్టినట్టు రాశాం ✓' : 'Marked paid ✓');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final people = askodoxPosList(_data?['people']);
    final oldest = people.isEmpty ? '' : people.map((p) => '${p['oldest'] ?? ''}').where((d) => d.isNotEmpty).fold<String>('', (a, b) => a.isEmpty || b.compareTo(a) < 0 ? b : a);
    return AskodoxBizScaffold(
      key: const Key('askodoxBizDues'),
      businessId: widget.businessId,
      tone: askodoxBizTones['money']!,
      icon: Icons.menu_book_outlined,
      title: te ? 'బాకీలు' : 'Dues',
      trail: [te ? 'బిల్లులు & డబ్బు' : 'Bills & money', te ? 'బాకీలు' : 'Dues'],
      page: 'money',
      onRefresh: _load,
      askHint: te ? '"రాజేష్ బాకీ ఎంత?"' : '"How much does Rajesh owe?"',
      children: [
        if (_error != null) AskodoxPosError(error: _error!, onRetry: _load),
        AskodoxBizStrip(cells: [
          (te ? 'మొత్తం బాకీ' : 'Total due', askodoxPaise(askodoxPosInt(_data?['total_paise'])), const Color(0xFFB45309)),
          (te ? 'ఎంత మంది' : 'People', '${people.length}', const Color(0xFF1E3FA0)),
          (te ? 'పాత బాకీ' : 'Oldest', oldest.length >= 10 ? '${oldest.substring(8, 10)}/${oldest.substring(5, 7)}' : '—',
              const Color(0xFFB91C1C)),
        ]),
        const SizedBox(height: 10),
        if (_data == null && _error == null) const Center(child: CircularProgressIndicator()),
        if (_data != null && people.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(te ? 'ఎవరూ బాకీ లేరు 👍' : 'Nobody owes anything 👍', textAlign: TextAlign.center),
          ),
        for (final p in people)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(children: [
              ListTile(
                key: Key('askodoxDuePerson-${p['name']}-${p['last4']}'),
                leading: CircleAvatar(
                    backgroundColor: const Color(0xFFFFF1E3),
                    child: Text('${p['name']}'.isEmpty ? '?' : '${p['name']}'.characters.first,
                        style: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w900))),
                title: Text('${p['name']}'.isEmpty ? (te ? 'పేరు లేదు' : 'No name') : '${p['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text([
                  if ('${p['last4']}'.isNotEmpty) '••${p['last4']}',
                  te ? '${askodoxPosList(p['bills']).length} బిల్లులు' : '${askodoxPosList(p['bills']).length} bills',
                ].join(' · ')),
                trailing: Text(askodoxPaise(askodoxPosInt(p['due_paise'])),
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFB45309), fontSize: 16)),
                onTap: () => setState(() => _open = _open == '${p['name']}|${p['last4']}' ? null : '${p['name']}|${p['last4']}'),
              ),
              if (_open == '${p['name']}|${p['last4']}')
                for (final b in askodoxPosList(p['bills']))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
                    child: Row(children: [
                      Expanded(
                        child: Text('${b['number']} · ${b['local_date']}\n${te ? 'బాకీ' : 'Due'} ${askodoxPaise(askodoxPosInt(b['due_paise']))} / ${askodoxPaise(askodoxPosInt(b['total_paise']))}',
                            style: const TextStyle(fontSize: 12.5)),
                      ),
                      FilledButton.tonal(
                        key: Key('askodoxDuePaid-${b['id']}'),
                        onPressed: () => _paid(b),
                        child: Text(te ? 'కట్టారు' : 'Paid'),
                      ),
                    ]),
                  ),
            ]),
          ),
      ],
    );
  }
}

/// `/biz/:id/money/history` -- every history page has this shape: search, date chips, kind chips, groups per day.
class AskodoxBizBillHistoryScreen extends ConsumerStatefulWidget {
  const AskodoxBizBillHistoryScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizBillHistoryScreen> createState() => _AskodoxBizBillHistoryScreenState();
}

class _AskodoxBizBillHistoryScreenState extends ConsumerState<AskodoxBizBillHistoryScreen> {
  String _range = 'today';
  String _kind = 'all';
  String _q = '';
  AskodoxJson? _data;
  Object? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  (String, String) _dates() {
    final now = DateTime.now();
    String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    return switch (_range) {
      'today' => (d(now), d(now)),
      'yesterday' => (d(now.subtract(const Duration(days: 1))), d(now.subtract(const Duration(days: 1)))),
      'week' => (d(now.subtract(const Duration(days: 6))), d(now)),
      _ => (d(DateTime(now.year, now.month)), d(now)),
    };
  }

  Future<void> _load() async {
    final (from, to) = _dates();
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).billHistory(widget.businessId, from: from, to: to, q: _q);
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

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final bills = askodoxPosList(_data?['bills']).where((b) {
      final modes = (b['modes'] as List? ?? const []).map((m) => '$m').toList();
      return switch (_kind) {
        'cash' => modes.contains('cash'),
        'online' => modes.any((m) => m != 'cash'),
        'due' => askodoxPosInt(b['due_paise']) > 0,
        'cancelled' => b['status'] == 'cancelled',
        _ => true,
      };
    }).toList();
    final days = <String, List<AskodoxJson>>{};
    for (final b in bills) {
      days.putIfAbsent('${b['local_date']}', () => []).add(b);
    }
    Widget chips(List<(String, String, String)> items, String current, ValueChanged<String> pick) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (k, en, tel) in items)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(te ? tel : en), selected: current == k, onSelected: (_) => pick(k)),
              ),
          ]),
        );
    return AskodoxBizScaffold(
      key: const Key('askodoxBizBillHistory'),
      businessId: widget.businessId,
      tone: askodoxBizTones['money']!,
      icon: Icons.history,
      title: te ? 'బిల్లుల చరిత్ర' : 'Bill history',
      trail: [te ? 'బిల్లులు & డబ్బు' : 'Bills & money', te ? 'చరిత్ర' : 'History'],
      page: 'money',
      onRefresh: _load,
      askHint: te ? '"నిన్న సురేష్ బిల్లు చూపించు"' : '"Show Suresh\'s bill from yesterday"',
      children: [
        TextField(
          key: const Key('askodoxBillHistorySearch'),
          onChanged: (v) {
            _q = v.trim();
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), _load);
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: te ? 'బిల్ నంబర్ / ఫోన్ నంబర్' : 'Bill number / phone number',
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        chips([('today', 'Today', 'ఈ రోజు'), ('yesterday', 'Yesterday', 'నిన్న'), ('week', '7 days', '7 రోజులు'), ('month', 'This month', 'ఈ నెల')],
            _range, (k) {
          setState(() {
            _range = k;
            _data = null;
          });
          unawaited(_load());
        }),
        const SizedBox(height: 6),
        chips([('all', 'All', 'అన్నీ'), ('cash', 'Cash', 'క్యాష్'), ('online', 'Online', 'ఆన్‌లైన్'), ('due', 'Baaki', 'బాకీ'), ('cancelled', 'Cancelled', 'రద్దు')],
            _kind, (k) => setState(() => _kind = k)),
        if (_error != null) AskodoxPosError(error: _error!, onRetry: _load),
        if (_data == null && _error == null) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (_data != null && bills.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text(te ? 'బిల్లులు లేవు.' : 'No bills.', textAlign: TextAlign.center)),
        for (final day in days.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
            child: Text(
                '${day.key} · ${day.value.length} ${te ? 'బిల్లులు' : 'bills'} · ${askodoxPaise(day.value.where((b) => b['status'] != 'cancelled').fold<int>(0, (a, b) => a + askodoxPosInt(b['total_paise'])))}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF4B5563), fontSize: 12.5)),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final b in day.value)
                ListTile(
                  key: Key('askodoxBillRow-${b['id']}'),
                  leading: Icon(
                      b['status'] == 'cancelled'
                          ? Icons.block
                          : askodoxPosInt(b['due_paise']) > 0
                              ? Icons.menu_book_outlined
                              : ((b['modes'] as List? ?? const []).contains('cash') ? Icons.payments_outlined : Icons.phone_android),
                      color: b['status'] == 'cancelled'
                          ? const Color(0xFF9CA3AF)
                          : askodoxPosInt(b['due_paise']) > 0
                              ? const Color(0xFFB45309)
                              : const Color(0xFF17784C)),
                  title: Text('${b['number']}${'${b['customer_name'] ?? ''}'.isNotEmpty ? ' · ${b['customer_name']}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([
                    '${b['issued_at'] ?? ''}'.length >= 16 ? '${b['issued_at']}'.substring(11, 16) : '',
                    if (askodoxPosInt(b['due_paise']) > 0) '${te ? 'బాకీ' : 'Due'} ${askodoxPaise(askodoxPosInt(b['due_paise']))}',
                    if (b['status'] == 'cancelled') te ? 'రద్దు / మార్చారు' : 'cancelled / changed',
                  ].where((x) => x.isNotEmpty).join(' · ')),
                  trailing: Text(askodoxPaise(askodoxPosInt(b['total_paise'])), style: const TextStyle(fontWeight: FontWeight.w900)),
                  onTap: () => context.push('/bills/${widget.businessId}'),
                ),
            ]),
          ),
        ],
      ],
    );
  }
}
