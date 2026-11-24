import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../steps/presentation/step_kit.dart';
import '../data/pos_repository.dart';
import 'pos_common.dart';

/// Delivery jobs for the shop's own people (owner plan 2026-11-24, design 5wns7Bm9FEEnr4ug3E9PQv, step 1).
/// Owner: ONE line -> job card -> who goes (free first) -> answers -> give. Person: colour, offers, the job, money.
/// Calls = the phone's own dialer; directions = the phone's Google Maps; online money = the OWNER's own UPI QR.

String askodoxRupee(Object? paise) {
  final p = paise is num ? paise.toInt() : int.tryParse('$paise') ?? 0;
  return p % 100 == 0 ? '₹${p ~/ 100}' : '₹${(p / 100).toStringAsFixed(2)}';
}

const askodoxWorkColours = <String, (Color, String, String)>{
  'free': (Color(0xFF16A34A), 'Free', 'ఖాళీ'),
  'busy': (Color(0xFFEA580C), 'On a job', 'పనిలో'),
  'off': (Color(0xFFDC2626), 'Busy / off', 'బిజీ / ఆఫ్'),
  'unknown': (Color(0xFF94A3B8), 'Not set', 'తెలియదు'),
};

Future<void> _dial(String phone) async {
  if (phone.isEmpty) return;
  try {
    await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

String _answerWords(String a, bool te) => switch (a) {
      'now' => te ? 'వెంటనే' : 'Now',
      'no' => te ? 'కుదరదు' : "Can't",
      'waiting' => te ? 'జవాబు రాలేదు' : 'No answer yet',
      _ => te ? '$a ని.' : '$a min',
    };

/// Owner / cashier: "Send delivery" in 3 steps.
class AskodoxDeliveryJobsScreen extends ConsumerStatefulWidget {
  const AskodoxDeliveryJobsScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<AskodoxDeliveryJobsScreen> createState() => _DeliveryJobsState();
}

class _DeliveryJobsState extends ConsumerState<AskodoxDeliveryJobsScreen> {
  final _line = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _item = TextEditingController();
  final _fee = TextEditingController();
  final _collect = TextEditingController();
  int _step = 1;
  bool _busy = false;
  bool _autoFirst = false;
  double? _km;
  int? _minutes;
  List<AskodoxJson> _people = const [];
  final Set<String> _chosen = {};
  AskodoxJson? _job;
  List<AskodoxJson> _today = const [];
  Timer? _poll;

  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadToday());
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final c in [_line, _from, _to, _item, _fee, _collect]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadToday() async {
    try {
      final jobs = await _repo.deliveryJobs(widget.businessId);
      if (mounted) setState(() => _today = jobs);
    } catch (_) {}
  }

  int _paise(TextEditingController c) => ((double.tryParse(c.text.trim()) ?? 0) * 100).round();

  Future<void> _read(String text) async {
    if (text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final d = await _repo.deliveryDraft(widget.businessId, text.trim());
      _from.text = '${d['from'] ?? ''}';
      _to.text = '${d['to'] ?? ''}';
      _item.text = '${d['item'] ?? ''}';
      final fee = (d['fee_paise'] as num?)?.toInt() ?? 0;
      final collect = (d['collect_paise'] as num?)?.toInt() ?? 0;
      _fee.text = fee == 0 ? '' : '${fee / 100}'.replaceAll(RegExp(r'\.0$'), '');
      _collect.text = collect == 0 ? '' : '${collect / 100}'.replaceAll(RegExp(r'\.0$'), '');
      _km = (d['km'] as num?)?.toDouble();
      _minutes = (d['minutes'] as num?)?.toInt();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toPeople() async {
    if (_to.text.trim().isEmpty) {
      askodoxPosSnack(context, askodoxPosT(context, 'Say where it goes', 'ఎక్కడికి వెళ్ళాలో చెప్పండి'));
      return;
    }
    setState(() => _busy = true);
    try {
      final people = await _repo.deliveryPeople(widget.businessId);
      if (!mounted) return;
      setState(() {
        _people = people.where((p) => p['role'] != 'owner').toList();
        _chosen
          ..clear()
          ..addAll(_people.where((p) => p['colour'] == 'free').map((p) => '${p['id']}'));
        _step = 2;
      });
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_chosen.isEmpty) {
      askodoxPosSnack(context, askodoxPosT(context, 'Choose who to ask', 'ఎవరిని అడగాలో ఎంచుకోండి'));
      return;
    }
    setState(() => _busy = true);
    try {
      final job = await _repo.deliveryCreate(widget.businessId, {
        'from': _from.text.trim(),
        'to': _to.text.trim(),
        'item': _item.text.trim(),
        'fee_paise': _paise(_fee),
        'collect_paise': _paise(_collect),
        if (_km != null) 'km': _km,
        if (_minutes != null) 'minutes': _minutes,
        'ask': _chosen.toList(),
        'auto_first': _autoFirst,
      });
      if (!mounted) return;
      setState(() {
        _job = job;
        _step = 3;
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refreshJob());
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshJob() async {
    final id = _job?['id'];
    if (id == null) return;
    try {
      final jobs = await _repo.deliveryJobs(widget.businessId);
      final job = jobs.where((j) => j['id'] == id).firstOrNull;
      if (!mounted) return;
      setState(() {
        _today = jobs;
        if (job != null) _job = job;
      });
      if (job != null && job['status'] != 'asking') _poll?.cancel();
    } catch (_) {}
  }

  Future<void> _give(String person) async {
    final id = '${_job?['id'] ?? ''}';
    if (id.isEmpty) return;
    try {
      final job = await _repo.deliveryGive(widget.businessId, id, person);
      if (mounted) setState(() => _job = job);
      _poll?.cancel();
      unawaited(_loadToday());
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    }
  }

  void _restart() {
    _poll?.cancel();
    for (final c in [_line, _from, _to, _item, _fee, _collect]) {
      c.clear();
    }
    setState(() {
      _step = 1;
      _job = null;
      _km = null;
      _minutes = null;
    });
    unawaited(_loadToday());
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return AskodoxStepScaffold(
      key: const Key('askodoxDeliveryJobs'),
      title: te ? 'డెలివరీ పంపు' : 'Send delivery',
      step: _step,
      question: switch (_step) {
        1 => te ? 'ఏం, ఎక్కడికి పంపాలి?' : 'What goes where?',
        2 => te ? 'ఎవరికి పంపాలి?' : 'Who should go?',
        _ => te ? 'ఎవరు వస్తారు?' : 'Who is coming?',
      },
      hint: _step == 1 ? (te ? 'ఉదా: ఉయ్యూరు నుంచి పారం కి కేక్ డెలివరీ, 250 రూపాయలు' : 'e.g. Uyyuru to Param, one cake, collect 250') : null,
      onBack: _step == 1 ? null : () => setState(() => _step = _step == 3 ? 1 : _step - 1),
      body: switch (_step) {
        1 => _card(te),
        2 => _who(te),
        _ => _answers(te),
      },
      bottom: switch (_step) {
        1 => AskodoxStepBottom(
            buttonKey: const Key('askodoxDeliveryNext'),
            label: te ? 'ఎవరికి పంపాలి →' : 'Who goes →',
            icon: Icons.arrow_forward_rounded,
            busy: _busy,
            onPressed: _toPeople,
            onSpoken: (said) {
              _line.text = said;
              unawaited(_read(said));
            },
          ),
        2 => AskodoxStepBottom(
            buttonKey: const Key('askodoxDeliverySend'),
            label: te ? 'అడుగు (${_chosen.length})' : 'Ask (${_chosen.length})',
            icon: Icons.send_rounded,
            busy: _busy,
            onPressed: _send,
          ),
        _ => AskodoxStepBottom(
            buttonKey: const Key('askodoxDeliveryNew'),
            label: te ? 'ఇంకో డెలివరీ' : 'Another delivery',
            icon: Icons.add_rounded,
            outline: true,
            onPressed: _restart,
          ),
      },
    );
  }

  Widget _card(bool te) {
    final box = (TextEditingController c, String label, Key key, {bool money = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            key: key,
            controller: c,
            keyboardType: money ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), prefixText: money ? '₹ ' : null),
          ),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      TextField(
        key: const Key('askodoxDeliveryLine'),
        controller: _line,
        minLines: 1,
        maxLines: 3,
        textInputAction: TextInputAction.done,
        onSubmitted: _read,
        decoration: InputDecoration(
          hintText: te ? 'ఒక్క లైన్ లో చెప్పండి / టైప్ చేయండి' : 'Say or type it in one line',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
              key: const Key('askodoxDeliveryRead'),
              icon: const Icon(Icons.auto_fix_high_rounded),
              onPressed: () => _read(_line.text)),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: box(_from, te ? 'ఎక్కడి నుంచి (ఖాళీ = షాప్)' : 'From (empty = shop)', const Key('askodoxDeliveryFrom'))),
        const SizedBox(width: 8),
        Expanded(child: box(_to, te ? 'ఎక్కడికి' : 'To', const Key('askodoxDeliveryTo'))),
      ]),
      box(_item, te ? 'ఏమిటి' : 'What', const Key('askodoxDeliveryItem')),
      Row(children: [
        Expanded(child: box(_collect, te ? 'కస్టమర్ కట్టాల్సింది' : 'Collect', const Key('askodoxDeliveryCollect'), money: true)),
        const SizedBox(width: 8),
        Expanded(child: box(_fee, te ? 'వెళ్ళేవాళ్ళకి' : 'To the rider', const Key('askodoxDeliveryFee'), money: true)),
      ]),
      if (_km != null)
        Container(
          key: const Key('askodoxDeliveryRoute'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.route_rounded, color: Color(0xFF1D4ED8)),
            const SizedBox(width: 8),
            Text('≈ ${_km!.toStringAsFixed(1)} km${_minutes == null ? '' : ' · $_minutes ${te ? 'ని.' : 'min'}'}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
        ),
      if (_today.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(te ? 'ఈ రోజు' : 'Today', style: const TextStyle(fontWeight: FontWeight.w800)),
        for (final j in _today.take(8))
          ListTile(
            key: ValueKey('askodoxDeliveryToday-${j['id']}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Text('${j['label']}', style: const TextStyle(fontWeight: FontWeight.w900)),
            title: Text('${j['from']} → ${j['to']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              '${j['assignee_label'] ?? ''}',
              _statusWords('${j['status']}', te),
              if (j['money_mode'] == 'cash') '${askodoxRupee(j['collect_paise'])} ${te ? 'క్యాష్' : 'cash'}',
            ].where((x) => x.isNotEmpty).join(' · ')),
          ),
      ],
    ]);
  }

  Widget _who(bool te) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      Row(children: [
        Expanded(
          child: OutlinedButton(
            key: const Key('askodoxDeliveryAskFree'),
            onPressed: () => setState(() {
              _chosen
                ..clear()
                ..addAll(_people.where((p) => p['colour'] == 'free').map((p) => '${p['id']}'));
            }),
            child: Text(te ? 'ఖాళీగా ఉన్న అందరూ' : 'Everyone free'),
          ),
        ),
      ]),
      SwitchListTile(
        key: const Key('askodoxDeliveryAutoFirst'),
        contentPadding: EdgeInsets.zero,
        value: _autoFirst,
        onChanged: (v) => setState(() => _autoFirst = v),
        title: Text(te ? '"వెంటనే వస్తా" అన్న మొదటివాళ్ళకి దానంతట అదే ఇవ్వు' : "Give it to the first 'now' by itself"),
      ),
      if (_people.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(te ? 'ఇంకా సిబ్బంది లేరు. Staff పేజీలో delivery వాళ్ళను చేర్చండి.' : 'No staff yet. Add delivery people on the Staff page.'),
        ),
      for (final p in _people)
        Card(
          child: CheckboxListTile(
            key: ValueKey('askodoxDeliveryPerson-${p['id']}'),
            value: _chosen.contains('${p['id']}'),
            onChanged: (v) => setState(() => v == true ? _chosen.add('${p['id']}') : _chosen.remove('${p['id']}')),
            secondary: CircleAvatar(backgroundColor: (askodoxWorkColours['${p['colour']}'] ?? askodoxWorkColours['unknown']!).$1, radius: 10),
            title: Text('${p['label']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(te
                ? (askodoxWorkColours['${p['colour']}'] ?? askodoxWorkColours['unknown']!).$3
                : (askodoxWorkColours['${p['colour']}'] ?? askodoxWorkColours['unknown']!).$2),
          ),
        ),
    ]);
  }

  Widget _answers(bool te) {
    final job = _job ?? const <String, Object?>{};
    final asks = askodoxPosList(job['asks']);
    final given = job['status'] != 'asking';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: askodoxStepGreenSoft, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${job['label'] ?? ''}  ${job['from'] ?? ''} → ${job['to'] ?? ''}',
              key: const Key('askodoxDeliveryCard'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          if ('${job['item'] ?? ''}'.isNotEmpty) Text('${job['item']}'),
          Text([
            if (((job['collect_paise'] as num?) ?? 0) > 0) '${te ? 'కట్టించుకోవాలి' : 'Collect'} ${askodoxRupee(job['collect_paise'])}',
            if (((job['fee_paise'] as num?) ?? 0) > 0) '${te ? 'వెళ్ళేవాళ్ళకి' : 'Rider'} ${askodoxRupee(job['fee_paise'])}',
          ].join(' · ')),
          if (given)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('✓ ${job['assignee_label']} ${te ? 'కి ఇచ్చారు' : 'is going'}',
                  key: const Key('askodoxDeliveryGiven'), style: const TextStyle(fontWeight: FontWeight.w900, color: askodoxStepDone)),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      for (final a in asks)
        Card(
          child: ListTile(
            key: ValueKey('askodoxDeliveryAnswer-${a['user']}'),
            title: Text('${a['label']} – ${_answerWords('${a['answer']}', te)}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if ('${a['phone'] ?? ''}'.isNotEmpty)
                IconButton(
                    tooltip: te ? 'కాల్' : 'Call',
                    icon: const Icon(Icons.call_rounded),
                    onPressed: () => _dial('${a['phone']}')),
              if (!given && a['answer'] != 'no')
                FilledButton(
                  key: ValueKey('askodoxDeliveryGive-${a['user']}'),
                  onPressed: () => _give('${a['user']}'),
                  child: Text(te ? 'ఇవ్వు' : 'Give'),
                ),
            ]),
          ),
        ),
    ]);
  }
}

String _statusWords(String status, bool te) => switch (status) {
      'asking' => te ? 'అడుగుతున్నాం' : 'asking',
      'given' => te ? 'ఇచ్చారు' : 'given',
      'picked' => te ? 'తీసుకెళ్తున్నారు' : 'on the way',
      'done' => te ? 'అయింది' : 'done',
      'cancelled' => te ? 'రద్దు' : 'cancelled',
      _ => status,
    };

/// The person's page: my colour, offers to answer, my job (directions, call the shop, money, done).
class AskodoxMyDeliveriesScreen extends ConsumerStatefulWidget {
  const AskodoxMyDeliveriesScreen({super.key});

  @override
  ConsumerState<AskodoxMyDeliveriesScreen> createState() => _MyDeliveriesState();
}

class _MyDeliveriesState extends ConsumerState<AskodoxMyDeliveriesScreen> {
  AskodoxJson? _data;
  Object? _error;
  Timer? _poll;
  final Map<String, AskodoxJson> _qr = {};

  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _repo.myDeliveryJobs();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _do(Future<Object?> Function() call) async {
    try {
      await call();
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final data = _data;
    final status = askodoxPosMap(data?['status']);
    final colour = '${status['colour'] ?? 'unknown'}';
    final offers = askodoxPosList(data?['offers']);
    final running = askodoxPosList(data?['running']);
    final cash = askodoxPosList(data?['cash_today']);
    return Scaffold(
      key: const Key('askodoxMyDeliveries'),
      appBar: AppBar(title: Text(te ? 'నా డెలివరీ పని' : 'My delivery work')),
      body: data == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : AskodoxPosError(error: _error!, onRetry: _load))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  for (final c in const ['free', 'busy', 'off']) ...[
                    if (c != 'free') const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 64,
                        child: FilledButton(
                          key: ValueKey('askodoxWorkStatus-$c'),
                          style: FilledButton.styleFrom(
                              backgroundColor: colour == c ? askodoxWorkColours[c]!.$1 : const Color(0xFFF1F5F9),
                              foregroundColor: colour == c ? Colors.white : const Color(0xFF334155),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          onPressed: () => _do(() => _repo.setWorkStatus(c)),
                          child: FittedBox(
                            child: Text(te ? askodoxWorkColours[c]!.$3 : askodoxWorkColours[c]!.$2,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ]),
                if (colour == 'unknown')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(te ? '3 గంటలుగా రంగు మార్చలేదు – ఇప్పుడు ఏది?' : 'No colour for 3 hours – which is it now?',
                        style: const TextStyle(color: Color(0xFF64748B))),
                  ),
                for (final c in cash)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('${te ? 'ఈ రోజు నా దగ్గర క్యాష్' : 'Cash with me today'}: ${askodoxRupee(c['paise'])} (${c['jobs']})',
                        key: const Key('askodoxMyCashToday'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                for (final job in running) _running(job, te),
                if (offers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(te ? 'మిమ్మల్ని అడుగుతున్నారు' : 'You are asked', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ],
                for (final job in offers) _offer(job, te),
                if (offers.isEmpty && running.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(child: Text(te ? 'ఇప్పుడు ఏ పనీ లేదు' : 'No work right now')),
                  ),
              ]),
            ),
    );
  }

  Widget _offer(AskodoxJson job, bool te) {
    final mine = '${job['my_answer'] ?? 'waiting'}';
    return Card(
      key: ValueKey('askodoxOffer-${job['id']}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${job['shop']} · ${job['label']}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF15803D))),
          Text('${job['from']} → ${job['to']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text([
            if (job['km'] != null) '≈ ${(job['km'] as num).toStringAsFixed(1)} km',
            if (((job['fee_paise'] as num?) ?? 0) > 0) '${te ? 'మీకు' : 'You get'} ${askodoxRupee(job['fee_paise'])}',
            if ('${job['item'] ?? ''}'.isNotEmpty) '${job['item']}',
          ].join(' · ')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in const ['now', '10', '20', '30', 'no'])
              ChoiceChip(
                key: ValueKey('askodoxOfferAnswer-${job['id']}-$a'),
                selected: mine == a,
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(a == 'now' ? (te ? 'వెంటనే వస్తా' : "I'll come now") : _answerWords(a, te),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                onSelected: (_) => _do(() => _repo.answerDeliveryJob('${job['id']}', a)),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _running(AskodoxJson job, bool te) {
    final id = '${job['id']}';
    final collect = ((job['collect_paise'] as num?) ?? 0).toInt();
    final qr = _qr[id] ?? askodoxPosMap(job['request']);
    return Card(
      key: ValueKey('askodoxMyJob-$id'),
      color: const Color(0xFFFFF7ED),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${job['label']} · ${job['shop']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('${job['from']} → ${job['to']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          if (collect > 0) Text('${te ? 'కట్టించుకోవాలి' : 'Collect'} ${askodoxRupee(collect)}', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: ValueKey('askodoxMyJobMaps-$id'),
                icon: const Icon(Icons.directions_rounded),
                label: Text(te ? 'దారి చూపించు' : 'Directions'),
                onPressed: () => launchUrl(Uri.parse('${job['maps_url']}'), mode: LaunchMode.externalApplication),
              ),
            ),
            if (job['status'] == 'given') ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: ValueKey('askodoxMyJobPicked-$id'),
                  onPressed: () => _do(() => _repo.stepDeliveryJob(id, 'picked')),
                  child: Text(te ? 'తీసుకున్నా' : 'Picked up'),
                ),
              ),
            ],
          ]),
          if (qr['upi_link'] != null) ...[
            const SizedBox(height: 10),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(key: ValueKey('askodoxMyJobQr-$id'), data: '${qr['upi_link']}', size: 200),
              ),
            ),
            Center(
              child: Text(
                  qr['status'] == 'matched' || qr['status'] == 'confirmed'
                      ? '✓ ${askodoxRupee(qr['amount_paise'])} ${te ? 'వచ్చింది' : 'received'}'
                      : '${askodoxRupee(qr['amount_paise'])} · ${te ? 'ఓనర్ నిర్ధారణ కోసం' : 'waiting for the owner'}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
          const SizedBox(height: 10),
          if (collect > 0)
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  key: ValueKey('askodoxMyJobUpi-$id'),
                  onPressed: () async {
                    try {
                      final r = await _repo.collectDeliveryJob(id);
                      if (mounted) setState(() => _qr[id] = r);
                    } on AskodoxPosException catch (e) {
                      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
                    }
                  },
                  child: const Text('UPI / QR'),
                ),
              ),
            ]),
          const SizedBox(height: 8),
          Text(te ? 'డబ్బు ఎలా?' : 'How was it paid?', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(children: [
            for (final (i, m) in (collect > 0 ? const ['cash', 'upi', 'prepaid'] : const ['prepaid']).indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    key: ValueKey('askodoxMyJobDone-$id-$m'),
                    style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen),
                    onPressed: () => _do(() => _repo.stepDeliveryJob(id, 'done', money: m)),
                    child: FittedBox(
                      child: Text(switch (m) {
                        'cash' => te ? 'క్యాష్ – అయింది' : 'Cash – done',
                        'upi' => te ? 'UPI – అయింది' : 'UPI – done',
                        _ => te ? 'అయింది' : 'Done',
                      }),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
