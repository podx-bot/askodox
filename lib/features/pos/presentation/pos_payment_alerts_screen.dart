import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/flags/askodox_remote_flags.dart';
import '../../../core/providers/backend_providers.dart';
import '../data/pos_payment_alerts.dart';
import '../data/pos_repository.dart';
import 'pos_common.dart';

/// Short time "10:21 AM" (local) from an ISO timestamp.
String askodoxPayAlertTime(Object? iso) {
  final at = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (at == null) return '';
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final now = DateTime.now();
  final day = at.year == now.year && at.month == now.month && at.day == now.day ? '' : '${at.day}/${at.month} ';
  return '$day$h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
}

/// What this device did with an event: its own ack, else the native "spoken" state.
String askodoxMySpokenState(AskodoxJson e) {
  for (final a in askodoxPosList(e['acks'])) {
    if (a['mine'] == true) return '${a['state']}';
  }
  return '${e['spoken'] ?? ''}';
}

Color _statusColor(AskodoxJson e) => e['test'] == true
    ? const Color(0xFF6B7280)
    : switch ('${e['status']}') {
        'provider_verified' => const Color(0xFF15803D),
        'ambiguous' => const Color(0xFFB45309),
        'failed' => const Color(0xFFB91C1C),
        _ => const Color(0xFF1D4ED8),
      };

/// The live strip at the top of the shop dashboard: the latest payment alert at a glance (or how to turn it on).
class AskodoxPosPaymentAlertStrip extends ConsumerStatefulWidget {
  const AskodoxPosPaymentAlertStrip({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosPaymentAlertStrip> createState() => _AskodoxPosPaymentAlertStripState();
}

class _AskodoxPosPaymentAlertStripState extends ConsumerState<AskodoxPosPaymentAlertStrip> {
  AskodoxJson? _settings;
  AskodoxJson? _last;
  bool _hidden = false;
  bool _listener = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final s = await repo.paymentAlertSettings(widget.businessId);
      final ev = s['enabled'] == true ? askodoxPosList((await repo.paymentEvents(widget.businessId, limit: 1))['events']) : const <AskodoxJson>[];
      final st = await ref.read(askodoxPaymentAlertsBridgeProvider).status();
      if (!mounted) return;
      setState(() {
        _settings = s;
        _last = ev.isEmpty ? null : ev.first;
        _listener = st['listenerAllowed'] == true;
      });
    } on AskodoxPosException {
      if (mounted) setState(() => _hidden = true); // role not allowed / feature off: no strip
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final s = _settings;
    if (_hidden || s == null || s['feature_on'] == false || !ref.watch(askodoxFlagProvider('pos.payment_alerts'))) {
      return const SizedBox.shrink();
    }
    final last = _last;
    final on = s['enabled'] == true;
    Future<void> open() async {
      await context.push('/pos/${widget.businessId}/payment-alerts');
      if (mounted) await _load();
    }

    if (!on) {
      return Card(
        key: const Key('askodoxPayAlertStripOff'),
        child: ListTile(
          leading: const Icon(Icons.volume_up_outlined),
          title: Text(te ? 'UPI పేమెంట్ వాయిస్ అలర్ట్స్' : 'UPI payment voice alerts'),
          subtitle: Text(te ? 'మీ పేమెంట్ యాప్ నోటిఫికేషన్ వస్తే ఫోన్ తెలుగులో చెబుతుంది.' : 'Your phone speaks when your payment app shows a payment.'),
          trailing: Text(te ? 'ఆన్ చేయండి' : 'Turn on', style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: open,
        ),
      );
    }
    final spoken = last == null ? '' : askodoxMySpokenState(last);
    final (spokenEn, spokenTe) = askodoxSpokenLabel(spoken);
    final (stEn, stTe) = last == null ? ('', '') : askodoxPaymentStatusLabel(last);
    return Card(
      key: const Key('askodoxPayAlertStrip'),
      color: const Color(0xFFEFF6FF),
      child: ListTile(
        leading: Icon(_listener ? Icons.volume_up : Icons.volume_off_outlined, color: _listener ? const Color(0xFF1D4ED8) : const Color(0xFFB91C1C)),
        title: Text(last == null
            ? (te ? 'ఇంకా పేమెంట్ అలర్ట్ రాలేదు' : 'No payment alert yet')
            : '${askodoxRupees(last['amount_paise'])} · ${askodoxPayAlertTime(last['detected_at'])} · ${last['source_label']}'),
        subtitle: Text(!_listener
            ? (te ? 'ఈ ఫోన్‌లో నోటిఫికేషన్ యాక్సెస్ ఆఫ్‌లో ఉంది — తాకండి' : 'Notification access is off on this phone — tap to fix')
            : last == null
                ? (te ? 'వింటోంది. పేమెంట్ వస్తే చెబుతుంది.' : 'Listening. It will speak when a payment notification comes.')
                : '${te ? stTe : stEn}${spoken.isEmpty ? '' : ' · ${te ? spokenTe : spokenEn}'}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: open,
      ),
    );
  }
}

/// Payment Alerts: status, speaker test, history, settings, devices. Opened from the POS dashboard.
class AskodoxPosPaymentAlertsScreen extends ConsumerStatefulWidget {
  const AskodoxPosPaymentAlertsScreen({super.key, required this.businessId, this.pollEvery = const Duration(seconds: 8)});
  final String businessId;
  final Duration pollEvery;

  @override
  ConsumerState<AskodoxPosPaymentAlertsScreen> createState() => _AskodoxPosPaymentAlertsScreenState();
}

class _AskodoxPosPaymentAlertsScreenState extends ConsumerState<AskodoxPosPaymentAlertsScreen> {
  AskodoxJson _settings = const {};
  AskodoxJson _status = const {};
  List<AskodoxJson> _events = const [];
  List<AskodoxJson> _local = const [];
  List<AskodoxJson> _devices = const [];
  AskodoxJson _summary = const {};
  String? _deviceId;
  String _filter = '';
  String _query = '';
  String? _error;
  bool _loading = true;
  bool _busy = false;
  Timer? _timer;
  final _announced = <String>{};
  final _search = TextEditingController();

  String get _id => widget.businessId;
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);
  AskodoxPaymentAlertsBridge get _bridge => ref.read(askodoxPaymentAlertsBridgeProvider);

  @override
  void initState() {
    super.initState();
    _bridge.onEvent((_) => _refresh());
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bridge.onEvent(null);
    _search.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await _refresh(first: true);
    if (!mounted || widget.pollEvery == Duration.zero) return;
    _timer = Timer.periodic(widget.pollEvery, (_) => _poll());
  }

  Future<void> _registerDevice() async {
    try {
      final key = await askodoxPaymentAlertInstallKey();
      final out = await _repo.registerAlertDevice(_id, {
        'device_key': key,
        'label': 'Phone ${key.substring(key.length - 4)}',
        'listener_on': _status['listenerAllowed'] == true,
        'speaks_remote': true,
      });
      _deviceId = '${out['device_id']}';
      _devices = askodoxPosList(out['devices']);
    } on AskodoxPosException {
      // shown through the settings call's error
    }
  }

  /// Hands the shop's choices + this phone's identity to the native listener.
  Future<void> _configureNative() async {
    final session = ref.read(authSessionProvider);
    String base = '';
    try {
      base = ref.read(appConfigProvider).apiBaseUrl?.toString() ?? '';
    } catch (_) {}
    _status = await _bridge.configure({
      'enabled': _settings['enabled'] == true && _settings['feature_on'] != false,
      'language': _settings['language'] ?? 'te',
      'voice': _settings['voice'] ?? 'female',
      'rate_pct': _settings['rate_pct'] ?? 100,
      'volume_pct': _settings['volume_pct'] ?? 100,
      'quiet_start': _settings['quiet_start'] ?? '',
      'quiet_end': _settings['quiet_end'] ?? '',
      'apps': askodoxPosMap(_settings['apps']),
      'business_id': _id,
      'device_id': _deviceId ?? '',
      'base_url': base,
      'token': session.user == null ? '' : session.tokenPlaceholder,
    });
  }

  Future<void> _refresh({bool first = false}) async {
    try {
      _status = await _bridge.status();
      _settings = await _repo.paymentAlertSettings(_id);
      if (first || _deviceId == null) await _registerDevice();
      await _configureNative();
      await askodoxSyncPaymentAlerts(_repo, _bridge, _id, _deviceId);
      final data = await _repo.paymentEvents(_id, status: _filter, q: _query);
      _local = await _bridge.localEvents();
      if (!mounted) return;
      setState(() {
        _events = askodoxPosList(data['events']);
        _summary = askodoxPosMap(data['last_24h']);
        _error = null;
        _loading = false;
      });
      if (first) _announced.addAll(_events.map((e) => '${e['id']}'));
    } on AskodoxPosException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message(askodoxPosTe(context));
          _loading = false;
        });
      }
    }
  }

  /// Staff / second phones: speak alerts another device of this shop detected (only while this screen is open).
  Future<void> _poll() async {
    if (_busy) return;
    try {
      final data = await _repo.paymentEvents(_id, status: _filter, q: _query);
      final events = askodoxPosList(data['events']);
      final me = _devices.where((d) => d['id'] == _deviceId).firstOrNull;
      final speaks = me == null || me['speaks_remote'] != false;
      for (final e in events.reversed) {
        final id = '${e['id']}';
        if (_announced.contains(id)) continue;
        _announced.add(id);
        if (e['reported_by_me'] == true || _deviceId == null) continue;
        final lang = '${_settings['language'] ?? 'te'}';
        final text = '${askodoxPosMap(e['announcement'])[lang] ?? ''}';
        var state = 'seen';
        if (speaks && text.isNotEmpty) {
          await _bridge.speakText(text, lang);
          state = 'announced';
        }
        try {
          await _repo.ackPaymentEvent(_id, id, _deviceId!, state);
        } on AskodoxPosException {
          // not acknowledged: the owner keeps seeing "delivery pending" for this device
        }
      }
      if (mounted) {
        setState(() {
          _events = events;
          _summary = askodoxPosMap(data['last_24h']);
        });
      }
    } on AskodoxPosException {
      // offline: next tick
    }
  }

  Future<void> _save(AskodoxJson change) async {
    setState(() => _busy = true);
    try {
      _settings = await _repo.updatePaymentAlertSettings(_id, change);
      await _configureNative();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(askodoxPosTe(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOnAccess() async {
    final te = askodoxPosTe(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('askodoxPayAlertConsent'),
        title: Text(te ? 'నోటిఫికేషన్ యాక్సెస్' : 'Notification access'),
        content: Text(te
            ? 'ASKODOX మీరు ఎంచుకున్న పేమెంట్ యాప్‌ల (PhonePe Business, Google Pay, Paytm, BHIM…) నోటిఫికేషన్‌లలో '
                'మొత్తం, యాప్ పేరు, రిఫరెన్స్ చివరి 4 అంకెలు మాత్రమే చదువుతుంది. ఇతర యాప్‌లు, మెసేజ్‌లు, OTP లు చదవదు, '
                'నోటిఫికేషన్ టెక్స్ట్ సేవ్ చేయదు. ఇది బ్యాంక్ నిర్ధారణ కాదు. తర్వాతి స్క్రీన్‌లో ASKODOX ను ఆన్ చేయండి.'
            : 'ASKODOX reads only the amount, app name and last 4 characters of the reference from notifications of the '
                'payment apps you allow (PhonePe Business, Google Pay, Paytm, BHIM…). It never reads other apps, messages '
                'or OTPs and never stores the notification text. A notification is not a bank confirmation. '
                'On the next screen, switch ASKODOX on.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Not now')),
          FilledButton(
              key: const Key('askodoxPayAlertConsentYes'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(te ? 'అంగీకరించి తెరువు' : 'I agree, open settings')),
        ],
      ),
    );
    if (ok != true) return;
    await _bridge.openListenerSettings();
  }

  Future<void> _speakerTest() async {
    final te = askodoxPosTe(context);
    final route = await _bridge.speakTest(50000);
    if (!mounted) return;
    if (route['unavailable'] == true) {
      askodoxPosSnack(context, te ? 'ఈ పరికరంలో వాయిస్ లేదు.' : 'Voice is not available on this device.');
      return;
    }
    setState(() => _status = {..._status, 'audio': route});
    askodoxPosSnack(context, te ? 'టెస్ట్ వాయిస్ ప్లే అవుతోంది — వినిపించిందా?' : 'Playing a test announcement — did you hear it?');
  }

  Future<void> _staffTest() async {
    final te = askodoxPosTe(context);
    try {
      await _repo.reportPaymentEvent(_id, {
        'client_event_id': 'test-${DateTime.now().millisecondsSinceEpoch}',
        'amount_paise': 100,
        'test': true,
        if (_deviceId != null) 'device_id': _deviceId,
      });
      if (mounted) askodoxPosSnack(context, te ? 'టెస్ట్ అలర్ట్ సిబ్బంది ఫోన్‌లకు పంపాం.' : 'Test alert sent to staff phones.');
      await _refresh();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _detectionTest() async {
    final te = askodoxPosTe(context);
    final out = await _bridge.simulate('PhonePe Business', 'Received ₹1.00 from Test Customer. UPI Ref No. 999900001111');
    if (!mounted) return;
    askodoxPosSnack(
        context,
        out['unavailable'] == true
            ? (te ? 'ఫోన్‌లో మాత్రమే పనిచేస్తుంది.' : 'Works on the phone only.')
            : (te ? 'గుర్తింపు పరీక్ష: ${out['result']}' : 'Detection test: ${out['result']}'));
    await _refresh();
  }

  Future<void> _export() async {
    final csv = askodoxPaymentAlertsCsv(_events);
    try {
      await const MethodChannel('com.askodox.app/device')
          .invokeMethod<bool>('shareText', {'text': csv, 'subject': 'ASKODOX payment alerts', 'title': 'Share'});
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (mounted) askodoxPosSnack(context, askodoxPosTe(context) ? 'కాపీ చేశాం.' : 'Copied.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'పేమెంట్ వాయిస్ అలర్ట్స్' : 'Payment voice alerts'),
        actions: [
          IconButton(key: const Key('askodoxPayAlertExport'), onPressed: _events.isEmpty ? null : _export, icon: const Icon(Icons.ios_share)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _settings.isEmpty
              ? AskodoxPosError(error: _error!, onRetry: () => _refresh(first: true))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(key: const Key('askodoxPayAlerts'), padding: const EdgeInsets.all(12), children: [
                    if (_settings['feature_on'] == false)
                      Card(
                        color: const Color(0xFFFEF2F2),
                        child: ListTile(
                          leading: const Icon(Icons.block),
                          title: Text(te ? 'ASKODOX ఈ ఫీచర్‌ను ప్రస్తుతం ఆపింది.' : 'ASKODOX has switched this feature off for now.'),
                        ),
                      ),
                    _statusCard(te),
                    const SizedBox(height: 8),
                    _historyCard(te),
                    const SizedBox(height: 8),
                    if (_settings['can_edit'] == true) _settingsCard(te),
                    _devicesCard(te),
                    const SizedBox(height: 8),
                    Text(
                      te
                          ? 'ASKODOX డబ్బు తీసుకోదు, పంపదు. కస్టమర్లు మీ UPI ID / QR కే నేరుగా కడతారు. నోటిఫికేషన్ అంటే బ్యాంక్ నిర్ధారణ కాదు — '
                              'పెద్ద మొత్తాలు బ్యాంక్ / పేమెంట్ యాప్‌లో చూసుకోండి. ఇవి ఆదాయం / సెటిల్‌మెంట్‌గా లెక్కించబడవు.'
                          : 'ASKODOX never takes or sends money — customers pay your own UPI ID / QR. A notification is not a bank '
                              'confirmation: check big amounts in your bank / payment app. These are never counted as revenue or settlements.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ]),
                ),
    );
  }

  Widget _statusCard(bool te) {
    final listener = _status['listenerAllowed'] == true;
    final unavailable = _status['unavailable'] == true;
    final on = _settings['enabled'] == true;
    final audio = askodoxPosMap(_status['audio']);
    final output = '${audio['output'] ?? ''}';
    final outputText = switch (output) {
      'bluetooth' => te ? 'బ్లూటూత్ స్పీకర్: ${audio['bluetoothName']}' : 'Bluetooth speaker: ${audio['bluetoothName']}',
      'wired' => te ? 'వైర్డ్ హెడ్‌సెట్' : 'Wired headset',
      'phone' => te ? 'ఫోన్ స్పీకర్' : 'Phone speaker',
      _ => te ? 'తెలియదు' : 'Unknown',
    };
    final vol = askodoxPosInt(audio['mediaVolumePct']);
    Widget row(Key key, bool ok, String text, {Widget? action}) => ListTile(
          key: key,
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(ok ? Icons.check_circle : Icons.error_outline, color: ok ? const Color(0xFF15803D) : const Color(0xFFB91C1C)),
          title: Text(text),
          trailing: action,
        );
    return Card(
      key: const Key('askodoxPayAlertStatus'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(te ? 'స్థితి' : 'Status', style: const TextStyle(fontWeight: FontWeight.w800)),
          row(const Key('askodoxPayAlertShopOn'), on, on ? (te ? 'ఈ షాపుకు అలర్ట్స్ ఆన్' : 'Alerts on for this shop') : (te ? 'ఈ షాపుకు అలర్ట్స్ ఆఫ్' : 'Alerts off for this shop'),
              action: _settings['can_edit'] == true
                  ? Switch(key: const Key('askodoxPayAlertEnable'), value: on, onChanged: _busy ? null : (v) => _save({'enabled': v}))
                  : null),
          if (!unavailable)
            row(const Key('askodoxPayAlertListener'), listener,
                listener ? (te ? 'ఈ ఫోన్‌లో నోటిఫికేషన్ యాక్సెస్ ఆన్' : 'Notification access on (this phone)') : (te ? 'ఈ ఫోన్‌లో నోటిఫికేషన్ యాక్సెస్ ఆఫ్' : 'Notification access off (this phone)'),
                action: listener
                    ? null
                    : TextButton(key: const Key('askodoxPayAlertGrant'), onPressed: _turnOnAccess, child: Text(te ? 'ఆన్ చేయండి' : 'Turn on'))),
          if (!unavailable)
            row(const Key('askodoxPayAlertAudio'), vol > 0, '$outputText · ${te ? 'మీడియా వాల్యూమ్' : 'media volume'} $vol%',
                action: IconButton(onPressed: () async {
                  final r = await _bridge.showVolume();
                  if (mounted) setState(() => _status = {..._status, 'audio': r});
                }, icon: const Icon(Icons.volume_up_outlined))),
          if (_status['ttsLanguageOk'] == false)
            Text(te ? 'ఫోన్‌లో తెలుగు వాయిస్ లేదు — ఇంగ్లీష్‌లో చెబుతాం. Settings > Text-to-speech లో తెలుగు డౌన్‌లోడ్ చేయండి.'
                    : 'This phone has no Telugu voice — English is used. Download Telugu in Settings > Text-to-speech.',
                style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
          if (unavailable)
            Text(te ? 'వినడం Android ఫోన్‌లో మాత్రమే.' : 'Listening works on the Android phone only.', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton.tonalIcon(key: const Key('askodoxPayAlertSpeakerTest'), onPressed: _speakerTest, icon: const Icon(Icons.campaign_outlined), label: Text(te ? 'స్పీకర్ టెస్ట్' : 'Speaker test')),
            OutlinedButton.icon(key: const Key('askodoxPayAlertDetectTest'), onPressed: _detectionTest, icon: const Icon(Icons.science_outlined), label: Text(te ? 'గుర్తింపు టెస్ట్' : 'Detection test')),
            OutlinedButton.icon(key: const Key('askodoxPayAlertStaffTest'), onPressed: _staffTest, icon: const Icon(Icons.groups_outlined), label: Text(te ? 'సిబ్బందికి టెస్ట్' : 'Test to staff')),
            TextButton.icon(onPressed: _bridge.openBluetoothSettings, icon: const Icon(Icons.bluetooth), label: Text(te ? 'బ్లూటూత్' : 'Bluetooth')),
            TextButton.icon(onPressed: _bridge.openBatterySettings, icon: const Icon(Icons.battery_saver_outlined), label: Text(te ? 'బ్యాటరీ అనుమతి' : 'Battery: allow')),
          ]),
          const SizedBox(height: 4),
          Text(
              te
                  ? 'బ్లూటూత్ స్పీకర్ కనెక్ట్ అయి మీడియా కోసం ఎంచుకుంటే వాయిస్ దానిలో వస్తుంది; లేకపోతే ఫోన్ స్పీకర్‌లో. స్పీకర్ డిస్‌కనెక్ట్ అయితే ఫోన్‌లోనే చెబుతుంది. '
                      'ఫోన్ కొన్నిసార్లు బ్యాక్‌గ్రౌండ్ యాప్‌లను ఆపుతుంది — "బ్యాటరీ అనుమతి" ఇవ్వండి.'
                  : 'If a Bluetooth speaker is connected for media, the voice plays there; otherwise on the phone speaker. If the speaker '
                      'disconnects, the phone speaks. Some phones stop background apps — use "Battery: allow".',
              style: const TextStyle(fontSize: 11.5)),
        ]),
      ),
    );
  }

  Widget _historyCard(bool te) {
    const filters = [
      ('', 'All', 'అన్నీ'),
      ('notification_unverified', 'Unverified', 'నిర్ధారించనివి'),
      ('ambiguous', 'Ambiguous', 'స్పష్టంగా లేనివి'),
      ('duplicate', 'Duplicates', 'డూప్లికేట్'),
      ('provider_verified', 'Verified', 'నిర్ధారించినవి'),
    ];
    final pendingLocal = _local.where((e) => e['server_id'] == null && e['upload_error'] == null && e['test'] != true).length;
    return Card(
      key: const Key('askodoxPayAlertHistory'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(te ? 'పేమెంట్ అలర్ట్స్' : 'Payment alerts', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(
            te
                ? 'గత 24 గం: ${_summary['count'] ?? 0} నోటిఫికేషన్లు · ${askodoxRupees(_summary['notified_total_paise'] ?? 0)} (నిర్ధారించలేదు)'
                : 'Last 24 h: ${_summary['count'] ?? 0} notifications · ${askodoxRupees(_summary['notified_total_paise'] ?? 0)} (unverified)',
            key: const Key('askodoxPayAlertSummary'),
            style: const TextStyle(fontSize: 12.5),
          ),
          if (pendingLocal > 0)
            Text(te ? '$pendingLocal ఈ ఫోన్ నుండి ఇంకా పంపాలి (ఇంటర్నెట్ వచ్చాక)' : '$pendingLocal from this phone waiting to send (when online)',
                key: const Key('askodoxPayAlertPendingLocal'), style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
          const SizedBox(height: 6),
          TextField(
            key: const Key('askodoxPayAlertSearch'),
            controller: _search,
            decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                hintText: te ? 'మొత్తం / యాప్ / రిఫరెన్స్ (ఉదా: 500)' : 'Amount / app / reference (e.g. 500)'),
            onSubmitted: (v) {
              _query = v.trim();
              _refresh();
            },
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final (value, en, tel) in filters)
              ChoiceChip(
                key: ValueKey('askodoxPayAlertFilter-${value.isEmpty ? 'all' : value}'),
                label: Text(te ? tel : en),
                selected: _filter == value,
                onSelected: (_) {
                  _filter = value;
                  _refresh();
                },
              ),
          ]),
          if (_events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(te ? 'ఇంకా అలర్ట్స్ లేవు.' : 'No alerts yet.', key: const Key('askodoxPayAlertEmpty')),
            ),
          for (final e in _events) _eventTile(e, te),
        ]),
      ),
    );
  }

  Widget _eventTile(AskodoxJson e, bool te) {
    final (stEn, stTe) = askodoxPaymentStatusLabel(e);
    final mine = askodoxMySpokenState(e);
    final local = _local.where((l) => l['server_id'] == e['id']).firstOrNull;
    final spoken = mine.isNotEmpty ? mine : '${local?['spoken'] ?? ''}';
    final (spEn, spTe) = askodoxSpokenLabel(spoken);
    final pending = askodoxPosInt(e['delivery_pending']);
    final ref = '${e['reference_tail'] ?? ''}';
    final acks = askodoxPosList(e['acks']).where((a) => a['mine'] != true).toList();
    return ListTile(
      key: ValueKey('askodoxPayAlertEvent-${e['id']}'),
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: _statusColor(e).withValues(alpha: 0.12),
        child: Icon(e['status'] == 'ambiguous' ? Icons.help_outline : Icons.currency_rupee, color: _statusColor(e)),
      ),
      title: Text('${askodoxRupees(e['amount_paise'])} · ${e['source_label']}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(te ? stTe : stEn, style: TextStyle(color: _statusColor(e), fontSize: 12.5, fontWeight: FontWeight.w600)),
        Text([
          askodoxPayAlertTime(e['detected_at']),
          if (ref.isNotEmpty) 'Ref ••$ref',
          if ('${e['receiving_device'] ?? ''}'.isNotEmpty) '${e['receiving_device']}',
          '${te ? 'వాయిస్' : 'Voice'}: ${te ? spTe : spEn}',
          if (askodoxPosInt(e['duplicates']) > 0) '${te ? 'డూప్లికేట్' : 'duplicate'} ×${e['duplicates']}',
        ].join(' · '), style: const TextStyle(fontSize: 12)),
        if (acks.isNotEmpty || pending > 0)
          Text([
            for (final a in acks) '${a['device']}: ${te ? askodoxSpokenLabel('${a['state']}').$2 : askodoxSpokenLabel('${a['state']}').$1}',
            if (pending > 0) te ? '$pending పరికరాలకు ఇంకా అందలేదు' : 'delivery pending on $pending device(s)',
          ].join(' · '), style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
      ]),
    );
  }

  Widget _settingsCard(bool te) {
    final lang = '${_settings['language'] ?? 'te'}';
    final roles = (_settings['all_roles'] as List? ?? const []).map((e) => '$e').toList();
    final chosen = (_settings['roles'] as List? ?? const []).map((e) => '$e').toSet();
    final apps = askodoxPosMap(_settings['apps']);
    return Card(
      key: const Key('askodoxPayAlertSettings'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(te ? 'సెట్టింగ్స్ (యజమాని)' : 'Settings (owner)', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(te ? 'భాష' : 'Language'),
          Wrap(spacing: 6, children: [
            for (final (v, label) in const [('te', 'తెలుగు'), ('hi', 'हिन्दी'), ('en', 'English')])
              ChoiceChip(
                  key: ValueKey('askodoxPayAlertLang-$v'),
                  label: Text(label),
                  selected: lang == v,
                  onSelected: _busy ? null : (_) => _save({'language': v})),
          ]),
          Text(te ? 'వాయిస్ (ఫోన్‌లో ఉంటే)' : 'Voice (when the phone has it)'),
          Wrap(spacing: 6, children: [
            for (final (v, en, tel) in const [('female', 'Female', 'స్త్రీ'), ('male', 'Male', 'పురుషుడు')])
              ChoiceChip(
                  label: Text(te ? tel : en),
                  selected: '${_settings['voice']}' == v,
                  onSelected: _busy ? null : (_) => _save({'voice': v})),
          ]),
          Text('${te ? 'వేగం' : 'Speed'} ${_settings['rate_pct']}%'),
          Slider(
              key: const Key('askodoxPayAlertRate'),
              min: 50,
              max: 200,
              divisions: 15,
              value: askodoxPosInt(_settings['rate_pct']).clamp(50, 200).toDouble(),
              onChanged: (v) => setState(() => _settings = {..._settings, 'rate_pct': v.round()}),
              onChangeEnd: (v) => _save({'rate_pct': v.round()})),
          Text('${te ? 'వాల్యూమ్' : 'Volume'} ${_settings['volume_pct']}%'),
          Slider(
              key: const Key('askodoxPayAlertVolume'),
              min: 10,
              max: 100,
              divisions: 9,
              value: askodoxPosInt(_settings['volume_pct']).clamp(10, 100).toDouble(),
              onChanged: (v) => setState(() => _settings = {..._settings, 'volume_pct': v.round()}),
              onChangeEnd: (v) => _save({'volume_pct': v.round()})),
          ListTile(
            key: const Key('askodoxPayAlertQuiet'),
            contentPadding: EdgeInsets.zero,
            title: Text(te ? 'నిశ్శబ్ద సమయం' : 'Quiet hours'),
            subtitle: Text('${_settings['quiet_start']}'.isEmpty
                ? (te ? 'లేదు — ఎప్పుడూ చెబుతుంది' : 'None — always speaks')
                : '${_settings['quiet_start']} – ${_settings['quiet_end']} (${te ? 'రికార్డ్ అవుతుంది, చెప్పదు' : 'recorded, not spoken'})'),
          ),
          Wrap(spacing: 6, children: [
            TextButton(
                key: const Key('askodoxPayAlertQuietSet'),
                onPressed: _busy ? null : () => _save({'quiet_start': '22:00', 'quiet_end': '07:00'}),
                child: const Text('22:00 – 07:00')),
            TextButton(
                onPressed: _busy ? null : () => _save({'quiet_start': '', 'quiet_end': ''}),
                child: Text(te ? 'తీసివేయి' : 'Clear')),
          ]),
          Text(te ? 'ఏ సిబ్బంది చూడవచ్చు / వినవచ్చు' : 'Which staff roles get alerts'),
          Wrap(spacing: 6, children: [
            for (final r in roles)
              FilterChip(
                key: ValueKey('askodoxPayAlertRole-$r'),
                label: Text(r),
                selected: chosen.contains(r),
                onSelected: _busy
                    ? null
                    : (v) => _save({'roles': v ? [...chosen, r] : chosen.where((x) => x != r).toList()}),
              ),
          ]),
          const SizedBox(height: 6),
          Text(te ? 'చదవాల్సిన పేమెంట్ యాప్‌లు' : 'Payment apps to read'),
          for (final e in apps.entries)
            Text('• ${e.value}', style: const TextStyle(fontSize: 12.5)),
          Text(te ? 'జాబితా ASKODOX సపోర్ట్ మార్చగలదు.' : 'ASKODOX support can adjust this list.', style: const TextStyle(fontSize: 11.5)),
        ]),
      ),
    );
  }

  Widget _devicesCard(bool te) {
    final canRevokeOthers = _settings['can_edit'] == true;
    return Card(
      key: const Key('askodoxPayAlertDevices'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(te ? 'పరికరాలు' : 'Devices', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(
              te
                  ? 'సిబ్బంది ఫోన్‌లు: ఈ స్క్రీన్ తెరిచి ఉంటే వేరే ఫోన్‌లో వచ్చిన అలర్ట్ కూడా చెబుతుంది. ఇంటర్నెట్ / ఫోన్ ఆలస్యం వల్ల కొంచెం లేట్ అవ్వచ్చు.'
                  : 'Staff phones: with this screen open, alerts from another phone are spoken too. Internet / phone delays can make it late.',
              style: const TextStyle(fontSize: 11.5)),
          for (final d in _devices)
            ListTile(
              key: ValueKey('askodoxPayAlertDevice-${d['id']}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(d['revoked'] == true ? Icons.phonelink_erase : Icons.smartphone),
              title: Text('${d['label']}${d['mine'] == true ? (te ? ' (ఈ ఫోన్)' : ' (this phone)') : ''} · ${d['role']}'),
              subtitle: Text([
                if (d['revoked'] == true) te ? 'తీసివేశారు' : 'removed',
                if (d['listener_on'] == true) te ? 'వింటోంది' : 'listening',
                askodoxPayAlertTime(d['last_seen_at']),
              ].join(' · ')),
              trailing: d['revoked'] == true || !(canRevokeOthers || d['mine'] == true)
                  ? null
                  : TextButton(
                      onPressed: () async {
                        try {
                          final list = await _repo.revokeAlertDevice(_id, '${d['id']}');
                          if (mounted) setState(() => _devices = list);
                        } on AskodoxPosException catch (err) {
                          if (mounted) askodoxPosSnack(context, err.message(te));
                        }
                      },
                      child: Text(te ? 'తీసివేయి' : 'Remove')),
            ),
        ]),
      ),
    );
  }
}
