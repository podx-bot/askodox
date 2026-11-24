import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_agent_screens.dart' show askodoxAgentIcon;
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 24): the shop's AI agents `/pos/:id/agents` and one agent `/pos/:id/agents/:agent`.
/// List: top = how many proposals wait for approval, middle = ONE list of the agents my role may use, bottom = ONE big button
/// (review the approvals; owner / manager only). One agent: top = the question, middle = the answer + what it can do,
/// bottom = Ask (mic fills it). Answers come from the shop's own records; sensitive actions still wait for an owner /
/// manager. Old pages stay at `?full=1`.
class AskodoxAgentsStepsScreen extends ConsumerStatefulWidget {
  const AskodoxAgentsStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxAgentsStepsScreen> createState() => _AgentsStepsState();
}

class _AgentsStepsState extends ConsumerState<AskodoxAgentsStepsScreen> {
  List<AskodoxJson>? _agents;
  List<AskodoxJson> _pending = const [];
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
      final list = await _repo.agents(widget.businessId);
      final pending = await _repo.agentActions(widget.businessId, status: 'PENDING_APPROVAL');
      if (mounted) {
        setState(() {
          _agents = list;
          _pending = pending;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _agents == null) setState(() => _error = e);
    }
  }

  Future<void> _decide(AskodoxJson action, bool approve) async {
    final te = _te;
    try {
      final out = await _repo.agentDecide(widget.businessId, '${action['id']}', approve);
      if (!mounted) return;
      askodoxPosSnack(
          context,
          out['status'] == 'DONE'
              ? (te ? 'Approve చేశాం — పని అయింది.' : 'Approved and done.')
              : out['status'] == 'FAILED'
                  ? '${te ? 'కాలేదు' : 'Failed'}: ${out['error'] ?? ''}'
                  : (te ? 'Reject చేశాం.' : 'Rejected.'));
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _review() async {
    final te = _te;
    final action = await showModalBottomSheet<AskodoxJson>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(te ? 'Approval కోసం ఆగినవి' : 'Waiting for approval', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            for (final a in _pending) ...[
              const SizedBox(height: 10),
              Text('${a['summary']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${a['agent']} · ${a['mine'] == true ? (te ? 'మీరు propose చేశారు' : 'proposed by you') : '${a['proposed_by']}'}',
                  style: const TextStyle(color: askodoxStepMuted)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: FilledButton(
                        key: ValueKey('askodoxAgentsStepsApprove-${a['id']}'),
                        style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen, minimumSize: const Size.fromHeight(50)),
                        onPressed: () => Navigator.pop(ctx, {...a, '_ok': true}),
                        child: const Text('Approve'))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton(
                        key: ValueKey('askodoxAgentsStepsReject-${a['id']}'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: () => Navigator.pop(ctx, {...a, '_ok': false}),
                        child: const Text('Reject'))),
              ]),
            ],
          ]),
        ),
      ),
    );
    if (action == null || !mounted) return;
    await _decide(action, action['_ok'] == true);
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'AI Agents' : 'AI agents';
    final more = [
      AskodoxStepMore('askodoxAgentsStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded, () => context.push('/pos/${widget.businessId}/agents?full=1')),
    ];
    if (_error != null) return AskodoxStepScaffold(title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    final agents = _agents;
    if (agents == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull ?? const <String, Object?>{};
    final approver = business['my_role'] == 'owner' || business['my_role'] == 'manager';
    return AskodoxStepScaffold(
      key: const Key('askodoxAgentsSteps'),
      title: title,
      more: more,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          AskodoxStepBigNumber('${_pending.length}',
              label: _pending.isEmpty ? (te ? 'Approval కోసం ఏదీ ఆగలేదు ✓' : 'Nothing waiting for approval ✓') : (te ? 'Approval కోసం ఆగినవి' : 'Waiting for approval'),
              color: _pending.isEmpty ? askodoxStepDone : askodoxStepWarn,
              size: 44),
          const SizedBox(height: 10),
          if (agents.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(te ? 'మీ role కి agents లేవు.' : 'No agents for your role.', textAlign: TextAlign.center)),
          for (final a in agents)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxAgentsStepsAgent-${a['id']}'),
              name: '${te ? a['name_te'] : a['name_en']}',
              sub: '${te ? a['about_te'] : a['about_en']}',
              amount: '›',
              amountColor: askodoxStepMuted,
              onTap: () async {
                await context.push('/pos/${widget.businessId}/agents/${a['id']}');
                if (mounted) await _load();
              },
            ),
        ]),
      ),
      bottom: _pending.isEmpty || !approver
          ? null
          : AskodoxStepBottom(
              buttonKey: const Key('askodoxAgentsStepsReview'),
              label: te ? 'Approvals చూడు (${_pending.length})' : 'Review approvals (${_pending.length})',
              icon: Icons.check_circle_outline,
              onPressed: _review,
            ),
    );
  }
}

class AskodoxAgentStepsScreen extends ConsumerStatefulWidget {
  const AskodoxAgentStepsScreen({super.key, required this.businessId, required this.agent});
  final String businessId;
  final String agent;

  @override
  ConsumerState<AskodoxAgentStepsScreen> createState() => _AgentStepsState();
}

class _AgentStepsState extends ConsumerState<AskodoxAgentStepsScreen> {
  final _question = TextEditingController();
  final _note = TextEditingController();
  AskodoxJson? _answer;
  bool _busy = false;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void dispose() {
    _question.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    if (!mounted) return;
    final te = _te;
    setState(() => _busy = true);
    try {
      final out = await _repo.agentAsk(widget.businessId, widget.agent, _question.text.trim(), te ? 'te' : 'en');
      if (mounted) setState(() => _answer = out);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose(String action, AskodoxJson params) async {
    final te = _te;
    try {
      final out = await _repo.agentPropose(widget.businessId, widget.agent, action, params);
      if (!mounted) return;
      askodoxPosSnack(
          context,
          switch ('${out['status']}') {
            'DONE' => te ? 'అయింది.' : 'Done.',
            'PENDING_APPROVAL' => te ? 'Owner / manager approval కోసం పంపాం.' : 'Sent for owner / manager approval.',
            _ => '${te ? 'కాలేదు' : 'Failed'}: ${out['error'] ?? ''}',
          });
      await _ask();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _writeNote(AskodoxJson params) async {
    final te = _te;
    _note.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'Note రాయండి' : 'Write a note'),
        content: TextField(key: const Key('askodoxAgentStepsNote'), controller: _note, maxLength: 500, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'Save చేయండి' : 'Save')),
        ],
      ),
    );
    if (ok != true || _note.text.trim().isEmpty || !mounted) return;
    await _propose('complaint_note', {...params, 'text': _note.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final name = '${widget.agent[0].toUpperCase()}${widget.agent.substring(1)} agent';
    final answer = _answer;
    return AskodoxStepScaffold(
      key: const Key('askodoxAgentSteps'),
      title: name,
      question: te ? 'ఏం అడగాలి?' : 'What do you want to ask?',
      hint: te ? 'ఉదా: ఈరోజు ఎవరికి call చేయాలి?' : 'e.g. who should I call today?',
      more: [
        AskodoxStepMore('askodoxAgentStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/agents/${widget.agent}?full=1')),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        TextField(
          key: const Key('askodoxAgentStepsQuestion'),
          controller: _question,
          onSubmitted: (_) => _ask(),
          decoration: InputDecoration(border: const OutlineInputBorder(), hintText: te ? 'ఇక్కడ రాయండి లేదా మైక్ నొక్కండి' : 'Type here or tap the mic'),
        ),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        if (answer != null) ...[
          Container(
            key: const Key('askodoxAgentStepsAnswer'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: askodoxStepGreenSoft, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${answer['answer']}', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                  answer['answer_source'] == 'ai'
                      ? (te ? 'AI shop records ని మాటల్లో చెప్పింది.' : 'AI re-worded your shop records.')
                      : (te ? 'Shop records నుండి నేరుగా.' : 'Straight from your shop records.'),
                  style: const TextStyle(fontSize: 12, color: askodoxStepMuted)),
            ]),
          ),
          const SizedBox(height: 10),
          for (final (i, s) in askodoxPosList(answer['suggestions']).indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                key: ValueKey('askodoxAgentStepsSuggest-$i'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => s['action'] == 'complaint_note' ? _writeNote(askodoxPosMap(s['params'])) : _propose('${s['action']}', askodoxPosMap(s['params'])),
                icon: Icon(askodoxAgentIcon(widget.agent), size: 18),
                label: Text('${te ? s['label_te'] : s['label_en']}'),
              ),
            ),
        ],
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxAgentStepsAsk'),
        label: te ? 'అడుగు' : 'Ask',
        icon: Icons.send_rounded,
        busy: _busy,
        onPressed: _ask,
        onSpoken: (said) {
          _question.text = said;
          unawaited(_ask());
        },
      ),
    );
  }
}
