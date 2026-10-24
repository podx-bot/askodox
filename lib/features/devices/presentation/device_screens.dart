import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../smart_tools/presentation/smart_tool_widgets.dart';
import '../data/ble_gateway.dart';
import '../data/device_repository.dart';
import '../domain/ble_standards.dart';
import '../domain/pairing_flow.dart';

String _categoryLabel(String category, bool te) => switch (category) {
      'weighing_scale' => te ? 'తూకం యంత్రం' : 'Weighing scale',
      'temperature_humidity_sensor' => te ? 'ఉష్ణోగ్రత / తేమ సెన్సార్' : 'Temperature / humidity sensor',
      'thermometer' => te ? 'థర్మామీటర్' : 'Thermometer',
      'heart_rate_monitor' => te ? 'హార్ట్ రేట్ మానిటర్' : 'Heart-rate monitor',
      'any_ble' => te ? 'బ్లూటూత్ పరికరం' : 'Bluetooth device',
      _ => te ? 'తెలియని పరికరం (ప్రామాణికం కాదు)' : 'Unknown device (no standard profile)',
    };

// ---------------------------------------------------------------- dashboard

class AskodoxDevicesScreen extends ConsumerStatefulWidget {
  const AskodoxDevicesScreen({super.key});

  @override
  ConsumerState<AskodoxDevicesScreen> createState() => _AskodoxDevicesScreenState();
}

class _AskodoxDevicesScreenState extends ConsumerState<AskodoxDevicesScreen> {
  Future<List<AskodoxSavedDevice>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = ref.read(askodoxDeviceRepositoryProvider).list());

  Future<void> _forget(AskodoxSavedDevice device) async {
    final te = askodoxToolsTe(context);
    try {
      if (device.localId != null) await ref.read(askodoxBleGatewayProvider).disconnect(device.localId!);
      await ref.read(askodoxDeviceRepositoryProvider).forget(device.id);
    } on AskodoxDeviceException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message(te))));
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'నా పరికరాలు' : 'My devices'), actions: [
        IconButton(
          key: const Key('askodoxDeviceCompatibility'),
          tooltip: te ? 'ఏవి పని చేస్తాయి' : 'What works',
          icon: const Icon(Icons.fact_check_outlined),
          onPressed: () => context.push('/devices/compatibility'),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('askodoxAddDevice'),
        onPressed: () async {
          await context.push('/devices/add');
          if (mounted) _reload();
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(te ? 'పరికరం చేర్చు' : 'Add device'),
      ),
      body: FutureBuilder<List<AskodoxSavedDevice>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            final error = snap.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(error is AskodoxDeviceException ? error.message(te) : '$error',
                    key: const Key('askodoxDevicesError'), textAlign: TextAlign.center),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final devices = snap.data!;
          return ListView(
            key: const Key('askodoxDevices'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              Text(
                te
                    ? 'ప్రస్తుతం: బ్లూటూత్ LE ప్రామాణిక పరికరాలు (తూకం, ఉష్ణోగ్రత, తేమ, హార్ట్ రేట్, బ్యాటరీ). స్మార్ట్ హోమ్ బ్రాండ్లు ఇంకా లేవు.'
                    : 'Now: standard Bluetooth LE devices (scale, temperature, humidity, heart rate, battery). Smart-home brands are not connected yet.',
                style: const TextStyle(fontSize: 12.5),
              ),
              if (devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Text(te ? 'ఇంకా పరికరాలు లేవు.' : 'No devices yet.', textAlign: TextAlign.center),
                ),
              for (final d in devices)
                Card(
                  child: ListTile(
                    key: ValueKey('askodoxDevice-${d.id}'),
                    leading: const Icon(Icons.bluetooth_rounded),
                    title: Text(d.name),
                    subtitle: Text('${_categoryLabel(d.category, te)} · ${d.status}'),
                    trailing: IconButton(
                      tooltip: te ? 'మర్చిపో' : 'Forget',
                      icon: const Icon(Icons.link_off_rounded),
                      onPressed: () => _forget(d),
                    ),
                    onTap: d.localId == null
                        ? null
                        : () => context.push('/devices/live?id=${Uri.encodeComponent(d.localId!)}'
                            '&device=${Uri.encodeComponent(d.id)}&name=${Uri.encodeComponent(d.name)}'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- add device

class AskodoxAddDeviceScreen extends ConsumerStatefulWidget {
  const AskodoxAddDeviceScreen({super.key});

  @override
  ConsumerState<AskodoxAddDeviceScreen> createState() => _AskodoxAddDeviceScreenState();
}

class _AskodoxAddDeviceScreenState extends ConsumerState<AskodoxAddDeviceScreen> {
  late final AskodoxBleGateway _ble = ref.read(askodoxBleGatewayProvider);
  AskodoxPairingState _state = const AskodoxPairingState(AskodoxPairingStep.idle);
  List<AskodoxBleDevice> _found = const [];
  AskodoxBleDevice? _chosen;
  List<String> _services = const [];
  String? _saveError;

  void _event(AskodoxPairingEvent e, {String? reason}) {
    if (!mounted) return;
    setState(() => _state = askodoxPairingNext(_state, e, reason: reason));
  }

  Future<void> _start() async {
    final ble = _ble;
    _event(AskodoxPairingEvent.start);
    if (!await ble.isSupported()) {
      _event(AskodoxPairingEvent.bleUnsupported);
      return;
    }
    if (!await ble.isOn()) {
      _event(AskodoxPairingEvent.bleOff);
      return;
    }
    _event(AskodoxPairingEvent.bleOn);
    try {
      final found = await ble.scan(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _found = found);
      _event(AskodoxPairingEvent.scanDone);
    } on AskodoxBleException catch (e) {
      _event(e.code == 'permission_denied' ? AskodoxPairingEvent.permissionDenied : AskodoxPairingEvent.error,
          reason: e.code);
    }
  }

  Future<void> _choose(AskodoxBleDevice device) async {
    final ble = _ble;
    setState(() {
      _chosen = device;
      _saveError = null;
    });
    _event(AskodoxPairingEvent.select);
    try {
      await ble.connect(device.id);
      _event(AskodoxPairingEvent.connected);
      final services = await ble.discoverServices(device.id);
      if (!mounted) return;
      setState(() => _services = {...device.serviceUuids, ...services}.toList());
      _event(AskodoxPairingEvent.discovered);
    } on AskodoxBleException catch (e) {
      _event(e.code == 'permission_denied' ? AskodoxPairingEvent.permissionDenied : AskodoxPairingEvent.error,
          reason: e.code);
    }
  }

  Future<void> _save() async {
    final te = askodoxToolsTe(context);
    final device = _chosen;
    if (device == null) return;
    try {
      await ref.read(askodoxDeviceRepositoryProvider).add(
            name: device.name.isEmpty ? (te ? 'బ్లూటూత్ పరికరం' : 'Bluetooth device') : device.name,
            localId: device.id,
            serviceUuids: _services,
          );
      _event(AskodoxPairingEvent.saved);
    } on AskodoxDeviceException catch (e) {
      if (mounted) setState(() => _saveError = e.message(te));
    }
  }

  String _reason(String? reason, bool te) => switch (reason) {
        'permission_denied' => te
            ? 'బ్లూటూత్ "సమీప పరికరాలు" అనుమతి ఇవ్వలేదు. Settings లో అనుమతించి మళ్ళీ ప్రయత్నించండి.'
            : 'The Bluetooth "Nearby devices" permission was not given. Allow it in Settings and try again.',
        'connect_failed' => te ? 'కనెక్ట్ కాలేదు. పరికరం ఆన్‌లో, దగ్గరలో ఉందా?' : 'Could not connect. Is the device on and close by?',
        'discover_failed' => te ? 'పరికరం సేవలు చదవలేకపోయాను.' : 'Could not read the device services.',
        _ => te ? 'స్కాన్ విఫలమైంది.' : 'The scan failed.',
      };

  @override
  void dispose() {
    final chosen = _chosen;
    if (chosen != null && _state.step != AskodoxPairingStep.saved) unawaited(_ble.disconnect(chosen.id));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final step = _state.step;
    final profiles = askodoxProfilesFor(_services);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'పరికరం చేర్చండి' : 'Add device')),
      body: ListView(
        key: const Key('askodoxAddDeviceFlow'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            te
                ? 'బ్లూటూత్ LE ప్రామాణిక పరికరాలను మాత్రమే చదవగలను. స్కాన్ నొక్కినప్పుడే అనుమతి అడుగుతాను.'
                : 'ASKODOX reads standard Bluetooth LE devices. Permission is asked only when you tap Scan.',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Text('${te ? 'దశ' : 'Step'}: ${step.name}', key: const Key('askodoxPairingStep'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (step == AskodoxPairingStep.unsupported)
            Text(te ? 'ఈ ఫోన్‌లో బ్లూటూత్ LE లేదు.' : 'This phone has no Bluetooth LE.', key: const Key('askodoxBleUnsupported')),
          if (step == AskodoxPairingStep.bluetoothOff) ...[
            Text(te ? 'బ్లూటూత్ ఆఫ్‌లో ఉంది.' : 'Bluetooth is off.', key: const Key('askodoxBleOff')),
            TextButton(
              onPressed: () async {
                await _ble.requestTurnOn();
                await _start();
              },
              child: Text(te ? 'బ్లూటూత్ ఆన్ చేయి' : 'Turn Bluetooth on'),
            ),
          ],
          if (step == AskodoxPairingStep.failed)
            Text(_reason(_state.reason, te), key: const Key('askodoxPairingFailed'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_state.busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (const {AskodoxPairingStep.idle, AskodoxPairingStep.failed, AskodoxPairingStep.choose, AskodoxPairingStep.bluetoothOff}
              .contains(step))
            FilledButton.icon(
              key: const Key('askodoxBleScan'),
              onPressed: _start,
              icon: const Icon(Icons.bluetooth_searching_rounded),
              label: Text(step == AskodoxPairingStep.choose ? (te ? 'మళ్ళీ స్కాన్' : 'Scan again') : (te ? 'స్కాన్' : 'Scan')),
            ),
          if (step == AskodoxPairingStep.choose) ...[
            const SizedBox(height: 8),
            if (_found.isEmpty) Text(te ? 'పరికరాలు దొరకలేదు.' : 'No devices found.'),
            for (final d in _found)
              Card(
                child: ListTile(
                  key: ValueKey('askodoxBleFound-${d.id}'),
                  title: Text(d.name.isEmpty ? (te ? '(పేరు లేదు)' : '(no name)') : d.name),
                  subtitle: Text('${d.rssi} dBm · ${askodoxProfilesFor(d.serviceUuids).map((p) => te ? p.nameTe : p.nameEn).join(', ')}'),
                  onTap: () => _choose(d),
                ),
              ),
          ],
          if (step == AskodoxPairingStep.ready || step == AskodoxPairingStep.saved) ...[
            const SizedBox(height: 8),
            Text(_chosen?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if (profiles.isEmpty)
              Text(
                te
                    ? 'ఈ పరికరం ప్రామాణిక ప్రొఫైల్ వాడదు — రీడింగ్‌లు చూపించలేను (తయారీదారు యాప్ కావాలి).'
                    : 'This device does not use a standard profile — ASKODOX cannot show its readings (it needs the maker\'s app).',
                key: const Key('askodoxBleNoProfile'),
              )
            else
              Text('${te ? 'సపోర్ట్' : 'Supported'}: ${profiles.map((p) => te ? p.nameTe : p.nameEn).toSet().join(', ')}',
                  key: const Key('askodoxBleProfiles')),
            const SizedBox(height: 8),
            if (step == AskodoxPairingStep.ready)
              FilledButton(key: const Key('askodoxBleSave'), onPressed: _save, child: Text(te ? 'నా పరికరాల్లో సేవ్ చేయి' : 'Save to my devices')),
            if (step == AskodoxPairingStep.saved)
              Text(te ? 'సేవ్ అయింది.' : 'Saved.', key: const Key('askodoxBleSaved')),
            if (_saveError != null) Text(_saveError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (profiles.isNotEmpty && _chosen != null)
              OutlinedButton(
                key: const Key('askodoxBleLive'),
                onPressed: () => context.push('/devices/live?id=${Uri.encodeComponent(_chosen!.id)}'
                    '&name=${Uri.encodeComponent(_chosen!.name)}'),
                child: Text(te ? 'రీడింగ్ చూడు' : 'See reading'),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- live reading

class AskodoxDeviceLiveScreen extends ConsumerStatefulWidget {
  const AskodoxDeviceLiveScreen({super.key, required this.localId, required this.name, this.deviceId});
  final String localId;
  final String name;
  final String? deviceId;

  @override
  ConsumerState<AskodoxDeviceLiveScreen> createState() => _AskodoxDeviceLiveScreenState();
}

class _AskodoxDeviceLiveScreenState extends ConsumerState<AskodoxDeviceLiveScreen> {
  late final AskodoxBleGateway _ble;
  late final AskodoxDeviceRepository _repo;
  final Map<String, AskodoxReading> _latest = {};
  StreamSubscription<AskodoxReading>? _sub;
  String? _error;
  bool _connecting = true;

  @override
  void initState() {
    super.initState();
    _ble = ref.read(askodoxBleGatewayProvider);
    _repo = ref.read(askodoxDeviceRepositoryProvider);
    unawaited(_connect());
  }

  Future<void> _connect() async {
    final ble = _ble;
    try {
      await ble.connect(widget.localId);
      if (widget.deviceId != null) unawaited(_repo.setStatus(widget.deviceId!, 'connected'));
      _sub = ble.readings(widget.localId).listen((r) {
        if (mounted) setState(() => _latest[r.kind] = r);
      }, onError: (Object e) {
        if (mounted) setState(() => _error = '$e');
      });
    } on AskodoxBleException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_ble.disconnect(widget.localId));
    if (widget.deviceId != null) unawaited(_repo.setStatus(widget.deviceId!, 'disconnected'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name.isEmpty ? (te ? 'పరికరం' : 'Device') : widget.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(te ? 'పరికరం పంపిన రీడింగ్‌లు మాత్రమే — ధృవీకరించిన కొలత కాదు.'
              : 'Readings exactly as the device sends them — not a certified measurement.',
              style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 16),
          if (_connecting) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(te ? 'కనెక్షన్ సమస్య: $_error' : 'Connection problem: $_error', key: const Key('askodoxLiveError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (!_connecting && _error == null && _latest.isEmpty)
            Text(te ? 'రీడింగ్ కోసం వేచి ఉన్నాను… (తూకం యంత్రం మీద నిలబడండి)' : 'Waiting for a reading… (step on the scale / wait for the sensor)'),
          for (final r in _latest.values)
            Card(
              key: ValueKey('askodoxReading-${r.kind}'),
              child: ListTile(
                title: Text(r.kind),
                trailing: Text(r.formatted(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- compatibility

class AskodoxDeviceCompatibilityScreen extends ConsumerStatefulWidget {
  const AskodoxDeviceCompatibilityScreen({super.key});

  @override
  ConsumerState<AskodoxDeviceCompatibilityScreen> createState() => _AskodoxDeviceCompatibilityScreenState();
}

class _AskodoxDeviceCompatibilityScreenState extends ConsumerState<AskodoxDeviceCompatibilityScreen> {
  late final Future<ApiResult<Map<String, Object?>>> _future =
      ref.read(apiClientProvider).get<Map<String, Object?>>('/api/devices/compatibility', options: const ApiRequestOptions());

  static String statusLabel(String status, bool te) => switch (status) {
        'tested' => te ? 'పరీక్షించబడింది' : 'Tested',
        'standard_profile_untested' => te ? 'ప్రమాణం ప్రకారం నిర్మించారు, పరికరంతో ఇంకా పరీక్షించలేదు' : 'Built to the standard, not yet tested with a device',
        'needs_hub' => te ? 'హబ్ / గేట్‌వే కావాలి' : 'Needs a hub / gateway',
        'needs_vendor_sdk' => te ? 'బ్రాండ్ API / ఒప్పందం కావాలి' : 'Needs the brand\'s API and agreement',
        'unsupported_on_phone' => te ? 'ఫోన్‌లో ఆ హార్డ్‌వేర్ ఉండదు' : 'Phones lack this hardware',
        _ => te ? 'ఇంకా నిర్మించలేదు' : 'Not built yet',
      };

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఏవి కనెక్ట్ అవుతాయి' : 'What ASKODOX can connect to')),
      body: FutureBuilder<ApiResult<Map<String, Object?>>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final result = snap.data!;
          if (result is! ApiSuccess<Map<String, Object?>>) {
            return Center(child: Text(te ? 'ఇప్పుడు లోడ్ కాలేదు.' : 'Could not load right now.'));
          }
          final rows = result.data['devices'] as List? ?? const [];
          return ListView(
            key: const Key('askodoxCompatibilityList'),
            padding: const EdgeInsets.all(12),
            children: [
              for (final raw in rows)
                if (raw is Map)
                  Card(
                    child: ListTile(
                      title: Text('${raw['protocol']} — ${raw['standard']}'),
                      subtitle: Text('${statusLabel('${raw['status']}', te)}\n${raw['limitations'] ?? ''}'),
                      isThreeLine: true,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
