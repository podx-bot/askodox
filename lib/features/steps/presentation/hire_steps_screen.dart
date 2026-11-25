import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/delivery_jobs_screens.dart' show askodoxRupee;
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 26): a customer hires a worker `/hire`.
/// Home = ONE list of my bookings + ONE big button "I need a worker". The job in 3 steps: 1 what work (tiles) ->
/// 2 where + when -> 3 through whom (a business or an independent worker; tap = book, asks once). A booking row opens
/// who is coming, their number / UPI once given, stars (done, once) and a complaint. Old page stays at `?full=1`.
class AskodoxHireStepsScreen extends ConsumerStatefulWidget {
  const AskodoxHireStepsScreen({super.key});

  @override
  ConsumerState<AskodoxHireStepsScreen> createState() => _HireStepsState();
}

class _HireStepsState extends ConsumerState<AskodoxHireStepsScreen> {
  List<AskodoxJson> _types = const [];
  List<AskodoxJson> _orders = const [];
  List<AskodoxJson>? _options;
  bool _loaded = false;
  Object? _error;
  int _step = 0;
  String? _type;
  bool _booking = false;
  final _place = TextEditingController();
  final _when = TextEditingController();
  final _complaint = TextEditingController();

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _place.dispose();
    _when.dispose();
    _complaint.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final types = askodoxPosList((await _repo.hireTypes())['work_types']);
      final orders = askodoxPosList((await _repo.hireOrders())['orders']);
      if (!mounted) return;
      setState(() {
        _types = types;
        _orders = orders;
        _loaded = true;
        _error = null;
        if (orders.isEmpty && _step == 0) _step = 1;
      });
    } catch (e) {
      if (mounted && !_loaded) setState(() => _error = e);
    }
  }

  Future<void> _do(Future<Object?> Function() call, {String? done}) async {
    try {
      await call();
      if (done != null && mounted) askodoxPosSnack(context, done);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    }
  }

  String _work(AskodoxJson t) => _te && '${t['te'] ?? ''}'.isNotEmpty ? '${t['te']}' : '${t['en'] ?? t['key'] ?? ''}';

  Future<void> _toWho() async {
    final type = _type;
    if (type == null) return;
    setState(() {
      _step = 3;
      _options = null;
    });
    try {
      final options = askodoxPosList((await _repo.hireOptions(type))['options']);
      if (mounted) setState(() => _options = options);
    } on AskodoxPosException catch (e) {
      if (!mounted) return;
      setState(() => _options = const []);
      askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    }
  }

  String _optionId(AskodoxJson o) => '${o['business_id'] ?? o['worker'] ?? ''}';

  Future<void> _book(AskodoxJson o) async {
    final te = _te;
    if (_booking) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? '${o['name']} ద్వారా బుక్ చేయాలా?' : 'Book through ${o['name']}?'),
        content: Text([_place.text.trim(), _when.text.trim()].where((x) => x.isNotEmpty).join(' · ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(te ? 'వద్దు' : 'No')),
          FilledButton(
              key: const Key('askodoxHireStepsBookYes'),
              onPressed: () => Navigator.pop(d, true),
              child: Text(te ? 'బుక్' : 'Book')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _booking = true);
    try {
      await _repo.hirePlace({
        'work_type': _type,
        if (o['kind'] == 'independent') 'worker': o['worker'] else 'business_id': o['business_id'],
        'place': _place.text.trim(),
        'at': _when.text.trim(),
      });
      if (!mounted) return;
      askodoxPosSnack(context, te ? '✓ బుక్ అయింది – పేరు, నంబర్ వస్తాయి' : '✓ Booked – name and number will come');
      setState(() {
        _step = 0;
        _type = null;
        _options = null;
      });
      _place.clear();
      _when.clear();
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  Future<void> _order(AskodoxJson o) async {
    final te = _te;
    final id = '${o['id']}';
    final canRate = '${o['status']}' == 'done' && o['rated'] != true;
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${o['label'] ?? ''} ${te ? o['work_te'] ?? '' : o['work_en'] ?? ''}'.trim(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text('${o['authority'] ?? ''} · ${o['status'] ?? ''}', style: const TextStyle(color: askodoxStepMuted)),
            if ('${o['worker_name'] ?? ''}'.isNotEmpty)
              Text('${te ? 'వచ్చేది' : 'Coming'}: ${o['worker_name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if ('${o['worker_phone'] ?? ''}'.isNotEmpty) SelectableText('${o['worker_phone']}', style: const TextStyle(fontSize: 17)),
            if ('${o['pay_upi'] ?? ''}'.isNotEmpty) SelectableText('UPI ${o['pay_upi']}'),
            if (canRate) ...[
              const SizedBox(height: 12),
              Text(te ? 'ఎలా చేశారు?' : 'How was the work?', style: const TextStyle(fontWeight: FontWeight.w800)),
              Wrap(spacing: 4, children: [
                for (var s = 1; s <= 5; s++)
                  IconButton(
                    key: ValueKey('askodoxHireStepsRate-$id-$s'),
                    iconSize: 36,
                    onPressed: () => Navigator.pop(ctx, 'rate$s'),
                    icon: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                  ),
              ]),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              key: ValueKey('askodoxHireStepsComplain-$id'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => Navigator.pop(ctx, 'complain'),
              child: Text(te ? 'ఫిర్యాదు' : 'Complaint'),
            ),
          ]),
        ),
      ),
    );
    if (v == null || !mounted) return;
    if (v.startsWith('rate')) {
      await _do(() => _repo.hireRate(id, int.parse(v.substring(4))), done: te ? 'ధన్యవాదాలు ✓' : 'Thank you ✓');
      return;
    }
    _complaint.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? 'ఏం జరిగింది?' : 'What went wrong?'),
        content: TextField(key: const Key('askodoxHireStepsComplaintText'), controller: _complaint, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxHireStepsComplaintSend'),
              onPressed: () => Navigator.pop(d, true),
              child: Text(te ? 'పంపు' : 'Send')),
        ],
      ),
    );
    final text = _complaint.text.trim();
    if (ok == true && text.isNotEmpty && mounted) {
      await _do(() => _repo.hireComplain(id, text), done: te ? 'ఫిర్యాదు పంపాం ✓' : 'Complaint sent ✓');
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'పని వాళ్ళు కావాలి' : 'Hire a worker';
    final more = [
      AskodoxStepMore('askodoxHireStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
          () => context.push('/hire?full=1').then((_) => _load())),
    ];
    if (_error != null) return AskodoxStepScaffold(title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    if (!_loaded) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    return switch (_step) {
      1 => _whatWork(title, more),
      2 => _whereWhen(title, more),
      3 => _whoBy(title, more),
      _ => _home(title, more),
    };
  }

  Widget _home(String title, List<AskodoxStepMore> more) {
    final te = _te;
    final open = [for (final o in _orders) if ('${o['status']}' != 'done') o];
    return AskodoxStepScaffold(
      key: const Key('askodoxHireSteps'),
      title: title,
      more: more,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          AskodoxStepBigNumber('${open.length}', label: te ? 'నడుస్తున్న బుకింగ్స్' : 'Bookings running', color: askodoxStepGreen),
          const SizedBox(height: 8),
          for (final o in _orders)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxHireStepsOrder-${o['id']}'),
              name: '${o['label'] ?? ''} ${te ? o['work_te'] ?? '' : o['work_en'] ?? ''}'.trim(),
              sub: ['${o['authority'] ?? ''}', '${o['worker_name'] ?? ''}'].where((x) => x.isNotEmpty).join(' · '),
              amount: '${o['status']}' == 'done' ? (o['rated'] == true ? '✓' : '⭐') : '…',
              amountColor: '${o['status']}' == 'done' ? askodoxStepDone : askodoxStepWarn,
              onTap: () => _order(o),
            ),
        ]),
      ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxHireStepsNew'),
        label: te ? 'పని వాళ్ళు కావాలి' : 'I need a worker',
        icon: Icons.person_search_rounded,
        onPressed: () => setState(() => _step = 1),
      ),
    );
  }

  Widget _whatWork(String title, List<AskodoxStepMore> more) {
    final te = _te;
    return AskodoxStepScaffold(
      key: const Key('askodoxHireSteps'),
      title: title,
      step: 1,
      question: te ? 'ఏ పని కావాలి?' : 'What work do you need?',
      onBack: _orders.isEmpty ? null : () => setState(() => _step = 0),
      more: more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        if (_types.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(te ? 'ఇంకా ఏ పనులూ లేవు' : 'No work types yet')),
        for (final t in _types)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AskodoxStepChoice(
              key: ValueKey('askodoxHireStepsType-${t['key']}'),
              icon: Icons.work_outline_rounded,
              color: askodoxStepGreen,
              title: _work(t),
              sub: '',
              selected: _type == '${t['key']}',
              onTap: () => setState(() {
                _type = '${t['key']}';
                _step = 2;
              }),
            ),
          ),
      ]),
    );
  }

  Widget _whereWhen(String title, List<AskodoxStepMore> more) {
    final te = _te;
    return AskodoxStepScaffold(
      key: const Key('askodoxHireSteps'),
      title: title,
      step: 2,
      question: te ? 'ఎక్కడ, ఎప్పుడు?' : 'Where and when?',
      hint: te ? 'ఉదా: మా ఇల్లు, రేపు ఉదయం 9' : 'e.g. my house, tomorrow 9 am',
      onBack: () => setState(() => _step = 1),
      more: more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        TextField(
            key: const Key('askodoxHireStepsPlace'),
            controller: _place,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(labelText: te ? 'ఎక్కడ' : 'Where', border: const OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(
            key: const Key('askodoxHireStepsWhen'),
            controller: _when,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(labelText: te ? 'ఎప్పుడు' : 'When', border: const OutlineInputBorder())),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxHireStepsNext'),
        label: te ? 'ఎవరి ద్వారా? చూపించు' : 'Show who can come',
        icon: Icons.arrow_forward_rounded,
        onPressed: _toWho,
      ),
    );
  }

  Widget _whoBy(String title, List<AskodoxStepMore> more) {
    final te = _te;
    final options = _options;
    return AskodoxStepScaffold(
      key: const Key('askodoxHireSteps'),
      title: title,
      step: 3,
      question: te ? 'ఎవరి ద్వారా?' : 'Through whom?',
      hint: te ? 'నొక్కితే బుక్ అవుతుంది' : 'Tap to book',
      onBack: () => setState(() => _step = 2),
      more: more,
      body: options == null || _booking
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
              if (options.isEmpty)
                Padding(padding: const EdgeInsets.all(24), child: Text(te ? 'మీ దగ్గర ఇంకా ఎవరూ లేరు' : 'No one near you yet')),
              for (final o in options)
                AskodoxStepPersonRow(
                  key: ValueKey('askodoxHireStepsOption-${_optionId(o)}'),
                  name: '${o['name'] ?? ''}',
                  sub: o['kind'] == 'independent'
                      ? '${o['label'] ?? ''}'
                      : ['${o['address'] ?? ''}', if (o['team'] != null) '${o['team']} ${te ? 'మంది' : 'people'}']
                          .where((x) => x.isNotEmpty)
                          .join(' · '),
                  amount: o['price_paise'] != null ? askodoxRupee(o['price_paise']) : (te ? 'బుక్' : 'Book'),
                  amountColor: askodoxStepGreen,
                  onTap: () => _book(o),
                ),
            ]),
    );
  }
}
