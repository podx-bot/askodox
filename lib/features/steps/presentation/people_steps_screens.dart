import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_crm_screens.dart' show askodoxCrmAddLeadDialog, askodoxCrmStageLabel;
import '../../pos/presentation/pos_records_screens.dart' show AskodoxCustomerSuggestions;
import '../domain/step_logic.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, work pages batch 2): Customer list `/pos/:id/customers`, Enquiries
/// `/pos/:id/crm`, Workers & team `/pos/:id/team`. One number on top, one list in the middle, ONE big button at the
/// bottom; the old pages stay at `?full=1` (header ⋮). Today's post and Add an item were already one subject -> one
/// picture / preview -> one button pages, so they are not rebuilt.

// ============================================================================ customers
class AskodoxCustomersStepsScreen extends ConsumerStatefulWidget {
  const AskodoxCustomersStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxCustomersStepsScreen> createState() => _CustomersStepsState();
}

class _CustomersStepsState extends ConsumerState<AskodoxCustomersStepsScreen> {
  int _step = 0; // 0 = the list, 1..3 = a new customer
  List<AskodoxJson>? _list;
  Object? _error;
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  String _made = '';

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await _repo.customers(widget.businessId);
      if (mounted) {
        setState(() {
          _list = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _list == null) setState(() => _error = e);
    }
  }

  void _start() => setState(() {
        _name.clear();
        _phone.clear();
        _made = '';
        _step = 1;
      });

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repo.addCustomer(widget.businessId, {
        'name': _name.text.trim(),
        'phone': askodoxTenDigits(_phone.text),
        'address': '',
        'credit_limit_paise': 0,
      });
      if (!mounted) return;
      setState(() {
        _made = _name.text.trim();
        _step = 3;
      });
      unawaited(_load());
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<AskodoxStepMore> _more() => [
        AskodoxStepMore('askodoxCustomersStepsFull', _te ? 'పాత కస్టమర్ల పేజీ (GSTIN, చిరునామా, బాకీ పరిమితి)' : 'Old customers page (GSTIN, address, credit limit)',
            Icons.menu_book_rounded, () => context.push('/pos/${widget.businessId}/customers?full=1')),
      ];

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'కస్టమర్ల లిస్ట్' : 'Customers';
    switch (_step) {
      case 1:
        return AskodoxStepScaffold(
          key: const Key('askodoxCustomersSteps1'),
          title: title,
          step: 1,
          question: te ? 'కస్టమర్ పేరు?' : 'Customer name?',
          onBack: () => setState(() => _step = 0),
          more: _more(),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
            TextField(
              key: const Key('askodoxCustomersStepsName'),
              controller: _name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxCustomersStepsNext1'),
            label: te ? 'తర్వాత' : 'Next',
            icon: Icons.arrow_forward_rounded,
            onPressed: _name.text.trim().isEmpty ? null : () => setState(() => _step = 2),
            onSpoken: (w) => setState(() => _name.text = w.trim()),
          ),
        );
      case 2:
        return AskodoxStepScaffold(
          key: const Key('askodoxCustomersSteps2'),
          title: title,
          step: 2,
          question: te ? 'ఫోన్ నంబర్?' : 'Phone number?',
          onBack: () => setState(() => _step = 1),
          more: _more(),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
            TextField(
              key: const Key('askodoxCustomersStepsPhone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: InputDecoration(hintText: te ? 'ఐచ్ఛికం' : 'Optional', border: const OutlineInputBorder()),
            ),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxCustomersStepsSave'),
            label: te ? 'సేవ్ చేయి' : 'Save',
            icon: Icons.check_rounded,
            busy: _busy,
            onPressed: _save,
          ),
        );
      case 3:
        return AskodoxStepScaffold(
          key: const Key('askodoxCustomersSteps3'),
          title: title,
          step: 3,
          more: _more(),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
            const Center(child: AskodoxStepDoneMark()),
            const SizedBox(height: 22),
            AskodoxStepBigNumber(_made, label: te ? 'కస్టమర్ చేరారు' : 'Customer added', size: 32),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxCustomersStepsAnother'),
            label: te ? 'ఇంకొకరు' : 'Another',
            icon: Icons.add_rounded,
            onPressed: _start,
          ),
        );
    }
    final all = _list;
    final q = _search.text.trim().toLowerCase();
    final shown = all == null ? const <AskodoxJson>[] : [for (final c in all) if (q.isEmpty || '${c['name']}'.toLowerCase().contains(q)) c];
    final owed = all?.fold<int>(0, (s, c) => s + (askodoxPosInt(c['balance_paise']) > 0 ? askodoxPosInt(c['balance_paise']) : 0)) ?? 0;
    return AskodoxStepScaffold(
      key: const Key('askodoxCustomersSteps0'),
      title: title,
      more: _more(),
      body: _error != null && all == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : all == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber(askodoxStepRupees(owed), label: te ? 'కస్టమర్ల నుంచి రావాల్సింది' : 'Customers owe you', size: 40),
                    const SizedBox(height: 10),
                    AskodoxCustomerSuggestions(businessId: widget.businessId, onSaved: _load),
                    AskodoxStepSearch(
                      fieldKey: const Key('askodoxCustomersStepsSearch'),
                      controller: _search,
                      hint: te ? 'పేరు వెతకండి' : 'Search a name',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 6),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'కస్టమర్లు లేరు. కింద "కొత్త కస్టమర్" నొక్కండి.' : 'No customers. Tap "New customer" below.',
                            key: const Key('askodoxCustomersStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final c in shown)
                      AskodoxStepPersonRow(
                        key: Key('askodoxCustomersStepsRow-${c['id']}'),
                        name: '${c['name']}',
                        sub: '${c['gstin'] ?? 'B2C'}',
                        amount: askodoxPosInt(c['balance_paise']) > 0 ? askodoxStepRupees(askodoxPosInt(c['balance_paise'])) : '✓',
                        amountColor: askodoxPosInt(c['balance_paise']) > 0 ? askodoxStepWarn : askodoxStepDone,
                        onTap: () async {
                          await context.push('/pos/${widget.businessId}/customers/${c['id']}');
                          if (mounted) await _load();
                        },
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxCustomersStepsNew'),
        label: te ? 'కొత్త కస్టమర్' : 'New customer',
        icon: Icons.person_add_alt_1_rounded,
        onPressed: _start,
      ),
    );
  }
}

// ============================================================================ enquiries
class AskodoxEnquiriesStepsScreen extends ConsumerStatefulWidget {
  const AskodoxEnquiriesStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxEnquiriesStepsScreen> createState() => _EnquiriesStepsState();
}

class _EnquiriesStepsState extends ConsumerState<AskodoxEnquiriesStepsScreen> {
  List<AskodoxJson>? _leads;
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
      final l = await _repo.crmLeads(widget.businessId);
      if (mounted) {
        setState(() {
          _leads = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _leads == null) setState(() => _error = e);
    }
  }

  Future<void> _add() async {
    final id = await askodoxCrmAddLeadDialog(context, ref, widget.businessId);
    if (id == null || !mounted) return;
    await _load();
    if (mounted) await context.push('/pos/${widget.businessId}/crm/lead/$id');
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final leads = _leads;
    final open = leads?.where((l) => !const ['won', 'lost', 'closed'].contains('${l['stage']}')).toList() ?? const <AskodoxJson>[];
    return AskodoxStepScaffold(
      key: const Key('askodoxEnquiriesSteps'),
      title: te ? 'ఎంక్వైరీలు' : 'Enquiries',
      more: [
        AskodoxStepMore('askodoxEnquiriesStepsFull', te ? 'పాత CRM పేజీ (కొటేషన్లు, ఫిర్యాదులు, రిపోర్ట్స్)' : 'Old CRM page (quotations, complaints, reports)',
            Icons.menu_book_rounded, () => context.push('/pos/${widget.businessId}/crm?full=1')),
      ],
      body: _error != null && leads == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : leads == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber('${open.length}', label: te ? 'తెరిచి ఉన్న ఎంక్వైరీలు' : 'Open enquiries', size: 44),
                    const SizedBox(height: 10),
                    if (open.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ఎంక్వైరీలు లేవు. కింద "కొత్త ఎంక్వైరీ" నొక్కండి.' : 'No enquiries. Tap "New enquiry" below.',
                            key: const Key('askodoxEnquiriesStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final l in open)
                      AskodoxStepPersonRow(
                        key: Key('askodoxEnquiriesStepsRow-${l['id']}'),
                        name: '${l['name']}',
                        sub: [
                          askodoxCrmStageLabel('${l['stage']}', te),
                          if ('${l['need'] ?? ''}'.isNotEmpty) '${l['need']}',
                        ].join(' · '),
                        amount: askodoxPosInt(l['value_paise']) > 0 ? askodoxPaise(askodoxPosInt(l['value_paise'])) : '',
                        amountColor: askodoxStepInk,
                        onTap: () async {
                          await context.push('/pos/${widget.businessId}/crm/lead/${l['id']}');
                          if (mounted) await _load();
                        },
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxEnquiriesStepsNew'),
        label: te ? 'కొత్త ఎంక్వైరీ' : 'New enquiry',
        icon: Icons.add_rounded,
        onPressed: () => unawaited(_add()),
      ),
    );
  }
}

// ============================================================================ workers & team
class AskodoxTeamStepsScreen extends ConsumerStatefulWidget {
  const AskodoxTeamStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxTeamStepsScreen> createState() => _TeamStepsState();
}

class _TeamStepsState extends ConsumerState<AskodoxTeamStepsScreen> {
  AskodoxJson? _data;
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
      final d = await _repo.workforce(widget.businessId);
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

  void _full() => context.push('/pos/${widget.businessId}/team?full=1');

  Future<void> _tapWorker(AskodoxJson w) async {
    final te = _te;
    final phone = '${w['phone'] ?? ''}';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${w['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text('${w['jobs'] ?? 0} ${te ? 'పనులు' : 'jobs'}${w['rating'] != null ? ' · ${w['rating']} ⭐' : ''}'),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              if (phone.isNotEmpty)
                FilledButton.icon(
                  key: Key('askodoxTeamStepsCall-${w['user']}'),
                  style: FilledButton.styleFrom(minimumSize: const Size(140, 54)),
                  icon: const Icon(Icons.call_rounded),
                  label: Text(te ? 'కాల్' : 'Call'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication));
                  },
                ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(140, 54)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _full();
                },
                child: Text(te ? 'పత్రాలు, పోస్టింగ్, తీసేయి' : 'Documents, posting, remove'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final data = _data;
    final team = askodoxPosList(data?['team']);
    return AskodoxStepScaffold(
      key: const Key('askodoxTeamSteps'),
      title: te ? 'పని వాళ్ళు & టీమ్' : 'Workers & team',
      more: [
        AskodoxStepMore('askodoxTeamStepsFull', te ? 'పాత పేజీ (రిజిస్ట్రేషన్, ఆర్డర్లు)' : 'Old page (registration, orders)', Icons.menu_book_rounded, _full),
      ],
      body: _error != null && data == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber('${team.length}', label: te ? 'మీ టీమ్‌లో' : 'In your team', size: 44),
                    const SizedBox(height: 10),
                    if (team.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ఇంకా ఎవరూ లేరు. కింద "కొత్తవాళ్ళని వెతుకు" నొక్కండి.' : 'Nobody yet. Tap "Find workers" below.',
                            key: const Key('askodoxTeamStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final w in team)
                      AskodoxStepPersonRow(
                        key: Key('askodoxTeamStepsRow-${w['user']}'),
                        name: '${w['name']}',
                        sub: w['status'] == 'joined' ? (te ? 'చేరారు' : 'Joined') : (te ? 'అడిగాం' : 'Invited'),
                        amount: '${w['jobs'] ?? 0}',
                        amountColor: askodoxStepInk,
                        onTap: () => unawaited(_tapWorker(w)),
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxTeamStepsFind'),
        label: te ? 'కొత్తవాళ్ళని వెతుకు' : 'Find workers',
        icon: Icons.person_search_rounded,
        onPressed: _full,
      ),
    );
  }
}
