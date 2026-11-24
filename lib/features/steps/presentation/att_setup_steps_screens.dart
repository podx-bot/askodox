import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../location/application/location_controller.dart' show deviceLocationGatewayProvider;
import '../../location/domain/geo_models.dart' show GeoPoint, LocationPermissionStatus;
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 20): how attendance works `/biz/:id/staff/setup`. Top = ONE question, middle =
/// ONE list (tap a row = a small sheet with the big choices), bottom = ONE big button (the shop is here: sets the shop
/// location standing in the shop; a fake-GPS fix is never taken). The old page stays at `?full=1`.
class AskodoxAttSetupStepsScreen extends ConsumerStatefulWidget {
  const AskodoxAttSetupStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxAttSetupStepsScreen> createState() => _AttSetupState();
}

class _AttSetupState extends ConsumerState<AskodoxAttSetupStepsScreen> {
  AskodoxJson? _s;
  Object? _error;
  bool _busy = false;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final s = await _repo.attendanceSettings(widget.businessId);
      if (mounted) {
        setState(() {
          _s = s;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _s == null) setState(() => _error = e);
    }
  }

  Future<void> _save(AskodoxJson change) async {
    try {
      final s = await _repo.saveAttendanceSettings(widget.businessId, change);
      if (mounted) {
        setState(() => _s = {...?_s, ...s});
        askodoxPosSnack(context, _te ? 'సేవ్ అయింది ✓' : 'Saved ✓');
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    }
  }

  Future<void> _pinHere() async {
    final te = _te;
    setState(() => _busy = true);
    GeoPoint? at;
    try {
      final gate = ref.read(deviceLocationGatewayProvider);
      if (await gate.ensurePermission() == LocationPermissionStatus.granted) at = await gate.getCurrentPosition();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    if (at == null) {
      askodoxPosSnack(context, te ? 'లొకేషన్ దొరకలేదు — ఫోన్ లొకేషన్ ఆన్ చేయండి.' : 'No location — turn on the phone\'s location.');
      return;
    }
    if (at.mocked) {
      askodoxPosSnack(context, te ? 'ఈ ఫోన్ లో నకిలీ GPS యాప్ ఉంది — షాప్ లొకేషన్ గా తీసుకోం.' : 'A fake-GPS app is on — not taken as the shop.');
      return;
    }
    await _save({'pin_lat': at.latitude, 'pin_lng': at.longitude});
  }

  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _time(String key) async {
    final cur = '${_s?[key] ?? '09:00'}'.split(':');
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: int.tryParse(cur.first) ?? 9, minute: int.tryParse(cur.last) ?? 0));
    if (t != null && mounted) await _save({key: _hhmm(t)});
  }

  /// A sheet of switches; each flip saves at once.
  Future<void> _switches(String title, List<(String, String, String)> rows) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              for (final (key, name, sub) in rows)
                SwitchListTile(
                  key: Key('askodoxAttSetupSteps-$key'),
                  contentPadding: EdgeInsets.zero,
                  value: key == 'own_phone' || key == 'kiosk' ? _s?[key] == true : _s?[key] != false,
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(sub),
                  onChanged: (v) async {
                    await _save({key: v});
                    setSheet(() {});
                  },
                ),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _choosePicker(String title, String key, List<int> values, String unit) async {
    final cur = askodoxPosInt(_s?[key]);
    final v = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in values)
                ChoiceChip(
                  key: Key('askodoxAttSetupStepsPick-$key-$n'),
                  label: Text('$n $unit', style: const TextStyle(fontSize: 16)),
                  selected: cur == n,
                  onSelected: (_) => Navigator.pop(ctx, n),
                ),
            ]),
          ]),
        ),
      ),
    );
    if (v != null && mounted) await _save({key: v});
  }

  Future<void> _hours() async {
    final te = _te;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(te ? 'పని టైం' : 'Work hours', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              FilledButton(
                  key: const Key('askodoxAttSetupStepsStart'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: () async {
                    await _time('start_time');
                    setSheet(() {});
                  },
                  child: Text('${te ? 'మొదలు' : 'Start'}  ${_s?['start_time']}')),
              const SizedBox(height: 10),
              FilledButton(
                  key: const Key('askodoxAttSetupStepsEnd'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: askodoxStepWarn),
                  onPressed: () async {
                    await _time('end_time');
                    setSheet(() {});
                  },
                  child: Text('${te ? 'ముగింపు' : 'End'}  ${_s?['end_time']}')),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _holidays() async {
    final te = _te;
    var rows = <AskodoxJson>[];
    try {
      rows = await _repo.shopHolidays(widget.businessId);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setLocal) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(te ? 'షాప్ సెలవు రోజులు' : 'Shop holidays', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(te ? 'ఈ రోజుల్లో నెల జీతం ఉన్నవారికి జీతం కట్ అవ్వదు.' : 'People on a monthly salary are paid for these days.',
                  style: const TextStyle(color: askodoxStepMuted)),
              for (final h in rows)
                ListTile(
                  key: ValueKey('askodoxAttSetupStepsHoliday-${h['date']}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.celebration_outlined),
                  title: Text('${h['date']}${'${h['name'] ?? ''}'.isEmpty ? '' : ' · ${h['name']}'}'),
                  trailing: IconButton(
                    tooltip: te ? 'తీసేయి' : 'Remove',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () async {
                      try {
                        final next = await _repo.setShopHoliday(widget.businessId, '${h['date']}', remove: true);
                        setLocal(() => rows = next);
                      } on AskodoxPosException catch (_) {
                        // the list stays as it was
                      }
                    },
                  ),
                ),
              OutlinedButton.icon(
                key: const Key('askodoxAttSetupStepsHolidayAdd'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: const Icon(Icons.add),
                label: Text(te ? 'సెలవు రోజు చేర్చు' : 'Add a holiday'),
                onPressed: () async {
                  final now = DateTime.now();
                  final day = await showDatePicker(
                      context: sheet, initialDate: now, firstDate: now.subtract(const Duration(days: 31)), lastDate: now.add(const Duration(days: 366)));
                  if (day == null) return;
                  final date = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                  try {
                    final next = await _repo.setShopHoliday(widget.businessId, date);
                    setLocal(() => rows = next);
                  } on AskodoxPosException catch (_) {
                    // the list stays as it was
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'హాజరు సెటప్' : 'Attendance setup';
    final more = [
      AskodoxStepMore('askodoxAttSetupStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
          () => context.push('/biz/${widget.businessId}/staff/setup?full=1')),
    ];
    if (_error != null) return AskodoxStepScaffold(title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    final s = _s;
    if (s == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    final pinned = s['shop_pin'] == true;
    final methods = [if (s['own_phone'] == true) te ? 'ఫోన్' : 'Phone', if (s['kiosk'] == true) te ? 'షాప్ ట్యాబ్' : 'Shop tablet'];
    final checks = [s['require_location'] != false, s['require_live_face'] != false, s['outside_needs_ok'] != false].where((e) => e).length;
    return AskodoxStepScaffold(
      key: const Key('askodoxAttSetupSteps'),
      title: title,
      question: te ? 'హాజరు ఎలా వేయాలి?' : 'How is attendance marked?',
      hint: pinned
          ? (te ? 'షాప్ లొకేషన్ పెట్టారు ✓ — ${s['radius_m']} m లోపల ఉంటేనే హాజరు' : 'Shop location set ✓ — attendance only within ${s['radius_m']} m')
          : (te ? 'షాప్ లొకేషన్ ఇంకా లేదు. షాప్ లో నిలబడి కింద బటన్ నొక్కండి — ఒక్కసారే.' : 'No shop location yet. Stand in the shop and tap the button below — once.'),
      more: more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        AskodoxStepPersonRow(
          key: const Key('askodoxAttSetupStepsMethod'),
          name: te ? 'పద్ధతి' : 'Method',
          sub: te ? 'ప్రతి ఒక్కరి ఫోన్ లో / షాప్ ఫోన్ లో' : 'On each phone / on the shop phone',
          amount: methods.isEmpty ? (te ? 'ఆఫ్' : 'Off') : methods.length == 2 ? (te ? 'రెండూ' : 'Both') : methods.first,
          amountColor: methods.isEmpty ? askodoxStepBad : askodoxStepGreen,
          onTap: () => _switches(te ? 'పద్ధతి — ఒకటి లేదా రెండూ' : 'Method — one or both', [
            ('own_phone', te ? 'ప్రతి ఒక్కరి ఫోన్‌లో' : "On each person's phone", te ? 'షాప్ దగ్గర ఉన్నారా (GPS) + ముఖం లైవ్ చెక్' : 'At the shop (GPS) + a live face check'),
            ('kiosk', te ? 'షాప్ ఫోన్ / ట్యాబ్‌లో' : 'On the shop phone / tablet', te ? 'ఫోన్ లేనివారికి — ముఖం లైవ్ చెక్ + టైం' : 'For people without a phone — live face check + time'),
          ]),
        ),
        AskodoxStepPersonRow(
          key: const Key('askodoxAttSetupStepsHours'),
          name: te ? 'పని టైం' : 'Work hours',
          sub: te ? 'మొదలు, ముగింపు' : 'Start, end',
          amount: '${s['start_time']}',
          onTap: _hours,
        ),
        AskodoxStepPersonRow(
          key: const Key('askodoxAttSetupStepsGrace'),
          name: te ? 'ఆలస్యం ఓకే' : 'Late allowed',
          sub: te ? 'ఎన్ని నిమిషాల ఆలస్యం ఓకే' : 'Minutes of lateness that are fine',
          amount: te ? '${s['grace_min']} ని.' : '${s['grace_min']} min',
          onTap: () => _choosePicker(te ? 'ఎన్ని నిమిషాల ఆలస్యం ఓకే?' : 'Minutes of lateness allowed?', 'grace_min', const [0, 5, 10, 15, 30], te ? 'ని.' : 'min'),
        ),
        AskodoxStepPersonRow(
          key: const Key('askodoxAttSetupStepsRadius'),
          name: te ? 'షాప్ దగ్గర' : 'Near the shop',
          sub: te ? 'ఎన్ని మీటర్ల లోపల హాజరు' : 'Metres around the shop that count',
          amount: '${s['radius_m']} m',
          onTap: () => _choosePicker(te ? 'ఎన్ని మీటర్ల లోపల?' : 'Within how many metres?', 'radius_m', const [50, 100, 150, 300], 'm'),
        ),
        AskodoxStepPersonRow(
          key: const Key('askodoxAttSetupStepsCheats'),
          name: te ? 'మోసం రాకుండా' : 'No cheating',
          sub: te ? 'లొకేషన్ తప్పనిసరి, ముఖం లైవ్ చెక్, దూరంగా ఉంటే అడుగు' : 'Location a must, live face check, away = ask me',
          amount: '$checks/3',
          amountColor: checks == 3 ? askodoxStepGreen : askodoxStepWarn,
          onTap: () => _switches(te ? 'మోసం రాకుండా' : 'No cheating', [
            ('require_location', te ? 'లొకేషన్ తప్పనిసరి' : 'Location is a must', te ? 'GPS ఆఫ్ / నకిలీ GPS = హాజరు పడదు, మీకు వెంటనే తెలుస్తుంది' : 'GPS off / fake GPS = not marked, you are told at once'),
            ('require_live_face', te ? 'ముఖం లైవ్ చెక్' : 'Live face check', te ? 'ప్రతిసారీ వేరే కదలికలు — ఫోటో పెట్టి మోసం చేయలేరు. ఉచితం, ఫోన్ లోనే.' : 'Random moves every time — a photo cannot do it. Free, on the phone.'),
            ('outside_needs_ok', te ? 'దూరంగా ఉంటే నన్ను అడగాలి' : 'Away from the shop = ask me', te ? 'బయట పని అయితే "ఓనర్ ని అడుగు" — మీకు notification వస్తుంది' : 'Field work goes as "ask the owner" — you get a notification'),
          ]),
        ),
        AskodoxStepPersonRow(
          key: const Key('askodoxAttSetupStepsHolidays'),
          name: te ? 'షాప్ సెలవు రోజులు' : 'Shop holidays',
          sub: te ? 'జీతంతో సెలవు' : 'Paid days off',
          amount: te ? 'చూడు' : 'Open',
          onTap: _holidays,
        ),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxAttSetupStepsPin'),
        label: pinned ? (te ? 'మళ్ళీ — ఇక్కడే షాప్' : 'Again — the shop is here') : (te ? 'ఇక్కడే షాప్ — లొకేషన్ పెట్టు' : 'The shop is here — set it'),
        icon: Icons.my_location_rounded,
        busy: _busy,
        onPressed: _pinHere,
      ),
    );
  }
}
