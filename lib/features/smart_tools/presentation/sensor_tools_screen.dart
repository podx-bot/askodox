import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../domain/sensor_math.dart';
import 'smart_tool_widgets.dart';

/// Raw phone sensor streams, injectable so widget tests run without a phone.
abstract interface class AskodoxMotionSensors {
  Stream<AskodoxVec3> accelerometer();
  Stream<AskodoxVec3> magnetometer();
}

class DeviceMotionSensors implements AskodoxMotionSensors {
  const DeviceMotionSensors();

  @override
  Stream<AskodoxVec3> accelerometer() =>
      accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).map((e) => AskodoxVec3(e.x, e.y, e.z));

  @override
  Stream<AskodoxVec3> magnetometer() =>
      magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval).map((e) => AskodoxVec3(e.x, e.y, e.z));
}

final askodoxMotionSensorsProvider = Provider<AskodoxMotionSensors>((ref) => const DeviceMotionSensors());

/// No reading within this time = the phone has no such sensor (or it is off).
const askodoxSensorTimeout = Duration(seconds: 3);

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.te});
  final bool te;
  @override
  Widget build(BuildContext context) => Center(
        key: const Key('askodoxSensorUnavailable'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            te ? 'ఈ ఫోన్‌లో అవసరమైన సెన్సార్ దొరకలేదు.' : 'This phone did not report the sensor this tool needs.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

// ---------------------------------------------------------------- level

enum _LevelMode { flat, edge }

class AskodoxLevelScreen extends ConsumerStatefulWidget {
  const AskodoxLevelScreen({super.key});

  @override
  ConsumerState<AskodoxLevelScreen> createState() => _AskodoxLevelScreenState();
}

class _AskodoxLevelScreenState extends ConsumerState<AskodoxLevelScreen> {
  StreamSubscription<AskodoxVec3>? _sub;
  Timer? _timeout;
  AskodoxVec3? _g;
  bool _unavailable = false;
  _LevelMode _mode = _LevelMode.flat;
  double _offsetX = 0, _offsetY = 0, _offsetEdge = 0;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(askodoxSensorTimeout, () {
      if (mounted && _g == null) setState(() => _unavailable = true);
    });
    _sub = ref.read(askodoxMotionSensorsProvider).accelerometer().listen((v) {
      if (!mounted) return;
      setState(() => _g = _g == null ? v : _g!.smooth(v));
    }, onError: (_) {
      if (mounted) setState(() => _unavailable = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  void _calibrate() {
    final g = _g;
    if (g == null) return;
    setState(() {
      final flat = askodoxFlatTilt(g);
      _offsetX = flat.tiltX;
      _offsetY = flat.tiltY;
      _offsetEdge = askodoxEdgeAngle(g).fromVertical;
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final g = _g;
    Widget body;
    if (_unavailable) {
      body = _Unavailable(te: te);
    } else if (g == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_mode == _LevelMode.flat) {
      final t = askodoxFlatTilt(g);
      final x = t.tiltX - _offsetX, y = t.tiltY - _offsetY;
      final level = x.abs() < 0.5 && y.abs() < 0.5;
      body = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _Bubble(dx: (-x / 10).clamp(-1.0, 1.0), dy: (y / 10).clamp(-1.0, 1.0), level: level),
        const SizedBox(height: 20),
        Text('X ${x.toStringAsFixed(1)}°   Y ${y.toStringAsFixed(1)}°',
            key: const Key('askodoxLevelReading'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text(te ? 'మొత్తం వాలు ${askodoxInclination(g).toStringAsFixed(1)}°'
            : 'Overall tilt ${askodoxInclination(g).toStringAsFixed(1)}°'),
        if (level) Text(te ? 'సమతలం ✓' : 'Level ✓', style: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w800)),
      ]);
    } else {
      final e = askodoxEdgeAngle(g);
      final fromVertical = (e.fromVertical - _offsetEdge).abs();
      body = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Transform.rotate(
          angle: fromVertical * math.pi / 180,
          child: Container(width: 6, height: 160, color: fromVertical < 0.5 ? const Color(0xFF15803D) : Colors.orange),
        ),
        const SizedBox(height: 20),
        Text(te ? 'నిలువు నుండి ${fromVertical.toStringAsFixed(1)}°' : '${fromVertical.toStringAsFixed(1)}° from vertical',
            key: const Key('askodoxLevelReading'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text(te ? 'అడ్డం నుండి ${(90 - fromVertical).toStringAsFixed(1)}°'
            : '${(90 - fromVertical).toStringAsFixed(1)}° from horizontal'),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'లెవెల్ & వాలు కొలత' : 'Level & inclinometer')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const AskodoxToolSafetyNote('level'),
          SegmentedButton<_LevelMode>(
            segments: [
              ButtonSegment(value: _LevelMode.flat, label: Text(te ? 'ఫోన్ ఫ్లాట్‌గా' : 'Phone flat')),
              ButtonSegment(value: _LevelMode.edge, label: Text(te ? 'అంచుపై / ప్లంబ్' : 'On edge / plumb')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          Expanded(child: body),
          OutlinedButton.icon(
            key: const Key('askodoxLevelCalibrate'),
            onPressed: g == null ? null : _calibrate,
            icon: const Icon(Icons.tune_rounded),
            label: Text(te ? 'ఇక్కడ సున్నా చేయి (తెలిసిన సమతల ఉపరితలంపై)' : 'Set zero here (on a known level surface)'),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.dx, required this.dy, required this.level});
  final double dx;
  final double dy;
  final bool level;

  @override
  Widget build(BuildContext context) {
    const size = 220.0;
    const bubble = 44.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline, width: 2),
      ),
      child: Stack(alignment: Alignment.center, children: [
        Container(width: bubble + 8, height: bubble + 8,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey))),
        Align(
          alignment: Alignment(dx, dy),
          child: Container(
            width: bubble,
            height: bubble,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (level ? const Color(0xFF15803D) : Colors.lightGreen).withValues(alpha: 0.75),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- compass

class AskodoxCompassScreen extends ConsumerStatefulWidget {
  const AskodoxCompassScreen({super.key});

  @override
  ConsumerState<AskodoxCompassScreen> createState() => _AskodoxCompassScreenState();
}

class _AskodoxCompassScreenState extends ConsumerState<AskodoxCompassScreen> {
  final _subs = <StreamSubscription<AskodoxVec3>>[];
  Timer? _timeout;
  AskodoxVec3? _g;
  AskodoxVec3? _m;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    final sensors = ref.read(askodoxMotionSensorsProvider);
    void fail(Object _) {
      if (mounted) setState(() => _unavailable = true);
    }

    _subs.add(sensors.accelerometer().listen((v) {
      if (mounted) setState(() => _g = _g == null ? v : _g!.smooth(v));
    }, onError: fail));
    _subs.add(sensors.magnetometer().listen((v) {
      if (mounted) setState(() => _m = _m == null ? v : _m!.smooth(v));
    }, onError: fail));
    _timeout = Timer(askodoxSensorTimeout, () {
      if (mounted && (_g == null || _m == null)) setState(() => _unavailable = true);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final g = _g, m = _m;
    final heading = g == null || m == null ? null : askodoxHeading(g, m);
    final field = m?.length;
    // Earth's field is ~25-65 µT; far outside that = interference.
    final disturbed = field != null && (field < 20 || field > 80);
    Widget body;
    if (_unavailable) {
      body = _Unavailable(te: te);
    } else if (heading == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Transform.rotate(
          angle: -heading * math.pi / 180,
          child: const Icon(Icons.navigation_rounded, size: 160, color: Color(0xFFDC2626)),
        ),
        const SizedBox(height: 16),
        Text('${heading.toStringAsFixed(0)}° ${askodoxCardinal(heading, te: te)}',
            key: const Key('askodoxCompassReading'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        Text(te ? 'అయస్కాంత ఉత్తరం (నిజ ఉత్తరం కాదు)' : 'Magnetic north (not true north)'),
        if (disturbed)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              te ? 'దగ్గరలో లోహం/ఎలక్ట్రానిక్స్ వల్ల రీడింగ్ తప్పు కావచ్చు. ఫోన్‌ను 8 ఆకారంలో తిప్పండి.'
                  : 'Nearby metal or electronics may be disturbing the reading. Move the phone in a figure-8.',
              key: const Key('askodoxCompassInterference'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w700),
            ),
          ),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'దిక్సూచి' : 'Compass')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [const AskodoxToolSafetyNote('compass'), Expanded(child: body)]),
      ),
    );
  }
}
