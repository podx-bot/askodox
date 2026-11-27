import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-28 ("కట్టండి" on the agent team design): the three pages around the team map `/pos/:id/agents`.
/// OK inbox `/pos/:id/agents/inbox` (what waits, yes / no, a push opens it), History `/pos/:id/agents/log` (read only),
/// Team settings `/pos/:id/agents/settings` (owner only: which agents are on, who may say yes).
/// Agents never move money, message customers or delete -- these pages only show and decide what the existing
/// `pos_agents` rules already propose; nothing here adds a power.

String _agentName(AskodoxJson settings, String id, bool te) {
  for (final a in askodoxPosList(settings['all_agents'])) {
    if (a['id'] == id) return '${te ? a['name_te'] : a['name_en']}';
  }
  return id;
}

String _statusWord(String status, bool te) => switch (status) {
      'DONE' => te ? 'జరిగింది' : 'Done',
      'PENDING_APPROVAL' => te ? 'OK కోసం ఆగింది' : 'Waiting for OK',
      'REJECTED' => te ? 'ఆగింది' : 'Stopped',
      'FAILED' => te ? 'కాలేదు' : 'Failed',
      _ => te ? 'జరుగుతోంది' : 'Running',
    };

String _statusKind(String status) => switch (status) {
      'DONE' => 'good',
      'PENDING_APPROVAL' => 'warn',
      'FAILED' => 'bad',
      _ => 'grey',
    };

String _day(Object? iso) {
  final text = '$iso';
  if (text.length < 16) return '';
  return '${text.substring(8, 10)}/${text.substring(5, 7)} ${text.substring(11, 16)}';
}

class AskodoxAgentInboxScreen extends ConsumerStatefulWidget {
  const AskodoxAgentInboxScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxAgentInboxScreen> createState() => _InboxState();
}

class _InboxState extends ConsumerState<AskodoxAgentInboxScreen> {
  AskodoxJson? _team;
  List<AskodoxJson> _pending = const [];
  List<AskodoxJson> _earlier = const [];
  Object? _error;
  String _busyId = '';

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final team = await _repo.agentTeam(widget.businessId);
      final all = await _repo.agentActions(widget.businessId);
      if (!mounted) return;
      setState(() {
        _team = team;
        _pending = [for (final a in all) if (a['status'] == 'PENDING_APPROVAL') a];
        _earlier = [for (final a in all) if (a['status'] != 'PENDING_APPROVAL' && a['risk'] == 'sensitive') a].take(5).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted && _team == null) setState(() => _error = e);
    }
  }

  Future<void> _decide(AskodoxJson action, bool approve) async {
    final te = _te;
    setState(() => _busyId = '${action['id']}');
    try {
      final out = await _repo.agentDecide(widget.businessId, '${action['id']}', approve);
      if (!mounted) return;
      askodoxPosSnack(
          context,
          out['status'] == 'DONE'
              ? (te ? 'సరే చెప్పారు. పని అయింది.' : 'Approved. Done.')
              : out['status'] == 'FAILED'
                  ? '${te ? 'కాలేదు' : 'Failed'}: ${out['error'] ?? ''}'
                  : (te ? 'వద్దు అన్నారు. ఆపేశాం.' : 'Stopped.'));
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'మీ OK కోసం' : 'Waiting for your OK';
    if (_error != null) return AskodoxStepScaffold(title: title, body: AskodoxPosError(error: _error!, onRetry: _load));
    final team = _team;
    if (team == null) return AskodoxStepScaffold(title: title, body: const Center(child: CircularProgressIndicator()));
    final settings = askodoxPosMap(team['settings']);
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull ?? const <String, Object?>{};
    final role = '${business['my_role']}';
    final canDecide = role == 'owner' || (role == 'manager' && settings['approvers'] != 'owner');
    return AskodoxStepScaffold(
      key: const Key('askodoxAgentInbox'),
      title: title,
      sub: te ? 'సరే అనేవరకు ఏమీ మారదు.' : 'Nothing changes until you say yes.',
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          if (_pending.isEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(te ? 'ఏదీ ఆగలేదు ✓' : 'Nothing is waiting ✓',
                    key: const Key('askodoxAgentInboxEmpty'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: askodoxStepDone))),
          for (final a in _pending)
            Container(
              key: ValueKey('askodoxAgentInboxItem-${a['id']}'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: askodoxStepGreenSoft, borderRadius: BorderRadius.circular(16), border: Border.all(color: askodoxStepWarn, width: 2)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_agentName(settings, '${a['agent']}', te)} · ${_day(a['proposed_at'])}', style: const TextStyle(fontSize: 12, color: askodoxStepWarn, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${a['summary']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: askodoxStepInk)),
                if (canDecide) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: FilledButton(
                            key: ValueKey('askodoxAgentInboxApprove-${a['id']}'),
                            style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen, foregroundColor: askodoxStepGreenSoft, minimumSize: const Size.fromHeight(48)),
                            onPressed: _busyId.isEmpty ? () => _decide(a, true) : null,
                            child: Text(te ? 'సరే' : 'Yes'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: OutlinedButton(
                            key: ValueKey('askodoxAgentInboxReject-${a['id']}'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            onPressed: _busyId.isEmpty ? () => _decide(a, false) : null,
                            child: Text(te ? 'వద్దు' : 'No'))),
                  ]),
                ] else
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(te ? 'ఇది యజమాని చెప్పాలి.' : 'Only the owner says yes to this.',
                          key: const Key('askodoxAgentInboxOwnerOnly'), style: const TextStyle(fontSize: 13, color: askodoxStepMuted))),
              ]),
            ),
          if (_earlier.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(te ? 'ఇంతకు ముందు' : 'Earlier', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: askodoxStepMuted)),
            for (final a in _earlier)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(child: Text('${a['summary']}', style: const TextStyle(fontSize: 14, color: askodoxStepInk))),
                  const SizedBox(width: 8),
                  AskodoxStepPill(_statusWord('${a['status']}', te), kind: _statusKind('${a['status']}')),
                ]),
              ),
          ],
          const SizedBox(height: 12),
          Text(
              te
                  ? 'ఎవరు OK చెప్పొచ్చు: ${settings['approvers'] == 'owner' ? 'యజమాని మాత్రమే' : 'యజమాని, మేనేజర్'}. OK చెప్పినవారి పేరు మీదే పని జరుగుతుంది.'
                  : 'Who may say yes: ${settings['approvers'] == 'owner' ? 'the owner only' : 'the owner and managers'}. It runs under the name of whoever said yes.',
              key: const Key('askodoxAgentInboxRule'),
              style: const TextStyle(fontSize: 13, color: askodoxStepMuted)),
        ]),
      ),
    );
  }
}

class AskodoxAgentLogScreen extends ConsumerStatefulWidget {
  const AskodoxAgentLogScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxAgentLogScreen> createState() => _LogState();
}

class _LogState extends ConsumerState<AskodoxAgentLogScreen> {
  AskodoxJson _settings = const {};
  List<AskodoxJson>? _rows;
  Object? _error;
  String _filter = 'all';

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final settings = await _repo.agentSettings(widget.businessId);
      final rows = await _repo.agentActions(widget.businessId);
      if (mounted) {
        setState(() {
          _settings = settings;
          _rows = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _rows == null) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'చరిత్ర' : 'History';
    if (_error != null) return AskodoxStepScaffold(title: title, body: AskodoxPosError(error: _error!, onRetry: _load));
    final all = _rows;
    if (all == null) return AskodoxStepScaffold(title: title, body: const Center(child: CircularProgressIndicator()));
    final rows = switch (_filter) {
      'ask' => [for (final a in all) if (a['risk'] == 'sensitive') a],
      'stopped' => [for (final a in all) if (a['status'] == 'REJECTED' || a['status'] == 'FAILED') a],
      _ => all,
    };
    return AskodoxStepScaffold(
      key: const Key('askodoxAgentLog'),
      title: title,
      sub: te ? 'ఏజెంట్లు ఏం చేశాయి, ఎవరు OK చెప్పారు. చూడటానికి మాత్రమే.' : 'What the agents did and who said yes. Read only.',
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: AskodoxStepToggle(
                options: [('all', te ? 'అన్నీ' : 'All'), ('ask', te ? 'OK అడిగినవి' : 'Asked OK'), ('stopped', te ? 'ఆగినవి' : 'Stopped')],
                value: _filter,
                onChanged: (v) => setState(() => _filter = v))),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
              if (rows.isEmpty)
                Padding(padding: const EdgeInsets.all(24), child: Text(te ? 'ఇంకా ఏమీ లేదు.' : 'Nothing yet.', key: const Key('askodoxAgentLogEmpty'), textAlign: TextAlign.center)),
              for (final a in rows)
                Padding(
                  key: ValueKey('askodoxAgentLogRow-${a['id']}'),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${a['summary']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: askodoxStepInk)),
                      Text(
                          '${_day(a['proposed_at'])} · ${_agentName(_settings, '${a['agent']}', te)}'
                          '${a['mine'] == true ? (te ? ' · మీరు' : ' · you') : ''}',
                          style: const TextStyle(fontSize: 12, color: askodoxStepMuted)),
                    ])),
                    const SizedBox(width: 8),
                    AskodoxStepPill(_statusWord('${a['status']}', te), kind: _statusKind('${a['status']}')),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class AskodoxAgentSettingsScreen extends ConsumerStatefulWidget {
  const AskodoxAgentSettingsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxAgentSettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<AskodoxAgentSettingsScreen> {
  AskodoxJson? _settings;
  Object? _error;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final settings = await _repo.agentSettings(widget.businessId);
      if (mounted) {
        setState(() {
          _settings = settings;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _settings == null) setState(() => _error = e);
    }
  }

  Future<void> _save({List<String>? agentsOff, String? approvers}) async {
    final te = _te;
    try {
      final out = await _repo.setAgentSettings(widget.businessId, agentsOff: agentsOff, approvers: approvers);
      if (!mounted) return;
      setState(() => _settings = out);
      askodoxPosSnack(context, te ? 'సేవ్ అయింది.' : 'Saved.');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'టీమ్ సెట్టింగ్స్' : 'Team settings';
    if (_error != null) return AskodoxStepScaffold(title: title, body: AskodoxPosError(error: _error!, onRetry: _load));
    final settings = _settings;
    if (settings == null) return AskodoxStepScaffold(title: title, body: const Center(child: CircularProgressIndicator()));
    final owner = settings['is_owner'] == true;
    final off = <String>{for (final a in (settings['agents_off'] as List? ?? const [])) '$a'};
    return AskodoxStepScaffold(
      key: const Key('askodoxAgentSettings'),
      title: title,
      sub: owner ? (te ? 'యజమాని మాత్రమే మార్చగలరు.' : 'Only the owner can change these.') : (te ? 'చూడటానికి మాత్రమే. యజమాని మార్చగలరు.' : 'Read only. The owner can change these.'),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        for (final a in askodoxPosList(settings['all_agents']))
          SwitchListTile(
            key: ValueKey('askodoxAgentSettingsSwitch-${a['id']}'),
            contentPadding: EdgeInsets.zero,
            title: Text('${te ? a['name_te'] : a['name_en']}', style: const TextStyle(color: askodoxStepInk, fontWeight: FontWeight.w700)),
            value: !off.contains('${a['id']}'),
            onChanged: owner
                ? (on) {
                    final next = {...off};
                    if (on) {
                      next.remove('${a['id']}');
                    } else {
                      next.add('${a['id']}');
                    }
                    unawaited(_save(agentsOff: next.toList()));
                  }
                : null,
          ),
        const SizedBox(height: 14),
        Text(te ? 'ఎవరు OK చెప్పొచ్చు' : 'Who may say yes', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: askodoxStepInk)),
        const SizedBox(height: 8),
        AskodoxStepToggle(
            options: [('owner', te ? 'యజమాని మాత్రమే' : 'Owner only'), ('owner_manager', te ? 'యజమాని + మేనేజర్' : 'Owner + manager')],
            value: '${settings['approvers']}',
            onChanged: (v) {
              if (owner && v != '${settings['approvers']}') unawaited(_save(approvers: v));
            }),
        const SizedBox(height: 14),
        Text(
            te
                ? 'OK కావాల్సినప్పుడు మాత్రమే పుష్ వస్తుంది. ఏజెంట్ మాటలు AI Credits వాడొచ్చు; షాప్ లెక్కలు, బిల్లులు ఎప్పటిలాగే ఉచితం.'
                : 'You get a push only when an OK is needed. Agent wording may use AI Credits; shop accounts and bills stay free.',
            style: const TextStyle(fontSize: 13, color: askodoxStepMuted)),
      ]),
    );
  }
}
