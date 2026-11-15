import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/backend_providers.dart';
import '../data/pos_payment_alerts.dart';
import '../data/pos_repository.dart';
import 'pos_common.dart';

/// "My phone" payments (owner 2026-11-15): any signed-in person -- no shop, no registered UPI id -- gets the payment
/// notifications and bank SMS of the apps THEY choose read out on their own phone and kept in their own history.
/// Everything is on this phone only; every list (apps, accounts, history) can be edited and deleted.
///
/// Built for every phone, bank and app (owner rule: one example = all cases): the payment / bank / SMS apps found on
/// THIS phone are offered by themselves, and one checklist opens each Android page the phone needs (notification
/// access, battery, the maker's Autostart page, each app's own notifications, the SMS app) -- nothing to hunt for.
/// A phone that also listens for a shop chooses per app where it goes (shop or my phone); both work together.
class AskodoxMyPhonePaymentsScreen extends ConsumerStatefulWidget {
  const AskodoxMyPhonePaymentsScreen({super.key});

  @override
  ConsumerState<AskodoxMyPhonePaymentsScreen> createState() => _AskodoxMyPhonePaymentsScreenState();
}

class _AskodoxMyPhonePaymentsScreenState extends ConsumerState<AskodoxMyPhonePaymentsScreen> with WidgetsBindingObserver {
  AskodoxMyPhoneAlerts? _mine;
  AskodoxJson _status = const {};
  List<AskodoxJson> _events = const [];
  String _filter = 'all'; // all | in | out
  List<AskodoxJson> _installed = const [];
  Map<String, AskodoxJson> _appState = const {}; // package -> installed / batteryUnrestricted / lastSeenAt
  Set<String> _confirmed = {}; // steps the phone cannot check, confirmed by the person
  static const _confirmedKey = 'askodox.mine.payalert.setup.v1';
  late final AskodoxPaymentAlertsBridge _bridge = ref.read(askodoxPaymentAlertsBridgeProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bridge.onEvent((_) => unawaited(_reload()));
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bridge.onEvent(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reload());
  }

  Future<void> _start() async {
    final mine = await AskodoxMyPhoneAlerts.load();
    _mine = mine;
    final prefs = await SharedPreferences.getInstance();
    _confirmed = (prefs.getStringList(_confirmedKey) ?? const []).toSet();
    _installed = await _bridge.installedApps();
    if (!mine.setupDone) {
      // First visit: the money apps really on THIS phone are chosen for the person (they can remove any).
      final found = _found(mine, includeChosen: true);
      if (_installed.isNotEmpty) {
        final installedIds = {for (final a in _installed) '${a['package']}'};
        mine.apps = {
          for (final e in mine.apps.entries)
            if (installedIds.contains(e.key)) e.key: e.value,
          for (final a in found) '${a['package']}': '${a['label']}',
        };
        if (mine.apps.isEmpty) mine.apps = AskodoxMyPhoneAlerts.defaultApps();
      }
      mine.setupDone = true;
      await mine.save();
    }
    await _configure();
    await _reload();
  }

  /// Installed payment / bank / SMS apps (catalogue or by name), not yet in the list unless [includeChosen].
  List<AskodoxJson> _found(AskodoxMyPhoneAlerts m, {bool includeChosen = false}) => [
        for (final a in _installed)
          if (askodoxLooksLikeMoneyApp('${a['package']}', '${a['label']}') &&
              (includeChosen || !m.apps.containsKey('${a['package']}')))
            {
              'package': '${a['package']}',
              'label': askodoxMoneyAppCatalog['${a['package']}']?.$1 ?? '${a['label']}',
            },
      ];

  Future<void> _configure() async {
    final mine = _mine;
    if (mine == null) return;
    var base = '';
    var token = '';
    try {
      base = ref.read(appConfigProvider).apiBaseUrl?.toString() ?? '';
      final session = ref.read(authSessionProvider);
      token = session.user == null ? '' : session.tokenPlaceholder;
    } catch (_) {}
    _status = await _bridge.configurePersonal(mine.nativeConfig(baseUrl: base, token: token));
  }

  Future<void> _reload() async {
    final status = await _bridge.status();
    final events = (await _bridge.localEvents()).where((e) => e['direction'] != null || e['test'] == true).toList();
    final apps = _mine?.apps.keys.toList() ?? const <String>[];
    final state = await _bridge.paymentApps(apps);
    if (!mounted) return;
    setState(() {
      _status = status;
      _events = events.reversed.toList();
      _appState = {for (final a in state) '${a['package']}': a};
    });
  }

  Future<void> _confirm1(String id) async {
    _confirmed = {..._confirmed, id};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_confirmedKey, _confirmed.toList());
    if (mounted) setState(() {});
  }

  Future<void> _change(void Function(AskodoxMyPhoneAlerts m) edit) async {
    final mine = _mine;
    if (mine == null) return;
    edit(mine);
    await mine.save();
    await _configure();
    if (mounted) setState(() {});
  }

  Future<bool> _confirm(String title, String body, bool te) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
            FilledButton(key: const Key('askodoxMineConfirmYes'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'అవును' : 'Yes')),
          ],
        ),
      ) ==
      true;

  Future<String?> _ask(String title, String initial, bool te, {String? hint, bool digits = false}) async {
    final c = TextEditingController(text: initial);
    final out = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('askodoxMineAskField'),
          controller: c,
          autofocus: true,
          maxLength: digits ? 4 : 40,
          keyboardType: digits ? TextInputType.number : TextInputType.text,
          inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(counterText: '', hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(key: const Key('askodoxMineAskSave'), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    return out; // the dialog's exit animation still reads the controller: it is garbage collected, not disposed
  }

  Future<void> _toggle(bool on) async {
    await _change((m) => m.enabled = on);
    if (on && _status['listenerAllowed'] != true) await _bridge.openListenerSettings();
  }

  Future<void> _addApp(bool te) async {
    final installed = await _bridge.installedApps();
    final have = _mine?.apps.keys.toSet() ?? <String>{};
    final known = {for (final e in askodoxKnownMoneyApps.entries) e.key: '${e.value}'};
    final rows = <AskodoxJson>[
      for (final a in installed)
        if (!have.contains('${a['package']}')) a,
      for (final e in known.entries)
        if (!have.contains(e.key) && !installed.any((a) => a['package'] == e.key)) {'package': e.key, 'label': e.value},
    ];
    if (!mounted) return;
    final picked = await showModalBottomSheet<AskodoxJson>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AppPicker(rows: rows, te: te),
    );
    if (picked == null) return;
    final pkg = '${picked['package']}'.trim();
    if (pkg.isEmpty) return;
    await _change((m) => m.apps = {...m.apps, pkg: '${picked['label']}'.trim().isEmpty ? pkg : '${picked['label']}'.trim()});
    await _reload();
  }

  String _time(Object? at) {
    final t = DateTime.tryParse('${at ?? ''}')?.toLocal();
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.day}/${t.month} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final mine = _mine;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'నా ఫోన్ పేమెంట్లు' : 'My phone payments')),
      body: mine == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(key: const Key('askodoxMyPhonePayments'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
              _stateCard(mine, te),
              if (mine.enabled) _setupCard(mine, te),
              _foundCard(mine, te),
              _appsCard(mine, te),
              _accountsCard(mine, te),
              _historyCard(mine, te),
              const SizedBox(height: 8),
              Text(
                te
                    ? 'ఇవన్నీ ఈ ఫోన్‌లోనే ఉంటాయి. యాప్ నోటిఫికేషన్ / బ్యాంక్ SMS నోటిఫికేషన్ మాత్రమే చదువుతుంది — SMS ఇన్‌బాక్స్ కాదు. నోటిఫికేషన్ అంటే బ్యాంక్ నిర్ధారణ కాదు.'
                    : 'All of this stays on this phone. It reads only the notification of the apps / bank SMS you choose — never your SMS inbox. A notification is not a bank confirmation.',
                style: const TextStyle(fontSize: 12),
              ),
            ]),
    );
  }

  Widget _stateCard(AskodoxMyPhoneAlerts m, bool te) {
    final allowed = _status['listenerAllowed'] == true;
    return Card(
      key: const Key('askodoxMineState'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            key: const Key('askodoxMineEnabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(te ? 'నా ఫోన్‌కి వచ్చే పేమెంట్లు చెప్పు' : 'Say the payments that reach my phone',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(te ? 'ఎవరు ఎంత క్రెడిట్ / డెబిట్ అయ్యారో చెబుతుంది, హిస్టరీలో ఉంచుతుంది.' : 'Says who credited / debited and how much, and keeps it in your history.'),
            value: m.enabled,
            onChanged: _toggle,
          ),
          if (m.enabled && !allowed)
            ListTile(
              key: const Key('askodoxMineAccess'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309)),
              title: Text(te ? 'నోటిఫికేషన్ యాక్సెస్ ఇవ్వండి' : 'Allow notification access'),
              subtitle: Text(te ? 'ASKODOX ని ఆన్ చేయండి.' : 'Switch ASKODOX on in the list.'),
              trailing: FilledButton(onPressed: _bridge.openListenerSettings, child: Text(te ? 'తెరవండి' : 'Open')),
            ),
          const Divider(),
          Text(te ? 'భాష' : 'Language', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            key: const Key('askodoxMineLanguage'),
            segments: const [
              ButtonSegment(value: 'te', label: Text('తెలుగు')),
              ButtonSegment(value: 'hi', label: Text('हिन्दी')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {m.language},
            onSelectionChanged: (v) => _change((x) => x.language = v.first),
          ),
          SwitchListTile(
            key: const Key('askodoxMineSayName'),
            contentPadding: EdgeInsets.zero,
            title: Text(te ? 'పేరు చెప్పు' : 'Say the name'),
            value: m.sayName,
            onChanged: (v) => _change((x) => x.sayName = v),
          ),
          SwitchListTile(
            key: const Key('askodoxMineDebits'),
            contentPadding: EdgeInsets.zero,
            title: Text(te ? 'డెబిట్ (డబ్బు వెళ్ళినప్పుడు) కూడా చెప్పు' : 'Also say debits (money going out)'),
            subtitle: Text(te ? 'ఆఫ్ అయినా డెబిట్లు హిస్టరీలో ఉంటాయి.' : 'Off: debits are still kept in your history.'),
            value: m.announceDebits,
            onChanged: (v) => _change((x) => x.announceDebits = v),
          ),
          OutlinedButton.icon(
            key: const Key('askodoxMineTest'),
            onPressed: () async {
              await _bridge.speakTest(100, personal: true);
              await _confirm1('sound');
            },
            icon: const Icon(Icons.volume_up_outlined),
            label: Text(te ? 'సౌండ్ టెస్ట్' : 'Sound test'),
          ),
        ]),
      ),
    );
  }

  bool get _shopListening => _status['enabled'] == true;

  IconData _kindIcon(String kind) => switch (kind) {
        'sms' => Icons.sms_outlined,
        'bank' => Icons.account_balance_outlined,
        _ => Icons.qr_code_2_rounded,
      };

  String _kindLabel(String kind, bool te) => switch (kind) {
        'sms' => te ? 'బ్యాంక్ SMS' : 'Bank SMS',
        'bank' => te ? 'బ్యాంక్ యాప్' : 'Bank app',
        _ => te ? 'UPI యాప్' : 'UPI app',
      };

  /// "Not on this phone" / "Messages reach ASKODOX ✓" / "No message seen yet" for one chosen app.
  String _appLine(String pkg, bool te) {
    final st = _appState[pkg];
    if (st == null) return pkg;
    if (st['installed'] != true) return te ? 'ఈ ఫోన్‌లో లేదు' : 'Not on this phone';
    final seen = st['lastSeenAt'] is num && (st['lastSeenAt'] as num) > 0;
    return seen
        ? (te ? 'మెసేజ్‌లు అందుతున్నాయి ✓' : 'Messages reach ASKODOX ✓')
        : (te ? 'ఇంకా మెసేజ్ రాలేదు' : 'No message seen yet');
  }

  /// Battery wording for this phone's maker (the page names differ on every brand).
  String _batteryHow(bool te, {String? app}) {
    final maker = '${_status['maker'] ?? ''}';
    final who = app ?? 'ASKODOX';
    if (maker.contains('samsung')) {
      return te
          ? '$who పేజీ → Battery → Unrestricted. "Manage app if unused" / "Pause app activity" ఆఫ్ చేయండి.'
          : '$who page → Battery → Unrestricted. Switch off "Manage app if unused" / "Pause app activity".';
    }
    if (maker.contains('xiaomi') || maker.contains('redmi') || maker.contains('poco')) {
      return te
          ? '$who పేజీ → Battery saver → No restrictions. Autostart కూడా ఆన్ చేయండి.'
          : '$who page → Battery saver → No restrictions. Also switch Autostart on.';
    }
    if (maker.contains('oppo') || maker.contains('realme') || maker.contains('oneplus')) {
      return te
          ? '$who పేజీ → Battery usage → "Allow background activity" + "Allow auto launch" ఆన్ చేయండి.'
          : '$who page → Battery usage → switch on "Allow background activity" and "Allow auto launch".';
    }
    if (maker.contains('vivo') || maker.contains('iqoo')) {
      return te
          ? '$who పేజీ → Battery → "Allow high background power consumption" ఆన్ చేయండి.'
          : '$who page → Battery → switch on "Allow high background power consumption".';
    }
    return te ? '$who పేజీ → Battery → Unrestricted / Don\'t optimise.' : '$who page → Battery → Unrestricted / Don\'t optimise.';
  }

  /// One checklist for every phone: each row opens the exact Android page and turns ✓ by itself when the phone can
  /// check it (the rest are ticked by the person after doing them).
  Widget _setupCard(AskodoxMyPhoneAlerts m, bool te) {
    final rows = <Widget>[];
    var open = 0;
    void row(String id, bool done, String title, String how, Future<void> Function() go, {bool selfConfirm = false}) {
      if (!done) open++;
      rows.add(ListTile(
        key: ValueKey('askodoxMineStep-$id'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: done ? const Color(0xFF17784C) : const Color(0xFFB45309)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: done ? null : Text(how, style: const TextStyle(fontSize: 12)),
        trailing: done
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (selfConfirm)
                  TextButton(
                    key: ValueKey('askodoxMineStepDone-$id'),
                    onPressed: () => _confirm1(id),
                    child: Text(te ? 'అయింది' : 'Done'),
                  ),
                FilledButton(
                  key: ValueKey('askodoxMineStepGo-$id'),
                  onPressed: () async {
                    await go();
                    if (selfConfirm) await _confirm1('$id:opened');
                  },
                  child: Text(te ? 'తెరవండి' : 'Open'),
                ),
              ]),
      ));
    }

    if (_status['listenerDeclared'] != false) {
      row('access', _status['listenerAllowed'] == true, te ? '1. పేమెంట్ మెసేజ్ చదివే అనుమతి' : '1. Permission to read payment messages',
          te ? 'లిస్ట్‌లో ASKODOX ఆన్ చేసి వెనక్కి రండి.' : 'Switch ASKODOX on in the list, then come back.', _bridge.openListenerSettings);
    }
    row('battery', _status['batteryUnrestricted'] != false, te ? '2. ఫోన్ ASKODOX ను ఆపకూడదు' : '2. The phone must not stop ASKODOX',
        _batteryHow(te), _bridge.openBatterySettings);
    if (_status['autostartPage'] == true) {
      row('autostart', _confirmed.contains('autostart'), te ? '3. Autostart ఆన్' : '3. Autostart on',
          te ? 'తెరుచుకునే లిస్ట్‌లో ASKODOX తో పాటు మీ పేమెంట్ / బ్యాంక్ యాప్‌లు ఆన్ చేయండి.' : 'Switch on ASKODOX and your payment / bank apps in the list.',
          () async => _bridge.openAutostartSettings(), selfConfirm: true);
    }
    final sms = '${_status['smsApp'] ?? ''}';
    if (sms.isNotEmpty) {
      final inList = m.apps.containsKey(sms);
      final seen = (_appState[sms]?['lastSeenAt'] is num) && (_appState[sms]!['lastSeenAt'] as num) > 0;
      row('sms', inList && (seen || _confirmed.contains('sms')), te ? 'బ్యాంక్ SMS చదవడం' : 'Read bank SMS',
          inList
              ? (te
                  ? 'SMS యాప్ నోటిఫికేషన్లు ఆన్ చేయండి (QR పేమెంట్‌లకు చాలాసార్లు SMS మాత్రమే వస్తుంది). SMS ఇన్‌బాక్స్ చదవం.'
                  : 'Keep the SMS app notifications on (QR payments often give only an SMS). The inbox is never read.')
              : (te ? 'మీ SMS యాప్ లిస్ట్‌లో లేదు — "జోడించు" నొక్కండి.' : 'Your SMS app is not in the list — tap Add.'),
          () async {
            if (!inList) {
              final label = askodoxMoneyAppCatalog[sms]?.$1 ??
                  '${_installed.where((a) => a['package'] == sms).firstOrNull?['label'] ?? 'Messages'}';
              await _change((x) => x.apps = {...x.apps, sms: label});
              await _reload();
            } else {
              await _bridge.openSmsAppSettings();
            }
          },
          selfConfirm: inList);
    }
    for (final e in m.apps.entries) {
      final st = _appState[e.key];
      if (st == null || st['installed'] != true || e.key == sms) continue;
      final seen = st['lastSeenAt'] is num && (st['lastSeenAt'] as num) > 0;
      row('app_notifications:${e.key}', seen || _confirmed.contains('app_notifications:${e.key}'),
          te ? '${e.value} నోటిఫికేషన్లు ఆన్' : '${e.value} notifications on',
          te ? '${e.value} పేజీలో నోటిఫికేషన్లు అన్నీ ఆన్ చేయండి. అవి రాకపోతే ASKODOX కి పేమెంట్ తెలియదు.'
              : 'Switch all ${e.value} notifications on. Without them ASKODOX cannot hear the payment.',
          () => _bridge.openAppNotificationSettings(e.key),
          selfConfirm: true);
      row('app_battery:${e.key}', st['batteryUnrestricted'] == true, te ? '${e.value} ఆగకూడదు' : '${e.value} must not be stopped',
          _batteryHow(te, app: e.value), () => _bridge.openAppDetails(e.key));
    }
    row('sound', _confirmed.contains('sound'), te ? 'సౌండ్ టెస్ట్' : 'Sound test',
        te ? 'ఒక టెస్ట్ పేమెంట్ వినిపిస్తుంది.' : 'Plays a test payment.', () => _bridge.speakTest(100, personal: true).then((_) => _confirm1('sound')));
    return Card(
      key: const Key('askodoxMineSetup'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              open == 0
                  ? (te ? 'అన్నీ సిద్ధం ✓' : 'All set ✓')
                  : (te ? 'సెటప్ — ఇంకా $open మిగిలాయి' : 'Setup — $open left'),
              key: const Key('askodoxMineSetupTitle'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (open > 0) ...rows,
        ]),
      ),
    );
  }

  /// Payment / bank / SMS apps found on this phone that are not in the list yet: one tap adds one, or all.
  Widget _foundCard(AskodoxMyPhoneAlerts m, bool te) {
    final found = _found(m);
    if (found.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const Key('askodoxMineFound'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'ఈ ఫోన్‌లో దొరికిన పేమెంట్ / బ్యాంక్ యాప్‌లు' : 'Payment / bank apps found on this phone',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final a in found)
            ListTile(
              key: ValueKey('askodoxMineFound-${a['package']}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_kindIcon(askodoxMoneyAppKind('${a['package']}', '${a['label']}'))),
              title: Text('${a['label']}'),
              subtitle: Text(_kindLabel(askodoxMoneyAppKind('${a['package']}', '${a['label']}'), te)),
              trailing: TextButton(
                key: ValueKey('askodoxMineFoundAdd-${a['package']}'),
                onPressed: () async {
                  await _change((x) => x.apps = {...x.apps, '${a['package']}': '${a['label']}'});
                  await _reload();
                },
                child: Text(te ? 'జోడించు' : 'Add'),
              ),
            ),
          if (found.length > 1)
            FilledButton.tonal(
              key: const Key('askodoxMineFoundAll'),
              onPressed: () async {
                await _change((x) => x.apps = {...x.apps, for (final a in found) '${a['package']}': '${a['label']}'});
                await _reload();
              },
              child: Text(te ? 'అన్నీ జోడించు' : 'Add all'),
            ),
        ]),
      ),
    );
  }

  Widget _appsCard(AskodoxMyPhoneAlerts m, bool te) {
    final entries = m.apps.entries.toList()..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return Card(
      key: const Key('askodoxMineApps'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'నా యాప్‌లు / SMS' : 'My apps / SMS', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(te ? 'ఈ యాప్‌ల నోటిఫికేషన్లే చదువుతాం. మీకు కావలసినవి జోడించండి, వద్దనుకున్నవి తీసేయండి.' : 'Only these apps\' notifications are read. Add the ones you want; remove the rest.',
              style: const TextStyle(fontSize: 12.5)),
          for (final e in entries)
            ListTile(
              key: ValueKey('askodoxMineApp-${e.key}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_kindIcon(askodoxMoneyAppKind(e.key, e.value))),
              title: Text(e.value),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_kindLabel(askodoxMoneyAppKind(e.key, e.value), te)} · ${_appLine(e.key, te)}',
                    style: const TextStyle(fontSize: 11.5)),
                if (_shopListening)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 6, children: [
                      for (final d in const ['mine', 'shop'])
                        ChoiceChip(
                          key: ValueKey('askodoxMineDest-$d-${e.key}'),
                          visualDensity: VisualDensity.compact,
                          label: Text(d == 'shop' ? (te ? 'షాప్' : 'Shop') : (te ? 'నా ఫోన్' : 'My phone')),
                          selected: m.destinationOf(e.key) == d,
                          onSelected: (_) => _change((x) => x.destinations = {...x.destinations, e.key: d}),
                        ),
                    ]),
                  ),
              ]),
              isThreeLine: _shopListening,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  key: ValueKey('askodoxMineAppSettings-${e.key}'),
                  tooltip: te ? 'ఈ యాప్ నోటిఫికేషన్ సెట్టింగ్' : 'This app\'s notification settings',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => _bridge.openAppNotificationSettings(e.key),
                ),
                IconButton(
                  key: ValueKey('askodoxMineAppEdit-${e.key}'),
                  tooltip: te ? 'పేరు మార్చు' : 'Rename',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final name = await _ask(te ? 'యాప్ పేరు' : 'App name', e.value, te);
                    if (name != null && name.isNotEmpty) await _change((x) => x.apps = {...x.apps, e.key: name});
                  },
                ),
                IconButton(
                  key: ValueKey('askodoxMineAppDelete-${e.key}'),
                  tooltip: te ? 'తొలగించు' : 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    if (await _confirm(te ? 'ఈ యాప్ తొలగించాలా?' : 'Remove this app?', e.value, te)) {
                      await _change((x) => x
                        ..apps = ({...x.apps}..remove(e.key))
                        ..destinations = ({...x.destinations}..remove(e.key)));
                    }
                  },
                ),
              ]),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const Key('askodoxMineAppAdd'),
            onPressed: () => _addApp(te),
            icon: const Icon(Icons.add_rounded),
            label: Text(te ? 'యాప్ జోడించు' : 'Add an app'),
          ),
        ]),
      ),
    );
  }

  Widget _accountsCard(AskodoxMyPhoneAlerts m, bool te) {
    final entries = m.accounts.entries.toList();
    return Card(
      key: const Key('askodoxMineAccounts'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'నా ఖాతాలు' : 'My accounts', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(te ? 'బ్యాంక్ SMS లో ఖాతా చివరి అంకెలు ఉంటాయి. వాటికి పేరు పెట్టండి (సేవింగ్స్, కరెంట్…) — హిస్టరీలో ఆ పేరే కనిపిస్తుంది.' : 'Bank SMS carry the last digits of the account. Name them (Savings, Current…) and the history shows that name.',
              style: const TextStyle(fontSize: 12.5)),
          for (final e in entries)
            ListTile(
              key: ValueKey('askodoxMineAccount-${e.key}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(e.value),
              subtitle: Text('A/c ••${e.key}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  key: ValueKey('askodoxMineAccountEdit-${e.key}'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final name = await _ask(te ? 'ఖాతా పేరు' : 'Account name', e.value, te);
                    if (name != null && name.isNotEmpty) await _change((x) => x.accounts = {...x.accounts, e.key: name});
                  },
                ),
                IconButton(
                  key: ValueKey('askodoxMineAccountDelete-${e.key}'),
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    if (await _confirm(te ? 'ఈ ఖాతా తొలగించాలా?' : 'Remove this account name?', e.value, te)) {
                      await _change((x) => x.accounts = {...x.accounts}..remove(e.key));
                    }
                  },
                ),
              ]),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const Key('askodoxMineAccountAdd'),
            onPressed: () async {
              final tail = await _ask(te ? 'ఖాతా చివరి 4 అంకెలు' : 'Last 4 digits of the account', '', te, digits: true);
              if (tail == null || tail.length < 3) return;
              if (!mounted) return;
              final name = await _ask(te ? 'ఈ ఖాతా పేరు' : 'Name for this account', '', te, hint: te ? 'సేవింగ్స్' : 'Savings');
              if (name == null || name.isEmpty) return;
              await _change((x) => x.accounts = {...x.accounts, tail: name});
            },
            icon: const Icon(Icons.add_rounded),
            label: Text(te ? 'ఖాతా జోడించు' : 'Add an account'),
          ),
        ]),
      ),
    );
  }

  Widget _historyCard(AskodoxMyPhoneAlerts m, bool te) {
    final shown = _events.where((e) => _filter == 'all' || (_filter == 'in' ? e['direction'] != 'out' : e['direction'] == 'out')).toList();
    return Card(
      key: const Key('askodoxMineHistory'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(te ? 'నా హిస్టరీ' : 'My history', style: const TextStyle(fontWeight: FontWeight.w800))),
            TextButton.icon(
              key: const Key('askodoxMineHistoryClear'),
              onPressed: _events.isEmpty
                  ? null
                  : () async {
                      if (await _confirm(te ? 'హిస్టరీ మొత్తం తొలగించాలా?' : 'Delete all history?', te ? 'ఈ ఫోన్‌లోని అన్ని వరుసలు పోతాయి.' : 'Every row on this phone is removed.', te)) {
                        await _bridge.deleteEvents();
                        await _reload();
                      }
                    },
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(te ? 'అన్నీ' : 'Clear all'),
            ),
          ]),
          Wrap(spacing: 8, children: [
            for (final f in const ['all', 'in', 'out'])
              ChoiceChip(
                key: ValueKey('askodoxMineFilter-$f'),
                label: Text(switch (f) { 'in' => te ? 'వచ్చినవి' : 'In', 'out' => te ? 'వెళ్ళినవి' : 'Out', _ => te ? 'అన్నీ' : 'All' }),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ]),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(te ? 'ఇంకా ఏదీ లేదు.' : 'Nothing yet.', style: const TextStyle(fontSize: 13)),
            ),
          for (final e in shown)
            ListTile(
              key: ValueKey('askodoxMineEvent-${e['local_id']}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(e['direction'] == 'out' ? Icons.call_made_rounded : Icons.call_received_rounded,
                  color: e['direction'] == 'out' ? const Color(0xFFB91C1C) : const Color(0xFF17784C)),
              title: Text(
                  '${e['direction'] == 'out' ? '−' : '+'}${e['amount_paise'] is num ? askodoxRupees(e['amount_paise']) : '—'}'
                  '${'${e['party'] ?? ''}'.isEmpty ? '' : ' · ${e['party']}'}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text([
                '${e['source_label'] ?? ''}${'${e['also_from'] ?? ''}'.isEmpty ? '' : ' + ${e['also_from']}'}',
                m.accountName('${e['account'] ?? ''}'),
                _time(e['detected_at']),
                (te ? askodoxSpokenLabel('${e['spoken']}').$2 : askodoxSpokenLabel('${e['spoken']}').$1),
              ].where((x) => x.isNotEmpty).join(' · ')),
              trailing: IconButton(
                key: ValueKey('askodoxMineEventDelete-${e['local_id']}'),
                tooltip: te ? 'తొలగించు' : 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  await _bridge.deleteEvents(['${e['local_id']}']);
                  await _reload();
                },
              ),
            ),
        ]),
      ),
    );
  }
}

class _AppPicker extends StatefulWidget {
  const _AppPicker({required this.rows, required this.te});
  final List<AskodoxJson> rows;
  final bool te;

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  String _q = '';
  final _pkg = TextEditingController();

  @override
  void dispose() {
    _pkg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final rows = widget.rows.where((r) => '${r['label']} ${r['package']}'.toLowerCase().contains(_q.toLowerCase())).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: const Key('askodoxMineAppSearch'),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: te ? 'యాప్ వెతకండి' : 'Search apps'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView(children: [
              for (final r in rows)
                ListTile(
                  key: ValueKey('askodoxMinePick-${r['package']}'),
                  title: Text('${r['label']}'),
                  subtitle: Text('${r['package']}', style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(context, r),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('askodoxMineAppPackage'),
                  controller: _pkg,
                  decoration: InputDecoration(labelText: te ? 'లేదా ప్యాకేజీ ID టైప్ చేయండి' : 'Or type a package id'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('askodoxMineAppPackageAdd'),
                onPressed: () {
                  final v = _pkg.text.trim();
                  if (v.contains('.') && !v.contains(' ')) Navigator.pop(context, {'package': v, 'label': v.split('.').last});
                },
                child: Text(te ? 'జోడించు' : 'Add'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
