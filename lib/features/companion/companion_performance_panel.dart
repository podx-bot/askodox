import 'dart:async';
import 'dart:io' show ProcessInfo;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'askodox_companion.dart';

/// Dart-side startup marks (set from main()): main -> first frame.
class AskodoxStartupMetrics {
  static final Stopwatch _clock = Stopwatch();
  static int? mainToFirstFrameMs;

  static void markMain() {
    _clock
      ..reset()
      ..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => mainToFirstFrameMs ??= _clock.elapsedMilliseconds);
  }

  /// Milliseconds since the first frame (to turn the process uptime into
  /// "process start -> first frame").
  static int? get sinceFirstFrameMs =>
      mainToFirstFrameMs == null ? null : _clock.elapsedMilliseconds - mainToFirstFrameMs!;
}

/// Frame statistics from the engine's own timings (build + raster).
class AskodoxFrameStats {
  final _build = <int>[];
  final _raster = <int>[];
  final _total = <int>[];
  DateTime? _since;

  void add(List<FrameTiming> timings) {
    _since ??= DateTime.now();
    for (final t in timings) {
      _build.add(t.buildDuration.inMicroseconds);
      _raster.add(t.rasterDuration.inMicroseconds);
      _total.add(t.totalSpan.inMicroseconds);
    }
    const keep = 600;
    for (final list in [_build, _raster, _total]) {
      if (list.length > keep) list.removeRange(0, list.length - keep);
    }
  }

  static double? _pct(List<int> values, double p) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    return sorted[((sorted.length - 1) * p).round()] / 1000.0;
  }

  int get frames => _total.length;
  double? get buildP50 => _pct(_build, .5);
  double? get rasterP50 => _pct(_raster, .5);
  double? get rasterP90 => _pct(_raster, .9);
  double? get frameP90 => _pct(_total, .9);

  /// Frames per second the phone could sustain for this content (1000 / p50
  /// of the longer of build and raster), capped at 60 for display.
  double? get sustainableFps {
    final b = buildP50, r = rasterP50;
    if (b == null || r == null) return null;
    final worst = b > r ? b : r;
    return worst <= 0 ? 60 : (1000 / worst).clamp(0, 60).toDouble();
  }
}

/// Profile > Companion performance: what the companion costs on THIS phone
/// (frames, memory, battery / thermal, startup) with a live companion
/// animating, so real-device numbers can be read and shared. Nothing leaves
/// the phone unless the user copies the report.
class AskodoxCompanionPerformancePanel extends ConsumerStatefulWidget {
  const AskodoxCompanionPerformancePanel({super.key, this.channel = const MethodChannel('com.askodox.app/device')});

  final MethodChannel channel;

  @override
  ConsumerState<AskodoxCompanionPerformancePanel> createState() => _AskodoxCompanionPerformancePanelState();
}

class _AskodoxCompanionPerformancePanelState extends ConsumerState<AskodoxCompanionPerformancePanel> {
  final _frames = AskodoxFrameStats();
  Map<String, Object?> _device = const {};
  Timer? _tick;
  AskodoxCompanionMood _mood = AskodoxCompanionMood.speaking;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _refresh();
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _tick?.cancel();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) => _frames.add(timings);

  Future<void> _refresh() async {
    Map<String, Object?>? device;
    try {
      device = await widget.channel.invokeMapMethod<String, Object?>('deviceHealth');
    } catch (_) {
      device = null;
    }
    if (mounted) setState(() => _device = device ?? const {});
  }

  String _fmt(double? v, [String unit = 'ms']) => v == null ? '-' : '${v.toStringAsFixed(1)} $unit';

  List<(String, String)> _rows() {
    final settings = ref.read(askodoxCompanionSettingsProvider);
    int? rssMb;
    try {
      rssMb = ProcessInfo.currentRss ~/ (1024 * 1024);
    } catch (_) {
      rssMb = null;
    }
    final uptime = (_device['processUptimeMs'] as num?)?.toInt();
    final since = AskodoxStartupMetrics.sinceFirstFrameMs;
    final thermal = switch ((_device['thermalStatus'] as num?)?.toInt()) {
      0 => 'none',
      1 => 'light',
      2 => 'moderate',
      3 => 'severe',
      4 => 'critical',
      5 => 'emergency',
      6 => 'shutdown',
      _ => '-',
    };
    return [
      ('Companion', '${settings.companion}${settings.render3d ? '' : ' (3D off)'}'),
      ('Step-down level', switch (AskodoxCompanionPerformance.level) {
        0 => 'full 3D',
        1 => 'robot lite (slow frames)',
        _ => 'flat 2D (slow frames)',
      }),
      if (AskodoxCompanionPerformance.vrmFallback != null) ('Human HD', 'fell back: ${AskodoxCompanionPerformance.vrmFallback}'),
      ('Frames measured', '${_frames.frames}'),
      ('Sustainable fps', _fmt(_frames.sustainableFps, 'fps')),
      ('Build p50', _fmt(_frames.buildP50)),
      ('Raster p50 / p90', '${_fmt(_frames.rasterP50)} / ${_fmt(_frames.rasterP90)}'),
      ('Frame span p90', _fmt(_frames.frameP90)),
      ('App memory (RSS)', rssMb == null ? '-' : '$rssMb MB'),
      ('App memory (PSS)', _device['appPssKb'] == null ? '-' : '${(_device['appPssKb'] as num) ~/ 1024} MB'),
      ('Phone memory free', _device['deviceAvailMb'] == null
          ? '-'
          : '${_device['deviceAvailMb']} / ${_device['deviceTotalMb']} MB${_device['lowMemory'] == true ? ' (LOW)' : ''}'),
      ('Battery', _device['batteryPercent'] == null
          ? '-'
          : '${_device['batteryPercent']}%${_device['charging'] == true ? ' charging' : ''}'
              '${_device['powerSave'] == true ? ' · battery saver' : ''}'),
      ('Battery temperature', _device['batteryTempC'] == null ? '-' : '${_device['batteryTempC']} °C'),
      ('Thermal state', thermal),
      ('Startup (Dart main → first frame)', AskodoxStartupMetrics.mainToFirstFrameMs == null
          ? '-'
          : '${AskodoxStartupMetrics.mainToFirstFrameMs} ms'),
      ('Startup (process → first frame)', uptime == null || since == null ? '-' : '${uptime - since} ms'),
      ('Phone', '${_device['model'] ?? '-'} · Android SDK ${_device['sdk'] ?? '-'}'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return Scaffold(
      appBar: AppBar(title: const Text('Companion performance')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: AskodoxCompanion(key: const Key('askodoxPerfCompanion'), mood: _mood, size: 140)),
        Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
          for (final m in [
            AskodoxCompanionMood.idle,
            AskodoxCompanionMood.listening,
            AskodoxCompanionMood.thinking,
            AskodoxCompanionMood.speaking,
            AskodoxCompanionMood.explaining,
          ])
            ChoiceChip(label: Text(m.name), selected: _mood == m, onSelected: (_) => setState(() => _mood = m)),
        ]),
        const SizedBox(height: 8),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF64748B)))),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        const SizedBox(height: 8),
        const Text(
          'Frames come from Flutter\'s own frame timings while the companion above animates. APK size per '
          'build is in the Live Build artifact (APK_SIZES.txt). GPU counters are not exposed to apps on Android.',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
        Row(children: [
          FilledButton.tonalIcon(
            key: const Key('askodoxPerfCopy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: [for (final (l, v) in _rows()) '$l: $v'].join('\n')));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report copied')));
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy report'),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const Key('askodoxPerfVrmLab'),
            onPressed: () => context.push('/companion-lab'),
            child: const Text('Human HD engine lab'),
          ),
        ]),
      ]),
    );
  }
}
