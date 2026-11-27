import '../../../config/theme/askodox_look.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/delivery_jobs_screens.dart' show askodoxRupee, askodoxWorkColours;
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 22): a delivery person's own work `/me/deliveries`. Top = my colour (free / on a
/// job / off), middle = ONE list (the job I am on, then the ones I am asked), bottom = ONE big button (open the first job).
/// Tap a row = directions / picked up / UPI QR / done (cash, UPI, prepaid) or my answer. Old page stays at `?full=1`.
/// Money: the QR is the OWNER's own UPI; ASKODOX only records.
class AskodoxMyDeliveriesStepsScreen extends ConsumerStatefulWidget {
  const AskodoxMyDeliveriesStepsScreen({super.key});

  @override
  ConsumerState<AskodoxMyDeliveriesStepsScreen> createState() => _MyDeliveriesStepsState();
}

class _MyDeliveriesStepsState extends ConsumerState<AskodoxMyDeliveriesStepsScreen> {
  AskodoxJson? _data;
  Object? _error;
  Timer? _poll;

  bool get _te => askodoxPosTe(context);
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
      if (mounted && _data == null) setState(() => _error = e);
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

  String _answerWords(String a) => switch (a) {
        'now' => _te ? 'వెంటనే వస్తా' : "I'll come now",
        'no' => _te ? 'కుదరదు' : "Can't",
        _ => _te ? '$a నిమిషాల్లో' : 'In $a min',
      };

  Future<void> _showQr(String id) async {
    final te = _te;
    try {
      final r = await _repo.collectDeliveryJob(id);
      if (!mounted) return;
      final link = '${r['upi_link'] ?? ''}';
      if (link.isEmpty) return;
      await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
                title: Text(askodoxRupee(r['amount_paise'])),
                content: SizedBox(
                    width: 240,
                    height: 240,
                    child: QrImageView(key: ValueKey('askodoxMyDeliveriesStepsQr-$id'), data: link, size: 220, backgroundColor: Colors.white)),
                actions: [TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(te ? 'సరే' : 'OK'))],
              ));
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    }
  }

  Future<void> _running(AskodoxJson job) async {
    final te = _te;
    final id = '${job['id']}';
    final collect = askodoxPosInt(job['collect_paise']);
    final given = '${job['status']}' == 'given';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${job['label']} · ${job['shop']}', style: const TextStyle(fontWeight: FontWeight.w800, color: askodoxStepMuted)),
            Text('${job['from']} → ${job['to']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            if (collect > 0) Text('${te ? 'కట్టించుకోవాలి' : 'Collect'} ${askodoxRupee(collect)}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                key: ValueKey('askodoxMyDeliveriesStepsMaps-$id'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => Navigator.pop(ctx, 'maps'),
                icon: const Icon(Icons.directions_rounded),
                label: Text(te ? 'దారి చూపించు' : 'Directions')),
            if (given) ...[
              const SizedBox(height: 8),
              FilledButton(
                  key: ValueKey('askodoxMyDeliveriesStepsPicked-$id'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: () => Navigator.pop(ctx, 'picked'),
                  child: Text(te ? 'తీసుకున్నా' : 'Picked up')),
            ],
            if (collect > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                  key: ValueKey('askodoxMyDeliveriesStepsUpi-$id'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => Navigator.pop(ctx, 'qr'),
                  child: const Text('UPI / QR')),
            ],
            const SizedBox(height: 12),
            Text(te ? 'డబ్బు ఎలా?' : 'How was it paid?', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final m in (collect > 0 ? const ['cash', 'upi', 'prepaid'] : const ['prepaid'])) ...[
              FilledButton(
                key: ValueKey('askodoxMyDeliveriesStepsDone-$id-$m'),
                style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen, minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.pop(ctx, 'done-$m'),
                child: Text(switch (m) {
                  'cash' => te ? 'క్యాష్ – అయింది' : 'Cash – done',
                  'upi' => te ? 'UPI – అయింది' : 'UPI – done',
                  _ => te ? 'అయింది' : 'Done',
                }),
              ),
              const SizedBox(height: 8),
            ],
          ]),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'maps') {
      try {
        await launchUrl(Uri.parse('${job['maps_url']}'), mode: LaunchMode.externalApplication);
      } catch (_) {}
    } else if (action == 'picked') {
      await _do(() => _repo.stepDeliveryJob(id, 'picked'));
    } else if (action == 'qr') {
      await _showQr(id);
    } else if (action.startsWith('done-')) {
      await _do(() => _repo.stepDeliveryJob(id, 'done', money: action.substring(5)));
    }
  }

  Future<void> _offer(AskodoxJson job) async {
    final te = _te;
    final id = '${job['id']}';
    final mine = '${job['my_answer'] ?? 'waiting'}';
    final answer = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${job['shop']} · ${job['label']}', style: const TextStyle(fontWeight: FontWeight.w800, color: askodoxStepMuted)),
            Text('${job['from']} → ${job['to']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text([
              if (job['km'] != null) '≈ ${(job['km'] as num).toStringAsFixed(1)} km',
              if (askodoxPosInt(job['fee_paise']) > 0) '${te ? 'మీకు' : 'You get'} ${askodoxRupee(job['fee_paise'])}',
              if ('${job['item'] ?? ''}'.isNotEmpty) '${job['item']}',
            ].join(' · ')),
            const SizedBox(height: 12),
            for (final a in const ['now', '10', '20', '30', 'no']) ...[
              FilledButton(
                key: ValueKey('askodoxMyDeliveriesStepsAnswer-$id-$a'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: mine == a ? askodoxStepGreen : const Color(0xFF1F2432),
                    foregroundColor: mine == a ? AskodoxLook.sheet : const Color(0xFFBCCDE6)),
                onPressed: () => Navigator.pop(ctx, a),
                child: Text(_answerWords(a), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
            ],
          ]),
        ),
      ),
    );
    if (answer == null || !mounted) return;
    await _do(() => _repo.answerDeliveryJob(id, answer));
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'నా డెలివరీ పని' : 'My delivery work';
    final more = [
      AskodoxStepMore('askodoxMyDeliveriesStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded, () => context.push('/me/deliveries?full=1')),
    ];
    if (_error != null) return AskodoxStepScaffold(title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    final data = _data;
    if (data == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    final colour = '${askodoxPosMap(data['status'])['colour'] ?? 'unknown'}';
    final offers = askodoxPosList(data['offers']);
    final running = askodoxPosList(data['running']);
    final cash = askodoxPosList(data['cash_today']);
    final first = running.isNotEmpty ? running.first : (offers.isNotEmpty ? offers.first : null);
    return AskodoxStepScaffold(
      key: const Key('askodoxMyDeliveriesSteps'),
      title: title,
      sub: '',
      question: colour == 'unknown' ? (te ? 'ఇప్పుడు ఏ రంగు?' : 'Which are you now?') : null,
      more: more,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          AskodoxStepToggle(
            options: [for (final c in const ['free', 'busy', 'off']) (c, te ? askodoxWorkColours[c]!.$3 : askodoxWorkColours[c]!.$2)],
            value: colour,
            onChanged: (c) => _do(() => _repo.setWorkStatus(c)),
          ),
          for (final c in cash)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('${te ? 'ఈ రోజు నా దగ్గర క్యాష్' : 'Cash with me today'}: ${askodoxRupee(c['paise'])}',
                  key: const Key('askodoxMyDeliveriesStepsCash'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          const SizedBox(height: 10),
          if (first == null)
            Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(te ? 'ఇప్పుడు ఏ పనీ లేదు' : 'No work right now'))),
          for (final j in running)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxMyDeliveriesStepsJob-${j['id']}'),
              name: '${j['from']} → ${j['to']}',
              sub: '${j['label']} · ${j['shop']}',
              amount: askodoxPosInt(j['collect_paise']) > 0 ? askodoxRupee(j['collect_paise']) : '✓',
              amountColor: askodoxStepWarn,
              onTap: () => _running(j),
            ),
          if (offers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text(te ? 'మిమ్మల్ని అడుగుతున్నారు' : 'You are asked', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          for (final j in offers)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxMyDeliveriesStepsOffer-${j['id']}'),
              name: '${j['from']} → ${j['to']}',
              sub: '${j['shop']} · ${j['label']}',
              amount: askodoxPosInt(j['fee_paise']) > 0 ? askodoxRupee(j['fee_paise']) : '?',
              amountColor: askodoxStepGreen,
              onTap: () => _offer(j),
            ),
        ]),
      ),
      bottom: first == null
          ? null
          : AskodoxStepBottom(
              buttonKey: const Key('askodoxMyDeliveriesStepsOpen'),
              label: running.isNotEmpty ? (te ? 'ఈ పని తెరువు' : 'Open this job') : (te ? 'జవాబు చెప్పు' : 'Answer'),
              icon: Icons.local_shipping_outlined,
              onPressed: () => running.isNotEmpty ? _running(running.first) : _offer(offers.first),
            ),
    );
  }
}
