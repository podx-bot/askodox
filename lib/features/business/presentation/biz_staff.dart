import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../location/application/location_controller.dart' show deviceLocationGatewayProvider;
import '../../location/domain/geo_models.dart' show LocationPermissionStatus;
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart' show askodoxPaise, askodoxParsePaise;
import '../../pos/presentation/pos_common.dart';
import 'biz_hub.dart';

/// Staff & attendance (owner 2026-11-18): who came when (own phone lock + location, or the shop phone with a photo),
/// the month calendar P / A / OT / leave, salary worked out line by line, advances, tasks.

const _purple = Color(0xFF5B2A9E);
const _green = Color(0xFF17784C);
const _red = Color(0xFFB91C1C);
const _orange = Color(0xFFB45309);
const _muted = Color(0xFF4B5563);

final askodoxAttTodayProvider = FutureProvider.autoDispose.family<AskodoxJson, String>(
    (ref, id) => ref.watch(askodoxPosRepositoryProvider).attendanceToday(id));

String _clock(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '—';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')}${t.hour < 12 ? ' AM' : ' PM'}';
}

/// P / A / OT / leave / half in words and a colour everyone can read.
(String, Color) askodoxAttLabel(String status, bool te) => switch (status) {
      'P' => (te ? 'వచ్చారు' : 'Present', _green),
      'OT' => (te ? 'ఎక్కువ గంటలు' : 'Overtime', _orange),
      'A' => (te ? 'రాలేదు' : 'Absent', _red),
      'leave' => (te ? 'సెలవు' : 'Leave', _purple),
      'half' => (te ? 'సగం రోజు' : 'Half day', _orange),
      _ => (te ? 'ఇంకా రాలేదు' : 'Not yet', const Color(0xFF6B7280)),
    };

Widget _pill(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(9)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
    );

/// `/biz/:id/staff` -- the staff group: today, everyday buttons, set-once buttons. A staff member sees their own part.
class AskodoxBizStaffScreen extends ConsumerWidget {
  const AskodoxBizStaffScreen({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    final today = ref.watch(askodoxAttTodayProvider(businessId));
    final tone = askodoxBizTones['staff']!;
    return AskodoxBizScaffold(
      key: const Key('askodoxBizGroupPage-staff'),
      businessId: businessId,
      tone: tone,
      icon: Icons.groups_outlined,
      title: te ? 'సిబ్బంది & హాజరు' : 'Staff & attendance',
      trail: [te ? 'సిబ్బంది & హాజరు' : 'Staff & attendance'],
      page: 'staff',
      onRefresh: () async => ref.invalidate(askodoxAttTodayProvider(businessId)),
      askHint: te ? '"చింతయ్యకి 500 అడ్వాన్స్ రాయి"' : '"Advance 500 to Chintayya"',
      children: today.when(
        loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
        error: (e, _) => [AskodoxPosError(error: e, onRetry: () => ref.invalidate(askodoxAttTodayProvider(businessId)))],
        data: (d) {
          final boss = d['boss'] == true;
          final people = askodoxPosList(d['people']);
          final counts = askodoxPosMap(d['counts']);
          Widget tile(String key, IconData icon, String title, String sub, String tn, String route, {String? badge}) =>
              AskodoxBizTile(
                key: Key(key),
                icon: icon,
                title: title,
                sub: sub,
                tone: askodoxBizTones[tn]!,
                badge: badge,
                onTap: () async {
                  await context.push(route);
                  ref.invalidate(askodoxAttTodayProvider(businessId));
                },
              );
          return [
            AskodoxBizStrip(cells: [
              (te ? 'వచ్చారు' : 'Present', '${askodoxPosInt(counts['present'])}/${people.length}', _green),
              (te ? 'ఆలస్యం' : 'Late', '${askodoxPosInt(counts['late'])}', _orange),
              (te ? 'దూరంగా' : 'Far away', '${askodoxPosInt(counts['far'])}', _red),
            ]),
            AskodoxBizSection(boss ? (te ? 'ఈ రోజు — నొక్కితే వారి పేజీ' : 'Today — tap for their page') : (te ? 'నా హాజరు' : 'My attendance')),
            if (people.isEmpty)
              Text(te ? 'ఇంకా సిబ్బంది లేరు. "సిబ్బందిని చేర్చు" నొక్కండి.' : 'No staff yet. Tap "Add staff".'),
            AskodoxBizGrid(children: [
              for (final p in people)
                _PersonTile(businessId: businessId, person: p),
            ]),
            AskodoxBizSection(te ? 'రోజూ వాడేవి' : 'Every day'),
            AskodoxBizGrid(children: [
              tile('askodoxStaffCheckIn', Icons.fingerprint, te ? 'హాజరు వేయి' : 'Check in / out',
                  te ? 'మీ ఫోన్ లాక్‌తో' : 'With your phone lock', 'purple', '/biz/$businessId/staff/checkin'),
              tile('askodoxStaffTasks', Icons.task_alt, te ? 'పనులు' : 'Tasks', te ? 'ఎవరికి ఏ పని' : 'Who does what', 'purple',
                  '/biz/$businessId/staff/tasks'),
              if (boss) ...[
                tile('askodoxStaffToday', Icons.how_to_reg_outlined, te ? 'ఈ రోజు హాజరు' : "Today's attendance",
                    te ? 'ఒక్క నొక్కుతో P / A / OT / సెలవు' : 'One tap P / A / OT / leave', 'green', '/biz/$businessId/staff/today'),
                tile('askodoxStaffKiosk', Icons.camera_front_outlined, te ? 'షాప్ ఫోన్ హాజరు' : 'Shop phone attendance',
                    te ? 'ఫోన్ లేనివారికి — ఫోటోతో' : 'For people without a phone — with a photo', 'teal',
                    '/biz/$businessId/staff/kiosk'),
                tile('askodoxStaffSalary', Icons.payments_outlined, te ? 'జీతాలు & అడ్వాన్స్' : 'Salary & advance',
                    te ? 'ఆటో లెక్క' : 'Worked out for you', 'green', '/biz/$businessId/staff/salary'),
              ],
            ]),
            if (boss) ...[
              AskodoxBizSection(te ? 'ఒకసారి సెట్ చేసేవి' : 'Set once'),
              AskodoxBizGrid(children: [
                tile('askodoxStaffAdd', Icons.person_add_alt_1_outlined, te ? 'సిబ్బందిని చేర్చు' : 'Add staff',
                    te ? 'పేరు, నంబర్, పాత్ర' : 'Name, number, role', 'gray', askodoxBizRoute(businessId, 'staff.add')),
                tile('askodoxStaffSetup', Icons.tune, te ? 'హాజరు సెటప్' : 'Attendance setup',
                    te ? 'సమయం, దూరం, పద్ధతి' : 'Hours, distance, method', 'gray', '/biz/$businessId/staff/setup'),
                tile('askodoxStaffSounds', Icons.notifications_active_outlined, te ? 'ఎవరికి ఏ సౌండ్' : 'Who hears what',
                    te ? 'ఒక్క పట్టిక' : 'One table', 'purple', askodoxBizRoute(businessId, 'staff.alerts')),
              ]),
            ],
          ];
        },
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.businessId, required this.person});
  final String businessId;
  final AskodoxJson person;

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final today = askodoxPosMap(person['today']);
    final status = '${today['status'] ?? ''}';
    var (label, color) = askodoxAttLabel(today.isEmpty ? '' : status, te);
    if (today.isNotEmpty && askodoxPosInt(today['late_min']) > 0 && status == 'P') {
      label = te ? 'ఆలస్యం ${askodoxPosInt(today['late_min'])} ని.' : 'Late ${askodoxPosInt(today['late_min'])} min';
      color = _orange;
    }
    final name = '${person['name']}'.isEmpty ? '••${person['ref']}' : '${person['name']}';
    return Material(
      color: askodoxBizTones['staff']!.bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('askodoxStaffPerson-${person['ref']}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/biz/$businessId/staff/person/${person['ref']}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  child: Text(name.characters.first, style: const TextStyle(color: _purple, fontWeight: FontWeight.w900))),
              const Spacer(),
              _pill(label, color),
            ]),
            const SizedBox(height: 6),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
                [
                  '${person['role']}',
                  if (today['in_at'] != null) '${te ? 'వచ్చింది' : 'in'} ${_clock(today['in_at'])}',
                  if (today['far'] == true) te ? 'షాప్‌కి దూరం' : 'far from shop',
                ].join(' · '),
                style: const TextStyle(fontSize: 11.5, color: _muted)),
          ]),
        ),
      ),
    );
  }
}

/// `/biz/:id/staff/checkin` -- the person's own phone: phone lock (fingerprint / face / PIN) + where the phone is.
class AskodoxBizCheckInScreen extends ConsumerStatefulWidget {
  const AskodoxBizCheckInScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizCheckInScreen> createState() => _AskodoxBizCheckInScreenState();
}

class _AskodoxBizCheckInScreenState extends ConsumerState<AskodoxBizCheckInScreen> {
  static const _hardware = MethodChannel('com.askodox.app/hardware');
  bool _busy = false;
  String _place = '';

  Future<String> _lock(bool te) async {
    try {
      return await _hardware.invokeMethod<String>('confirmDeviceLock', {
            'title': te ? 'హాజరు — మీరేనా?' : 'Attendance — is it you?',
            'subtitle': te ? 'మీ ఫోన్ వేలిముద్ర / ముఖం / PIN' : 'Your phone fingerprint / face / PIN',
          }) ??
          'unsupported';
    } catch (_) {
      return 'unsupported';
    }
  }

  Future<(double?, double?)> _where() async {
    try {
      final gate = ref.read(deviceLocationGatewayProvider);
      if (await gate.ensurePermission() != LocationPermissionStatus.granted) return (null, null);
      final p = await gate.getCurrentPosition();
      return (p?.latitude, p?.longitude);
    } catch (_) {
      return (null, null);
    }
  }

  Future<void> _go(String action) async {
    final te = askodoxPosTe(context);
    setState(() => _busy = true);
    try {
      var method = 'device_lock';
      String photo = '';
      if (action != 'leave') {
        final lock = await _lock(te);
        if (lock == 'cancelled') return;
        if (lock == 'no_lock' || lock == 'unsupported') {
          // No screen lock on this phone: a selfie proves it instead.
          final shot = await ImagePicker().pickImage(
              source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, maxWidth: 480, imageQuality: 60);
          if (shot == null) return;
          photo = base64Encode(await shot.readAsBytes());
          method = 'photo';
        }
      }
      final (lat, lng) = await _where();
      final out = await ref.read(askodoxPosRepositoryProvider).attendanceCheck(widget.businessId, {
        'action': action,
        'method': method,
        if (photo.isNotEmpty) 'photo': photo,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });
      if (!mounted) return;
      setState(() => _place = out['far'] == true
          ? (te ? 'షాప్‌కి ${askodoxPosInt(out['distance_m'])} మీ. దూరంలో ఉన్నారు — ఓనర్‌కి తెలుస్తుంది' : '${askodoxPosInt(out['distance_m'])} m from the shop — the owner will see it')
          : out['distance_m'] != null
              ? (te ? 'షాప్ దగ్గర ఉన్నారు ✓ (${askodoxPosInt(out['distance_m'])} మీ.)' : 'At the shop ✓ (${askodoxPosInt(out['distance_m'])} m)')
              : (te ? 'లొకేషన్ దొరకలేదు' : 'No location'));
      askodoxPosSnack(
          context,
          out['already'] == true
              ? (te ? 'ముందే వేశారు ✓' : 'Already done ✓')
              : switch (action) {
                  'in' => te ? 'వచ్చినట్టు రాశాం ✓ ${_clock(out['in_at'])}' : 'Checked in ✓ ${_clock(out['in_at'])}',
                  'out' => te ? 'వెళ్ళినట్టు రాశాం ✓' : 'Checked out ✓',
                  _ => te ? 'సెలవు రాశాం' : 'Leave noted',
                });
      ref.invalidate(askodoxAttTodayProvider(widget.businessId));
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final today = ref.watch(askodoxAttTodayProvider(widget.businessId)).valueOrNull;
    final mine = askodoxPosList(today?['people']).where((p) => today?['boss'] != true).firstOrNull;
    final att = askodoxPosMap(mine?['today']);
    Widget big(String key, String label, IconData icon, Color color, String action) => Expanded(
          child: FilledButton.icon(
            key: Key(key),
            style: FilledButton.styleFrom(
                backgroundColor: color,
                minimumSize: const Size.fromHeight(64),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: _busy ? null : () => _go(action),
            icon: Icon(icon),
            label: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          ),
        );
    return AskodoxBizScaffold(
      key: const Key('askodoxBizCheckIn'),
      businessId: widget.businessId,
      tone: askodoxBizTones['staff']!,
      icon: Icons.fingerprint,
      title: te ? 'హాజరు వేయి' : 'Check in / out',
      trail: [te ? 'సిబ్బంది & హాజరు' : 'Staff & attendance', te ? 'హాజరు' : 'Attendance'],
      page: 'staff',
      askHint: te ? '"నేను వచ్చాను" అని చెప్పినా చాలు' : '"I have come" is enough',
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: const Color(0xFFE7F5EE), border: Border.all(color: _green, width: 4)),
                child: _busy
                    ? const Padding(padding: EdgeInsets.all(50), child: CircularProgressIndicator())
                    : const Icon(Icons.fingerprint, size: 90, color: _green),
              ),
              const SizedBox(height: 10),
              Text(te ? 'మీ ఫోన్ వేలిముద్ర / ముఖం తాకండి' : 'Touch your phone fingerprint / face',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16), textAlign: TextAlign.center),
              Text(te ? 'ఫోన్ లాక్ లేకపోతే సెల్ఫీ అడుగుతుంది' : 'No phone lock? It asks for a selfie',
                  style: const TextStyle(color: _muted, fontSize: 12.5)),
              if (att.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                    [
                      if (att['in_at'] != null) '${te ? 'వచ్చింది' : 'In'} ${_clock(att['in_at'])}',
                      if (att['out_at'] != null) '${te ? 'వెళ్ళింది' : 'Out'} ${_clock(att['out_at'])}',
                    ].join(' · '),
                    key: const Key('askodoxCheckInToday'),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: _green)),
              ],
            ]),
          ),
        ),
        if (_place.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFE7F5EE), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.place_outlined, color: _green),
              const SizedBox(width: 8),
              Expanded(child: Text(_place, style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          big('askodoxCheckInIn', te ? 'వచ్చాను' : 'I am in', Icons.login, _green, 'in'),
          const SizedBox(width: 8),
          big('askodoxCheckInOut', te ? 'వెళ్తున్నా' : 'Leaving', Icons.logout, _red, 'out'),
        ]),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('askodoxCheckInLeave'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : () => _go('leave'),
          child: Text(te ? 'ఈ రోజు సెలవు' : 'On leave today'),
        ),
        const SizedBox(height: 8),
        Text(
            te
                ? 'ఓనర్‌కి వెంటనే: టైం, పద్ధతి, షాప్ నుంచి దూరం. ఫోటోలు ఓనర్‌కి మాత్రమే, 90 రోజుల తర్వాత తీసేస్తాం.'
                : 'The owner sees the time, the method and the distance from the shop. Photos are for the owner only and deleted after 90 days.',
            style: const TextStyle(fontSize: 12, color: _muted)),
      ],
    );
  }
}

/// `/biz/:id/staff/kiosk` -- the shop phone / tablet: tap a name, a front-camera photo, in or out.
class AskodoxBizKioskScreen extends ConsumerStatefulWidget {
  const AskodoxBizKioskScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizKioskScreen> createState() => _AskodoxBizKioskScreenState();
}

class _AskodoxBizKioskScreenState extends ConsumerState<AskodoxBizKioskScreen> {
  String? _who;
  bool _busy = false;
  String _last = '';

  Future<void> _go(String action) async {
    final te = askodoxPosTe(context);
    final who = _who;
    if (who == null) {
      askodoxPosSnack(context, te ? 'ముందు పేరు నొక్కండి.' : 'Tap a name first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final shot = await ImagePicker().pickImage(
          source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, maxWidth: 480, imageQuality: 60);
      if (shot == null) return;
      final out = await ref.read(askodoxPosRepositoryProvider).attendanceCheck(widget.businessId, {
        'action': action,
        'for_ref': who,
        'photo': base64Encode(await shot.readAsBytes()),
      });
      if (!mounted) return;
      setState(() {
        _last = action == 'in'
            ? (te ? '${_clock(out['in_at'])} కి వచ్చారు ✓' : 'In at ${_clock(out['in_at'])} ✓')
            : (te ? 'వెళ్ళినట్టు రాశాం ✓' : 'Out ✓');
        _who = null;
      });
      ref.invalidate(askodoxAttTodayProvider(widget.businessId));
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final people = askodoxPosList(ref.watch(askodoxAttTodayProvider(widget.businessId)).valueOrNull?['people']);
    return Scaffold(
      key: const Key('askodoxBizKiosk'),
      backgroundColor: const Color(0xFF16203F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16203F),
        foregroundColor: Colors.white,
        title: Text(te ? 'హాజరు — షాప్ ఫోన్' : 'Attendance — shop phone'),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(te ? '1. మీ పేరు నొక్కండి  2. వచ్చాను / వెళ్తున్నా  3. ఫోటో' : '1. Tap your name  2. In / out  3. Photo',
              style: const TextStyle(color: Color(0xFFC7CEE0), fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final p in people)
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 52) / 3,
                height: 72,
                child: FilledButton(
                  key: Key('askodoxKioskName-${p['ref']}'),
                  style: FilledButton.styleFrom(
                      backgroundColor: _who == '${p['ref']}' ? _green : const Color(0xFF26304F),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: () => setState(() => _who = '${p['ref']}'),
                  child: Text('${p['name']}'.isEmpty ? '••${p['ref']}' : '${p['name']}',
                      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
          if (_last.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(14)),
              child: Text(_last, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
            ),
          ],
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('askodoxKioskIn'),
                style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size.fromHeight(64)),
                onPressed: _busy ? null : () => _go('in'),
                icon: const Icon(Icons.login),
                label: Text(te ? 'వచ్చాను' : 'In', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const Key('askodoxKioskOut'),
                style: FilledButton.styleFrom(backgroundColor: _red, minimumSize: const Size.fromHeight(64)),
                onPressed: _busy ? null : () => _go('out'),
                icon: const Icon(Icons.logout),
                label: Text(te ? 'వెళ్తున్నా' : 'Out', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// `/biz/:id/staff/person/:ref` -- one person: this month as a calendar (one tap = P / A / OT / leave), salary lines,
/// advance, pay settings.
class AskodoxBizStaffPersonScreen extends ConsumerStatefulWidget {
  const AskodoxBizStaffPersonScreen({super.key, required this.businessId, required this.staffRef});
  final String businessId;
  final String staffRef;

  @override
  ConsumerState<AskodoxBizStaffPersonScreen> createState() => _AskodoxBizStaffPersonScreenState();
}

class _AskodoxBizStaffPersonScreenState extends ConsumerState<AskodoxBizStaffPersonScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  AskodoxJson? _data;
  Object? _error;

  String get _ym => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).attendanceMonth(widget.businessId, ref: widget.staffRef, month: _ym);
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

  Future<void> _mark(String date, String status) async {
    final te = askodoxPosTe(context);
    var ot = 0;
    if (status == 'OT') {
      final hours = await _number(te ? 'ఎన్ని గంటలు ఎక్కువ?' : 'How many extra hours?', '2');
      if (hours == null) return;
      ot = (hours * 60).round();
    }
    try {
      await ref.read(askodoxPosRepositoryProvider).attendanceMark(widget.businessId, widget.staffRef, date, status, otMin: ot);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<double?> _number(String title, String initial) async {
    final c = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(askodoxPosTe(ctx) ? 'వద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
    c.dispose();
    return double.tryParse((v ?? '').trim());
  }

  Future<void> _advance() async {
    final te = askodoxPosTe(context);
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'అడ్వాన్స్ ఎంత?' : 'Advance amount'),
        content: TextField(
            key: const Key('askodoxAdvanceBox'),
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₹ ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(te ? 'రాయి' : 'Save')),
        ],
      ),
    );
    c.dispose();
    final paise = askodoxParsePaise(v ?? '');
    if (paise == null || paise <= 0) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).staffAdvance(widget.businessId, widget.staffRef, paise);
      await _load();
      if (mounted) askodoxPosSnack(context, te ? 'అడ్వాన్స్ రాశాం — క్యాష్‌బుక్‌లో కూడా ✓' : 'Advance saved — in the cashbook too ✓');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _paySettings(AskodoxJson pay) async {
    final te = askodoxPosTe(context);
    var kind = '${pay['salary_kind'] ?? 'month'}';
    final amount = TextEditingController(
        text: askodoxPosInt(pay['salary_paise']) > 0 ? '${askodoxPosInt(pay['salary_paise']) ~/ 100}' : '');
    final ot = TextEditingController(
        text: askodoxPosInt(pay['ot_rate_paise']) > 0 ? '${askodoxPosInt(pay['ot_rate_paise']) ~/ 100}' : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(te ? 'జీతం ఎలా?' : 'How is the salary?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'month', label: Text(te ? 'నెలకు' : 'Per month')),
                ButtonSegment(value: 'day', label: Text(te ? 'రోజుకు' : 'Per day')),
              ],
              selected: {kind},
              onSelectionChanged: (v) => setD(() => kind = v.first),
            ),
            const SizedBox(height: 8),
            TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(prefixText: '₹ ', labelText: te ? 'జీతం' : 'Salary')),
            TextField(
                controller: ot,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(prefixText: '₹ ', labelText: te ? 'ఎక్కువ గంటకు (OT)' : 'Per extra hour (OT)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      ),
    );
    final body = {
      'salary_kind': kind,
      'salary_paise': (int.tryParse(amount.text.trim()) ?? 0) * 100,
      'ot_rate_paise': (int.tryParse(ot.text.trim()) ?? 0) * 100,
    };
    amount.dispose();
    ot.dispose();
    if (ok != true) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).staffPay(widget.businessId, widget.staffRef, body);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final d = _data;
    final counts = askodoxPosMap(d?['counts']);
    final salary = askodoxPosMap(d?['salary']);
    final name = '${d?['name'] ?? ''}'.isEmpty ? '••${widget.staffRef}' : '${d?['name']}';
    const weekdays = ['సోమ', 'మంగళ', 'బుధ', 'గురు', 'శుక్ర', 'శని', 'ఆది'];
    const weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return AskodoxBizScaffold(
      key: const Key('askodoxBizStaffPerson'),
      businessId: widget.businessId,
      tone: askodoxBizTones['staff']!,
      icon: Icons.person_outline,
      title: name,
      trail: [te ? 'సిబ్బంది & హాజరు' : 'Staff & attendance', name],
      page: 'staff',
      onRefresh: _load,
      askHint: te ? '"17న వచ్చారు, మార్చు" "500 అడ్వాన్స్"' : '"Mark the 17th present"',
      children: [
        if (_error != null) AskodoxPosError(error: _error!, onRetry: _load),
        Row(children: [
          for (final (i, c) in [
            ('${askodoxPosInt(counts['present'])}', te ? 'వచ్చారు' : 'Present', _green),
            ('${askodoxPosInt(counts['absent'])}', te ? 'రాలేదు' : 'Absent', _red),
            ((askodoxPosInt(counts['ot_min']) / 60).toStringAsFixed(1), te ? 'OT గం.' : 'OT h', _orange),
            (askodoxPaise(askodoxPosInt(d?['advance_paise'])), te ? 'అడ్వాన్స్' : 'Advance', _purple),
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  FittedBox(child: Text(c.$1, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: c.$3))),
                  Text(c.$2, style: const TextStyle(fontSize: 11, color: _muted)),
                ]),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            IconButton(
                onPressed: () {
                  setState(() => _month = DateTime(_month.year, _month.month - 1));
                  unawaited(_load());
                },
                icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(_ym, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, color: _purple))),
            IconButton(
                onPressed: () {
                  setState(() => _month = DateTime(_month.year, _month.month + 1));
                  unawaited(_load());
                },
                icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        const SizedBox(height: 6),
        Text(te ? 'ఒక్క నొక్కుతో మార్చండి: P = వచ్చారు, A = రాలేదు, OT = ఎక్కువ గంటలు, సె = సెలవు' : 'One tap: P present, A absent, OT overtime, L leave',
            style: const TextStyle(fontSize: 11.5, color: _muted)),
        const SizedBox(height: 6),
        if (d == null && _error == null) const Center(child: CircularProgressIndicator()),
        if (d != null)
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final day in askodoxPosList(d['days']).reversed)
                Container(
                  key: Key('askodoxAttDay-${day['date']}'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF0F3)))),
                  child: Row(children: [
                    SizedBox(
                      width: 42,
                      child: Column(children: [
                        Text('${day['date']}'.substring(8, 10), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        Text((te ? weekdays : weekdaysEn)[askodoxPosInt(day['weekday']).clamp(0, 6)],
                            style: const TextStyle(fontSize: 10.5, color: _muted)),
                      ]),
                    ),
                    for (final (s, short, color) in [
                      ('P', 'P', _green),
                      ('A', 'A', _red),
                      ('OT', 'OT', _orange),
                      ('leave', te ? 'సె' : 'L', _purple),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: InkWell(
                          key: Key('askodoxAttMark-${day['date']}-$s'),
                          customBorder: const CircleBorder(),
                          onTap: () => _mark('${day['date']}', s),
                          child: Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: askodoxPosMap(day['att'])['status'] == s ? color : Colors.transparent,
                              border: Border.all(color: color, width: 1.6),
                            ),
                            child: Text(short,
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    color: askodoxPosMap(day['att'])['status'] == s ? Colors.white : color)),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(askodoxPosInt(day['advance_paise']) > 0 ? askodoxPaise(askodoxPosInt(day['advance_paise'])) : '',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: _purple, fontSize: 12.5)),
                  ]),
                ),
            ]),
          ),
        AskodoxBizSection(te ? 'జీతం — ఈ నెల' : 'Salary — this month'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: salary['set'] != true
                ? Text(te ? 'జీతం ఇంకా పెట్టలేదు — "జీతం సెట్టింగ్" నొక్కండి.' : 'Salary not set yet — tap "Salary settings".')
                : Column(children: [
                    _line(te ? 'జీతం (${salary['days']} రోజులు × ${askodoxPaise(askodoxPosInt(salary['per_day_paise']))})' : 'Salary (${salary['days']} days × ${askodoxPaise(askodoxPosInt(salary['per_day_paise']))})',
                        askodoxPaise(askodoxPosInt(salary['base_paise']))),
                    _line('OT ${salary['ot_hours']} ${te ? 'గం.' : 'h'}', '+ ${askodoxPaise(askodoxPosInt(salary['ot_paise']))}'),
                    _line(te ? 'అడ్వాన్స్' : 'Advance', '− ${askodoxPaise(askodoxPosInt(salary['advance_paise']))}', color: _red),
                    const Divider(),
                    _line(te ? 'ఇవ్వాల్సింది' : 'To give', askodoxPaise(askodoxPosInt(salary['net_paise'])), bold: true, color: _green),
                  ]),
          ),
        ),
        const SizedBox(height: 10),
        AskodoxBizGrid(children: [
          AskodoxBizTile(
            key: const Key('askodoxStaffAdvance'),
            icon: Icons.currency_rupee,
            title: te ? 'అడ్వాన్స్ ఇచ్చాను' : 'Gave an advance',
            sub: te ? 'క్యాష్‌బుక్‌లో కూడా' : 'Also in the cashbook',
            tone: askodoxBizTones['purple']!,
            minHeight: 76,
            onTap: _advance,
          ),
          AskodoxBizTile(
            key: const Key('askodoxStaffPaySettings'),
            icon: Icons.tune,
            title: te ? 'జీతం సెట్టింగ్' : 'Salary settings',
            sub: '${askodoxPaise(askodoxPosInt(askodoxPosMap(d?['pay'])['salary_paise']))} ${askodoxPosMap(d?['pay'])['salary_kind'] == 'day' ? (te ? '/ రోజు' : '/ day') : (te ? '/ నెల' : '/ month')}',
            tone: askodoxBizTones['gray']!,
            minHeight: 76,
            onTap: () => _paySettings(askodoxPosMap(d?['pay'])),
          ),
        ]),
      ],
    );
  }

  Widget _line(String a, String b, {bool bold = false, Color color = const Color(0xFF16203F)}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w500, color: _muted))),
          Text(b, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: bold ? 17 : 14)),
        ]),
      );
}

/// `/biz/:id/staff/salary` -- everyone's salary this month, worked out; "given" writes it into the cashbook.
class AskodoxBizSalaryScreen extends ConsumerStatefulWidget {
  const AskodoxBizSalaryScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizSalaryScreen> createState() => _AskodoxBizSalaryScreenState();
}

class _AskodoxBizSalaryScreenState extends ConsumerState<AskodoxBizSalaryScreen> {
  AskodoxJson? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).teamSalary(widget.businessId);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _paid(AskodoxJson p) async {
    final te = askodoxPosTe(context);
    final net = askodoxPaise(askodoxPosInt(askodoxPosMap(p['salary'])['net_paise']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? '${p['name']} కి $net ఇచ్చారా?' : 'Gave $net to ${p['name']}?'),
        content: Text(te ? 'క్యాష్‌బుక్‌లో జీతం ఖర్చుగా రాస్తాం.' : 'It is written in the cashbook as salary.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'ఇచ్చేశాను ✓' : 'Given ✓')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).salaryPaid(widget.businessId, '${p['ref']}', '${_data?['month']}');
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final people = askodoxPosList(_data?['people']);
    return AskodoxBizScaffold(
      key: const Key('askodoxBizSalary'),
      businessId: widget.businessId,
      tone: askodoxBizTones['staff']!,
      icon: Icons.payments_outlined,
      title: te ? 'జీతాలు — ${_data?['month'] ?? ''}' : 'Salary — ${_data?['month'] ?? ''}',
      trail: [te ? 'సిబ్బంది & హాజరు' : 'Staff & attendance', te ? 'జీతాలు' : 'Salary'],
      page: 'staff',
      onRefresh: _load,
      askHint: te ? '"ప్రసాద్‌కి జీతం ఇచ్చేశాను"' : '"Gave Prasad his salary"',
      children: [
        if (_error != null) AskodoxPosError(error: _error!, onRetry: _load),
        if (_data == null && _error == null) const Center(child: CircularProgressIndicator()),
        AskodoxBizSection(te ? 'ఎవరికి ఎంత — ఆటోగా లెక్కించింది' : 'Who gets how much — worked out'),
        for (final p in people)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              key: Key('askodoxSalaryRow-${p['ref']}'),
              onTap: () => context.push('/biz/${widget.businessId}/staff/person/${p['ref']}'),
              title: Text('${p['name']}'.isEmpty ? '••${p['ref']}' : '${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(askodoxPosMap(p['salary'])['set'] == true
                  ? (te
                      ? '${askodoxPosMap(p['salary'])['days']} రోజులు · OT ${askodoxPosMap(p['salary'])['ot_hours']} గం. · అడ్వాన్స్ ${askodoxPaise(askodoxPosInt(askodoxPosMap(p['salary'])['advance_paise']))}'
                      : '${askodoxPosMap(p['salary'])['days']} days · OT ${askodoxPosMap(p['salary'])['ot_hours']} h · advance ${askodoxPaise(askodoxPosInt(askodoxPosMap(p['salary'])['advance_paise']))}')
                  : (te ? 'జీతం పెట్టలేదు — నొక్కి పెట్టండి' : 'Salary not set — tap to set')),
              trailing: p['paid'] != null
                  ? _pill(te ? 'ఇచ్చారు ✓' : 'Given ✓', _green)
                  : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(askodoxPaise(askodoxPosInt(askodoxPosMap(p['salary'])['net_paise'])),
                          style: const TextStyle(fontWeight: FontWeight.w900, color: _green)),
                      if (askodoxPosMap(p['salary'])['set'] == true)
                        InkWell(
                          key: Key('askodoxSalaryPaid-${p['ref']}'),
                          onTap: () => _paid(p),
                          child: Text(te ? 'ఇచ్చేశాను' : 'Mark given',
                              style: const TextStyle(color: _purple, fontWeight: FontWeight.w800, fontSize: 12.5)),
                        ),
                    ]),
            ),
          ),
        Text(te ? '"ఇచ్చేశాను" నొక్కితే క్యాష్‌బుక్‌లో జీతం ఖర్చుగా ఆటోగా పడుతుంది.' : '"Mark given" writes it into the cashbook as salary.',
            style: const TextStyle(fontSize: 12, color: _muted)),
      ],
    );
  }
}

/// `/biz/:id/staff/tasks` -- give a task (it rings their phone); they tap done; it shows in the night report.
class AskodoxBizTasksScreen extends ConsumerStatefulWidget {
  const AskodoxBizTasksScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizTasksScreen> createState() => _AskodoxBizTasksScreenState();
}

class _AskodoxBizTasksScreenState extends ConsumerState<AskodoxBizTasksScreen> {
  AskodoxJson? _data;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).tasks(widget.businessId);
      if (mounted) setState(() => _data = d);
    } catch (_) {}
  }

  Future<void> _add(List<AskodoxJson> people) async {
    final te = askodoxPosTe(context);
    final title = TextEditingController();
    String? who = people.isEmpty ? null : '${people.first['ref']}';
    TimeOfDay? due;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(te ? 'పని కేటాయించు' : 'Give a task', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              TextField(
                  key: const Key('askodoxTaskTitle'),
                  controller: title,
                  autofocus: true,
                  decoration: InputDecoration(
                      labelText: te ? 'ఏ పని? (ఉదా: టేబుల్స్ శుభ్రం)' : 'What? (e.g. clean the tables)',
                      border: const OutlineInputBorder())),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in people)
                  ChoiceChip(
                    label: Text('${p['name']}'.isEmpty ? '••${p['ref']}' : '${p['name']}'),
                    selected: who == '${p['ref']}',
                    onSelected: (_) => setS(() => who = '${p['ref']}'),
                  ),
              ]),
              TextButton.icon(
                onPressed: () async {
                  final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                  if (t != null) setS(() => due = t);
                },
                icon: const Icon(Icons.schedule),
                label: Text(due == null ? (te ? 'ఎప్పటిలోపు? (ఐచ్ఛికం)' : 'By when? (optional)') : due!.format(ctx)),
              ),
              FilledButton(
                  key: const Key('askodoxTaskSave'),
                  style: FilledButton.styleFrom(backgroundColor: _purple, minimumSize: const Size.fromHeight(48)),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(te ? 'పంపు — వారి ఫోన్ మోగుతుంది' : 'Send — their phone rings')),
            ]),
          ),
        ),
      ),
    );
    final text = title.text.trim();
    title.dispose();
    if (ok != true || text.isEmpty || who == null) return;
    var dueAt = '';
    if (due != null) {
      final n = DateTime.now();
      dueAt = DateTime(n.year, n.month, n.day, due!.hour, due!.minute).toIso8601String();
    }
    try {
      await ref.read(askodoxPosRepositoryProvider).taskAdd(widget.businessId, text, who!, dueAt: dueAt);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final tasks = askodoxPosList(_data?['tasks']);
    final counts = askodoxPosMap(_data?['counts']);
    final today = ref.watch(askodoxAttTodayProvider(widget.businessId)).valueOrNull;
    final boss = today?['boss'] == true;
    final people = askodoxPosList(today?['people']);
    return AskodoxBizScaffold(
      key: const Key('askodoxBizTasks'),
      businessId: widget.businessId,
      tone: askodoxBizTones['staff']!,
      icon: Icons.task_alt,
      title: te ? 'పనులు' : 'Tasks',
      trail: [te ? 'సిబ్బంది & హాజరు' : 'Staff & attendance', te ? 'పనులు' : 'Tasks'],
      page: 'staff',
      onRefresh: _load,
      askHint: te ? '"ప్రసాద్‌కి 3 గంటలకు టేబుల్స్ శుభ్రం పని"' : '"Prasad: clean the tables at 3"',
      children: [
        AskodoxBizStrip(cells: [
          (te ? 'జరుగుతున్నవి' : 'Open', '${askodoxPosInt(counts['open'])}', _purple),
          (te ? 'పూర్తి' : 'Done', '${askodoxPosInt(counts['done'])}', _green),
          (te ? 'ఆలస్యం' : 'Late', '${askodoxPosInt(counts['late'])}', _red),
        ]),
        const SizedBox(height: 10),
        if (boss)
          OutlinedButton.icon(
            key: const Key('askodoxTaskAdd'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48), foregroundColor: _purple, side: const BorderSide(color: _purple, width: 1.5)),
            onPressed: () => _add(people),
            icon: const Icon(Icons.add),
            label: Text(te ? 'పని కేటాయించు' : 'Give a task'),
          ),
        const SizedBox(height: 8),
        if (_data != null && tasks.isEmpty) Text(te ? 'పనులు లేవు.' : 'No tasks.', textAlign: TextAlign.center),
        if (tasks.isNotEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final t in tasks)
                CheckboxListTile(
                  key: Key('askodoxTask-${t['id']}'),
                  value: t['status'] == 'done',
                  onChanged: (v) async {
                    await ref.read(askodoxPosRepositoryProvider).taskDone(widget.businessId, '${t['id']}', undo: v != true);
                    await _load();
                  },
                  title: Text('${t['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([
                    '${t['assignee_name']}'.isEmpty ? '••${t['assignee']}' : '${t['assignee_name']}',
                    if (t['due_at'] != null) _clock(t['due_at']),
                    if (t['late'] == true) te ? 'ఆలస్యం' : 'late',
                  ].join(' · '),
                      style: TextStyle(color: t['late'] == true ? _red : _muted)),
                ),
            ]),
          ),
      ],
    );
  }
}

/// `/biz/:id/staff/setup` -- hours, how near the shop counts, which ways of checking in are on.
class AskodoxBizAttSetupScreen extends ConsumerStatefulWidget {
  const AskodoxBizAttSetupScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizAttSetupScreen> createState() => _AskodoxBizAttSetupScreenState();
}

class _AskodoxBizAttSetupScreenState extends ConsumerState<AskodoxBizAttSetupScreen> {
  AskodoxJson? _s;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final s = await ref.read(askodoxPosRepositoryProvider).attendanceSettings(widget.businessId);
        if (mounted) setState(() => _s = s);
      } catch (_) {}
    }());
  }

  Future<void> _save(AskodoxJson change) async {
    final te = askodoxPosTe(context);
    try {
      final s = await ref.read(askodoxPosRepositoryProvider).saveAttendanceSettings(widget.businessId, change);
      if (mounted) {
        setState(() => _s = {...?_s, ...s});
        askodoxPosSnack(context, te ? 'సేవ్ అయింది ✓' : 'Saved ✓');
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _time(String key) async {
    final cur = '${_s?[key] ?? '09:00'}'.split(':');
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: int.tryParse(cur.first) ?? 9, minute: int.tryParse(cur.last) ?? 0));
    if (t != null) await _save({key: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'});
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final s = _s;
    return AskodoxBizScaffold(
      key: const Key('askodoxBizAttSetup'),
      businessId: widget.businessId,
      tone: askodoxBizTones['staff']!,
      icon: Icons.tune,
      title: te ? 'హాజరు ఎలా వేయాలి?' : 'How attendance works',
      trail: [te ? 'సిబ్బంది & హాజరు' : 'Staff & attendance', te ? 'హాజరు సెటప్' : 'Setup'],
      page: 'staff',
      askHint: te ? '"అందరికీ 9 గంటల టైం"' : '"Everyone starts at 9"',
      children: s == null
          ? [const Center(child: CircularProgressIndicator())]
          : [
              AskodoxBizSection(te ? 'పద్ధతి — ఒకటి లేదా రెండూ' : 'Method — one or both'),
              SwitchListTile(
                key: const Key('askodoxAttOwnPhone'),
                tileColor: Colors.white,
                value: s['own_phone'] == true,
                onChanged: (v) => _save({'own_phone': v}),
                title: Text(te ? 'ప్రతి ఒక్కరి ఫోన్‌లో' : "On each person's phone"),
                subtitle: Text(te ? 'వారి ఫోన్ వేలిముద్ర / ముఖం / PIN + షాప్ దగ్గర ఉన్నారా' : 'Their phone lock + are they at the shop'),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                key: const Key('askodoxAttKiosk'),
                tileColor: Colors.white,
                value: s['kiosk'] == true,
                onChanged: (v) => _save({'kiosk': v}),
                title: Text(te ? 'షాప్ ఫోన్ / ట్యాబ్‌లో' : 'On the shop phone / tablet'),
                subtitle: Text(te ? 'ఫోన్ లేనివారికి — ఫోటో + టైం' : 'For people without a phone — photo + time'),
              ),
              if (s['shop_pin'] != true) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFFF1E3), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                      te
                          ? 'షాప్ మ్యాప్ పిన్ ఇంకా పెట్టలేదు — "బిజినెస్ వివరాలు"లో పెడితే "షాప్ దగ్గర ఉన్నారా" చూడగలం.'
                          : 'The shop map pin is not set — set it in "Business details" to check "at the shop".',
                      style: const TextStyle(color: _orange, fontWeight: FontWeight.w700)),
                ),
              ],
              AskodoxBizSection(te ? 'నియమాలు' : 'Rules'),
              AskodoxBizGrid(children: [
                AskodoxBizTile(
                  key: const Key('askodoxAttStart'),
                  icon: Icons.login,
                  title: te ? 'పని మొదలు' : 'Start',
                  sub: '${s['start_time']}',
                  tone: askodoxBizTones['green']!,
                  minHeight: 72,
                  onTap: () => _time('start_time'),
                ),
                AskodoxBizTile(
                  key: const Key('askodoxAttEnd'),
                  icon: Icons.logout,
                  title: te ? 'పని ముగింపు' : 'End',
                  sub: '${s['end_time']}',
                  tone: askodoxBizTones['orange']!,
                  minHeight: 72,
                  onTap: () => _time('end_time'),
                ),
                AskodoxBizTile(
                  key: const Key('askodoxAttGrace'),
                  icon: Icons.timer_outlined,
                  title: te ? 'ఆలస్యం ఓకే' : 'Late allowed',
                  sub: te ? '${s['grace_min']} ని.' : '${s['grace_min']} min',
                  tone: askodoxBizTones['blue']!,
                  minHeight: 72,
                  onTap: () async {
                    final v = await _ask(te ? 'ఎన్ని నిమిషాల ఆలస్యం ఓకే?' : 'Minutes of lateness allowed?', '${s['grace_min']}');
                    if (v != null) await _save({'grace_min': v});
                  },
                ),
                AskodoxBizTile(
                  key: const Key('askodoxAttRadius'),
                  icon: Icons.place_outlined,
                  title: te ? 'షాప్ దగ్గర' : 'Near the shop',
                  sub: te ? '${s['radius_m']} మీటర్ల లోపల' : 'within ${s['radius_m']} m',
                  tone: askodoxBizTones['teal']!,
                  minHeight: 72,
                  onTap: () async {
                    final v = await _ask(te ? 'ఎన్ని మీటర్ల లోపల?' : 'Within how many metres?', '${s['radius_m']}');
                    if (v != null) await _save({'radius_m': v});
                  },
                ),
              ]),
            ],
    );
  }

  Future<int?> _ask(String title, String initial) async {
    final c = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK'))],
      ),
    );
    c.dispose();
    return int.tryParse((v ?? '').trim());
  }
}

/// `/biz/:id/staff/today` -- everyone today: when they came, how (phone lock / photo / owner), near the shop or not,
/// and ONE tap to set P / A / OT / leave.
class AskodoxBizAttTodayScreen extends ConsumerWidget {
  const AskodoxBizAttTodayScreen({super.key, required this.businessId});
  final String businessId;

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    final data = ref.watch(askodoxAttTodayProvider(businessId));
    Future<void> mark(String ref0, String status) async {
      var ot = 0;
      if (status == 'OT') {
        final c = TextEditingController(text: '2');
        final v = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(te ? 'ఎన్ని గంటలు ఎక్కువ?' : 'How many extra hours?'),
            content: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK'))],
          ),
        );
        c.dispose();
        final hours = double.tryParse((v ?? '').trim());
        if (hours == null || hours <= 0) return;
        ot = (hours * 60).round();
      }
      try {
        await ref.read(askodoxPosRepositoryProvider).attendanceMark(businessId, ref0, _today(), status, otMin: ot);
        ref.invalidate(askodoxAttTodayProvider(businessId));
      } on AskodoxPosException catch (e) {
        if (context.mounted) askodoxPosSnack(context, e.message(te));
      }
    }

    return AskodoxBizScaffold(
      key: const Key('askodoxBizAttToday'),
      businessId: businessId,
      tone: askodoxBizTones['staff']!,
      icon: Icons.how_to_reg_outlined,
      title: te ? 'ఈ రోజు హాజరు' : "Today's attendance",
      trail: [te ? 'సిబ్బంది & హాజరు' : 'Staff & attendance', te ? 'హాజరు' : 'Attendance'],
      page: 'staff',
      onRefresh: () async => ref.invalidate(askodoxAttTodayProvider(businessId)),
      askHint: te ? '"రవి ఈ రోజు సెలవు" "ప్రసాద్ 2 గంటలు OT"' : '"Ravi is on leave today" "Prasad 2 hours OT"',
      children: data.when(
        loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
        error: (e, _) => [AskodoxPosError(error: e, onRetry: () => ref.invalidate(askodoxAttTodayProvider(businessId)))],
        data: (d) {
          final people = askodoxPosList(d['people']);
          final counts = askodoxPosMap(d['counts']);
          return [
            AskodoxBizStrip(cells: [
              (te ? 'వచ్చారు' : 'Present', '${askodoxPosInt(counts['present'])}', _green),
              (te ? 'రాలేదు' : 'Absent', '${(people.length - askodoxPosInt(counts['present'])).clamp(0, 999)}', _red),
              (te ? 'ఆలస్యం' : 'Late', '${askodoxPosInt(counts['late'])}', _orange),
            ]),
            AskodoxBizSection(te ? 'ఎవరు ఎప్పుడు — ఎలా వేశారు, ఎక్కడ' : 'Who came when — how, and where'),
            for (final p in people) _todayRow(context, p, te, mark),
            const SizedBox(height: 6),
            Text(te ? 'P = వచ్చారు · A = రాలేదు · OT = ఎక్కువ గంటలు · సె = సెలవు — రంగులతో, చదవకపోయినా అర్థమవుతుంది' : 'P present · A absent · OT overtime · L leave',
                style: const TextStyle(fontSize: 11.5, color: _muted)),
          ];
        },
      ),
    );
  }

  Widget _todayRow(BuildContext context, AskodoxJson p, bool te, Future<void> Function(String, String) mark) {
    final t = askodoxPosMap(p['today']);
    final status = t.isEmpty ? '' : '${t['status']}';
    final name = '${p['name']}'.isEmpty ? '••${p['ref']}' : '${p['name']}';
    final how = switch ('${t['method'] ?? ''}') {
      'device_lock' => te ? 'ఫోన్ లాక్ ✓' : 'Phone lock ✓',
      'photo' || 'kiosk' => te ? 'ఫోటో ✓' : 'Photo ✓',
      'owner' => te ? 'ఓనర్ రాశారు' : 'By owner',
      _ => '',
    };
    return Card(
      key: Key('askodoxAttTodayRow-${p['ref']}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFF1EBFB),
                child: Text(name.characters.first, style: const TextStyle(color: _purple, fontWeight: FontWeight.w900))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$name · ${p['role']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                    [
                      '${te ? 'వచ్చింది' : 'in'} ${_clock(t['in_at'])}',
                      '${te ? 'వెళ్ళింది' : 'out'} ${_clock(t['out_at'])}',
                      if (how.isNotEmpty) how,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: _muted)),
              ]),
            ),
            if (t['distance_m'] != null)
              _pill(t['far'] == true ? (te ? 'దూరంగా' : 'Far') : (te ? 'షాప్ దగ్గర' : 'At shop'), t['far'] == true ? _red : _green),
          ]),
          if (askodoxPosInt(t['late_min']) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _pill(te ? 'ఆలస్యం ${askodoxPosInt(t['late_min'])} ని.' : 'Late ${askodoxPosInt(t['late_min'])} min', _orange),
            ),
          const SizedBox(height: 8),
          Row(children: [
            for (final (s, short, color) in [
              ('P', 'P', _green),
              ('A', 'A', _red),
              ('OT', 'OT', _orange),
              ('leave', te ? 'సెలవు' : 'Leave', _purple),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton(
                    key: Key('askodoxAttToday-${p['ref']}-$s'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: status == s ? color : null,
                      foregroundColor: status == s ? Colors.white : color,
                      side: BorderSide(color: color, width: 1.5),
                      minimumSize: const Size.fromHeight(40),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => mark('${p['ref']}', s),
                    child: Text(short, style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}
