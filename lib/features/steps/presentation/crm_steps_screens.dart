import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_crm_screens.dart'
    show askodoxCrmOpenStages, askodoxCrmPickWhen, askodoxCrmSourceLabel, askodoxCrmStageLabel, askodoxCrmWhen;
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 10): one enquiry / lead `/pos/:id/crm/lead/:lid`. Top = what it is worth, middle =
/// what happened (follow-ups, then the timeline), bottom = ONE big button (move to the next stage). Notes, follow-up,
/// quotation, assign, lost, customer and the old page are in the header menu. Money is only recorded.
class AskodoxCrmLeadStepsScreen extends ConsumerStatefulWidget {
  const AskodoxCrmLeadStepsScreen({super.key, required this.businessId, required this.leadId});
  final String businessId;
  final String leadId;

  @override
  ConsumerState<AskodoxCrmLeadStepsScreen> createState() => _LeadState();
}

class _LeadState extends ConsumerState<AskodoxCrmLeadStepsScreen> {
  AskodoxJson? _lead;
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
      final l = await _repo.crmLead(widget.businessId, widget.leadId);
      if (mounted) {
        setState(() {
          _lead = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _lead == null) setState(() => _error = e);
    }
  }

  Future<void> _patch(AskodoxJson body) async {
    try {
      await _repo.crmUpdateLead(widget.businessId, widget.leadId, body);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    }
  }

  Future<String?> _ask(String title, String label) async {
    final te = _te;
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            key: const Key('askodoxCrmStepsAsk'),
            controller: text,
            autofocus: true,
            maxLength: 240,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(key: const Key('askodoxCrmStepsAskYes'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    return ok == true ? text.text.trim() : null;
  }

  Future<String?> _pickInvoice(AskodoxJson lead) async {
    final te = _te;
    final customerId = '${lead['customer_id'] ?? ''}';
    if (customerId.isEmpty) return '';
    List<AskodoxJson> bills;
    try {
      final history = await _repo.crmCustomerHistory(widget.businessId, customerId);
      bills = [for (final b in askodoxPosList(history['invoices'])) if (b['doc_kind'] == 'invoice' && b['status'] == 'issued') b];
    } on AskodoxPosException {
      return '';
    }
    if (bills.isEmpty || !mounted) return '';
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(te ? 'ఏ బిల్లుతో ఫైనల్ అయింది?' : 'Which bill closed it?', style: const TextStyle(fontWeight: FontWeight.w800))),
          ListTile(key: const Key('askodoxCrmStepsNoBill'), title: Text(te ? 'బిల్లు లేకుండా' : 'Without a bill'), onTap: () => Navigator.pop(ctx, '')),
          for (final b in bills.take(15))
            ListTile(
              title: Text('${b['number']} · ${askodoxPaise(askodoxPosInt(b['total_paise']))}'),
              subtitle: Text('${b['local_date']}'),
              onTap: () => Navigator.pop(ctx, '${b['id']}'),
            ),
        ]),
      ),
    );
  }

  Future<void> _stage(AskodoxJson lead, String stage) async {
    final te = _te;
    final body = <String, Object?>{'stage': stage, 'version': lead['version']};
    if (stage == 'lost') {
      final reason = await _ask(te ? 'ఎందుకు పోయింది?' : 'Why was it lost?', te ? 'కారణం' : 'Reason');
      if (reason == null || reason.isEmpty) return;
      body['lost_reason'] = reason;
    }
    if (stage == 'won' && mounted) {
      final invoice = await _pickInvoice(lead);
      if (invoice == null) return;
      if (invoice.isNotEmpty) body['won_invoice_id'] = invoice;
    }
    await _patch(body);
  }

  Future<void> _note(String kind) async {
    final te = _te;
    final text = await _ask(kind == 'call' ? (te ? 'కాల్‌లో ఏం మాట్లాడారు?' : 'What was said on the call?') : (te ? 'నోట్ రాయండి' : 'Write a note'), te ? 'నోట్' : 'Note');
    if (text == null || text.isEmpty || !mounted) return;
    try {
      await _repo.crmActivity(widget.businessId, {'lead_id': widget.leadId, 'kind': kind, 'text': text});
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _followup() async {
    final te = _te;
    final when = await askodoxCrmPickWhen(context);
    if (when == null || !mounted) return;
    final note = await _ask(te ? 'ఫాలో-అప్‌లో ఏం చేయాలి?' : 'What to do on the follow-up?', te ? 'నోట్' : 'Note');
    if (note == null || note.isEmpty || !mounted) return;
    try {
      await _repo.crmAddFollowup(widget.businessId, {'lead_id': widget.leadId, 'due_at': when, 'note': note});
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _toCustomer() async {
    final te = _te;
    try {
      await _repo.crmLeadToCustomer(widget.businessId, widget.leadId, {});
      if (mounted) askodoxPosSnack(context, te ? 'కస్టమర్ల లిస్ట్‌లో సేవ్ అయింది.' : 'Saved to your customers.');
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _assign() async {
    final te = _te;
    List<AskodoxJson> staff;
    try {
      staff = await _repo.crmStaff(widget.businessId);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (!mounted) return;
    final who = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final s in staff)
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(s['me'] == true ? (te ? 'నేను' : 'Me') : '…${s['last4']}'),
              subtitle: Text('${s['role']}'),
              onTap: () => Navigator.pop(ctx, '${s['ref']}'),
            ),
        ]),
      ),
    );
    if (who != null) await _patch({'assigned_to': who});
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final lead = _lead;
    if (lead == null) {
      return AskodoxStepScaffold(
          key: const Key('askodoxCrmLeadSteps'),
          title: te ? 'ఎంక్వైరీ' : 'Enquiry',
          body: _error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final stage = '${lead['stage']}';
    final closed = stage == 'won' || stage == 'lost';
    final customerId = '${lead['customer_id'] ?? ''}';
    final assigned = askodoxPosMap(lead['assigned_to']);
    final idx = askodoxCrmOpenStages.indexOf(stage);
    final next = closed ? null : (idx < 0 || idx >= askodoxCrmOpenStages.length - 1 ? 'won' : askodoxCrmOpenStages[idx + 1]);
    final sub = [
      askodoxCrmSourceLabel('${lead['source']}', te),
      if ('${lead['phone'] ?? ''}'.isNotEmpty) '${lead['phone']}',
      if (assigned.isNotEmpty) '${te ? 'బాధ్యత' : 'Owner'}: ${assigned['me'] == true ? (te ? 'నేను' : 'me') : '…${assigned['last4']}'}',
    ].join(' · ');
    final followups = askodoxPosList(lead['followups']);
    final timeline = askodoxPosList(lead['timeline']);
    return AskodoxStepScaffold(
      key: const Key('askodoxCrmLeadSteps'),
      title: '${lead['name']}',
      sub: sub,
      more: [
        if (!closed) AskodoxStepMore('askodoxCrmStepsLost', te ? 'పోయింది (Lost)' : 'Lost', Icons.cancel_outlined, () => _stage(lead, 'lost')),
        AskodoxStepMore('askodoxCrmStepsCall', te ? 'కాల్ నోట్' : 'Call note', Icons.call_outlined, () => _note('call')),
        AskodoxStepMore('askodoxCrmStepsNote', te ? 'నోట్' : 'Note', Icons.edit_note, () => _note('note')),
        AskodoxStepMore('askodoxCrmStepsFollowup', te ? 'ఫాలో-అప్' : 'Follow-up', Icons.alarm_add, _followup),
        AskodoxStepMore('askodoxCrmStepsQuote', te ? 'కొటేషన్ తయారు చేయండి' : 'Make quotation', Icons.request_quote_outlined,
            () => context.push('/pos/${widget.businessId}/sale?lead=${widget.leadId}${customerId.isEmpty ? '' : '&customer=$customerId'}')),
        AskodoxStepMore('askodoxCrmStepsAssign', te ? 'ఎవరికి ఇవ్వాలి' : 'Assign', Icons.assignment_ind_outlined, _assign),
        if (customerId.isEmpty)
          AskodoxStepMore('askodoxCrmStepsToCustomer', te ? 'కస్టమర్‌గా సేవ్' : 'Save as customer', Icons.person_add_alt, _toCustomer)
        else
          AskodoxStepMore('askodoxCrmStepsHistory', te ? 'కస్టమర్ హిస్టరీ' : 'Customer history', Icons.history,
              () => context.push('/pos/${widget.businessId}/crm/customer/$customerId')),
        AskodoxStepMore('askodoxCrmStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/crm/lead/${widget.leadId}?full=1')),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          AskodoxStepBigNumber(askodoxPaise(askodoxPosInt(lead['value_paise'])), label: te ? 'అంచనా విలువ' : 'Estimated value', size: 40),
          const SizedBox(height: 6),
          Center(
              child: AskodoxStepPill('${te ? 'స్టేజ్' : 'Stage'}: ${askodoxCrmStageLabel(stage, te)}', kind: stage == 'lost' ? 'warn' : 'good')),
          if ('${lead['need'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${lead['need']}', textAlign: TextAlign.center)),
          if (stage == 'lost') Padding(padding: const EdgeInsets.only(top: 6), child: Text('${te ? 'కారణం' : 'Reason'}: ${lead['lost_reason']}', textAlign: TextAlign.center)),
          const SizedBox(height: 12),
          for (final f in followups)
            AskodoxStepPersonRow(
              key: Key('askodoxCrmStepsFollowup-${f['id']}'),
              name: '${f['note']}',
              sub: askodoxCrmWhen(f['due_at']),
              amount: f['status'] == 'open' ? (te ? 'ఫాలో-అప్' : 'Follow-up') : '✓',
              amountColor: f['status'] == 'open' ? askodoxStepWarn : askodoxStepDone,
            ),
          for (final t in timeline)
            AskodoxStepPersonRow(name: '${t['text']}', sub: askodoxCrmWhen(t['at']), amount: '${t['kind']}', amountColor: askodoxStepMuted),
        ]),
      ),
      bottom: next == null
          ? AskodoxStepBottom(
              buttonKey: const Key('askodoxCrmStepsNoteBtn'),
              label: te ? 'నోట్ రాయి' : 'Write a note',
              icon: Icons.edit_note,
              onPressed: () => _note('note'))
          : AskodoxStepBottom(
              buttonKey: const Key('askodoxCrmStepsNext'),
              label: next == 'won' ? (te ? 'దొరికింది (Won) ✓' : 'Won ✓') : '${te ? 'తర్వాత' : 'Next'}: ${askodoxCrmStageLabel(next, te)}',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => _stage(lead, next)),
    );
  }
}
