import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/pos_repository.dart';
import 'pos_common.dart';

/// Role-based AI agents of a shop (backend `pos_agents.py`). An agent is offered only when
/// the person's POS role has its permission; its answer comes from the shop's records (the
/// AI only re-words them); sensitive actions are PROPOSED and run only after an owner /
/// manager approves.

String askodoxAgentActionLabel(String action, bool te) => switch (action) {
      'crm_followup' => te ? 'Follow-up పెట్టండి' : 'Set a follow-up',
      'crm_stage' => te ? 'Lead stage మార్చండి' : 'Move a lead stage',
      'complaint_note' => te ? 'Complaint కి note' : 'Note on a complaint',
      'complaint_resolve' => te ? 'Complaint close (approval)' : 'Close a complaint (approval)',
      'record_payment' => te ? 'డబ్బు వచ్చింది అని record (approval)' : 'Record money received (approval)',
      'stock_adjust' => te ? 'Stock మార్పు (approval)' : 'Change stock (approval)',
      'set_member_role' => te ? 'Staff role మార్పు (owner approval)' : 'Change a staff role (owner approval)',
      _ => action,
    };

IconData askodoxAgentIcon(String id) => switch (id) {
      'owner' => Icons.workspace_premium_outlined,
      'sales' => Icons.trending_up,
      'support' => Icons.support_agent,
      'finance' => Icons.account_balance_wallet_outlined,
      'inventory' => Icons.inventory_2_outlined,
      'hr' => Icons.badge_outlined,
      'tax' => Icons.receipt_long_outlined,
      _ => Icons.smart_toy_outlined,
    };

/// `/pos/:id/agents`: the agents this role may use + what waits for approval.
class AskodoxPosAgentsScreen extends ConsumerStatefulWidget {
  const AskodoxPosAgentsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosAgentsScreen> createState() => _AskodoxPosAgentsScreenState();
}

class _AskodoxPosAgentsScreenState extends ConsumerState<AskodoxPosAgentsScreen> {
  late Future<(List<AskodoxJson>, List<AskodoxJson>)> _data = _load();

  Future<(List<AskodoxJson>, List<AskodoxJson>)> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    final list = await repo.agents(widget.businessId);
    final pending = await repo.agentActions(widget.businessId, status: 'PENDING_APPROVAL');
    return (list, pending);
  }

  void _refresh() => setState(() {
        _data = _load();
      });

  Future<void> _decide(AskodoxJson action, bool approve) async {
    final te = askodoxPosTe(context);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).agentDecide(widget.businessId, '${action['id']}', approve);
      if (!mounted) return;
      askodoxPosSnack(
          context,
          out['status'] == 'DONE'
              ? (te ? 'Approve చేశాం — పని అయింది.' : 'Approved and done.')
              : out['status'] == 'FAILED'
                  ? '${te ? 'కాలేదు' : 'Failed'}: ${out['error'] ?? ''}'
                  : (te ? 'Reject చేశాం.' : 'Rejected.'));
      _refresh();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull ?? const <String, Object?>{};
    final approver = business['my_role'] == 'owner' || business['my_role'] == 'manager';
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'AI Agents' : 'AI agents')),
      body: FutureBuilder<(List<AskodoxJson>, List<AskodoxJson>)>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _refresh);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (list, pending) = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
              Text(
                te
                    ? 'మీ role కి అనుమతి ఉన్న agents మాత్రమే. జవాబులు shop records నుండే; డబ్బు, stock, staff మార్పులు owner / manager approve చేశాకే జరుగుతాయి.'
                    : 'Only the agents your role allows. Answers come from your shop records; money, stock and staff changes happen only after an owner / manager approves.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(te ? 'Approval కోసం ఆగినవి' : 'Waiting for approval', style: Theme.of(context).textTheme.titleSmall),
                for (final a in pending)
                  Card(
                    key: ValueKey('askodoxAgentPending-${a['id']}'),
                    child: ListTile(
                      title: Text('${a['summary']}'),
                      subtitle: Text('${a['agent']} · ${a['mine'] == true ? (te ? 'మీరు propose చేశారు' : 'proposed by you') : '${a['proposed_by']}'}'),
                      trailing: approver
                          ? Wrap(children: [
                              IconButton(
                                  key: ValueKey('askodoxAgentApprove-${a['id']}'),
                                  tooltip: te ? 'Approve' : 'Approve',
                                  onPressed: () => _decide(a, true),
                                  icon: const Icon(Icons.check_circle_outline)),
                              IconButton(
                                  key: ValueKey('askodoxAgentReject-${a['id']}'),
                                  tooltip: te ? 'Reject' : 'Reject',
                                  onPressed: () => _decide(a, false),
                                  icon: const Icon(Icons.cancel_outlined)),
                            ])
                          : null,
                    ),
                  ),
              ],
              const SizedBox(height: 10),
              for (final a in list)
                Card(
                  child: ListTile(
                    key: ValueKey('askodoxAgent-${a['id']}'),
                    leading: Icon(askodoxAgentIcon('${a['id']}')),
                    title: Text('${te ? a['name_te'] : a['name_en']}'),
                    subtitle: Text('${te ? a['about_te'] : a['about_en']}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await context.push('/pos/${widget.businessId}/agents/${a['id']}');
                      if (mounted) _refresh();
                    },
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

/// `/pos/:id/agents/:agent`: ask the agent; see the facts it used; propose actions.
class AskodoxPosAgentScreen extends ConsumerStatefulWidget {
  const AskodoxPosAgentScreen({super.key, required this.businessId, required this.agent});
  final String businessId;
  final String agent;

  @override
  ConsumerState<AskodoxPosAgentScreen> createState() => _AskodoxPosAgentScreenState();
}

class _AskodoxPosAgentScreenState extends ConsumerState<AskodoxPosAgentScreen> {
  final _question = TextEditingController();
  AskodoxJson? _answer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    if (!mounted) return;
    final te = askodoxPosTe(context);
    setState(() => _busy = true);
    try {
      final out = await ref
          .read(askodoxPosRepositoryProvider)
          .agentAsk(widget.businessId, widget.agent, _question.text.trim(), te ? 'te' : 'en');
      if (mounted) setState(() => _answer = out);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose(String action, AskodoxJson params) async {
    final te = askodoxPosTe(context);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).agentPropose(widget.businessId, widget.agent, action, params);
      if (!mounted) return;
      final status = '${out['status']}';
      askodoxPosSnack(
          context,
          switch (status) {
            'DONE' => te ? 'అయింది.' : 'Done.',
            'PENDING_APPROVAL' => te ? 'Owner / manager approval కోసం పంపాం.' : 'Sent for owner / manager approval.',
            _ => '${te ? 'కాలేదు' : 'Failed'}: ${out['error'] ?? ''}',
          });
      _ask();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final answer = _answer;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.agent[0].toUpperCase()}${widget.agent.substring(1)} agent')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        TextField(
          key: const Key('askodoxAgentQuestion'),
          controller: _question,
          onSubmitted: (_) => _ask(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: te ? 'అడగండి: ఈరోజు ఎవరికి call చేయాలి?' : 'Ask: who should I call today?',
            suffixIcon: IconButton(key: const Key('askodoxAgentAsk'), onPressed: _busy ? null : _ask, icon: const Icon(Icons.send)),
          ),
        ),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        if (answer != null) ...[
          Card(
            key: const Key('askodoxAgentAnswer'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${answer['answer']}'),
                const SizedBox(height: 6),
                Text(
                  answer['answer_source'] == 'ai'
                      ? (te ? 'AI shop records ని మాటల్లో చెప్పింది.' : 'AI re-worded your shop records.')
                      : (te ? 'Shop records నుండి నేరుగా.' : 'Straight from your shop records.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
            ),
          ),
          if (answer['answer_source'] == 'ai') ...[
            Text(te ? 'వాడిన facts' : 'Facts used', style: Theme.of(context).textTheme.titleSmall),
            for (final line in (answer['facts_text'] as List? ?? const []))
              Padding(padding: const EdgeInsets.only(top: 2), child: Text('$line', style: Theme.of(context).textTheme.bodySmall)),
          ],
          const SizedBox(height: 10),
          for (final (i, s) in askodoxPosList(answer['suggestions']).indexed)
            OutlinedButton.icon(
              key: ValueKey('askodoxAgentSuggest-$i'),
              onPressed: s['action'] == 'complaint_note'
                  ? () => _note(askodoxPosMap(s['params']))
                  : () => _propose('${s['action']}', askodoxPosMap(s['params'])),
              icon: const Icon(Icons.bolt_outlined),
              label: Text('${te ? s['label_te'] : s['label_en']}'),
            ),
        ],
      ]),
    );
  }

  Future<void> _note(AskodoxJson params) async {
    final te = askodoxPosTe(context);
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'Note రాయండి' : 'Write a note'),
        content: AskodoxPosField(controller: text, label: 'Note', maxLength: 500),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'Save చేయండి' : 'Save')),
        ],
      ),
    );
    if (ok != true || text.text.trim().isEmpty || !mounted) return;
    await _propose('complaint_note', {...params, 'text': text.text.trim()});
  }
}

/// `/me/agent`: the personal buyer agent (only your own records; it never pays or approves for you).
class AskodoxBuyerAgentScreen extends ConsumerStatefulWidget {
  const AskodoxBuyerAgentScreen({super.key});

  @override
  ConsumerState<AskodoxBuyerAgentScreen> createState() => _AskodoxBuyerAgentScreenState();
}

class _AskodoxBuyerAgentScreenState extends ConsumerState<AskodoxBuyerAgentScreen> {
  Future<AskodoxJson>? _data;

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    _data ??= ref.read(askodoxPosRepositoryProvider).buyerAgentAsk('', te ? 'te' : 'en');
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'Buyer agent (నా సహాయకుడు)' : 'Buyer agent')),
      body: FutureBuilder<AskodoxJson>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${snap.data!['answer']}', key: const Key('askodoxBuyerAgentAnswer')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: () => context.push('/me/shop-advances'),
                icon: const Icon(Icons.savings_outlined),
                label: Text(te ? 'Shop advances చూడండి' : 'Open shop advances')),
          ]);
        },
      ),
    );
  }
}
