import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../business/presentation/biz_staff.dart' show askodoxAttTodayProvider;
import '../../location/application/location_controller.dart' show deviceLocationGatewayProvider;
import '../../location/domain/geo_models.dart' show LocationPermissionStatus;
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

const _purple = Color(0xFF7C3AED);

/// `/biz/:id/staff/checkin` (owner 2026-11-22, "3 steps"; owner AND staff mark their own): ① one big round button
/// (I'm in / I'm leaving, by today's state) ② the phone's own fingerprint / face / PIN (no lock -> a selfie)
/// ③ ✓ the time + how far from the shop. Half day / leave are the small words under the button. Old page `?full=1`.
class AskodoxCheckInStepsScreen extends ConsumerStatefulWidget {
  const AskodoxCheckInStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxCheckInStepsScreen> createState() => _AskodoxCheckInStepsScreenState();
}

class _AskodoxCheckInStepsScreenState extends ConsumerState<AskodoxCheckInStepsScreen> {
  static const _hardware = MethodChannel('com.askodox.app/hardware');
  int _step = 1;
  String _action = 'in';
  AskodoxJson? _out;
  String _shopName = '';
  Timer? _clock;
  DateTime _now = DateTime.now();

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    unawaited(ref.read(askodoxPosRepositoryProvider).shopState(widget.businessId).then((shop) {
      if (mounted) setState(() => _shopName = '${shop['name'] ?? ''}');
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  static String _hm(DateTime t, bool te) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final am = t.hour < 12;
    return te ? '$h:$m ${am ? 'ఉ.' : 'సా.'}' : '$h:$m ${am ? 'AM' : 'PM'}';
  }

  static String _clockOf(Object? iso, bool te) {
    final t = DateTime.tryParse('${iso ?? ''}');
    return t == null ? '' : _hm(t.toLocal(), te);
  }

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

  /// Step 2 runs by itself: the phone lock (or a selfie), the place, the record.
  Future<void> _go(String action) async {
    final te = _te;
    setState(() {
      _action = action;
      _step = 2;
    });
    try {
      var method = 'device_lock';
      var photo = '';
      if (action != 'leave') {
        final lock = await _lock(te);
        if (lock == 'cancelled') {
          if (mounted) setState(() => _step = 1);
          return;
        }
        if (lock == 'no_lock' || lock == 'unsupported') {
          final shot = await ImagePicker().pickImage(
              source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, maxWidth: 480, imageQuality: 60);
          if (shot == null) {
            if (mounted) setState(() => _step = 1);
            return;
          }
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
      ref.invalidate(askodoxAttTodayProvider(widget.businessId));
      setState(() {
        _out = out;
        _step = 3;
      });
    } on AskodoxPosException catch (e) {
      if (mounted) {
        setState(() => _step = 1);
        askodoxPosSnack(context, e.message(te));
      }
    }
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    final id = widget.businessId;
    return [
      AskodoxStepMore('askodoxCheckInStepsToday', te ? 'ఈ రోజు హాజరు' : "Today's attendance", Icons.how_to_reg_rounded,
          () => context.push('/biz/$id/staff/today')),
      AskodoxStepMore('askodoxCheckInStepsFull', te ? 'పాత హాజరు పేజీ' : 'Old check-in page', Icons.fingerprint_rounded,
          () => context.push('/biz/$id/staff/checkin?full=1')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'నా హాజరు' : 'My attendance';
    return switch (_step) {
      2 => AskodoxStepScaffold(
          key: const Key('askodoxCheckInSteps2'),
          title: title,
          sub: _shopName,
          step: 2,
          color: _purple,
          question: _action == 'leave' ? (te ? 'రాస్తున్నాం…' : 'Saving…') : (te ? 'మీరేనా? ఫోన్ లాక్ చూపించండి' : 'Is it you? Use your phone lock'),
          hint: _action == 'leave'
              ? null
              : (te ? 'వేలిముద్ర / ముఖం / PIN — లాక్ లేకపోతే సెల్ఫీ అడుగుతుంది' : 'Fingerprint / face / PIN — no lock? It asks for a selfie'),
          body: const Center(
            child: SizedBox(
              width: 170,
              height: 170,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(width: 170, height: 170, child: CircularProgressIndicator(strokeWidth: 5, color: _purple)),
                Icon(Icons.fingerprint_rounded, size: 100, color: _purple),
              ]),
            ),
          ),
        ),
      3 => AskodoxStepScaffold(
          key: const Key('askodoxCheckInSteps3'),
          title: title,
          sub: _shopName,
          step: 3,
          color: _purple,
          more: _more(),
          body: _doneStep(te),
          bottom: AskodoxStepBottom(
              buttonKey: const Key('askodoxCheckInStepsOk'),
              label: te ? 'సరే' : 'OK',
              color: _purple,
              onPressed: () => Navigator.of(context).maybePop()),
        ),
      _ => AskodoxStepScaffold(
          key: const Key('askodoxCheckInSteps1'),
          title: title,
          sub: _shopName,
          step: 1,
          color: _purple,
          more: _more(),
          body: _firstStep(te),
        ),
    };
  }

  Widget _firstStep(bool te) {
    final today = ref.watch(askodoxAttTodayProvider(widget.businessId)).valueOrNull;
    // `me` = the caller's own day (owner / manager included); an older server only had it for staff (first row).
    final att = today?['me'] is Map
        ? askodoxPosMap(today?['me'])
        : askodoxPosMap((today?['boss'] == true ? null : askodoxPosList(today?['people']).firstOrNull)?['today']);
    final start = '${askodoxPosMap(today?['settings'])['start_time'] ?? ''}';
    final inAt = att['in_at'];
    final outAt = att['out_at'];
    final leave = '${att['status'] ?? ''}' == 'leave';
    final finished = leave || (inAt != null && outAt != null);
    final action = inAt != null && outAt == null ? 'out' : 'in';
    final dayName = te
        ? const ['సోమవారం', 'మంగళవారం', 'బుధవారం', 'గురువారం', 'శుక్రవారం', 'శనివారం', 'ఆదివారం'][_now.weekday - 1]
        : const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][_now.weekday - 1];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 16), children: [
      AskodoxStepBigNumber(_hm(_now, te),
          label: [dayName, if (start.isNotEmpty) (te ? 'షిఫ్ట్ $start కి' : 'shift at $start')].join(' · '), size: 46),
      const SizedBox(height: 36),
      if (finished)
        Column(children: [
          const AskodoxStepDoneMark(color: _purple),
          const SizedBox(height: 28),
          Text(
              leave
                  ? (te ? 'ఈ రోజు సెలవు రాశాం' : 'On leave today')
                  : (te
                      ? '${_clockOf(inAt, te)} వచ్చారు · ${_clockOf(outAt, te)} వెళ్ళారు'
                      : 'In ${_clockOf(inAt, te)} · out ${_clockOf(outAt, te)}'),
              key: const Key('askodoxCheckInStepsFinished'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: askodoxStepInk)),
        ])
      else
        Center(
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0xFFEDE7FB), spreadRadius: 16), BoxShadow(color: Color(0xFFF6F2FD), spreadRadius: 32)],
            ),
            child: Material(
              color: action == 'out' ? const Color(0xFFB91C1C) : _purple,
              shape: const CircleBorder(),
              child: InkWell(
                key: Key('askodoxCheckInStepsGo-$action'),
                customBorder: const CircleBorder(),
                onTap: () => _go(action),
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(action == 'out' ? Icons.logout_rounded : Icons.fingerprint_rounded, size: 76, color: Colors.white),
                    const SizedBox(height: 6),
                    Text(action == 'out' ? (te ? 'వెళ్తున్నా' : "I'm leaving") : (te ? 'వచ్చాను' : "I'm in"),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    if (inAt != null)
                      Text(te ? '${_clockOf(inAt, te)} కి వచ్చారు' : 'In at ${_clockOf(inAt, te)}',
                          style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: 40),
      if (!finished)
        Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 4, children: [
          TextButton(
              key: const Key('askodoxCheckInStepsHalf'),
              onPressed: () => _go('half'),
              child: Text(te ? 'ఈ రోజు హాఫ్ డే' : 'Half day today')),
          if (inAt == null)
            TextButton(
                key: const Key('askodoxCheckInStepsLeave'),
                onPressed: () => _go('leave'),
                child: Text(te ? 'ఈ రోజు సెలవు' : 'On leave today')),
        ]),
    ]);
  }

  Widget _doneStep(bool te) {
    final out = _out ?? const <String, Object?>{};
    final distance = out['distance_m'];
    final late = askodoxPosInt(out['late_min']);
    final when = switch (_action) {
      'out' => te ? '${_clockOf(out['out_at'], te)} కి వెళ్ళారు' : 'Left at ${_clockOf(out['out_at'], te)}',
      'leave' => te ? 'ఈ రోజు సెలవు రాశాం' : 'Leave noted for today',
      'half' => te ? 'ఈ రోజు హాఫ్ డే రాశాం' : 'Half day noted',
      _ => te ? '${_clockOf(out['in_at'], te)} కి వచ్చారు' : 'In at ${_clockOf(out['in_at'], te)}',
    };
    return ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
      const Center(child: AskodoxStepDoneMark(color: _purple)),
      const SizedBox(height: 26),
      AskodoxStepBigNumber(out['already'] == true ? (te ? 'ముందే వేశారు ✓' : 'Already done ✓') : when,
          label: _action == 'in' && late > 0 ? (te ? '$late ని. లేట్' : '$late min late') : null, size: 30),
      const SizedBox(height: 12),
      if (distance != null)
        Center(
          child: AskodoxStepPill(
              out['far'] == true
                  ? (te
                      ? 'షాప్‌కి ${askodoxPosInt(distance)} మీ. దూరం — ఓనర్‌కి తెలుస్తుంది'
                      : '${askodoxPosInt(distance)} m from the shop — the owner will see it')
                  : (te ? 'షాప్ దగ్గరే ఉన్నారు · ${askodoxPosInt(distance)} మీ.' : 'At the shop · ${askodoxPosInt(distance)} m'),
              kind: out['far'] == true ? 'warn' : 'good'),
        )
      else if (_action != 'leave')
        Center(child: AskodoxStepPill(te ? 'లొకేషన్ దొరకలేదు' : 'No location', kind: 'grey')),
      const SizedBox(height: 18),
      Text(
          te
              ? 'ఓనర్‌కి: టైం, పద్ధతి, షాప్ నుంచి దూరం. ఫోటోలు ఓనర్‌కి మాత్రమే, 90 రోజుల తర్వాత తీసేస్తాం.'
              : 'The owner sees the time, the method and the distance. Photos are for the owner only, deleted after 90 days.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: askodoxStepMuted)),
    ]);
  }
}
