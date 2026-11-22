import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/backend_providers.dart';
import '../data/pos_hardware.dart' show AskodoxScanException;
import '../data/pos_payment_alerts.dart';
import '../data/pos_repository.dart';
import '../domain/money_accounts.dart';
import 'offline_voice_card.dart';
import 'pos_collect_screens.dart' show askodoxQrReaderProvider;
import 'pos_common.dart';
import 'pay_alert_disclaimer.dart';
import 'payment_source_icon.dart';

/// "My phone" payments (owner 2026-11-15): any signed-in person -- no shop, no registered UPI id -- gets the payment
/// notifications and bank SMS of the apps THEY choose read out on their own phone and kept in their own history.
/// Everything is on this phone only; every list (apps, accounts, history) can be edited and deleted.
///
/// Built for every phone, bank and app (owner rule: one example = all cases): the payment / bank / SMS apps found on
/// THIS phone are offered by themselves, and one checklist opens each Android page the phone needs (notification
/// access, battery, the maker's Autostart page, each app's own notifications, the SMS app) -- nothing to hunt for.
/// A phone that also listens for a shop chooses per app where it goes (shop or my phone); both work together.
class AskodoxMyPhonePaymentsScreen extends ConsumerStatefulWidget {
  const AskodoxMyPhonePaymentsScreen({super.key, this.open = ''});

  /// Opens one part at once (history | apps | accounts | voice) -- the Money screen's folder pages link straight in.
  final String open;

  @override
  ConsumerState<AskodoxMyPhonePaymentsScreen> createState() => _AskodoxMyPhonePaymentsScreenState();
}

class _AskodoxMyPhonePaymentsScreenState extends ConsumerState<AskodoxMyPhonePaymentsScreen> with WidgetsBindingObserver {
  AskodoxMyPhoneAlerts? _mine;
  AskodoxJson _status = const {};
  List<AskodoxJson> _events = const [];
  String _filter = 'all'; // all | in | out
  String? _account; // null = all accounts
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
    unawaited(_importMethods());
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
      token = session.user == null ? '' : (session.tokenPlaceholder ?? '');
    } catch (_) {}
    _status = await _bridge.configurePersonal(mine.nativeConfig(baseUrl: base, token: token));
  }

  Future<void> _reload() async {
    final status = await _bridge.status();
    final events = (await _bridge.localEvents())
        .where((e) => (e['direction'] != null && e['direction'] != 'due') || e['test'] == true)
        .toList();
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
              _quickCard(mine, te),
              if (mine.enabled) _setupCard(mine, te),
              // Owner 2026-11-19: four tiles, one thing each -- a tap shows just that part (tap again to close).
              _tiles(te),
              if (_section == 'apps') ...[_foundCard(mine, te), _appsCard(mine, te)],
              if (_section == 'accounts') _accountsCard(mine, te),
              if (_section == 'voice') _stateCard(mine, te),
              if (_section == 'history' || _section.isEmpty) _historyCard(mine, te),
              // Everything else is tucked away: the page stays short once setup is done (owner 2026-11-16).
              if (_section.isEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const Key('askodoxMineMore'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(te ? 'మరిన్ని సెట్టింగ్స్ (భాష, యాప్‌లు, ఖాతాలు)' : 'More settings (language, apps, accounts)',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  children: [
                    _stateCard(mine, te),
                    _foundCard(mine, te),
                    _appsCard(mine, te),
                    _accountsCard(mine, te),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                te
                    ? 'ఇవన్నీ ఈ ఫోన్‌లోనే ఉంటాయి. మీరు ఎంచుకున్న యాప్‌ల నోటిఫికేషన్ / బ్యాంక్ SMS నోటిఫికేషన్ మాత్రమే చదువుతుంది — SMS ఇన్‌బాక్స్ కాదు.'
                    : 'All of this stays on this phone. It reads only the notification of the apps / bank SMS you choose — never your SMS inbox.',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              AskodoxPayAlertDisclaimer(te: te),
            ]),
    );
  }

  /// ONE card at the top: a single button turns everything on (the alerts, every money / SMS app found on this phone,
  /// and opens the system's notification-access list if ASKODOX is not allowed yet); once it is all on, one line.
  Widget _quickCard(AskodoxMyPhoneAlerts m, bool te) {
    final allowed = _status['listenerAllowed'] == true;
    final ready = m.enabled && allowed;
    return Card(
      key: const Key('askodoxMineQuick'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ready
            ? Row(children: [
                const Icon(Icons.check_circle, color: Color(0xFF15803D)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(te ? 'పేమెంట్ అలర్ట్స్ ఆన్ ✓ (${m.apps.length} యాప్‌లు)' : 'Payment alerts are on ✓ (${m.apps.length} apps)',
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                TextButton(
                    key: const Key('askodoxMineQuickTest'),
                    onPressed: () async {
                      await _bridge.speakTest(100, personal: true);
                      await _confirm1('sound');
                    },
                    child: Text(te ? 'టెస్ట్' : 'Test')),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(te ? 'ఒక్క నొక్కుతో అన్నీ ఆన్' : 'Turn everything on in one tap', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(te ? 'మీ ఫోన్‌లో ఉన్న పేమెంట్ / బ్యాంక్ / SMS యాప్‌లన్నీ చేర్చి, అలర్ట్స్ ఆన్ చేస్తుంది. తర్వాత ASKODOX ని ఆన్ చేయమని లిస్ట్ తెరుస్తుంది.' : 'Adds every payment / bank / SMS app on this phone and switches the alerts on, then opens the list where you switch ASKODOX on.',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('askodoxMineQuickOn'),
                  onPressed: () async {
                    final found = _found(m);
                    await _change((x) {
                      x.enabled = true;
                      x.apps = {...x.apps, for (final a in found) '${a['package']}': '${a['label']}'};
                    });
                    await _reload();
                    if (_status['listenerAllowed'] != true) await _bridge.openListenerSettings();
                  },
                  icon: const Icon(Icons.bolt),
                  label: Text(te ? 'అన్నీ ఆన్ చేయి' : 'Turn all on'),
                ),
              ]),
      ),
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
            subtitle: Text(te ? 'ఎవరు ఎంత పంపారో / ఎవరికి ఎంత వెళ్ళిందో చెబుతుంది, హిస్టరీలో ఉంచుతుంది.' : 'Says who credited / debited and how much, and keeps it in your history.'),
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
            emptySelectionAllowed: true,
            selected: {if (const ['te', 'hi', 'en'].contains(m.language)) m.language},
            onSelectionChanged: (v) {
              if (v.isNotEmpty) _change((x) => x.language = v.first);
            },
          ),
          // Every other Indian language: one more row in the native table, nothing per language in the app.
          DropdownButton<String>(
            key: const Key('askodoxMineLanguageMore'),
            isExpanded: true,
            hint: Text(te ? 'ఇతర భాషలు' : 'Other languages'),
            value: const ['te', 'hi', 'en'].contains(m.language) ? null : m.language,
            items: const [
              DropdownMenuItem(value: 'ta', child: Text('தமிழ்')),
              DropdownMenuItem(value: 'kn', child: Text('ಕನ್ನಡ')),
              DropdownMenuItem(value: 'ml', child: Text('മലയാളം')),
              DropdownMenuItem(value: 'mr', child: Text('मराठी')),
              DropdownMenuItem(value: 'bn', child: Text('বাংলা')),
              DropdownMenuItem(value: 'gu', child: Text('ગુજરાતી')),
              DropdownMenuItem(value: 'pa', child: Text('ਪੰਜਾਬੀ')),
              DropdownMenuItem(value: 'or', child: Text('ଓଡ଼ିଆ')),
              DropdownMenuItem(value: 'ur', child: Text('اردو')),
            ],
            onChanged: (v) {
              if (v != null) _change((x) => x.language = v);
            },
          ),
          AskodoxOfflineVoiceCard(language: m.language),
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

  bool _showDone = false;

  /// Which tile is open ('' = none: the history and the folded "More settings" show as before).
  late String _section = const {'history', 'apps', 'accounts', 'voice'}.contains(widget.open) ? widget.open : '';

  Widget _tiles(bool te) {
    Widget tile(String id, IconData icon, String en, String tel, String subEn, String subTe) {
      final on = _section == id;
      return Expanded(
        child: Material(
          color: on ? const Color(0xFFE9EEFF) : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: on ? const Color(0xFF2B4BC0) : const Color(0xFFE3E6EE))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('askodoxMineTile-$id'),
            onTap: () => setState(() => _section = on ? '' : id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 22, color: const Color(0xFF141B4D)),
                const SizedBox(height: 4),
                Text(te ? tel : en, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(te ? subTe : subEn,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
              ]),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        Row(children: [
          tile('history', Icons.history, 'History', 'హిస్టరీ', 'Payments received', 'వచ్చిన పేమెంట్లు'),
          const SizedBox(width: 10),
          tile('apps', Icons.apps, 'Apps', 'యాప్‌లు', 'Which apps are read', 'ఏ యాప్‌లు చదవాలి'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile('accounts', Icons.account_balance_outlined, 'Accounts', 'ఖాతాలు', 'Bank accounts, names', 'బ్యాంక్ ఖాతాలు, పేర్లు'),
          const SizedBox(width: 10),
          tile('voice', Icons.record_voice_over_outlined, 'Language, voice', 'భాష, వాయిస్', 'What is spoken', 'ఏం చెప్పాలి'),
        ]),
      ]),
    );
  }

  /// One checklist for every phone: each row opens the exact Android page and turns ✓ by itself when the phone can
  /// check it (the rest are ticked by the person after doing them).
  Widget _setupCard(AskodoxMyPhoneAlerts m, bool te) {
    final rows = <Widget>[];
    final doneRows = <Widget>[];
    var open = 0;
    void row(String id, bool done, String title, String how, Future<void> Function() go, {bool selfConfirm = false}) {
      if (!done) open++;
      // Owner 2026-11-19: what is LEFT comes first; finished steps fold under one line (the list was 20+ rows long).
      (done ? doneRows : rows).add(ListTile(
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
          if (open > 0 && doneRows.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('askodoxMineSetupDoneToggle'),
                onPressed: () => setState(() => _showDone = !_showDone),
                child: Text(_showDone
                    ? (te ? 'పూర్తయినవి దాచు ▴' : 'Hide finished ▴')
                    : (te ? '${doneRows.length} పూర్తయ్యాయి ✓ · చూపించు ▾' : '${doneRows.length} done ✓ · show ▾')),
              ),
            ),
          if (open > 0 && _showDone) ...doneRows,
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

  // ------------------------------------------------------------------ my money accounts (owner 2026-11-17)

  /// "Ways to get paid" the person saved (bank / UPI) become accounts here too -- added once, never twice.
  Future<void> _importMethods() async {
    final mine = _mine;
    if (mine == null) return;
    try {
      if (ref.read(authSessionProvider).user == null) return;
      final methods = await ref.read(askodoxPosRepositoryProvider).myPaymentMethods();
      final fresh = askodoxPlacesFromMethods(methods, mine.places, mine.dismissedMethods);
      if (fresh.isNotEmpty) await _change((x) => x..places = [...x.places, ...fresh]..syncAccounts());
    } catch (_) {
      // offline / signed out: the person can still add accounts by hand
    }
  }

  Future<void> _savePlace(AskodoxMoneyPlace place) => _change((x) {
        x.places = [for (final p in x.places) if (p.key != place.key) p, place];
        x.syncAccounts();
      });

  Future<void> _deletePlace(AskodoxMoneyPlace place) => _change((x) {
        x.places = [for (final p in x.places) if (p.key != place.key) p];
        if (place.fromMethod.isNotEmpty) x.dismissedMethods = {...x.dismissedMethods, place.fromMethod};
        x.assigned = {for (final e in x.assigned.entries) if (e.value != place.key) e.key: e.value};
        if (_account == place.key) _account = null;
        x.syncAccounts();
      });

  /// Add (or edit) an account: bank (last digits), UPI ID, wallet or QR (photo of the QR).
  Future<void> _editPlace(AskodoxMyPhoneAlerts m, bool te, {AskodoxMoneyPlace? place, String type = 'bank', String tail = ''}) async {
    final out = await showModalBottomSheet<AskodoxMoneyPlace>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlaceSheet(apps: m.apps, te: te, place: place, type: type, tail: tail, others: m.places),
    );
    if (out != null) await _savePlace(out);
  }

  Widget _accountsCard(AskodoxMyPhoneAlerts m, bool te) {
    return Card(
      key: const Key('askodoxMineAccounts'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'నా డబ్బు ఖాతాలు' : 'My money accounts', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(
              te
                  ? 'బ్యాంక్ ఖాతా, UPI ID, వాలెట్, QR — ఏదైనా జోడించండి. హిస్టరీ ఖాతాల వారీగా కనిపిస్తుంది. ఒక యాప్‌ని ఖాతాకి లింక్ చేస్తే (ఉదా. PhonePe = HDFC కరెంట్) ఆ యాప్ పేమెంట్లు ఆ ఖాతాలో పడతాయి.'
                  : 'Add any bank account, UPI ID, wallet or QR. The history is shown account by account. Link an app to an account (e.g. PhonePe = HDFC current) and its payments go there.',
              style: const TextStyle(fontSize: 12.5)),
          for (final p in m.places)
            ListTile(
              key: ValueKey('askodoxMineAccount-${p.key}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (p.type) {
                'upi' => Icons.alternate_email_rounded,
                'wallet' => Icons.account_balance_wallet_outlined,
                'qr' => Icons.qr_code_2_rounded,
                _ => Icons.account_balance_outlined,
              }),
              title: Text(p.name),
              subtitle: Text([
                te ? askodoxMoneyPlaceTypeLabel(p.type).$2 : askodoxMoneyPlaceTypeLabel(p.type).$1,
                if (p.tail.isNotEmpty) '••${p.tail}',
                if (p.upi.isNotEmpty) p.upi,
                if (p.apps.isNotEmpty) '🔗 ${p.apps.map((a) => m.apps[a] ?? a).join(', ')}',
              ].join(' · ')),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  key: ValueKey('askodoxMineAccountEdit-${p.key}'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editPlace(m, te, place: p),
                ),
                IconButton(
                  key: ValueKey('askodoxMineAccountDelete-${p.key}'),
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    if (await _confirm(te ? 'ఈ ఖాతా తొలగించాలా?' : 'Remove this account?', p.name, te)) await _deletePlace(p);
                  },
                ),
              ]),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const Key('askodoxMineAccountAdd'),
            onPressed: () => _editPlace(m, te),
            icon: const Icon(Icons.add_rounded),
            label: Text(te ? 'ఖాతా జోడించు' : 'Add an account'),
          ),
          SwitchListTile(
            key: const Key('askodoxMineSayAccount'),
            contentPadding: EdgeInsets.zero,
            value: m.sayAccount,
            title: Text(te ? 'వాయిస్‌లో ఖాతా పేరు చెప్పు' : 'Say the account name in the voice'),
            subtitle: Text(te ? 'ఉదా. "HDFC కరెంట్: ₹240 వచ్చింది" (బ్యాంక్ SMS లో ఖాతా నంబర్ ఉన్నప్పుడు)' : 'e.g. "HDFC current: ₹240 came" (when the bank SMS shows the account)'),
            onChanged: (v) => _change((x) => x.sayAccount = v),
          ),
        ]),
      ),
    );
  }

  String _placeName(AskodoxMyPhoneAlerts m, String key, bool te) {
    if (key.isEmpty) return te ? 'ఖాతా తెలియదు' : 'Account not known';
    for (final p in m.places) {
      if (p.key == key) return p.name;
    }
    return key.startsWith('bank:') ? 'A/c ••${key.substring(5)}' : key;
  }

  Map<String, String> _labelToPackage(AskodoxMyPhoneAlerts m) => {for (final e in m.apps.entries) e.value: e.key};

  /// Move one history row to another account (by hand).
  Future<void> _moveRow(AskodoxMyPhoneAlerts m, AskodoxJson e, String current, bool te) async {
    final keys = <String>{for (final p in m.places) p.key, current, askodoxUnknownAccount};
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(te ? 'ఈ పేమెంట్ ఏ ఖాతాది?' : 'Which account is this payment?', style: const TextStyle(fontWeight: FontWeight.w800))),
          for (final k in keys)
            ListTile(
              key: ValueKey('askodoxMineMoveTo-$k'),
              leading: Icon(k == current ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(_placeName(m, k, te)),
              onTap: () => Navigator.pop(ctx, k),
            ),
        ]),
      ),
    );
    if (picked == null || picked == current) return;
    await _change((x) => x.assigned = {...x.assigned, '${e['local_id']}': picked});
  }

  /// Owner 2026-11-21: one row -- the message it was read from (kept on this phone only), "wrong" corrections that
  /// also teach the phone, and the account. A correction never sends anything anywhere.
  Future<void> _rowSheet(AskodoxMyPhoneAlerts m, AskodoxJson e, String current, bool te) async {
    final id = '${e['local_id']}';
    final raw = [
      '${e['raw_title'] ?? ''}'.trim(),
      '${e['raw_text'] ?? ''}'.trim(),
    ].where((x) => x.isNotEmpty).join('\n');
    final also = e['raw_also'] is List ? (e['raw_also'] as List).map((x) => '$x').where((x) => x.trim().isNotEmpty).toList() : const <String>[];
    final out = e['direction'] == 'out';
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                '${e['direction'] == 'info' ? '' : out ? '−' : '+'}${e['amount_paise'] is num ? askodoxRupees(e['amount_paise']) : '—'}'
                '${'${e['party'] ?? ''}'.isEmpty ? '' : ' · ${e['party']}'}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (askodoxRowDoubt(e) case final d?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(te ? d.$2 : d.$1, style: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 12),
            Text(te ? 'ఈ message నుంచి చదివాం' : 'Read from this message', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Container(
              key: const Key('askodoxMineRowRaw'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
              child: SelectableText(
                raw.isEmpty
                    ? (te
                        ? 'ఈ వరుస పాత build లో వచ్చింది — అప్పుడు message దాచలేదు.'
                        : 'This row came on an older build — the message was not kept then.')
                    : [raw, ...also].join('\n\n'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 4),
            Text(te ? 'ఇది ఈ ఫోన్‌లోనే ఉంటుంది, ఎక్కడికీ పంపము.' : 'This stays on this phone; it is never sent anywhere.',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
            const SizedBox(height: 14),
            Text(te ? 'తప్పుగా చదివిందా?' : 'Read wrongly?', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (out || e['excluded'] == true)
              ListTile(
                key: const Key('askodoxMineRowCorrect-in'),
                leading: const Icon(Icons.call_received_rounded, color: Color(0xFF17784C)),
                title: Text(te ? 'తప్పు: ఇది వచ్చిన డబ్బు' : 'Wrong: this money came in'),
                onTap: () => Navigator.pop(ctx, 'in'),
              ),
            if (!out || e['excluded'] == true)
              ListTile(
                key: const Key('askodoxMineRowCorrect-out'),
                leading: const Icon(Icons.call_made_rounded, color: Color(0xFFB91C1C)),
                title: Text(te ? 'తప్పు: ఇది వెళ్ళిన డబ్బు' : 'Wrong: this money went out'),
                onTap: () => Navigator.pop(ctx, 'out'),
              ),
            if (e['excluded'] != true)
              ListTile(
                key: const Key('askodoxMineRowCorrect-none'),
                leading: const Icon(Icons.block_rounded),
                title: Text(te ? 'ఇది payment కాదు' : 'This is not a payment'),
                onTap: () => Navigator.pop(ctx, 'none'),
              ),
            const Divider(),
            ListTile(
              key: const Key('askodoxMineRowAccount'),
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(te ? 'ఖాతా మార్చు' : 'Change account'),
              subtitle: Text(_placeName(m, current, te)),
              onTap: () => Navigator.pop(ctx, 'account'),
            ),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'account') {
      await _moveRow(m, e, current, te);
      return;
    }
    final result = await _bridge.correctEvent(id, choice);
    await _reload();
    if (!mounted) return;
    final learned = result['learned'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(te
            ? (learned ? 'సరిచేశాం. ఇలాంటి message ఇకపై ఇలాగే చదువుతుంది.' : 'సరిచేశాం.')
            : (learned ? 'Fixed. Messages like this are read this way from now on.' : 'Fixed.'))));
  }

  Widget _historyCard(AskodoxMyPhoneAlerts m, bool te) {
    final toPkg = _labelToPackage(m);
    String accountOf(AskodoxJson e) => askodoxAccountOf(e, m.places, m.assigned, labelToPackage: toPkg);
    final inAccount = _events.where((e) => _account == null || accountOf(e) == _account).toList();
    final shown =
        inAccount.where((e) => _filter == 'all' || (_filter == 'in' ? e['direction'] != 'out' && e['direction'] != 'info' : e['direction'] == 'out')).toList();
    final present = <String>{for (final e in _events) accountOf(e)};
    final chips = <String>[for (final p in m.places) if (present.contains(p.key)) p.key];
    for (final k in present) {
      if (!chips.contains(k) && k.isNotEmpty) chips.add(k);
    }
    if (present.contains(askodoxUnknownAccount)) chips.add(askodoxUnknownAccount);
    final unnamed = askodoxUnnamedTails(_events, m.places);
    final now = DateTime.now();
    final today = askodoxMoneyTotals(inAccount, DateTime(now.year, now.month, now.day));
    final month = askodoxMoneyTotals(inAccount, DateTime(now.year, now.month));
    return Card(
      key: const Key('askodoxMineHistory'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(te ? 'నా హిస్టరీ' : 'My history', style: const TextStyle(fontWeight: FontWeight.w800))),
            TextButton(
              key: const Key('askodoxMineOpenMoney'),
              onPressed: () => context.push('/money'),
              child: Text(te ? 'అన్నీ ఒకే చోట' : 'All in one'),
            ),
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
          // A bank account seen in an SMS but not named yet: one tap to name it.
          for (final tail in unnamed.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  key: ValueKey('askodoxMineNameAccount-$tail'),
                  dense: true,
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(te ? 'కొత్త ఖాతా ••$tail కనిపించింది' : 'New account ••$tail found'),
                  subtitle: Text(te ? 'పేరు పెట్టండి (ఉదా. HDFC కరెంట్)' : 'Give it a name (e.g. HDFC current)'),
                  trailing: Text(te ? 'పేరు పెట్టు' : 'Name it', style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => _editPlace(m, te, type: 'bank', tail: tail),
                ),
              ),
            ),
          if (chips.length > 1 || (chips.length == 1 && chips.first.isNotEmpty))
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: const Key('askodoxMineAccountFilter-all'),
                    label: Text(te ? 'అన్ని ఖాతాలు' : 'All accounts'),
                    selected: _account == null,
                    onSelected: (_) => setState(() => _account = null),
                  ),
                ),
                for (final k in chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: ValueKey('askodoxMineAccountFilter-$k'),
                      label: Text(_placeName(m, k, te)),
                      selected: _account == k,
                      onSelected: (_) => setState(() => _account = k),
                    ),
                  ),
              ]),
            ),
          Wrap(spacing: 8, children: [
            for (final f in const ['all', 'in', 'out'])
              ChoiceChip(
                key: ValueKey('askodoxMineFilter-$f'),
                label: Text(switch (f) { 'in' => te ? 'వచ్చినవి' : 'In', 'out' => te ? 'వెళ్ళినవి' : 'Out', _ => te ? 'అన్నీ' : 'All' }),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ]),
          if (inAccount.isNotEmpty)
            Padding(
              key: const Key('askodoxMineTotals'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                  te
                      ? 'ఈ రోజు: వచ్చింది ${askodoxRupees(today.inPaise)} · పోయింది ${askodoxRupees(today.outPaise)}\nఈ నెల: వచ్చింది ${askodoxRupees(month.inPaise)} · పోయింది ${askodoxRupees(month.outPaise)}'
                      : 'Today: in ${askodoxRupees(today.inPaise)} · out ${askodoxRupees(today.outPaise)}\nThis month: in ${askodoxRupees(month.inPaise)} · out ${askodoxRupees(month.outPaise)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
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
              onTap: () => _rowSheet(m, e, accountOf(e), te),
              leading: AskodoxPaymentSourceIcon(
                  event: e,
                  fallback: Icon(e['direction'] == 'out' ? Icons.call_made_rounded : Icons.call_received_rounded,
                      color: e['direction'] == 'out' ? const Color(0xFFB91C1C) : const Color(0xFF17784C))),
              title: Text(
                  '${e['direction'] == 'info' ? (e['info'] == 'suspect' ? '⚠️ ' : 'ℹ️ ') : e['doubt'] != null ? '❓ ' : ''}'
                  '${e['direction'] == 'info' ? '' : e['direction'] == 'out' ? '−' : '+'}${e['amount_paise'] is num ? askodoxRupees(e['amount_paise']) : '—'}'
                  '${'${e['party'] ?? ''}'.isEmpty ? '' : ' · ${e['party']}'}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: e['excluded'] == true ? const Color(0xFF9CA3AF) : null,
                      decoration: e['excluded'] == true ? TextDecoration.lineThrough : null)),
              subtitle: Text([
                if (askodoxRowDoubt(e) case final d?) te ? d.$2 : d.$1,
                if (e['note'] == 'refund') te ? 'రిఫండ్ జమ' : 'Refund received',
                if (e['note'] == 'cashback') te ? 'క్యాష్‌బ్యాక్' : 'Cashback',
                if (e['note'] == 'interest') te ? 'వడ్డీ' : 'Interest',
                '${e['source_label'] ?? ''}${'${e['also_from'] ?? ''}'.isEmpty ? '' : ' + ${e['also_from']}'}',
                _placeName(m, accountOf(e), te),
                if (askodoxBankConfirmedLabel(e) case final b?) te ? b.$2 : b.$1,
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
          if (shown.isNotEmpty)
            Text(
                te
                    ? 'ఏ వరుసనైనా నొక్కితే: చదివిన అసలు message, "తప్పు" సరిచేయడం, ఖాతా మార్చడం.'
                    : 'Tap any row: the message it was read from, "wrong" corrections, change its account.',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
        ]),
      ),
    );
  }
}

/// Add / edit one money account: type, name, last digits (bank), UPI ID (typed or read from a QR photo), linked apps.
class _PlaceSheet extends ConsumerStatefulWidget {
  const _PlaceSheet({required this.apps, required this.te, this.place, this.type = 'bank', this.tail = '', this.others = const []});
  final Map<String, String> apps;
  final bool te;
  final AskodoxMoneyPlace? place;
  final String type;
  final String tail;
  final List<AskodoxMoneyPlace> others;

  @override
  ConsumerState<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends ConsumerState<_PlaceSheet> {
  late String _type = widget.place?.type ?? widget.type;
  late final _name = TextEditingController(text: widget.place?.name ?? '');
  late final _tail = TextEditingController(text: widget.place?.tail ?? widget.tail);
  late final _upi = TextEditingController(text: widget.place?.upi ?? '');
  late Set<String> _apps = {...?widget.place?.apps};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _tail.dispose();
    _upi.dispose();
    super.dispose();
  }

  Future<void> _scan(String source) async {
    try {
      final text = await ref.read(askodoxQrReaderProvider).read(source);
      final upi = text == null ? null : askodoxUpiFromQr(text);
      setState(() {
        if (upi != null) {
          _upi.text = upi;
          _error = null;
        } else if (text != null) {
          _error = widget.te ? 'ఈ QR లో UPI ID లేదు.' : 'This QR has no UPI ID.';
        }
      });
    } on AskodoxScanException catch (e) {
      setState(() => _error = e.code == 'not_found'
          ? (widget.te ? 'ఫోటోలో QR కనిపించలేదు. దగ్గరగా మళ్ళీ తీయండి.' : 'No QR found in the photo. Try again, closer.')
          : (widget.te ? 'కెమెరా తెరవలేకపోయాం.' : 'Could not open the camera.'));
    }
  }

  void _save() {
    final te = widget.te;
    final name = _name.text.trim();
    final tail = _tail.text.replaceAll(RegExp(r'\D'), '');
    final upi = _upi.text.trim();
    if (_type == 'bank' && (tail.length < 3 || tail.length > 4)) {
      setState(() => _error = te ? 'ఖాతా చివరి 3 లేదా 4 అంకెలు ఇవ్వండి.' : 'Give the last 3 or 4 digits of the account.');
      return;
    }
    if ((_type == 'upi' || _type == 'qr') && !upi.contains('@')) {
      setState(() => _error = te ? 'సరైన UPI ID ఇవ్వండి (ఉదా. name@ybl).' : 'Give a valid UPI ID (e.g. name@ybl).');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = te ? 'పేరు పెట్టండి.' : 'Give it a name.');
      return;
    }
    final key = widget.place?.key ??
        (_type == 'bank' ? askodoxBankKey(tail) : 'place:${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}');
    if (widget.place == null && widget.others.any((p) => p.key == key)) {
      setState(() => _error = te ? 'ఈ ఖాతా ఇప్పటికే ఉంది.' : 'This account is already there.');
      return;
    }
    Navigator.pop(
        context,
        AskodoxMoneyPlace(
            key: key,
            type: _type,
            name: name,
            tail: _type == 'bank' ? tail : '',
            upi: _type == 'bank' || _type == 'wallet' ? '' : upi,
            apps: _apps.toList(),
            fromMethod: widget.place?.fromMethod ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final editing = widget.place != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(editing ? (te ? 'ఖాతా మార్చు' : 'Edit account') : (te ? 'ఖాతా జోడించు' : 'Add an account'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (!editing)
            Wrap(spacing: 8, children: [
              for (final t in askodoxMoneyPlaceTypes)
                ChoiceChip(
                  key: ValueKey('askodoxPlaceType-$t'),
                  label: Text(te ? askodoxMoneyPlaceTypeLabel(t).$2 : askodoxMoneyPlaceTypeLabel(t).$1),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ]),
          const SizedBox(height: 10),
          if (_type == 'bank')
            TextField(
              key: const Key('askodoxPlaceTail'),
              controller: _tail,
              enabled: !editing,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: te ? 'ఖాతా చివరి 4 అంకెలు' : 'Last 4 digits of the account',
                  helperText: te ? 'బ్యాంక్ SMS లో "A/c XX6911" లా ఉంటుంది' : 'Bank SMS show it as "A/c XX6911"'),
            ),
          if (_type == 'upi' || _type == 'qr') ...[
            TextField(
              key: const Key('askodoxPlaceUpi'),
              controller: _upi,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'UPI ID' : 'UPI ID', hintText: 'name@ybl'),
            ),
            Row(children: [
              TextButton.icon(
                  key: const Key('askodoxPlaceQrCamera'),
                  onPressed: () => _scan('camera'),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(te ? 'QR ఫోటో తీయి' : 'Photo of the QR')),
              TextButton.icon(
                  key: const Key('askodoxPlaceQrGallery'),
                  onPressed: () => _scan('photos'),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(te ? 'గ్యాలరీ నుంచి' : 'From gallery')),
            ]),
          ],
          const SizedBox(height: 8),
          TextField(
            key: const Key('askodoxPlaceName'),
            controller: _name,
            maxLength: 40,
            decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: te ? 'పేరు' : 'Name',
                hintText: switch (_type) {
                  'bank' => te ? 'HDFC కరెంట్' : 'HDFC current',
                  'wallet' => te ? 'Paytm వాలెట్' : 'Paytm wallet',
                  _ => te ? 'షాప్ QR' : 'Shop QR',
                }),
          ),
          Text(te ? 'ఏ యాప్ పేమెంట్లు ఈ ఖాతావి? (ఆప్షనల్)' : 'Which apps\' payments belong to this account? (optional)',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 6, children: [
            for (final e in widget.apps.entries)
              FilterChip(
                key: ValueKey('askodoxPlaceApp-${e.key}'),
                label: Text(e.value),
                selected: _apps.contains(e.key),
                onSelected: (v) => setState(() => _apps = v ? {..._apps, e.key} : ({..._apps}..remove(e.key))),
              ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
            ),
          const SizedBox(height: 12),
          FilledButton(key: const Key('askodoxPlaceSave'), onPressed: _save, child: Text(te ? 'సేవ్' : 'Save')),
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
