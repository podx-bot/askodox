import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../location/application/location_controller.dart' show deviceLocationGatewayProvider;
import '../../location/domain/geo_models.dart' show LocationPermissionStatus;
import '../../steps/presentation/live_face_screen.dart';
import '../data/pos_repository.dart';
import 'delivery_jobs_screens.dart' show askodoxRupee;
import 'pos_common.dart';

/// Workers under an authority (owner plan 2026-11-24, design 73xSUHd4dbqVsLgRfCuX9X, steps 3-6).
/// `/me/work` = the worker; `/pos/:id/team` = the authority; `/hire` = a customer.

List<AskodoxJson> _l(Object? v) => askodoxPosList(v);
String _s(Object? v) => v == null ? '' : '$v';

Future<void> _guard(BuildContext context, Future<void> Function() run) async {
  try {
    await run();
  } on AskodoxPosException catch (e) {
    if (context.mounted) askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
  }
}

Widget _section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
      child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
    );

const _docKinds = ['licence', 'rc', 'police_verification', 'passbook', 'nursing_certificate'];

String _docName(String k, bool te) => switch (k) {
      'licence' => te ? 'లైసెన్స్' : 'Licence',
      'rc' => 'RC',
      'police_verification' => te ? 'పోలీస్ వెరిఫికేషన్' : 'Police verification',
      'passbook' => te ? 'పాస్‌బుక్' : 'Passbook',
      'nursing_certificate' => te ? 'నర్సింగ్ సర్టిఫికేట్' : 'Nursing certificate',
      _ => k,
    };

// ============================================================================ the worker
class AskodoxMyWorkScreen extends ConsumerStatefulWidget {
  const AskodoxMyWorkScreen({super.key});

  @override
  ConsumerState<AskodoxMyWorkScreen> createState() => _MyWorkState();
}

class _MyWorkState extends ConsumerState<AskodoxMyWorkScreen> {
  AskodoxJson? _me;
  AskodoxJson _orders = const {};
  Object? _error;
  bool _editing = false;
  final _name = TextEditingController();
  final _town = TextEditingController();
  final _udyam = TextEditingController();
  final _upi = TextEditingController();
  final Set<String> _types = {};
  final Set<String> _when = {'day'};
  double _km = 10;
  bool _adult = false;

  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [_name, _town, _udyam, _upi]) {
      c.dispose();
    }
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
        final w = askodoxPosMap(me['worker']);
        if (w.isNotEmpty && !_editing) {
          _name.text = _s(w['name']);
          _town.text = _s(w['town']);
          _udyam.text = _s(w['udyam']);
          _upi.text = _s(w['upi']);
          _km = ((w['km'] as num?) ?? 10).toDouble();
          _types
            ..clear()
            ..addAll(_l(w['work_types']).map((t) => _s(t['key'])));
          _when
            ..clear()
            ..addAll(((w['free_when'] as List?) ?? const ['day']).map((x) => '$x'));
          _adult = true;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() => _guard(context, () async {
        await _repo.saveMyWork({
          'name': _name.text.trim(),
          'work_types': _types.toList(),
          'town': _town.text.trim(),
          'km': _km.round(),
          'free_when': _when.toList(),
          'adult': _adult,
          'udyam': _udyam.text.trim(),
          'upi': _upi.text.trim(),
        });
        _editing = false;
        await _load();
      });

  Future<void> _addDoc(String kind) => _guard(context, () async {
        final file = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1200, imageQuality: 70);
        if (file == null) return;
        final bytes = await file.readAsBytes();
        await _repo.addWorkDoc(kind, base64Encode(bytes), 'image/jpeg');
        await _load();
      });

  Future<void> _siteIn(String postingId, bool te) => _guard(context, () async {
        final face = await askodoxLiveFaceCheck(context, te: te);
        if (face == null) return;
        double? lat, lon;
        try {
          final gate = ref.read(deviceLocationGatewayProvider);
          if (await gate.ensurePermission() == LocationPermissionStatus.granted) {
            final p = await gate.getCurrentPosition();
            lat = p?.latitude;
            lon = p?.longitude;
          }
        } catch (_) {}
        await _repo.siteAttendance(postingId, lat, lon);
        if (mounted) askodoxPosSnack(context, te ? 'హాజరు వేశాం ✓' : 'Attendance marked ✓');
      });

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final me = _me;
    return Scaffold(
      key: const Key('askodoxMyWork'),
      appBar: AppBar(title: Text(te ? 'నేను పని చేస్తా' : 'I want work')),
      body: me == null
          ? (_error == null ? const Center(child: CircularProgressIndicator()) : AskodoxPosError(error: _error!, onRetry: _load))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (me['worker'] == null || _editing) ..._form(me, te) else ..._overview(me, te),
              ]),
            ),
    );
  }

  List<Widget> _form(AskodoxJson me, bool te) => [
        TextField(
            key: const Key('askodoxWorkName'),
            controller: _name,
            decoration: InputDecoration(labelText: te ? 'పేరు' : 'Name', border: const OutlineInputBorder())),
        _section(te ? 'ఏ పని చేస్తారు?' : 'What work?'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in _l(me['work_types']))
            FilterChip(
              key: ValueKey('askodoxWorkType-${t['key']}'),
              selected: _types.contains(_s(t['key'])),
              label: Text(te && _s(t['te']).isNotEmpty ? _s(t['te']) : _s(t['en'])),
              onSelected: (on) => setState(() => on ? _types.add(_s(t['key'])) : _types.remove(_s(t['key']))),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
            controller: _town,
            decoration: InputDecoration(labelText: te ? 'ఊరు / ఏరియా' : 'Town / area', border: const OutlineInputBorder())),
        Row(children: [
          Text('${_km.round()} km', style: const TextStyle(fontWeight: FontWeight.w800)),
          Expanded(child: Slider(value: _km, min: 1, max: 50, divisions: 49, onChanged: (v) => setState(() => _km = v))),
        ]),
        Wrap(spacing: 8, children: [
          for (final w in const ['day', 'night', 'sundays'])
            FilterChip(
              selected: _when.contains(w),
              label: Text(switch (w) {
                'day' => te ? 'పగలు' : 'Day',
                'night' => te ? 'రాత్రి' : 'Night',
                _ => te ? 'ఆదివారాలు' : 'Sundays',
              }),
              onSelected: (on) => setState(() => on ? _when.add(w) : _when.remove(w)),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
            controller: _udyam,
            decoration: InputDecoration(
                labelText: te ? 'Udyam నంబర్ (ఉంటే)' : 'Udyam number (if you have one)', border: const OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
            controller: _upi,
            decoration: InputDecoration(
                labelText: te ? 'మీ UPI ID (స్వతంత్రుడు అయ్యాక)' : 'Your UPI ID (once independent)',
                border: const OutlineInputBorder())),
        CheckboxListTile(
          key: const Key('askodoxWorkAdult'),
          contentPadding: EdgeInsets.zero,
          value: _adult,
          onChanged: (v) => setState(() => _adult = v == true),
          title: Text(te ? 'నాకు 18 ఏళ్ళు నిండాయి' : 'I am 18 or older'),
          subtitle: Text(te ? 'పిల్లలతో పని చేయించడం చట్ట విరుద్ధం' : 'Child labour is illegal'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 54,
          child: FilledButton(
            key: const Key('askodoxWorkSave'),
            onPressed: _adult && _types.isNotEmpty ? _save : null,
            child: Text(te ? 'నా కార్డ్ పెట్టు' : 'Put up my card'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              te
                  ? 'మీ కార్డ్ (పేరు, పని, ఊరు, రేటింగ్) మాత్రమే businesses కి వెళ్తుంది. ఫోన్ నంబర్ మీరు చేరిన తర్వాతే.'
                  : 'Only your card (name, work, town, rating) goes to businesses. Your number only after you join.',
              style: const TextStyle(color: Color(0xFF64748B))),
        ),
      ];

  List<Widget> _overview(AskodoxJson me, bool te) {
    final w = askodoxPosMap(me['worker']);
    final badge = askodoxPosMap(me['badge']);
    final links = _l(me['links']);
    final docs = {for (final d in _l(me['docs'])) _s(d['kind'])};
    final offers = _l(_orders['offers']);
    final mine = _l(_orders['mine']);
    return [
      Card(
        child: ListTile(
          key: const Key('askodoxWorkCard'),
          title: Text(_s(w['name']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          subtitle: Text([
            _l(w['work_types']).map((t) => te && _s(t['te']).isNotEmpty ? _s(t['te']) : _s(t['en'])).join(', '),
            '${w['jobs'] ?? 0} ${te ? 'పనులు' : 'jobs'}',
            if (w['rating'] != null) '${w['rating']} ⭐',
          ].join(' · ')),
          trailing: IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => setState(() => _editing = true)),
        ),
      ),
      Container(
        key: const Key('askodoxWorkBadge'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: badge['has'] == true ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(badge['has'] == true ? (te ? '✓ స్వతంత్రుడు' : '✓ Independent') : (te ? 'స్వతంత్రుడు అవ్వాలంటే' : 'To become independent'),
              style: const TextStyle(fontWeight: FontWeight.w900)),
          for (final e in askodoxPosMap(badge['steps']).entries)
            Text('${e.value == true ? '✓' : '○'} ${switch (e.key) {
              'days' => te ? '${askodoxPosMap(badge['need'])['days']} రోజులు ఒక business కింద' : '${askodoxPosMap(badge['need'])['days']} days under a business',
              'jobs' => te ? '${askodoxPosMap(badge['need'])['jobs']} పనులు' : '${askodoxPosMap(badge['need'])['jobs']} jobs',
              'rating' => te ? 'రేటింగ్ ${askodoxPosMap(badge['need'])['rating']}+' : 'Rating ${askodoxPosMap(badge['need'])['rating']}+',
              'complaints' => te ? 'ఫిర్యాదులు లేవు' : 'No open complaints',
              _ => te ? 'మీ Udyam నంబర్' : 'Your Udyam number',
            }}'),
          const SizedBox(height: 6),
          Text(_s(me['reject_note']), style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412))),
        ]),
      ),
      if (offers.isNotEmpty) _section(te ? 'పని అడుగుతున్నారు' : 'Work offered'),
      for (final o in offers)
        Card(
          child: ListTile(
            key: ValueKey('askodoxWorkOffer-${o['id']}'),
            title: Text('${o['label']} ${te ? o['work_te'] : o['work_en']} · ${o['authority'] ?? ''}'),
            subtitle: Text([_s(o['place']), _s(o['at_text'])].where((x) => x.isNotEmpty).join(' · ')),
            trailing: Wrap(spacing: 6, children: [
              FilledButton(
                key: ValueKey('askodoxWorkTake-${o['id']}'),
                onPressed: () => _guard(context, () async {
                  await _repo.answerWorkOrder(_s(o['id']), true);
                  await _load();
                }),
                child: Text(te ? 'వెళ్తా' : 'Take'),
              ),
              OutlinedButton(
                onPressed: () => _guard(context, () async {
                  await _repo.answerWorkOrder(_s(o['id']), false);
                  await _load();
                }),
                child: Text(te ? 'కుదరదు' : 'No'),
              ),
            ]),
          ),
        ),
      if (mine.isNotEmpty) _section(te ? 'నా పనులు' : 'My jobs'),
      for (final o in mine)
        Card(
          child: ListTile(
            key: ValueKey('askodoxWorkMine-${o['id']}'),
            title: Text('${o['label']} ${te ? o['work_te'] : o['work_en']} · ${o['place'] ?? ''}'),
            subtitle: Text([
              if (o['money_mode'] == 'cash') te ? 'క్యాష్ – మీరే తీసుకోండి' : 'Cash – you collect',
              if (o['money_mode'] == 'upi') te ? 'డబ్బు business UPI కి' : 'Money to the business UPI',
              if (((o['share_paise'] as num?) ?? 0) > 0) '${te ? 'మీకు' : 'You got'} ${askodoxRupee(o['share_paise'])}',
            ].join(' · ')),
            trailing: o['status'] == 'done'
                ? (((o['share_paise'] as num?) ?? 0) > 0 && o['share_ack'] != true
                    ? TextButton(
                        key: ValueKey('askodoxWorkShareOk-${o['id']}'),
                        onPressed: () => _guard(context, () async {
                          await _repo.workShareReceived(_s(o['id']));
                          await _load();
                        }),
                        child: Text(te ? 'అందింది' : 'Received'),
                      )
                    : const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)))
                : FilledButton(
                    key: ValueKey('askodoxWorkDone-${o['id']}'),
                    onPressed: () => _guard(context, () async {
                      await _repo.workOrderDone(_s(o['id']));
                      await _load();
                    }),
                    child: Text(te ? 'అయింది' : 'Done'),
                  ),
          ),
        ),
      for (final p in _l(me['postings']))
        Card(
          child: ListTile(
            key: ValueKey('askodoxWorkPosting-${p['id']}'),
            title: Text('${p['site']} · ${p['shift'] == 'night' ? (te ? 'రాత్రి' : 'night') : (te ? 'పగలు' : 'day')}'),
            subtitle: Text('${p['agency']} · ${p['month']}'),
            trailing: FilledButton(onPressed: () => _siteIn(_s(p['id']), te), child: Text(te ? 'హాజరు' : 'Check in')),
          ),
        ),
      _section(te ? 'నేను చేరిన businesses' : 'Businesses I am in'),
      if (links.isEmpty)
        Text(te ? 'ఇంకా ఎవరూ అడగలేదు. మీ కార్డ్ దగ్గరి businesses కి వెళ్ళింది.' : 'No invites yet. Your card reached nearby businesses.'),
      for (final l in links)
        Card(
          child: ListTile(
            key: ValueKey('askodoxWorkLink-${l['business_id']}'),
            title: Text(_s(l['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(l['status'] == 'invited'
                ? '${te ? 'చేర్చుకోవాలనుకుంటోంది' : 'wants you'}${_s(l['asks']).isEmpty ? '' : ' · ${te ? 'అడుగుతున్నవి' : 'asks'}: ${l['asks']}'}'
                : (te ? 'చేరారు' : 'Joined')),
            trailing: l['status'] == 'invited'
                ? Wrap(spacing: 6, children: [
                    FilledButton(
                      key: ValueKey('askodoxWorkJoin-${l['business_id']}'),
                      onPressed: () => _guard(context, () async {
                        await _repo.answerWorkInvite(_s(l['business_id']), true);
                        await _load();
                      }),
                      child: Text(te ? 'చేరుతా' : 'Join'),
                    ),
                    OutlinedButton(
                      onPressed: () => _guard(context, () async {
                        await _repo.answerWorkInvite(_s(l['business_id']), false);
                        await _load();
                      }),
                      child: Text(te ? 'వద్దు' : 'No'),
                    ),
                  ])
                : PopupMenuButton<String>(
                    onSelected: (v) => _guard(context, () async {
                      if (v == 'code') {
                        final r = await _repo.workDocCode(_s(l['business_id']));
                        if (!mounted) return;
                        await showDialog<void>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(te ? 'Documents చూపించే కోడ్' : 'Code to show documents'),
                            content: Text('${r['code']}\n${te ? '${r['minutes']} నిమిషాలు, ఒక్కసారే' : '${r['minutes']} minutes, one time'}',
                                key: const Key('askodoxWorkDocCode'),
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4)),
                          ),
                        );
                      } else {
                        await _repo.leaveWork(_s(l['business_id']));
                        await _load();
                      }
                    }),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'code', child: Text(te ? 'Documents కోడ్' : 'Documents code')),
                      PopupMenuItem(value: 'leave', child: Text(te ? 'వదిలేయి' : 'Leave')),
                    ],
                  ),
          ),
        ),
      _section(te ? 'నా documents (మీ కోడ్ తోనే చూస్తారు)' : 'My documents (seen only with your code)'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in _docKinds)
          ActionChip(
            key: ValueKey('askodoxWorkDoc-$k'),
            avatar: Icon(docs.contains(k) ? Icons.check_circle_rounded : Icons.photo_camera_rounded, size: 18),
            label: Text(_docName(k, te)),
            onPressed: () => _addDoc(k),
          ),
      ]),
    ];
  }
}

// ============================================================================ the authority
class AskodoxAuthorityTeamScreen extends ConsumerStatefulWidget {
  const AskodoxAuthorityTeamScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<AskodoxAuthorityTeamScreen> createState() => _TeamState();
}

class _TeamState extends ConsumerState<AskodoxAuthorityTeamScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  AskodoxJson? _data;
  List<AskodoxJson> _cards = const [];
  List<AskodoxJson> _orders = const [];
  Object? _error;
  final _gst = TextEditingController();
  final _udyam = TextEditingController();
  final _address = TextEditingController();
  bool _agency = false;
  String _money = 'cash';
  final Map<String, TextEditingController> _prices = {};

  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);
  String get _id => widget.businessId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_gst, _udyam, _address, ..._prices.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _repo.workforce(_id);
      var cards = const <AskodoxJson>[];
      var orders = const <AskodoxJson>[];
      if (data['can_browse'] == true) {
        cards = _l((await _repo.workerCards(_id))['cards']);
        orders = _l((await _repo.workforceOrders(_id))['orders']);
      }
      if (!mounted) return;
      final a = askodoxPosMap(data['authority']);
      setState(() {
        _data = data;
        _cards = cards;
        _orders = orders;
        _error = null;
        if (a.isNotEmpty) {
          _gst.text = _s(a['gstin']);
          _udyam.text = _s(a['udyam']);
          _address.text = _s(a['address']);
          _agency = a['agency'] == 1 || a['agency'] == true;
          _money = _s(a['assigned_money']).isEmpty ? 'cash' : _s(a['assigned_money']);
        }
        for (final t in _l(data['work_types'])) {
          final c = _prices.putIfAbsent(_s(t['key']), TextEditingController.new);
          if (c.text.isEmpty && t['price_paise'] != null) c.text = '${(t['price_paise'] as num) ~/ 100}';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final data = _data;
    return Scaffold(
      key: const Key('askodoxAuthorityTeam'),
      appBar: AppBar(
        title: Text(te ? 'పని వాళ్ళు & టీమ్' : 'Workers & team'),
        bottom: TabBar(controller: _tabs, isScrollable: true, tabs: [
          Tab(text: te ? 'టీమ్' : 'Team'),
          Tab(text: te ? 'కొత్తవాళ్ళు' : 'Find'),
          Tab(text: te ? 'ఆర్డర్లు' : 'Orders'),
          Tab(text: te ? 'రిజిస్ట్రేషన్' : 'Registration'),
        ]),
      ),
      body: data == null
          ? (_error == null ? const Center(child: CircularProgressIndicator()) : AskodoxPosError(error: _error!, onRetry: _load))
          : TabBarView(controller: _tabs, children: [_team(data, te), _find(data, te), _ordersTab(te), _registration(data, te)]),
    );
  }

  Widget _team(AskodoxJson data, bool te) {
    final team = _l(data['team']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(_s(data['adding_note']), style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412))),
      if (team.isEmpty) Padding(padding: const EdgeInsets.only(top: 24), child: Text(te ? 'ఇంకా ఎవరూ లేరు' : 'Nobody yet')),
      for (final w in team)
        Card(
          child: ExpansionTile(
            key: ValueKey('askodoxTeamWorker-${w['user']}'),
            title: Text('${w['name']} · ${w['status'] == 'joined' ? (te ? 'చేరారు' : 'joined') : (te ? 'అడిగాం' : 'invited')}'),
            subtitle: Text([
              _l(w['work_types']).map((t) => te && _s(t['te']).isNotEmpty ? _s(t['te']) : _s(t['en'])).join(', '),
              '${w['jobs'] ?? 0} ${te ? 'పనులు' : 'jobs'}',
              if (w['rating'] != null) '${w['rating']} ⭐',
            ].join(' · ')),
            children: [
              if (_s(w['phone']).isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.call_rounded),
                  title: Text(_s(w['phone'])),
                  onTap: () => launchUrl(Uri(scheme: 'tel', path: _s(w['phone'])), mode: LaunchMode.externalApplication),
                ),
              for (final c in _l(w['suggested_checks']))
                CheckboxListTile(
                  value: askodoxPosMap(w['checks'])[_s(c['key'])] == true,
                  title: Text(te ? _s(c['te']) : _s(c['en'])),
                  onChanged: (v) => _guard(context, () async {
                    final checks = {
                      for (final e in askodoxPosMap(w['checks']).entries) e.key: e.value == true,
                      _s(c['key']): v == true,
                    };
                    await _repo.setWorkerChecks(_id, _s(w['user']), checks);
                    await _load();
                  }),
                ),
              if (w['status'] == 'joined')
                OverflowBar(alignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    key: ValueKey('askodoxTeamDocs-${w['user']}'),
                    icon: const Icon(Icons.lock_open_rounded),
                    label: Text(te ? 'Documents (కోడ్)' : 'Documents (code)'),
                    onPressed: () => _openDocs(_s(w['user']), te),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.place_rounded),
                    label: Text(te ? 'నెలవారీ పోస్టింగ్' : 'Monthly posting'),
                    onPressed: () => _post(_s(w['user']), te),
                  ),
                  TextButton(
                    onPressed: () => _guard(context, () async {
                      await _repo.removeWorker(_id, _s(w['user']));
                      await _load();
                    }),
                    child: Text(te ? 'తీసేయి' : 'Remove'),
                  ),
                ]),
            ],
          ),
        ),
    ]);
  }

  Future<void> _openDocs(String worker, bool te) async {
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(te ? 'Worker చెప్పిన 6 అంకెల కోడ్' : "The worker's 6-digit code"),
        content: TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog, true), child: Text(te ? 'చూడు' : 'View'))],
      ),
    );
    if (ok != true || !mounted) return;
    await _guard(context, () async {
      final opened = await _repo.openWorkerDocs(_id, worker, code.text.trim());
      final images = <(String, List<int>)>[];
      for (final d in _l(opened['docs'])) {
        final img = await _repo.workerDoc(_id, worker, _s(d['id']));
        images.add((_docName(_s(d['kind']), te), base64Decode(_s(img['image_base64']))));
      }
      if (!mounted) return;
      // View only: shown here, no save / share button; the code works once and the view ends in 10 minutes.
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(te ? 'చూడటానికి మాత్రమే' : 'View only')),
          body: ListView(children: [
            for (final (name, bytes) in images) ...[
              Padding(padding: const EdgeInsets.all(12), child: Text(name, style: const TextStyle(fontWeight: FontWeight.w900))),
              Image.memory(Uint8List.fromList(bytes)),
            ],
          ]),
        ),
      ));
    });
    code.dispose();
  }

  Future<void> _post(String worker, bool te) async {
    final site = TextEditingController();
    var night = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, set) => AlertDialog(
          title: Text(te ? 'నెలవారీ పోస్టింగ్' : 'Monthly posting'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: site, decoration: InputDecoration(labelText: te ? 'సైట్ / కంపెనీ' : 'Site / company')),
            SwitchListTile(
                value: night, onChanged: (v) => set(() => night = v), title: Text(te ? 'రాత్రి shift' : 'Night shift')),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog, true), child: Text(te ? 'పెట్టు' : 'Post'))],
        ),
      ),
    );
    if (ok == true && site.text.trim().isNotEmpty && mounted) {
      await _guard(context, () async {
        await _repo.addPosting(_id, {'worker': worker, 'site': site.text.trim(), 'shift': night ? 'night' : 'day'});
        if (mounted) askodoxPosSnack(context, te ? 'పోస్టింగ్ పెట్టాం ✓' : 'Posted ✓');
      });
    }
    site.dispose();
  }

  Widget _find(AskodoxJson data, bool te) {
    if (data['can_browse'] != true) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text(te
            ? 'GST లేదా Udyam నంబర్ ఉన్న businesses మాత్రమే కొత్త పని వాళ్ళను చూడగలవు. మీ సిబ్బందిని Staff పేజీలో ఫోన్ నంబర్ తో చేర్చుకోవచ్చు.'
            : 'Only businesses with a GST or Udyam number can find new workers. Add your own staff by phone on the Staff page.'),
        const SizedBox(height: 12),
        Text(_s(data['udyam_help']), style: const TextStyle(color: Color(0xFF15803D))),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (_cards.isEmpty) Text(te ? 'మీ ఏరియాలో ఇంకా కార్డులు లేవు' : 'No cards in your area yet'),
      for (final c in _cards)
        Card(
          child: ListTile(
            key: ValueKey('askodoxWorkerCard-${c['user']}'),
            title: Text('${c['name']}${c['badge'] == true ? ' · స్వతంత్రుడు' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text([
              _l(c['work_types']).map((t) => te && _s(t['te']).isNotEmpty ? _s(t['te']) : _s(t['en'])).join(', '),
              _s(c['town']),
              '${c['jobs'] ?? 0} ${te ? 'పనులు' : 'jobs'}',
              if (c['rating'] != null) '${c['rating']} ⭐',
              if (c['km_away'] != null) '${c['km_away']} km',
            ].where((x) => x.isNotEmpty).join(' · ')),
            trailing: FilledButton(
              key: ValueKey('askodoxWorkerInvite-${c['user']}'),
              onPressed: () => _guard(context, () async {
                await _repo.inviteWorker(_id, _s(c['user']), '');
                await _load();
                if (mounted) askodoxPosSnack(context, te ? 'అడిగాం – వాళ్ళు ఒప్పుకుంటేనే చేరతారు' : 'Asked – they join only if they accept');
              }),
              child: Text(te ? 'చేర్చుకోమని అడుగు' : 'Invite'),
            ),
          ),
        ),
    ]);
  }

  Widget _ordersTab(bool te) {
    final team = _l(_data?['team']).where((w) => w['status'] == 'joined').toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (_orders.isEmpty) Text(te ? 'ఇంకా ఆర్డర్లు లేవు' : 'No orders yet'),
      for (final o in _orders)
        Card(
          child: ListTile(
            key: ValueKey('askodoxAuthorityOrder-${o['id']}'),
            title: Text('${o['label']} ${te ? o['work_te'] : o['work_en']} · ${o['place'] ?? ''}'),
            subtitle: Text([
              _s(o['status']),
              if (_s(o['worker_name']).isNotEmpty) _s(o['worker_name']),
              if (o['taken_by'] == 'worker') te ? 'తనే ఒప్పుకున్నారు – క్యాష్' : 'took it – cash',
              for (final c in _l(o['complaints'])) '⚠ ${c['text']}',
            ].join(' · ')),
            trailing: o['status'] == 'open' && team.isNotEmpty
                ? PopupMenuButton<String>(
                    key: ValueKey('askodoxAuthorityAssign-${o['id']}'),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    onSelected: (worker) => _assign(_s(o['id']), worker, te),
                    itemBuilder: (_) => [for (final w in team) PopupMenuItem(value: _s(w['user']), child: Text(_s(w['name'])))],
                  )
                : (o['status'] == 'done' && ((o['share_paise'] as num?) ?? 0) == 0
                    ? TextButton(onPressed: () => _share(_s(o['id']), te), child: Text(te ? 'ఇచ్చాను ₹' : 'Paid ₹'))
                    : null),
          ),
        ),
    ]);
  }

  Future<void> _assign(String orderId, String worker, bool te) async {
    try {
      await _repo.assignWorkOrder(_id, orderId, worker);
    } on AskodoxPosException catch (e) {
      if (!mounted) return;
      if (e.code != 'home_entry') {
        askodoxPosSnack(context, e.detail.isEmpty ? e.kind : e.detail);
        return;
      }
      final go = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          content: Text(te
              ? 'ఈ పని ఇంటి లోపల. ఈ వ్యక్తికి పోలీస్ వెరిఫికేషన్ టిక్ లేదు. అయినా పంపాలా?'
              : 'This work is inside a home and police verification is not ticked. Send anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(te ? 'వద్దు' : 'No')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(te ? 'పంపు' : 'Send')),
          ],
        ),
      );
      if (go == true && mounted) await _guard(context, () => _repo.assignWorkOrder(_id, orderId, worker, money: 'confirm_home'));
    }
    await _load();
  }

  Future<void> _share(String orderId, bool te) async {
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(te ? 'వాళ్ళకి ఎంత ఇచ్చారు? (రికార్డ్ మాత్రమే)' : 'How much did you give? (record only)'),
        content: TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹ ')),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog, true), child: Text(te ? 'సేవ్' : 'Save'))],
      ),
    );
    if (ok == true && mounted) {
      await _guard(context, () => _repo.recordWorkShare(_id, orderId, ((int.tryParse(amount.text.trim()) ?? 0) * 100)));
      await _load();
    }
    amount.dispose();
  }

  Widget _registration(AskodoxJson data, bool te) {
    final types = _l(data['work_types']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
          key: const Key('askodoxAuthorityGst'),
          controller: _gst,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: te ? 'GST నంబర్' : 'GST number', border: const OutlineInputBorder())),
      const SizedBox(height: 8),
      TextField(
          key: const Key('askodoxAuthorityUdyam'),
          controller: _udyam,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: te ? 'లేదా Udyam నంబర్' : 'or Udyam number', border: const OutlineInputBorder())),
      const SizedBox(height: 8),
      TextField(
          controller: _address,
          decoration: InputDecoration(
              labelText: te ? 'సర్టిఫికేట్ లోని అడ్రస్' : 'Address on the certificate', border: const OutlineInputBorder())),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _agency,
        onChanged: (v) => setState(() => _agency = v),
        title: Text(te ? 'మ్యాన్‌పవర్ / HR (అన్ని రకాల పనులు)' : 'Manpower / HR (every kind of work)'),
      ),
      Text(te ? 'మీరు ఇచ్చిన ఆర్డర్ల డబ్బు ఎలా?' : 'Money for orders YOU assign', style: const TextStyle(fontWeight: FontWeight.w800)),
      Wrap(spacing: 8, children: [
        for (final m in const ['cash', 'upi', 'both'])
          ChoiceChip(
            selected: _money == m,
            label: Text(switch (m) {
              'cash' => te ? 'క్యాష్' : 'Cash',
              'upi' => te ? 'నా UPI' : 'My UPI',
              _ => te ? 'రెండూ' : 'Both',
            }),
            onSelected: (_) => setState(() => _money = m),
          ),
      ]),
      Text(te ? 'Worker తనే ఒప్పుకున్న ఆర్డర్ = ఎప్పుడూ క్యాష్, worker దగ్గర.' : 'An order the worker takes himself = always cash, with him.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      _section(te ? 'మీ ధరలు (కస్టమర్ కి కనిపిస్తాయి)' : 'Your prices (customers see them)'),
      for (final t in types)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: _prices.putIfAbsent(_s(t['key']), TextEditingController.new),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: te && _s(t['te']).isNotEmpty ? _s(t['te']) : _s(t['en']),
                prefixText: '₹ ',
                border: const OutlineInputBorder()),
          ),
        ),
      const SizedBox(height: 8),
      SizedBox(
        height: 54,
        child: FilledButton(
          key: const Key('askodoxAuthoritySave'),
          onPressed: () => _guard(context, () async {
            await _repo.setWorkforce(_id, {
              'gstin': _gst.text.trim(),
              'udyam': _udyam.text.trim(),
              'address': _address.text.trim(),
              'agency': _agency,
              'assigned_money': _money,
              'prices': {
                for (final e in _prices.entries)
                  if (int.tryParse(e.value.text.trim()) != null) e.key: int.parse(e.value.text.trim()) * 100,
              },
            });
            await _load();
            if (mounted) askodoxPosSnack(context, te ? 'సేవ్ అయింది ✓' : 'Saved ✓');
          }),
          child: Text(te ? 'సేవ్' : 'Save'),
        ),
      ),
      const SizedBox(height: 12),
      Text(_s(data['udyam_help']), style: const TextStyle(color: Color(0xFF15803D))),
    ]);
  }
}

// ============================================================================ the customer
class AskodoxHireScreen extends ConsumerStatefulWidget {
  const AskodoxHireScreen({super.key});

  @override
  ConsumerState<AskodoxHireScreen> createState() => _HireState();
}

class _HireState extends ConsumerState<AskodoxHireScreen> {
  List<AskodoxJson> _types = const [];
  List<AskodoxJson> _options = const [];
  List<AskodoxJson> _orders = const [];
  String? _type;
  final _place = TextEditingController();
  final _when = TextEditingController();

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
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final types = _l((await _repo.hireTypes())['work_types']);
      final orders = _l((await _repo.hireOrders())['orders']);
      if (mounted) {
        setState(() {
          _types = types;
          _orders = orders;
        });
      }
    } catch (_) {}
  }

  Future<void> _pick(String type) async {
    setState(() => _type = type);
    await _guard(context, () async {
      final options = _l((await _repo.hireOptions(type))['options']);
      if (mounted) setState(() => _options = options);
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      key: const Key('askodoxHire'),
      appBar: AppBar(title: Text(te ? 'పని వాళ్ళు కావాలి' : 'Hire a worker')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in _types)
              ChoiceChip(
                key: ValueKey('askodoxHireType-${t['key']}'),
                selected: _type == _s(t['key']),
                label: Text(te && _s(t['te']).isNotEmpty ? _s(t['te']) : _s(t['en'])),
                onSelected: (_) => _pick(_s(t['key'])),
              ),
          ]),
          if (_type != null) ...[
            const SizedBox(height: 12),
            TextField(
                controller: _place,
                decoration: InputDecoration(labelText: te ? 'ఎక్కడ' : 'Where', border: const OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: _when,
                decoration: InputDecoration(labelText: te ? 'ఎప్పుడు' : 'When', border: const OutlineInputBorder())),
            _section(te ? 'ఎవరి ద్వారా?' : 'Through whom?'),
            if (_options.isEmpty) Text(te ? 'మీ దగ్గర ఇంకా ఎవరూ లేరు' : 'No one near you yet'),
            for (final o in _options)
              Card(
                child: ListTile(
                  key: ValueKey('askodoxHireOption-${o['business_id'] ?? o['worker']}'),
                  title: Text(_s(o['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(o['kind'] == 'independent'
                      ? _s(o['label'])
                      : [
                          _s(o['address']),
                          if (o['price_paise'] != null) askodoxRupee(o['price_paise']),
                          '${o['team']} ${te ? 'మంది' : 'people'}',
                        ].where((x) => x.isNotEmpty).join(' · ')),
                  trailing: FilledButton(
                    key: ValueKey('askodoxHireBook-${o['business_id'] ?? o['worker']}'),
                    onPressed: () => _guard(context, () async {
                      await _repo.hirePlace({
                        'work_type': _type,
                        if (o['kind'] == 'independent') 'worker': o['worker'] else 'business_id': o['business_id'],
                        'place': _place.text.trim(),
                        'at': _when.text.trim(),
                      });
                      await _load();
                      if (mounted) askodoxPosSnack(this.context, te ? 'బుక్ అయింది – పేరు, నంబర్ వస్తాయి' : 'Booked – name and number will come');
                    }),
                    child: Text(te ? 'బుక్' : 'Book'),
                  ),
                ),
              ),
          ],
          if (_orders.isNotEmpty) _section(te ? 'నా బుకింగ్స్' : 'My bookings'),
          for (final o in _orders)
            Card(
              child: ListTile(
                key: ValueKey('askodoxHireOrder-${o['id']}'),
                title: Text('${o['label']} ${te ? o['work_te'] : o['work_en']} · ${o['authority'] ?? ''}'),
                subtitle: Text([
                  _s(o['status']),
                  if (_s(o['worker_name']).isNotEmpty) _s(o['worker_name']),
                  if (_s(o['worker_phone']).isNotEmpty) _s(o['worker_phone']),
                  if (_s(o['pay_upi']).isNotEmpty) 'UPI ${o['pay_upi']}',
                ].join(' · ')),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => _guard(context, () async {
                    if (v.startsWith('rate')) {
                      await _repo.hireRate(_s(o['id']), int.parse(v.substring(4)));
                    } else {
                      final text = TextEditingController();
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (dialog) => AlertDialog(
                          title: Text(te ? 'ఏం జరిగింది?' : 'What went wrong?'),
                          content: TextField(controller: text, maxLines: 3),
                          actions: [TextButton(onPressed: () => Navigator.pop(dialog, true), child: Text(te ? 'పంపు' : 'Send'))],
                        ),
                      );
                      if (ok == true && text.text.trim().isNotEmpty) await _repo.hireComplain(_s(o['id']), text.text.trim());
                      text.dispose();
                    }
                    await _load();
                  }),
                  itemBuilder: (_) => [
                    if (o['status'] == 'done' && o['rated'] != true)
                      for (var s = 5; s >= 1; s--) PopupMenuItem(value: 'rate$s', child: Text('⭐' * s)),
                    PopupMenuItem(value: 'complain', child: Text(te ? 'ఫిర్యాదు' : 'Complaint')),
                  ],
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
