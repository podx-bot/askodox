import '../../../config/theme/askodox_look.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../business/presentation/biz_staff.dart' show askodoxAttTodayProvider;
import '../../location/application/location_controller.dart' show deviceLocationGatewayProvider;
import '../../location/domain/geo_models.dart' show GeoPoint, LocationPermissionStatus;
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import '../domain/step_logic.dart' show askodoxDistanceM, askodoxDistanceText;
import 'live_face_screen.dart';
import 'step_kit.dart';

const _purple = Color(0xFFBCACFB);

/// `/biz/:id/staff/checkin` (owner 2026-11-22, "3 steps"; owner AND staff mark their own): ① one big round button
/// (I'm in / I'm leaving, by today's state) ② WHERE: the phone's real location inside the shop's radius (owner
/// 2026-11-23: compulsory; fake GPS refused; far = "ask the owner"; the owner sets the shop pin here the first time),
/// then WHO: a live face check (random head turn / tilt / blink -- a photo of a photo cannot do it) ③ ✓ the time + how
/// far from the shop. Half day / leave are the small words under the button. Old page `?full=1`.
class AskodoxCheckInStepsScreen extends ConsumerStatefulWidget {
  const AskodoxCheckInStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxCheckInStepsScreen> createState() => _AskodoxCheckInStepsScreenState();
}

class _AskodoxCheckInStepsScreenState extends ConsumerState<AskodoxCheckInStepsScreen> {
  int _step = 1;
  String _action = 'in';
  AskodoxJson? _out;
  String _shopName = '';
  Timer? _clock;
  DateTime _now = DateTime.now();

  /// Step 2's state: place (reading GPS) | no_location | set_pin (owner) | no_pin (staff) | far | face | saving | error
  String _phase = 'place';
  String _problem = '';
  AskodoxJson _settings = const {};
  GeoPoint? _pos;
  int? _distance;
  bool _outside = false;

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

  Future<GeoPoint?> _where() async {
    try {
      final gate = ref.read(deviceLocationGatewayProvider);
      if (await gate.ensurePermission() != LocationPermissionStatus.granted) return null;
      return await gate.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  bool _boss = false;

  /// Step 2 runs by itself: where (location + shop radius), then the live face, then the record.
  Future<void> _go(String action) async {
    // read now, while step 1 still watches today's list (an owner / manager may set the shop pin)
    _boss = ref.read(askodoxAttTodayProvider(widget.businessId)).valueOrNull?['boss'] == true;
    setState(() {
      _action = action;
      _step = 2;
      _phase = 'place';
      _problem = '';
      _outside = false;
      _distance = null;
    });
    if (action == 'leave') return _submit();
    try {
      _settings = await ref.read(askodoxPosRepositoryProvider).attendanceSettings(widget.businessId);
    } catch (_) {
      _settings = const {}; // the server still checks everything
    }
    final pos = await _where();
    if (!mounted) return;
    _pos = pos;
    final needPlace = _settings['require_location'] != false;
    if (pos == null) {
      if (needPlace) {
        setState(() => _phase = 'no_location');
        return;
      }
      return _face();
    }
    // A fake-GPS fix goes to the server as such: it refuses and tells the owner (the phone shows why).
    if (pos.mocked) return _submit();
    final pin = askodoxPosMap(_settings['pin']);
    if (pin['lat'] is num && pin['lng'] is num) {
      _distance = askodoxDistanceM((pin['lat'] as num).toDouble(), (pin['lng'] as num).toDouble(), pos.latitude, pos.longitude);
      final radius = askodoxPosInt(_settings['radius_m']);
      if (radius > 0 && _distance! > radius && _settings['outside_needs_ok'] != false) {
        setState(() => _phase = 'far');
        return;
      }
    } else if (needPlace) {
      setState(() => _phase = _boss ? 'set_pin' : 'no_pin');
      return;
    }
    return _face();
  }

  /// The owner / manager, standing in the shop: "this is the shop" -- the pin is set once from this phone.
  Future<void> _setPinHere() async {
    final pos = _pos;
    if (pos == null || pos.mocked) return;
    setState(() => _phase = 'saving');
    try {
      _settings = await ref
          .read(askodoxPosRepositoryProvider)
          .saveAttendanceSettings(widget.businessId, {'pin_lat': pos.latitude, 'pin_lng': pos.longitude});
      _distance = 0;
      if (mounted) await _face();
    } on AskodoxPosException catch (e) {
      if (mounted) {
        setState(() {
          _phase = 'error';
          _problem = e.message(_te);
        });
      }
    }
  }

  Future<void> _face() async {
    final needFace = _settings['require_live_face'] != false && (_action == 'in' || _action == 'half');
    List<int>? still;
    if (needFace) {
      setState(() => _phase = 'face');
      still = await askodoxLiveFaceCheck(context, te: _te);
      if (!mounted) return;
      if (still == null) {
        setState(() => _step = 1);
        return;
      }
    }
    await _submit(still: still);
  }

  Future<void> _submit({List<int>? still}) async {
    final te = _te;
    setState(() => _phase = 'saving');
    try {
      final pos = _pos;
      final out = await ref.read(askodoxPosRepositoryProvider).attendanceCheck(widget.businessId, {
        'action': _action,
        'method': still != null ? 'face_live' : 'device_lock',
        if (still != null) 'photo': base64Encode(still),
        if (pos != null && _action != 'leave') 'lat': pos.latitude,
        if (pos != null && _action != 'leave') 'lng': pos.longitude,
        'mocked': pos?.mocked == true,
        'outside': _outside,
      });
      if (!mounted) return;
      ref.invalidate(askodoxAttTodayProvider(widget.businessId));
      setState(() {
        _out = out;
        _step = 3;
      });
    } on AskodoxPosException catch (e) {
      if (mounted) {
        setState(() {
          _phase = 'error';
          _problem = e.message(te);
        });
      }
    }
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    final id = widget.businessId;
    return [
      AskodoxStepMore('askodoxCheckInStepsToday', te ? 'ఈ రోజు హాజరు' : "Today's attendance", Icons.how_to_reg_rounded,
          () => context.push('/biz/$id/staff/today')),
      AskodoxStepMore('askodoxCheckInStepsFull', te ? 'పాత హాజరు పేజీ' : 'Old check-in page', Icons.history_rounded,
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
          question: _placeQuestion(te),
          onBack: () => setState(() => _step = 1),
          body: _placeBody(te),
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

  String _placeQuestion(bool te) => switch (_phase) {
        'no_location' => te ? 'లొకేషన్ ఆన్ చేయండి' : 'Turn on location',
        'set_pin' => te ? 'ఇదే షాప్ లొకేషనా?' : 'Is this the shop?',
        'no_pin' => te ? 'షాప్ లొకేషన్ ఇంకా లేదు' : 'The shop location is not set',
        'far' => te ? 'మీరు షాప్ కి దూరంగా ఉన్నారు' : 'You are away from the shop',
        'face' => te ? 'ముఖం లైవ్ చెక్' : 'Live face check',
        'saving' => te ? 'రాస్తున్నాం…' : 'Saving…',
        'error' => te ? 'హాజరు పడలేదు' : 'Not marked',
        _ => te ? 'షాప్ దగ్గర ఉన్నారా?' : 'Are you at the shop?',
      };

  Widget _placeBody(bool te) {
    Widget note(IconData icon, Color color, String text, List<Widget> buttons) =>
        ListView(padding: const EdgeInsets.fromLTRB(20, 30, 20, 20), children: [
          Icon(icon, size: 84, color: color),
          const SizedBox(height: 18),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: askodoxStepInk)),
          const SizedBox(height: 22),
          ...buttons,
        ]);
    Widget button(String key, String label, VoidCallback onTap, {bool main = true}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            height: 52,
            child: main
                ? FilledButton(key: Key(key), style: FilledButton.styleFrom(backgroundColor: _purple), onPressed: onTap, child: Text(label))
                : OutlinedButton(key: Key(key), onPressed: onTap, child: Text(label)),
          ),
        );
    final radius = askodoxPosInt(_settings['radius_m']);
    return switch (_phase) {
      'no_location' => note(
          Icons.location_off_rounded,
          const Color(0xFFFB9E6A),
          te
              ? 'హాజరుకి మీరు ఎక్కడ ఉన్నారో కావాలి. ఫోన్ లొకేషన్ ఆన్ చేసి ASKODOX కి అనుమతి ఇవ్వండి.'
              : 'Attendance needs where you are. Turn on the phone\'s location and allow ASKODOX.',
          [
            button('askodoxCheckInOpenLocation', te ? 'లొకేషన్ సెట్టింగ్స్ తెరువు' : 'Open location settings',
                () => unawaited(ref.read(deviceLocationGatewayProvider).openLocationSettings())),
            button('askodoxCheckInRetry', te ? 'మళ్ళీ చూడు' : 'Check again', () => _go(_action), main: false),
          ]),
      'set_pin' => note(
          Icons.add_location_alt_rounded,
          _purple,
          te
              ? 'షాప్ లొకేషన్ ఇంకా పెట్టలేదు. మీరు ఇప్పుడు షాప్ లోనే ఉంటే, ఇదే షాప్ లొకేషన్ గా పెడతాం — ఒక్కసారే.'
              : 'The shop location is not set. If you are in the shop now, this place becomes the shop — once.',
          [
            button('askodoxCheckInPinHere', te ? 'అవును, ఇదే షాప్' : 'Yes, this is the shop', _setPinHere),
            button('askodoxCheckInPinNo', te ? 'కాదు' : 'No', () => setState(() => _step = 1), main: false),
          ]),
      'no_pin' => note(
          Icons.wrong_location_rounded,
          const Color(0xFFFB9E6A),
          te ? 'ఓనర్ ఇంకా షాప్ లొకేషన్ పెట్టలేదు. ఓనర్ కి చెప్పండి — హాజరు సెటప్ లో ఒక్కసారి పెడితే చాలు.'
              : 'The owner has not set the shop location yet. Tell the owner — once in Attendance setup.',
          [button('askodoxCheckInBack', te ? 'సరే' : 'OK', () => setState(() => _step = 1), main: false)]),
      'far' => note(
          Icons.near_me_disabled_rounded,
          const Color(0xFFFB9E6A),
          te
              ? 'షాప్ కి ${askodoxDistanceText(_distance ?? 0)} దూరం (అనుమతి $radius m). బయట పని అయితే ఓనర్ ని అడగండి — ఓనర్ కి వెంటనే తెలుస్తుంది.'
              : '${askodoxDistanceText(_distance ?? 0)} from the shop (allowed $radius m). Field work? Ask the owner — they are told at once.',
          [
            button('askodoxCheckInAskOwner', te ? 'బయట పని — ఓనర్ ని అడుగు' : 'Field work — ask the owner', () {
              _outside = true;
              unawaited(_face());
            }),
            button('askodoxCheckInBack', te ? 'వెనక్కి' : 'Back', () => setState(() => _step = 1), main: false),
          ]),
      'error' => note(Icons.error_outline_rounded, const Color(0xFFFEA195), _problem, [
          button('askodoxCheckInRetry', te ? 'మళ్ళీ' : 'Try again', () => _go(_action)),
          button('askodoxCheckInBack', te ? 'వెనక్కి' : 'Back', () => setState(() => _step = 1), main: false),
        ]),
      _ => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
                width: 150, height: 150, child: CircularProgressIndicator(strokeWidth: 5, color: _purple)),
            const SizedBox(height: 18),
            Text(
                _distance != null
                    ? (te ? 'షాప్ నుంచి ${askodoxDistanceText(_distance!)} ✓' : '${askodoxDistanceText(_distance!)} from the shop ✓')
                    : (te ? 'GPS తో చూస్తున్నా…' : 'Reading GPS…'),
                key: const Key('askodoxCheckInPlace'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: askodoxStepInk)),
          ]),
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
              boxShadow: [BoxShadow(color: Color(0xFF000000), spreadRadius: 16), BoxShadow(color: Color(0xFF000000), spreadRadius: 32)],
            ),
            child: Material(
              color: action == 'out' ? const Color(0xFFFEA195) : _purple,
              shape: const CircleBorder(),
              child: InkWell(
                key: Key('askodoxCheckInStepsGo-$action'),
                customBorder: const CircleBorder(),
                onTap: () => _go(action),
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    // owner 2026-11-23: not a fingerprint any more -- the live face + location decide
                    Icon(action == 'out' ? Icons.logout_rounded : Icons.face_retouching_natural_rounded, size: 76, color: AskodoxLook.sheet),
                    const SizedBox(height: 6),
                    Text(action == 'out' ? (te ? 'వెళ్తున్నా' : "I'm leaving") : (te ? 'వచ్చాను' : "I'm in"),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AskodoxLook.sheet)),
                    if (inAt != null)
                      Text(te ? '${_clockOf(inAt, te)} కి వచ్చారు' : 'In at ${_clockOf(inAt, te)}',
                          style: const TextStyle(fontSize: 13, color: AskodoxLook.sheet70)),
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
      if ('${out['note'] ?? ''}'.contains('outside')) ...[
        const SizedBox(height: 8),
        Center(child: AskodoxStepPill(te ? 'బయట నుంచి — ఓనర్ ఒప్పుకోవాలి' : 'From outside — the owner decides', kind: 'warn')),
      ],
      if (out['method'] == 'face_live') ...[
        const SizedBox(height: 8),
        Center(child: AskodoxStepPill(te ? 'ముఖం లైవ్ గా చెక్ అయింది' : 'Live face checked', kind: 'good')),
      ],
      const SizedBox(height: 18),
      Text(
          te
              ? 'ఓనర్‌కి: టైం, పద్ధతి, షాప్ నుంచి దూరం, చివరి ఒక్క చిత్రం. ఫోటోలు ఓనర్‌కి మాత్రమే, 90 రోజుల తర్వాత తీసేస్తాం.'
              : 'The owner sees the time, the method and the distance. Photos are for the owner only, deleted after 90 days.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: askodoxStepMuted)),
    ]);
  }
}
