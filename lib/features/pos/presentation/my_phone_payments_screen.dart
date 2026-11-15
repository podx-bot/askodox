import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_payment_alerts.dart';
import '../data/pos_repository.dart';
import 'pos_common.dart';

/// "My phone" payments (owner 2026-11-15): any signed-in person -- no shop, no registered UPI id -- gets the payment
/// notifications and bank SMS of the apps THEY choose read out on their own phone and kept in their own history.
/// Everything is on this phone only; every list (apps, accounts, history) can be edited and deleted.
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
    await _configure();
    await _reload();
  }

  Future<void> _configure() async {
    final mine = _mine;
    if (mine == null) return;
    _status = await _bridge.configure(mine.nativeConfig());
  }

  Future<void> _reload() async {
    final status = await _bridge.status();
    final events = (await _bridge.localEvents()).where((e) => e['direction'] != null || e['test'] == true).toList();
    if (!mounted) return;
    setState(() {
      _status = status;
      _events = events.reversed.toList();
    });
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
            onPressed: () => _bridge.speakTest(100),
            icon: const Icon(Icons.volume_up_outlined),
            label: Text(te ? 'సౌండ్ టెస్ట్' : 'Sound test'),
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
              leading: const Icon(Icons.apps_rounded),
              title: Text(e.value),
              subtitle: Text(e.key, style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
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
                      await _change((x) => x.apps = {...x.apps}..remove(e.key));
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
                '${e['source_label'] ?? ''}',
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
