import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_crm_screens.dart'
    show askodoxCrmAddComplaintDialog, askodoxCrmAddLeadDialog, askodoxCrmComplaintLabel, askodoxCrmPickWhen, askodoxCrmStageLabel, askodoxCrmWhen;
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 11): one complaint `/pos/:id/crm/complaint/:cid` and one customer's history
/// `/pos/:id/crm/customer/:cid`. Old pages stay at `?full=1`. Money is only recorded.
class AskodoxCrmComplaintStepsScreen extends ConsumerStatefulWidget {
  const AskodoxCrmComplaintStepsScreen({super.key, required this.businessId, required this.complaintId});
  final String businessId;
  final String complaintId;

  @override
  ConsumerState<AskodoxCrmComplaintStepsScreen> createState() => _ComplaintState();
}

class _ComplaintState extends ConsumerState<AskodoxCrmComplaintStepsScreen> {
  AskodoxJson? _item;
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
      final c = await _repo.crmComplaint(widget.businessId, widget.complaintId);
      if (mounted) {
        setState(() {
          _item = c;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _item == null) setState(() => _error = e);
    }
  }

  Future<void> _setStatus(String status) async {
    final te = _te;
    final body = <String, Object?>{'status': status};
    if (status == 'resolved' || status == 'closed') {
      final text = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(te ? 'ఎలా పరిష్కరించారు?' : 'How was it solved?'),
          content: TextField(
              key: const Key('askodoxComplaintStepsResolution'),
              controller: text,
              autofocus: true,
              maxLength: 500,
              decoration: InputDecoration(labelText: te ? 'పరిష్కారం' : 'Resolution', border: const OutlineInputBorder())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(key: const Key('askodoxComplaintStepsResolutionYes'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      );
      if (ok != true) return;
      body['resolution'] = text.text.trim();
    }
    try {
      await _repo.crmUpdateComplaint(widget.businessId, widget.complaintId, body);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _reminder() async {
    final te = _te;
    final when = await askodoxCrmPickWhen(context);
    if (when == null || !mounted) return;
    try {
      await _repo.crmAddFollowup(widget.businessId, {'complaint_id': widget.complaintId, 'due_at': when, 'note': 'Complaint follow-up'});
      await _load();
      if (mounted) askodoxPosSnack(context, te ? 'రిమైండర్ పెట్టాం.' : 'Reminder set.');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final c = _item;
    if (c == null) {
      return AskodoxStepScaffold(
          key: const Key('askodoxComplaintSteps'),
          title: te ? 'ఫిర్యాదు' : 'Complaint',
          body: _error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final status = '${c['status']}';
    final customerId = '${c['customer_id'] ?? ''}';
    final next = switch (status) {
      'open' => 'in_progress',
      'in_progress' => 'resolved',
      'resolved' => 'closed',
      _ => null,
    };
    return AskodoxStepScaffold(
      key: const Key('askodoxComplaintSteps'),
      title: te ? 'ఫిర్యాదు' : 'Complaint',
      sub: '${c['name']} · ${c['priority']}',
      more: [
        AskodoxStepMore('askodoxComplaintStepsReminder', te ? 'రిమైండర్' : 'Reminder', Icons.alarm_add, _reminder),
        if (customerId.isNotEmpty)
          AskodoxStepMore('askodoxComplaintStepsHistory', te ? 'కస్టమర్ హిస్టరీ' : 'Customer history', Icons.history,
              () => context.push('/pos/${widget.businessId}/crm/customer/$customerId')),
        if (c['invoice_id'] != null)
          AskodoxStepMore('askodoxComplaintStepsBill', te ? 'బిల్లు చూడండి' : 'Open bill', Icons.receipt_long_outlined,
              () => context.push('/pos/${widget.businessId}/invoice/${c['invoice_id']}')),
        AskodoxStepMore('askodoxComplaintStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/crm/complaint/${widget.complaintId}?full=1')),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          Center(child: Text('${c['subject']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900))),
          const SizedBox(height: 8),
          Center(child: AskodoxStepPill(askodoxCrmComplaintLabel(status, te), kind: status == 'resolved' || status == 'closed' ? 'good' : 'warn')),
          if ('${c['detail'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${c['detail']}')),
          if ('${c['resolution'] ?? ''}'.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('${te ? 'పరిష్కారం' : 'Resolution'}: ${c['resolution']}', style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(height: 12),
          for (final t in askodoxPosList(c['timeline']))
            AskodoxStepPersonRow(name: '${t['text']}', sub: askodoxCrmWhen(t['at']), amount: '', amountColor: askodoxStepMuted, onTap: () {}),
        ]),
      ),
      bottom: next == null
          ? AskodoxStepBottom(buttonKey: const Key('askodoxComplaintStepsRemind'), label: te ? 'రిమైండర్' : 'Reminder', icon: Icons.alarm_add, onPressed: _reminder)
          : AskodoxStepBottom(
              buttonKey: const Key('askodoxComplaintStepsNext'),
              label: '${te ? 'తర్వాత' : 'Next'}: ${askodoxCrmComplaintLabel(next, te)}',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => _setStatus(next)),
    );
  }
}

class AskodoxCrmCustomerStepsScreen extends ConsumerStatefulWidget {
  const AskodoxCrmCustomerStepsScreen({super.key, required this.businessId, required this.customerId});
  final String businessId;
  final String customerId;

  @override
  ConsumerState<AskodoxCrmCustomerStepsScreen> createState() => _CustomerState();
}

class _CustomerState extends ConsumerState<AskodoxCrmCustomerStepsScreen> {
  AskodoxJson? _data;
  Object? _error;

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).crmCustomerHistory(widget.businessId, widget.customerId);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _data == null) setState(() => _error = e);
    }
  }

  Widget _head(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, color: askodoxStepMuted)),
      );

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final d = _data;
    if (d == null) {
      return AskodoxStepScaffold(
          key: const Key('askodoxCrmCustomerSteps'),
          title: te ? 'కస్టమర్ హిస్టరీ' : 'Customer history',
          body: _error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final c = askodoxPosMap(d['customer']);
    final s = askodoxPosMap(d['summary']);
    final due = askodoxPosInt(s['due_paise']);
    return AskodoxStepScaffold(
      key: const Key('askodoxCrmCustomerSteps'),
      title: '${c['name']}',
      sub: '${c['phone'] ?? ''}',
      more: [
        AskodoxStepMore('askodoxCrmCustomerStepsLead', te ? 'కొత్త Lead' : 'New lead', Icons.trending_up, () async {
          final id = await askodoxCrmAddLeadDialog(context, ref, widget.businessId, customerId: widget.customerId, customerName: '${c['name']}');
          if (id != null && mounted) await _load();
        }),
        AskodoxStepMore('askodoxCrmCustomerStepsComplaint', te ? 'ఫిర్యాదు' : 'Complaint', Icons.report_problem_outlined, () async {
          final id = await askodoxCrmAddComplaintDialog(context, ref, widget.businessId, customerId: widget.customerId, customerName: '${c['name']}');
          if (id != null && mounted) await _load();
        }),
        AskodoxStepMore('askodoxCrmCustomerStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/crm/customer/${widget.customerId}?full=1')),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          AskodoxStepBigNumber(askodoxPaise(askodoxPosInt(s['billed_paise'])), label: te ? 'మొత్తం కొన్నది' : 'Bought in all', size: 40),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                te
                    ? 'బిల్లులు ${s['bills'] ?? 0} · బాకీ ${askodoxPaise(due)} · ఓపెన్ Leads ${s['open_leads'] ?? 0} · ఫిర్యాదులు ${s['open_complaints'] ?? 0}'
                    : 'Bills ${s['bills'] ?? 0} · Due ${askodoxPaise(due)} · Open leads ${s['open_leads'] ?? 0} · Complaints ${s['open_complaints'] ?? 0}',
                key: const Key('askodoxCrmCustomerStepsSplit'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: askodoxStepMuted, fontWeight: FontWeight.w700)),
          ),
          _head(te ? 'బిల్లులు' : 'Bills'),
          for (final b in askodoxPosList(d['invoices']).take(20))
            AskodoxStepPersonRow(
              key: Key('askodoxCrmCustomerStepsBill-${b['id']}'),
              name: '${b['number']}',
              sub: '${b['local_date']} · ${b['status']}',
              amount: askodoxPaise(askodoxPosInt(b['total_paise'])),
              onTap: () => context.push('/pos/${widget.businessId}/invoice/${b['id']}'),
            ),
          _head('Leads'),
          for (final l in askodoxPosList(d['leads']))
            AskodoxStepPersonRow(
              name: '${l['name']}',
              sub: askodoxCrmStageLabel('${l['stage']}', te),
              amount: askodoxPaise(askodoxPosInt(l['value_paise'])),
              onTap: () => context.push('/pos/${widget.businessId}/crm/lead/${l['id']}'),
            ),
          _head(te ? 'ఫిర్యాదులు' : 'Complaints'),
          for (final k in askodoxPosList(d['complaints']))
            AskodoxStepPersonRow(
              name: '${k['subject']}',
              sub: askodoxCrmComplaintLabel('${k['status']}', te),
              amount: '',
              onTap: () => context.push('/pos/${widget.businessId}/crm/complaint/${k['id']}'),
            ),
        ]),
      ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxCrmCustomerStepsAccount'),
        label: te ? 'ఖాతా / బాకీ' : 'Account / dues',
        icon: Icons.account_balance_wallet_outlined,
        onPressed: () => context.push('/pos/${widget.businessId}/customers/${widget.customerId}'),
      ),
    );
  }
}
