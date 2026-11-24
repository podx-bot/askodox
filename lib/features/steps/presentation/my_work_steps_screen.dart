import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../location/application/location_controller.dart' show deviceLocationGatewayProvider;
import '../../location/domain/geo_models.dart' show LocationPermissionStatus;
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/delivery_jobs_screens.dart' show askodoxRupee;
import '../../pos/presentation/pos_common.dart';
import 'live_face_screen.dart';
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 25): a worker's own page `/me/work`.
/// No card yet = 3 steps (what work -> name, town, 18+ -> ✓ card up). With a card: top = ONE number (things waiting for
/// me), middle = ONE list (work offered, my jobs, site postings, invites, businesses I am in), bottom = ONE big button
/// (open the first waiting thing). Card + badge, documents, edit and the old page live in ⋮. Old page stays at `?full=1`.
/// Same calls as the old page; the worker's number never leaves until they join.
class AskodoxMyWorkStepsScreen extends ConsumerStatefulWidget {
  const AskodoxMyWorkStepsScreen({super.key});

  @override
  ConsumerState<AskodoxMyWorkStepsScreen> createState() => _MyWorkStepsState();
}

const _docKinds = ['licence', 'rc', 'police_verification', 'passbook', 'nursing_certificate'];

String _docName(String k, bool te) => switch (k) {
      'licence' => te ? 'లైసెన్స్' : 'Licence',
      'rc' => 'RC',
      'police_verification' => te ? 'పోలీస్ వెరిఫికేషన్' : 'Police verification',
      'passbook' => te ? 'పాస్‌బుక్' : 'Passbook',
      'nursing_certificate' => te ? 'నర్సింగ్ సర్టిఫికేట్' : 'Nursing certificate',
      _ => k,
    };

class _MyWorkStepsState extends ConsumerState<AskodoxMyWorkStepsScreen> {
  AskodoxJson? _me;
  AskodoxJson _orders = const {};
  Object? _error;
  int _setupStep = 1;
  bool _saving = false;
  bool _adult = false;
  final Set<String> _types = {};
  final _name = TextEditingController();
  final _town = TextEditingController();

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _name.dispose();
    _town.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = await _repo.myWork();
      AskodoxJson orders = const {};
      if (me['worker'] != null) orders = await _repo.workOrders();
      if (!mounted) return;
      setState(() {
        _me = me;
        _orders = orders;
        _error = null;
      });
    } catch (e) {
      if (mounted && _me == null) setState(() => _error = e);
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

  Future<void> _saveCard() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _repo.saveMyWork({
        'name': _name.text.trim(),
        'work_types': _types.toList(),
        'town': _town.text.trim(),
        'km': 10,
        'free_when': const ['day'],
        'adult': _adult,
        'udyam': '',
        'upi': '',
      });
      if (mounted) askodoxPosSnack(context, _te ? '✓ మీ కార్డ్ పెట్టాం' : '✓ Your card is up');
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addDoc(String kind) => _do(() async {
        final file = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1200, imageQuality: 70);
        if (file == null) return null;
        final bytes = await file.readAsBytes();
        return _repo.addWorkDoc(kind, base64Encode(bytes), 'image/jpeg');
      });

  Future<void> _siteIn(String postingId) async {
    final te = _te;
    final face = await askodoxLiveFaceCheck(context, te: te);
    if (face == null || !mounted) return;
    double? lat, lon;
    try {
      final gate = ref.read(deviceLocationGatewayProvider);
      if (await gate.ensurePermission() == LocationPermissionStatus.granted) {
        final p = await gate.getCurrentPosition();
        lat = p?.latitude;
        lon = p?.longitude;
      }
    } catch (_) {}
    await _do(() => _repo.siteAttendance(postingId, lat, lon), done: te ? 'హాజరు వేశాం ✓' : 'Attendance marked ✓');
  }

  /// One sheet with a title, a line and big buttons; returns the chosen value.
  Future<String?> _ask(String title, String line, List<(String, String, bool)> buttons, String keyBase) =>
      showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              if (line.isNotEmpty) Text(line, style: const TextStyle(color: askodoxStepMuted)),
              const SizedBox(height: 12),
              for (final (value, label, main) in buttons) ...[
                main
                    ? FilledButton(
                        key: ValueKey('$keyBase-$value'),
                        style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen, minimumSize: const Size.fromHeight(54)),
                        onPressed: () => Navigator.pop(ctx, value),
                        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)))
                    : OutlinedButton(
                        key: ValueKey('$keyBase-$value'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: () => Navigator.pop(ctx, value),
                        child: Text(label)),
                const SizedBox(height: 8),
              ],
            ]),
          ),
        ),
      );

  Future<void> _offer(AskodoxJson o) async {
    final te = _te;
    final id = '${o['id']}';
    final v = await _ask(
      '${o['label'] ?? ''} ${te ? o['work_te'] ?? '' : o['work_en'] ?? ''}'.trim(),
      ['${o['authority'] ?? ''}', '${o['place'] ?? ''}', '${o['at_text'] ?? ''}'].where((x) => x.isNotEmpty).join(' · '),
      [('take', te ? 'వెళ్తా' : 'Take', true), ('no', te ? 'కుదరదు' : 'No', false)],
      'askodoxMyWorkStepsOffer-$id',
    );
    if (v == null || !mounted) return;
    await _do(() => _repo.answerWorkOrder(id, v == 'take'));
  }

  Future<void> _job(AskodoxJson o) async {
    final te = _te;
    final id = '${o['id']}';
    final share = askodoxPosInt(o['share_paise']);
    final done = '${o['status']}' == 'done';
    if (done && (share <= 0 || o['share_ack'] == true)) return;
    final v = await _ask(
      '${o['label'] ?? ''} ${te ? o['work_te'] ?? '' : o['work_en'] ?? ''}'.trim(),
      [
        '${o['place'] ?? ''}',
        if (o['money_mode'] == 'cash') te ? 'క్యాష్ – మీరే తీసుకోండి' : 'Cash – you collect',
        if (o['money_mode'] == 'upi') te ? 'డబ్బు business UPI కి' : 'Money to the business UPI',
        if (share > 0) '${te ? 'మీకు' : 'You got'} ${askodoxRupee(share)}',
      ].where((x) => x.isNotEmpty).join(' · '),
      done ? [('got', te ? 'డబ్బు అందింది' : 'Money received', true)] : [('done', te ? 'పని అయింది' : 'Job done', true)],
      'askodoxMyWorkStepsJobDo-$id',
    );
    if (v == null || !mounted) return;
    await _do(() => v == 'got' ? _repo.workShareReceived(id) : _repo.workOrderDone(id));
  }

  Future<void> _link(AskodoxJson l) async {
    final te = _te;
    final id = '${l['business_id']}';
    if ('${l['status']}' == 'invited') {
      final asks = '${l['asks'] ?? ''}';
      final v = await _ask(
        '${l['name'] ?? ''}',
        '${te ? 'మిమ్మల్ని చేర్చుకోవాలనుకుంటోంది' : 'Wants you to join'}${asks.isEmpty ? '' : ' · ${te ? 'అడుగుతున్నవి' : 'asks'}: $asks'}',
        [('join', te ? 'చేరుతా' : 'Join', true), ('no', te ? 'వద్దు' : 'No', false)],
        'askodoxMyWorkStepsInvite-$id',
      );
      if (v == null || !mounted) return;
      await _do(() => _repo.answerWorkInvite(id, v == 'join'));
      return;
    }
    final v = await _ask(
      '${l['name'] ?? ''}',
      te ? 'మీరు ఇక్కడ చేరారు' : 'You joined here',
      [('code', te ? 'Documents చూపించే కోడ్' : 'Code to show documents', true), ('leave', te ? 'వదిలేయి' : 'Leave', false)],
      'askodoxMyWorkStepsLink-$id',
    );
    if (v == null || !mounted) return;
    if (v == 'leave') {
      final sure = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(te ? '${l['name']} వదిలేయాలా?' : 'Leave ${l['name']}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(te ? 'వద్దు' : 'No')),
            FilledButton(
                key: const Key('askodoxMyWorkStepsLeaveYes'),
                onPressed: () => Navigator.pop(d, true),
                child: Text(te ? 'వదిలేయి' : 'Leave')),
          ],
        ),
      );
      if (sure == true && mounted) await _do(() => _repo.leaveWork(id));
      return;
    }
    try {
      final r = await _repo.workDocCode(id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(te ? 'Documents చూపించే కోడ్' : 'Code to show documents'),
          content: Text('${r['code']}\n${te ? '${r['minutes']} నిమిషాలు, ఒక్కసారే' : '${r['minutes']} minutes, one time'}',
              key: const Key('askodoxMyWorkStepsDocCode'),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4)),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(te ? 'సరే' : 'OK'))],
        ),
      );
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
    }
  }

  Future<void> _cardSheet(AskodoxJson me) async {
    final te = _te;
    final w = askodoxPosMap(me['worker']);
    final badge = askodoxPosMap(me['badge']);
    final need = askodoxPosMap(badge['need']);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          key: const Key('askodoxMyWorkStepsCardSheet'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${w['name'] ?? ''}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text([
              askodoxPosList(w['work_types']).map(_work).join(', '),
              '${w['jobs'] ?? 0} ${te ? 'పనులు' : 'jobs'}',
              if (w['rating'] != null) '${w['rating']} ⭐',
            ].join(' · ')),
            const SizedBox(height: 14),
            Text(badge['has'] == true ? (te ? '✓ స్వతంత్రుడు' : '✓ Independent') : (te ? 'స్వతంత్రుడు అవ్వాలంటే' : 'To become independent'),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            for (final e in askodoxPosMap(badge['steps']).entries)
              Text('${e.value == true ? '✓' : '○'} ${switch (e.key) {
                'days' => te ? '${need['days']} రోజులు ఒక business కింద' : '${need['days']} days under a business',
                'jobs' => te ? '${need['jobs']} పనులు' : '${need['jobs']} jobs',
                'rating' => te ? 'రేటింగ్ ${need['rating']}+' : 'Rating ${need['rating']}+',
                'complaints' => te ? 'ఫిర్యాదులు లేవు' : 'No open complaints',
                _ => te ? 'మీ Udyam నంబర్' : 'Your Udyam number',
              }}'),
            if ('${me['reject_note'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${me['reject_note']}', style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412))),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('askodoxMyWorkStepsEdit'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/me/work?full=1').then((_) => _load());
              },
              icon: const Icon(Icons.edit_rounded),
              label: Text(te ? 'కార్డ్ మార్చు (దూరం, సమయం, UPI)' : 'Change card (distance, time, UPI)'),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _docsSheet(AskodoxJson me) async {
    final te = _te;
    final have = {for (final d in askodoxPosList(me['docs'])) '${d['kind']}'};
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(te ? 'నా documents' : 'My documents', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text(te ? 'మీరు ఇచ్చే కోడ్ తోనే చూస్తారు. ఫోటో తీయడానికి నొక్కండి.' : 'Seen only with your code. Tap to take a photo.',
                style: const TextStyle(color: askodoxStepMuted)),
            const SizedBox(height: 8),
            for (final k in _docKinds)
              ListTile(
                key: ValueKey('askodoxMyWorkStepsDoc-$k'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(have.contains(k) ? Icons.check_circle_rounded : Icons.photo_camera_rounded,
                    color: have.contains(k) ? askodoxStepGreen : askodoxStepMuted),
                title: Text(_docName(k, te), style: const TextStyle(fontWeight: FontWeight.w800)),
                onTap: () => Navigator.pop(ctx, k),
              ),
          ]),
        ),
      ),
    );
    if (kind != null && mounted) await _addDoc(kind);
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'నేను పని చేస్తా' : 'I want work';
    final old = AskodoxStepMore('askodoxMyWorkStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
        () => context.push('/me/work?full=1').then((_) => _load()));
    if (_error != null) return AskodoxStepScaffold(title: title, more: [old], body: AskodoxPosError(error: _error!, onRetry: _load));
    final me = _me;
    if (me == null) return AskodoxStepScaffold(title: title, more: [old], body: const Center(child: CircularProgressIndicator()));
    if (me['worker'] == null) return _setup(me, title, old);
    return _overview(me, title, old);
  }

  // ------------------------------------------------------------------ no card yet: 3 steps
  Widget _setup(AskodoxJson me, String title, AskodoxStepMore old) {
    final te = _te;
    if (_setupStep == 1) {
      return AskodoxStepScaffold(
        key: const Key('askodoxMyWorkSteps'),
        title: title,
        step: 1,
        question: te ? 'ఏ పని చేస్తారు?' : 'What work do you do?',
        hint: te ? 'ఒకటి లేదా ఎక్కువ ఎంచుకోండి' : 'Pick one or more',
        more: [old],
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          for (final t in askodoxPosList(me['work_types']))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AskodoxStepChoice(
                key: ValueKey('askodoxMyWorkStepsType-${t['key']}'),
                icon: _types.contains('${t['key']}') ? Icons.check_circle_rounded : Icons.work_outline_rounded,
                color: askodoxStepGreen,
                title: _work(t),
                sub: '',
                selected: _types.contains('${t['key']}'),
                onTap: () => setState(() => _types.contains('${t['key']}') ? _types.remove('${t['key']}') : _types.add('${t['key']}')),
              ),
            ),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxMyWorkStepsNext'),
          label: te ? 'తర్వాత' : 'Next',
          icon: Icons.arrow_forward_rounded,
          onPressed: _types.isEmpty ? null : () => setState(() => _setupStep = 2),
        ),
      );
    }
    return AskodoxStepScaffold(
      key: const Key('askodoxMyWorkSteps'),
      title: title,
      step: 2,
      question: te ? 'మీ పేరు, ఊరు?' : 'Your name and town?',
      hint: te ? 'Businesses కి కార్డ్ మాత్రమే, ఫోన్ నంబర్ కాదు' : 'Businesses see your card, never your number',
      onBack: () => setState(() => _setupStep = 1),
      more: [old],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        TextField(
            key: const Key('askodoxMyWorkStepsName'),
            controller: _name,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(labelText: te ? 'పేరు' : 'Name', border: const OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(
            key: const Key('askodoxMyWorkStepsTown'),
            controller: _town,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(labelText: te ? 'ఊరు / ఏరియా' : 'Town / area', border: const OutlineInputBorder())),
        CheckboxListTile(
          key: const Key('askodoxMyWorkStepsAdult'),
          contentPadding: EdgeInsets.zero,
          value: _adult,
          onChanged: (v) => setState(() => _adult = v == true),
          title: Text(te ? 'నాకు 18 ఏళ్ళు నిండాయి' : 'I am 18 or older', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(te ? 'పిల్లలతో పని చేయించడం చట్ట విరుద్ధం' : 'Child labour is illegal'),
        ),
        Text(
            te
                ? 'దూరం 10 km, పగలు. ఇవి తర్వాత ⋮ లో మార్చొచ్చు.'
                : 'Distance 10 km, day time. Change these later from ⋮.',
            style: const TextStyle(color: askodoxStepMuted)),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxMyWorkStepsSave'),
        label: te ? 'నా కార్డ్ పెట్టు' : 'Put up my card',
        icon: Icons.badge_outlined,
        busy: _saving,
        onPressed: _adult && _name.text.trim().isNotEmpty && _types.isNotEmpty ? _saveCard : null,
      ),
    );
  }

  // ------------------------------------------------------------------ with a card: number + list + one button
  Widget _overview(AskodoxJson me, String title, AskodoxStepMore old) {
    final te = _te;
    final offers = askodoxPosList(_orders['offers']);
    final mine = askodoxPosList(_orders['mine']);
    final open = [
      for (final o in mine)
        if ('${o['status']}' != 'done' || (askodoxPosInt(o['share_paise']) > 0 && o['share_ack'] != true)) o
    ];
    final closed = [for (final o in mine) if (!open.contains(o)) o];
    final postings = askodoxPosList(me['postings']);
    final links = askodoxPosList(me['links']);
    final invites = [for (final l in links) if ('${l['status']}' == 'invited') l];
    final joined = [for (final l in links) if ('${l['status']}' != 'invited') l];
    final waiting = offers.length + open.length + invites.length;
    final more = [
      AskodoxStepMore('askodoxMyWorkStepsCard', te ? 'నా కార్డ్ & badge' : 'My card & badge', Icons.badge_outlined, () => _cardSheet(me)),
      AskodoxStepMore('askodoxMyWorkStepsDocs', te ? 'నా documents' : 'My documents', Icons.folder_shared_outlined, () => _docsSheet(me)),
      old,
    ];
    Widget head(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        );
    String work(AskodoxJson o) => '${o['label'] ?? ''} ${te ? o['work_te'] ?? '' : o['work_en'] ?? ''}'.trim();
    VoidCallback? first;
    String firstLabel = '';
    if (offers.isNotEmpty) {
      first = () => _offer(offers.first);
      firstLabel = te ? 'పనికి జవాబు చెప్పు' : 'Answer the work';
    } else if (open.isNotEmpty) {
      first = () => _job(open.first);
      firstLabel = te ? 'నా పని తెరువు' : 'Open my job';
    } else if (invites.isNotEmpty) {
      first = () => _link(invites.first);
      firstLabel = te ? 'ఆహ్వానానికి జవాబు' : 'Answer the invite';
    } else if (postings.isNotEmpty) {
      first = () => _siteIn('${postings.first['id']}');
      firstLabel = te ? 'హాజరు వేయి' : 'Check in';
    }
    return AskodoxStepScaffold(
      key: const Key('askodoxMyWorkSteps'),
      title: title,
      more: more,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          AskodoxStepBigNumber(
            '$waiting',
            key: const Key('askodoxMyWorkStepsWaiting'),
            label: te ? 'మీ జవాబు కోసం ఎదురుచూస్తున్నవి' : 'Waiting for your answer',
            color: waiting > 0 ? askodoxStepWarn : askodoxStepGreen,
          ),
          if (waiting == 0 && postings.isEmpty && joined.isEmpty && closed.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: Text(
                      te ? 'ఇంకా ఎవరూ అడగలేదు. మీ కార్డ్ దగ్గరి businesses కి వెళ్ళింది.' : 'No invites yet. Your card reached nearby businesses.',
                      textAlign: TextAlign.center)),
            ),
          if (offers.isNotEmpty) head(te ? 'పని అడుగుతున్నారు' : 'Work offered'),
          for (final o in offers)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxMyWorkStepsOfferRow-${o['id']}'),
              name: work(o),
              sub: ['${o['authority'] ?? ''}', '${o['place'] ?? ''}', '${o['at_text'] ?? ''}'].where((x) => x.isNotEmpty).join(' · '),
              amount: '?',
              amountColor: askodoxStepWarn,
              onTap: () => _offer(o),
            ),
          if (open.isNotEmpty || closed.isNotEmpty) head(te ? 'నా పనులు' : 'My jobs'),
          for (final o in [...open, ...closed])
            AskodoxStepPersonRow(
              key: ValueKey('askodoxMyWorkStepsJob-${o['id']}'),
              name: work(o),
              sub: '${o['place'] ?? ''}',
              amount: '${o['status']}' == 'done'
                  ? (open.contains(o) ? askodoxRupee(o['share_paise']) : '✓')
                  : (te ? 'చేయాలి' : 'To do'),
              amountColor: open.contains(o) ? askodoxStepWarn : askodoxStepDone,
              onTap: () => _job(o),
            ),
          if (postings.isNotEmpty) head(te ? 'నా సైట్ డ్యూటీ' : 'My site duty'),
          for (final p in postings)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxMyWorkStepsPosting-${p['id']}'),
              name: '${p['site'] ?? ''}',
              sub: '${p['agency'] ?? ''} · ${p['shift'] == 'night' ? (te ? 'రాత్రి' : 'night') : (te ? 'పగలు' : 'day')}',
              amount: te ? 'హాజరు' : 'In',
              amountColor: askodoxStepGreen,
              onTap: () => _siteIn('${p['id']}'),
            ),
          if (invites.isNotEmpty || joined.isNotEmpty) head('Businesses'),
          for (final l in [...invites, ...joined])
            AskodoxStepPersonRow(
              key: ValueKey('askodoxMyWorkStepsLinkRow-${l['business_id']}'),
              name: '${l['name'] ?? ''}',
              sub: '${l['status']}' == 'invited' ? (te ? 'మిమ్మల్ని అడుగుతోంది' : 'Wants you') : (te ? 'చేరారు' : 'Joined'),
              amount: '${l['status']}' == 'invited' ? '?' : '✓',
              amountColor: '${l['status']}' == 'invited' ? askodoxStepWarn : askodoxStepDone,
              onTap: () => _link(l),
            ),
        ]),
      ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxMyWorkStepsOpen'),
        label: first == null ? (te ? 'నా కార్డ్ చూడు' : 'See my card') : firstLabel,
        icon: first == null ? Icons.badge_outlined : Icons.touch_app_rounded,
        outline: first == null,
        onPressed: first ?? () => _cardSheet(me),
      ),
    );
  }
}
