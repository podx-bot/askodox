import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../growth/data/growth_repository.dart';
import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import 'pos_common.dart';

/// Business CRM inside My Business, on the ONE POS core (backend `pos_crm.py`):
/// leads & enquiries, quotations (= the sale screen's quotation drafts), follow-ups
/// with reminders, complaints, customer history from real bills, pipeline, reports.
/// Customers / staff / bills are the shop's existing POS records -- nothing is copied.

const askodoxCrmStages = ['new', 'contacted', 'quoted', 'negotiation', 'won', 'lost'];
const askodoxCrmOpenStages = ['new', 'contacted', 'quoted', 'negotiation'];
const askodoxCrmSources = ['walk_in', 'phone_call', 'whatsapp', 'askodox', 'referral', 'online', 'other'];

String askodoxCrmStageLabel(String stage, bool te) => switch (stage) {
      'new' => te ? 'కొత్తది' : 'New',
      'contacted' => te ? 'మాట్లాడాం' : 'Contacted',
      'quoted' => te ? 'Quotation ఇచ్చాం' : 'Quoted',
      'negotiation' => te ? 'బేరం జరుగుతోంది' : 'Negotiation',
      'won' => te ? 'Won (ఫైనల్)' : 'Won',
      'lost' => te ? 'Lost (పోయింది)' : 'Lost',
      _ => stage,
    };

String askodoxCrmSourceLabel(String source, bool te) => switch (source) {
      'walk_in' => te ? 'షాప్‌కి వచ్చారు' : 'Walk-in',
      'phone_call' => te ? 'Phone call' : 'Phone call',
      'whatsapp' => 'WhatsApp',
      'askodox' => te ? 'ASKODOX app' : 'ASKODOX app',
      'referral' => te ? 'ఎవరో చెప్పారు' : 'Referral',
      'online' => 'Online',
      _ => te ? 'ఇతర' : 'Other',
    };

String askodoxCrmQuoteLabel(String status, bool te) => switch (status) {
      'sent' => te ? 'పంపాం' : 'Sent',
      'accepted' => te ? 'ఒప్పుకున్నారు' : 'Accepted',
      'rejected' => te ? 'వద్దన్నారు' : 'Rejected',
      'expired' => te ? 'గడువు అయిపోయింది' : 'Expired',
      'billed' => te ? 'Bill అయింది' : 'Billed',
      _ => te ? 'Draft' : 'Draft',
    };

String askodoxCrmComplaintLabel(String status, bool te) => switch (status) {
      'in_progress' => te ? 'పని జరుగుతోంది' : 'In progress',
      'resolved' => te ? 'పరిష్కారం అయింది' : 'Resolved',
      'closed' => te ? 'Close చేశాం' : 'Closed',
      _ => te ? 'Open' : 'Open',
    };

/// `2026-10-28T10:00+05:30` -> `2026-10-28 10:00`.
String askodoxCrmWhen(Object? iso) {
  final text = '${iso ?? ''}';
  if (text.length < 10) return text;
  return text.length >= 16 ? text.substring(0, 16).replaceFirst('T', ' ') : text.substring(0, 10);
}

/// Asks for a date + time; returns `YYYY-MM-DDTHH:MM` (shop time) or null.
Future<String?> askodoxCrmPickWhen(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
      context: context, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 366)),
      initialDate: now.add(const Duration(days: 1)));
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 0));
  if (time == null) return null;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}T${two(time.hour)}:${two(time.minute)}';
}

// ---------------------------------------------------------------- /crm entry
/// My Business -> Business CRM: opens the shop's CRM (picks the shop when there are several).
class AskodoxCrmEntryScreen extends ConsumerStatefulWidget {
  const AskodoxCrmEntryScreen({super.key});

  @override
  ConsumerState<AskodoxCrmEntryScreen> createState() => _AskodoxCrmEntryScreenState();
}

class _AskodoxCrmEntryScreenState extends ConsumerState<AskodoxCrmEntryScreen> {
  late final Future<List<AskodoxJson>> _shops = ref.read(askodoxPosRepositoryProvider).businesses();
  bool _jumped = false;

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'Business CRM' : 'Business CRM')),
      body: FutureBuilder<List<AskodoxJson>>(
        future: _shops,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final shops = snap.data!;
          if (shops.length == 1 && !_jumped) {
            _jumped = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.replace('/pos/${shops.first['id']}/crm');
            });
          }
          if (shops.isEmpty) {
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(te
                  ? 'CRM మీ shop records (customers, bills, staff) మీదే పని చేస్తుంది. ముందు Shop billing లో మీ shop ని చేర్చండి.'
                  : 'The CRM works on your shop records (customers, bills, staff). Add your shop in Shop billing first.'),
              const SizedBox(height: 12),
              FilledButton(
                  key: const Key('askodoxCrmCreateShop'),
                  onPressed: () => context.push('/pos'),
                  child: Text(te ? 'Shop billing తెరవండి' : 'Open Shop billing')),
            ]);
          }
          return ListView(children: [
            for (final s in shops)
              ListTile(
                key: ValueKey('askodoxCrmShop-${s['id']}'),
                leading: const Icon(Icons.storefront_outlined),
                title: Text('${s['name']}'),
                subtitle: Text('${s['my_role'] ?? ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/pos/${s['id']}/crm'),
              ),
          ]);
        },
      ),
    );
  }
}

// ------------------------------------------------------------ /pos/:id/crm
class AskodoxPosCrmScreen extends ConsumerStatefulWidget {
  const AskodoxPosCrmScreen({super.key, required this.businessId, this.initialTab = ''});
  final String businessId;
  final String initialTab;

  @override
  ConsumerState<AskodoxPosCrmScreen> createState() => _AskodoxPosCrmScreenState();
}

class _AskodoxPosCrmScreenState extends ConsumerState<AskodoxPosCrmScreen> with SingleTickerProviderStateMixin {
  static const _tabs = ['today', 'leads', 'quotations', 'complaints', 'reports'];
  late final TabController _tab =
      TabController(length: _tabs.length, vsync: this, initialIndex: _tabs.contains(widget.initialTab) ? _tabs.indexOf(widget.initialTab) : 0);
  int _version = 0;

  void _reload() => setState(() => _version += 1);

  @override
  void initState() {
    super.initState();
    _tab.addListener(() {
      if (!_tab.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _addLead() async {
    final id = await askodoxCrmAddLeadDialog(context, ref, widget.businessId);
    if (id == null || !mounted) return;
    _reload();
    context.push('/pos/${widget.businessId}/crm/lead/$id');
  }

  Future<void> _addComplaint() async {
    final id = await askodoxCrmAddComplaintDialog(context, ref, widget.businessId);
    if (id == null || !mounted) return;
    _reload();
    context.push('/pos/${widget.businessId}/crm/complaint/$id');
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull ?? const <String, Object?>{};
    final reports = askodoxPosCan(business, 'reports');
    final onComplaints = _tabs[_tab.index] == 'complaints';
    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'Business CRM' : 'Business CRM'),
        bottom: TabBar(controller: _tab, isScrollable: true, tabs: [
          Tab(key: const Key('askodoxCrmTab-today'), text: te ? 'ఈరోజు' : 'Today'),
          Tab(key: const Key('askodoxCrmTab-leads'), text: te ? 'Leads & Enquiries' : 'Leads & enquiries'),
          Tab(key: const Key('askodoxCrmTab-quotations'), text: te ? 'Quotations' : 'Quotations'),
          Tab(key: const Key('askodoxCrmTab-complaints'), text: te ? 'Complaints' : 'Complaints'),
          Tab(key: const Key('askodoxCrmTab-reports'), text: te ? 'Reports' : 'Reports'),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: Key(onComplaints ? 'askodoxCrmAddComplaint' : 'askodoxCrmAddLead'),
        onPressed: onComplaints ? _addComplaint : _addLead,
        icon: Icon(onComplaints ? Icons.report_problem_outlined : Icons.person_add_alt_1),
        label: Text(onComplaints ? (te ? 'Complaint చేర్చండి' : 'Add complaint') : (te ? 'Lead చేర్చండి' : 'Add lead')),
      ),
      body: TabBarView(controller: _tab, children: [
        _CrmToday(key: ValueKey('today$_version'), businessId: widget.businessId, onChanged: _reload),
        _CrmLeads(key: ValueKey('leads$_version'), businessId: widget.businessId),
        _CrmQuotations(key: ValueKey('quotes$_version'), businessId: widget.businessId),
        _CrmComplaints(key: ValueKey('complaints$_version'), businessId: widget.businessId),
        reports
            ? _CrmReports(businessId: widget.businessId)
            : Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(te ? 'Reports owner / manager / accountant కి మాత్రమే.' : 'Reports are for the owner, manager or accountant.'))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Today tab
class _CrmToday extends ConsumerStatefulWidget {
  const _CrmToday({super.key, required this.businessId, required this.onChanged});
  final String businessId;
  final VoidCallback onChanged;

  @override
  ConsumerState<_CrmToday> createState() => _CrmTodayState();
}

class _CrmTodayState extends ConsumerState<_CrmToday> {
  late Future<(AskodoxJson, List<AskodoxJson>, List<AskodoxLead>)> _data = _load();

  Future<(AskodoxJson, List<AskodoxJson>, List<AskodoxLead>)> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    final pipe = await repo.crmPipeline(widget.businessId);
    final due = await repo.crmFollowups(widget.businessId);
    // Customers' requests to this seller inside ASKODOX (contact stays masked until accepted there).
    var requests = const <AskodoxLead>[];
    try {
      requests = await ref.read(growthRepositoryProvider).leads();
    } catch (_) {}
    return (pipe, due, requests);
  }

  void _refresh() => setState(() => _data = _load());

  Future<void> _close(AskodoxJson f, String status) async {
    final te = askodoxPosTe(context);
    final outcome = TextEditingController();
    String? next;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(status == 'done' ? (te ? 'Follow-up అయింది' : 'Follow-up done') : (te ? 'Skip చేయాలా?' : 'Skip it?')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            AskodoxPosField(controller: outcome, label: te ? 'ఏమైంది (note)' : 'What happened (note)', maxLength: 240),
            TextButton.icon(
              key: const Key('askodoxCrmNextFollowup'),
              onPressed: () async {
                final when = await askodoxCrmPickWhen(ctx);
                if (when != null) setLocal(() => next = when);
              },
              icon: const Icon(Icons.event_repeat),
              label: Text(next == null ? (te ? 'మళ్ళీ follow-up పెట్టండి' : 'Set the next follow-up') : askodoxCrmWhen(next)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'Save చేయండి' : 'Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).crmCloseFollowup(widget.businessId, '${f['id']}', {
        'status': status,
        'outcome': outcome.text.trim(),
        if (next != null) 'next_at': next,
      });
      _refresh();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _saveRequest(AskodoxLead lead) async {
    final te = askodoxPosTe(context);
    try {
      final saved = await ref.read(askodoxPosRepositoryProvider).crmAddLead(widget.businessId, {
        'kind': 'enquiry',
        'source': 'askodox',
        'source_ref': lead.requestId,
        'name': te ? 'ASKODOX customer' : 'ASKODOX customer',
        'need': lead.message,
      });
      if (!mounted) return;
      widget.onChanged();
      context.push('/pos/${widget.businessId}/crm/lead/${saved['id']}');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return FutureBuilder<(AskodoxJson, List<AskodoxJson>, List<AskodoxLead>)>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _refresh);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (pipe, due, requests) = snap.data!;
        final stages = askodoxPosList(pipe['stages']);
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              _CrmStat(te ? 'Open value' : 'Open value', askodoxPaise(askodoxPosInt(pipe['open_value_paise']))),
              _CrmStat(te ? 'ఆలస్యమైన follow-ups' : 'Overdue follow-ups', '${pipe['followups_overdue'] ?? 0}'),
              _CrmStat(te ? 'ఈరోజు follow-ups' : 'Follow-ups today', '${pipe['followups_today'] ?? 0}'),
              _CrmStat(te ? 'కొత్త enquiries' : 'New enquiries', '${pipe['new_enquiries'] ?? 0}'),
              _CrmStat(te ? 'Open complaints' : 'Open complaints', '${pipe['complaints_active'] ?? 0}'),
            ]),
            const SizedBox(height: 14),
            Text(te ? 'Sales pipeline' : 'Sales pipeline', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final s in stages)
              ListTile(
                key: ValueKey('askodoxCrmStage-${s['stage']}'),
                dense: true,
                title: Text(askodoxCrmStageLabel('${s['stage']}', te)),
                trailing: Text('${s['count'] ?? 0} · ${askodoxPaise(askodoxPosInt(s['value_paise']))}'),
                onTap: () => context.push('/pos/${widget.businessId}/crm/leads?stage=${s['stage']}'),
              ),
            const Divider(),
            Text(te ? 'Follow-ups (ఆలస్యం + ఈరోజు)' : 'Follow-ups (overdue + today)', style: Theme.of(context).textTheme.titleSmall),
            if (due.isEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(te ? 'ఈరోజు follow-up ఏమీ లేదు.' : 'No follow-up due today.')),
            for (final f in due)
              Card(
                key: ValueKey('askodoxCrmFollowup-${f['id']}'),
                child: ListTile(
                  leading: Icon(f['overdue'] == true ? Icons.alarm : Icons.event_note,
                      color: f['overdue'] == true ? Theme.of(context).colorScheme.error : null),
                  title: Text('${f['note']}'),
                  subtitle: Text('${askodoxCrmWhen(f['due_at'])} · ${f['lead_name'] ?? f['customer_name'] ?? f['complaint_subject'] ?? ''}'),
                  onTap: f['lead_id'] == null ? null : () => context.push('/pos/${widget.businessId}/crm/lead/${f['lead_id']}'),
                  trailing: Wrap(children: [
                    IconButton(
                        tooltip: te ? 'అయింది' : 'Done',
                        onPressed: () => _close(f, 'done'),
                        icon: const Icon(Icons.check_circle_outline)),
                    IconButton(
                        tooltip: te ? 'Skip' : 'Skip',
                        onPressed: () => _close(f, 'skipped'),
                        icon: const Icon(Icons.skip_next_outlined)),
                  ]),
                ),
              ),
            if (requests.isNotEmpty) ...[
              const Divider(),
              Text(te ? 'ASKODOX లో మీకు వచ్చిన requests' : 'Requests to you in ASKODOX',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final r in requests.take(10))
                ListTile(
                  key: ValueKey('askodoxCrmRequest-${r.requestId}'),
                  leading: const Icon(Icons.mark_email_unread_outlined),
                  title: Text(r.message, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: TextButton(
                      onPressed: () => _saveRequest(r), child: Text(te ? 'CRM లో save' : 'Save to CRM')),
                ),
            ],
          ]),
        );
      },
    );
  }
}

class _CrmStat extends StatelessWidget {
  const _CrmStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Leads tab
class _CrmLeads extends ConsumerStatefulWidget {
  const _CrmLeads({super.key, required this.businessId, this.stage = 'open'});
  final String businessId;
  final String stage;

  @override
  ConsumerState<_CrmLeads> createState() => _CrmLeadsState();
}

class _CrmLeadsState extends ConsumerState<_CrmLeads> {
  late String _stage = widget.stage;
  bool _mine = false;
  final _q = TextEditingController();
  late Future<List<AskodoxJson>> _list = _load();

  Future<List<AskodoxJson>> _load() => ref
      .read(askodoxPosRepositoryProvider)
      .crmLeads(widget.businessId, stage: _stage == 'all' ? '' : _stage, mine: _mine, q: _q.text.trim());

  void _refresh() => setState(() => _list = _load());

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final filters = ['open', ...askodoxCrmStages, 'all'];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: TextField(
          key: const Key('askodoxCrmLeadSearch'),
          controller: _q,
          onSubmitted: (_) => _refresh(),
          decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              hintText: te ? 'పేరు, phone, అవసరం వెతకండి' : 'Search name, phone, need'),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          FilterChip(
              key: const Key('askodoxCrmMine'),
              label: Text(te ? 'నావి' : 'Mine'),
              selected: _mine,
              onSelected: (v) {
                _mine = v;
                _refresh();
              }),
          const SizedBox(width: 6),
          for (final f in filters)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(f == 'open' ? (te ? 'Open అన్నీ' : 'All open') : f == 'all' ? (te ? 'అన్నీ' : 'Everything') : askodoxCrmStageLabel(f, te)),
                selected: _stage == f,
                onSelected: (_) {
                  _stage = f;
                  _refresh();
                },
              ),
            ),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<AskodoxJson>>(
          future: _list,
          builder: (context, snap) {
            if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _refresh);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final leads = snap.data!;
            if (leads.isEmpty) {
              return Center(child: Text(te ? 'ఇక్కడ leads ఏమీ లేవు. + Lead చేర్చండి.' : 'No leads here. Tap + Add lead.'));
            }
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: leads.length,
                itemBuilder: (context, i) => _CrmLeadTile(businessId: widget.businessId, lead: leads[i], onBack: _refresh),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _CrmLeadTile extends StatelessWidget {
  const _CrmLeadTile({required this.businessId, required this.lead, required this.onBack});
  final String businessId;
  final AskodoxJson lead;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final next = askodoxPosMap(lead['next_followup']);
    final value = askodoxPosInt(lead['value_paise']);
    return ListTile(
      key: ValueKey('askodoxCrmLead-${lead['id']}'),
      leading: Icon(lead['kind'] == 'enquiry' ? Icons.help_outline : Icons.trending_up),
      title: Text('${lead['name']}${value > 0 ? ' · ${askodoxPaise(value)}' : ''}'),
      subtitle: Text([
        askodoxCrmStageLabel('${lead['stage']}', te),
        askodoxCrmSourceLabel('${lead['source']}', te),
        if ('${lead['need'] ?? ''}'.isNotEmpty) '${lead['need']}',
        if (next.isNotEmpty) '${te ? 'Follow-up' : 'Follow-up'} ${askodoxCrmWhen(next['due_at'])}',
      ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: next['overdue'] == true ? Icon(Icons.alarm, color: Theme.of(context).colorScheme.error) : null,
      onTap: () async {
        await context.push('/pos/$businessId/crm/lead/${lead['id']}');
        onBack();
      },
    );
  }
}

/// `/pos/:id/crm/leads?stage=` -- the leads list on its own (from a pipeline row).
class AskodoxPosCrmLeadsScreen extends StatelessWidget {
  const AskodoxPosCrmLeadsScreen({super.key, required this.businessId, this.stage = 'open'});
  final String businessId;
  final String stage;

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'Leads & Enquiries' : 'Leads & enquiries')),
      body: _CrmLeads(businessId: businessId, stage: stage.isEmpty ? 'open' : stage),
    );
  }
}

/// Add a lead / enquiry; returns the new lead id.
Future<String?> askodoxCrmAddLeadDialog(BuildContext context, WidgetRef ref, String businessId,
    {String? customerId, String customerName = ''}) async {
  final te = askodoxPosTe(context);
  final name = TextEditingController(text: customerName);
  final phone = TextEditingController();
  final need = TextEditingController();
  final value = TextEditingController();
  var kind = 'lead';
  var source = 'walk_in';
  String? followup;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(te ? 'కొత్త Lead / Enquiry' : 'New lead / enquiry'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, children: [
              for (final k in const ['lead', 'enquiry'])
                ChoiceChip(
                  key: ValueKey('askodoxCrmKind-$k'),
                  label: Text(k == 'lead' ? (te ? 'Lead (అమ్మే అవకాశం)' : 'Lead (sale chance)') : (te ? 'Enquiry (ప్రశ్న)' : 'Enquiry (question)')),
                  selected: kind == k,
                  onSelected: (_) => setLocal(() => kind = k),
                ),
            ]),
            const SizedBox(height: 8),
            if (customerId == null) ...[
              AskodoxPosField(controller: name, label: te ? 'పేరు' : 'Name', maxLength: 80),
              AskodoxPosField(controller: phone, number: true, decimal: false, label: te ? 'ఫోన్' : 'Phone', maxLength: 15),
            ],
            AskodoxPosField(
                controller: need,
                label: te ? 'ఏం కావాలి' : 'What they need',
                maxLength: 500,
                exampleEn: '6-seater dining table, teak',
                exampleTe: '6 మంది dining table, teak'),
            AskodoxPosField(controller: value, number: true, label: te ? 'అంచనా విలువ ₹' : 'Estimated value ₹'),
            Text(te ? 'ఎక్కడ నుండి వచ్చారు' : 'Where they came from', style: Theme.of(ctx).textTheme.labelMedium),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final s in askodoxCrmSources)
                ChoiceChip(
                  label: Text(askodoxCrmSourceLabel(s, te)),
                  selected: source == s,
                  onSelected: (_) => setLocal(() => source = s),
                ),
            ]),
            TextButton.icon(
              key: const Key('askodoxCrmLeadFollowup'),
              onPressed: () async {
                final when = await askodoxCrmPickWhen(ctx);
                if (when != null) setLocal(() => followup = when);
              },
              icon: const Icon(Icons.alarm_add),
              label: Text(followup == null ? (te ? 'Follow-up reminder పెట్టండి' : 'Set a follow-up reminder') : askodoxCrmWhen(followup)),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxCrmSaveLead'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(te ? 'Save చేయండి' : 'Save')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  try {
    final saved = await ref.read(askodoxPosRepositoryProvider).crmAddLead(businessId, {
      'kind': kind,
      'source': source,
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'need': need.text.trim(),
      'value_paise': askodoxParsePaise(value.text.trim()) ?? 0,
      if (customerId != null) 'customer_id': customerId,
      if (followup != null) 'followup_at': followup,
      if (followup != null) 'followup_note': need.text.trim().isEmpty ? 'Follow-up' : need.text.trim(),
    });
    return '${saved['id']}';
  } on AskodoxPosException catch (e) {
    if (context.mounted) askodoxPosSnack(context, e.message(te));
    return null;
  }
}

// ---------------------------------------------------------- Lead detail
class AskodoxPosCrmLeadScreen extends ConsumerStatefulWidget {
  const AskodoxPosCrmLeadScreen({super.key, required this.businessId, required this.leadId});
  final String businessId;
  final String leadId;

  @override
  ConsumerState<AskodoxPosCrmLeadScreen> createState() => _AskodoxPosCrmLeadScreenState();
}

class _AskodoxPosCrmLeadScreenState extends ConsumerState<AskodoxPosCrmLeadScreen> {
  late Future<AskodoxJson> _lead = _load();

  Future<AskodoxJson> _load() => ref.read(askodoxPosRepositoryProvider).crmLead(widget.businessId, widget.leadId);

  void _refresh() => setState(() => _lead = _load());

  Future<void> _patch(AskodoxJson body) async {
    if (!mounted) return;
    final te = askodoxPosTe(context);
    try {
      await ref.read(askodoxPosRepositoryProvider).crmUpdateLead(widget.businessId, widget.leadId, body);
      _refresh();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _stage(AskodoxJson lead, String stage) async {
    final te = askodoxPosTe(context);
    final body = <String, Object?>{'stage': stage, 'version': lead['version']};
    if (stage == 'lost') {
      final reason = await _ask(te ? 'ఎందుకు పోయింది?' : 'Why was it lost?', te ? 'కారణం' : 'Reason');
      if (reason == null || reason.isEmpty) return;
      body['lost_reason'] = reason;
    }
    if (stage == 'won' && mounted) {
      final invoice = await _pickInvoice(lead);
      if (invoice != null && invoice.isNotEmpty) body['won_invoice_id'] = invoice;
    }
    await _patch(body);
  }

  Future<String?> _ask(String title, String label) async {
    final text = TextEditingController();
    final te = askodoxPosTe(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: AskodoxPosField(controller: text, label: label, maxLength: 240),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'Save చేయండి' : 'Save')),
        ],
      ),
    );
    return ok == true ? text.text.trim() : null;
  }

  /// Won: optionally pick the real bill (this customer's recent bills).
  Future<String?> _pickInvoice(AskodoxJson lead) async {
    final te = askodoxPosTe(context);
    final customerId = '${lead['customer_id'] ?? ''}';
    if (customerId.isEmpty) return '';
    List<AskodoxJson> bills;
    try {
      final history = await ref.read(askodoxPosRepositoryProvider).crmCustomerHistory(widget.businessId, customerId);
      bills = [for (final b in askodoxPosList(history['invoices'])) if (b['doc_kind'] == 'invoice' && b['status'] == 'issued') b];
    } on AskodoxPosException {
      return '';
    }
    if (bills.isEmpty || !mounted) return '';
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => ListView(children: [
        ListTile(title: Text(te ? 'ఏ bill తో ఫైనల్ అయింది?' : 'Which bill closed it?')),
        ListTile(title: Text(te ? 'Bill లేకుండా Won' : 'Won without a bill'), onTap: () => Navigator.pop(ctx, '')),
        for (final b in bills.take(15))
          ListTile(
            title: Text('${b['number']} · ${askodoxPaise(askodoxPosInt(b['total_paise']))}'),
            subtitle: Text('${b['local_date']}'),
            onTap: () => Navigator.pop(ctx, '${b['id']}'),
          ),
      ]),
    );
  }

  Future<void> _note(String kind) async {
    final te = askodoxPosTe(context);
    final text = await _ask(kind == 'call' ? (te ? 'Call లో ఏం మాట్లాడారు?' : 'What was said on the call?') : (te ? 'Note రాయండి' : 'Write a note'),
        te ? 'Note' : 'Note');
    if (text == null || text.isEmpty || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).crmActivity(widget.businessId, {'lead_id': widget.leadId, 'kind': kind, 'text': text});
      _refresh();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _followup() async {
    final te = askodoxPosTe(context);
    final when = await askodoxCrmPickWhen(context);
    if (when == null || !mounted) return;
    final note = await _ask(te ? 'Follow-up లో ఏం చేయాలి?' : 'What to do on the follow-up?', te ? 'Note' : 'Note');
    if (note == null || note.isEmpty || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).crmAddFollowup(widget.businessId, {'lead_id': widget.leadId, 'due_at': when, 'note': note});
      _refresh();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _toCustomer() async {
    final te = askodoxPosTe(context);
    try {
      await ref.read(askodoxPosRepositoryProvider).crmLeadToCustomer(widget.businessId, widget.leadId, {});
      if (mounted) askodoxPosSnack(context, te ? 'Customers list లో save అయింది.' : 'Saved to your customers.');
      _refresh();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _assign() async {
    final te = askodoxPosTe(context);
    List<AskodoxJson> staff;
    try {
      staff = await ref.read(askodoxPosRepositoryProvider).crmStaff(widget.businessId);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (!mounted) return;
    final ref0 = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => ListView(children: [
        for (final s in staff)
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(s['me'] == true ? (te ? 'నేను' : 'Me') : '…${s['last4']}'),
            subtitle: Text('${s['role']}'),
            onTap: () => Navigator.pop(ctx, '${s['ref']}'),
          ),
      ]),
    );
    if (ref0 != null) await _patch({'assigned_to': ref0});
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'Lead వివరాలు' : 'Lead')),
      body: FutureBuilder<AskodoxJson>(
        future: _lead,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _refresh);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final lead = snap.data!;
          final stage = '${lead['stage']}';
          final closed = stage == 'won' || stage == 'lost';
          final assigned = askodoxPosMap(lead['assigned_to']);
          final customerId = '${lead['customer_id'] ?? ''}';
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
              Text('${lead['name']}', style: Theme.of(context).textTheme.titleLarge),
              Text([
                lead['kind'] == 'enquiry' ? 'Enquiry' : 'Lead',
                askodoxCrmSourceLabel('${lead['source']}', te),
                if ('${lead['phone'] ?? ''}'.isNotEmpty) '${lead['phone']}',
                if (assigned.isNotEmpty) '${te ? 'బాధ్యత' : 'Owner'}: ${assigned['me'] == true ? (te ? 'నేను' : 'me') : '…${assigned['last4']}'}',
              ].join(' · ')),
              if ('${lead['need'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${lead['need']}')),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${te ? 'అంచనా విలువ' : 'Estimated value'}: ${askodoxPaise(askodoxPosInt(lead['value_paise']))}'),
              ),
              if (stage == 'lost') Text('${te ? 'కారణం' : 'Reason'}: ${lead['lost_reason']}'),
              const SizedBox(height: 10),
              Text(te ? 'Stage' : 'Stage', style: Theme.of(context).textTheme.titleSmall),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final s in askodoxCrmStages)
                  ChoiceChip(
                    key: ValueKey('askodoxCrmSetStage-$s'),
                    label: Text(askodoxCrmStageLabel(s, te)),
                    selected: stage == s,
                    onSelected: s == stage || (closed && !askodoxCrmOpenStages.contains(s)) ? null : (_) => _stage(lead, s),
                  ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    key: const Key('askodoxCrmCall'),
                    onPressed: () => _note('call'),
                    icon: const Icon(Icons.call_outlined),
                    label: Text(te ? 'Call note' : 'Call note')),
                OutlinedButton.icon(
                    key: const Key('askodoxCrmNote'),
                    onPressed: () => _note('note'),
                    icon: const Icon(Icons.edit_note),
                    label: Text(te ? 'Note' : 'Note')),
                OutlinedButton.icon(
                    key: const Key('askodoxCrmAddFollowup'),
                    onPressed: _followup,
                    icon: const Icon(Icons.alarm_add),
                    label: Text(te ? 'Follow-up' : 'Follow-up')),
                OutlinedButton.icon(
                    key: const Key('askodoxCrmQuote'),
                    onPressed: () => context.push(
                        '/pos/${widget.businessId}/sale?lead=${widget.leadId}${customerId.isEmpty ? '' : '&customer=$customerId'}'),
                    icon: const Icon(Icons.request_quote_outlined),
                    label: Text(te ? 'Quotation తయారు చేయండి' : 'Make quotation')),
                OutlinedButton.icon(
                    key: const Key('askodoxCrmAssign'),
                    onPressed: _assign,
                    icon: const Icon(Icons.assignment_ind_outlined),
                    label: Text(te ? 'ఎవరికి ఇవ్వాలి' : 'Assign')),
                if (customerId.isEmpty)
                  OutlinedButton.icon(
                      key: const Key('askodoxCrmToCustomer'),
                      onPressed: _toCustomer,
                      icon: const Icon(Icons.person_add_alt),
                      label: Text(te ? 'Customer గా save' : 'Save as customer'))
                else
                  OutlinedButton.icon(
                      key: const Key('askodoxCrmOpenCustomer'),
                      onPressed: () => context.push('/pos/${widget.businessId}/crm/customer/$customerId'),
                      icon: const Icon(Icons.history),
                      label: Text(te ? 'Customer history' : 'Customer history')),
              ]),
              const Divider(height: 28),
              Text(te ? 'Follow-ups' : 'Follow-ups', style: Theme.of(context).textTheme.titleSmall),
              for (final f in askodoxPosList(lead['followups']))
                ListTile(
                  dense: true,
                  leading: Icon(f['status'] == 'open' ? Icons.alarm : Icons.check, size: 20),
                  title: Text('${f['note']}'),
                  subtitle: Text('${askodoxCrmWhen(f['due_at'])} · ${f['status']}${'${f['outcome'] ?? ''}'.isEmpty ? '' : ' · ${f['outcome']}'}'),
                ),
              Text(te ? 'Quotations' : 'Quotations', style: Theme.of(context).textTheme.titleSmall),
              for (final q in askodoxPosList(lead['quotations']))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.request_quote_outlined, size: 20),
                  title: Text('${q['title'] ?? q['draft_id']}'),
                  subtitle: Text('${askodoxCrmQuoteLabel('${q['status']}', te)} · ${askodoxPaise(askodoxPosInt(q['estimate_paise']))}'),
                ),
              const Divider(height: 28),
              Text(te ? 'Timeline' : 'Timeline', style: Theme.of(context).textTheme.titleSmall),
              for (final t in askodoxPosList(lead['timeline']))
                ListTile(
                  dense: true,
                  title: Text('${t['text']}'),
                  subtitle: Text('${askodoxCrmWhen(t['at'])} · ${t['kind']}'),
                ),
            ]),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------- Quotations tab
class _CrmQuotations extends ConsumerStatefulWidget {
  const _CrmQuotations({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<_CrmQuotations> createState() => _CrmQuotationsState();
}

class _CrmQuotationsState extends ConsumerState<_CrmQuotations> {
  late Future<List<AskodoxJson>> _list = _load();

  Future<List<AskodoxJson>> _load() => ref.read(askodoxPosRepositoryProvider).crmQuotations(widget.businessId);

  void _refresh() => setState(() => _list = _load());

  Future<void> _status(AskodoxJson q) async {
    final te = askodoxPosTe(context);
    final status = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => ListView(shrinkWrap: true, children: [
        for (final s in const ['sent', 'accepted', 'rejected', 'expired'])
          ListTile(title: Text(askodoxCrmQuoteLabel(s, te)), onTap: () => Navigator.pop(ctx, s)),
      ]),
    );
    if (status == null || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).crmSetQuote(widget.businessId, '${q['draft_id']}', {'status': status});
      _refresh();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return FutureBuilder<List<AskodoxJson>>(
      future: _list,
      builder: (context, snap) {
        if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _refresh);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final quotes = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            ListTile(
              key: const Key('askodoxCrmNewQuote'),
              leading: const Icon(Icons.add_circle_outline),
              title: Text(te ? 'కొత్త quotation (Bill screen లో items వేసి "Quotation" నొక్కండి)' : 'New quotation (add items on the bill screen, then "Quotation")'),
              onTap: () => context.push('/pos/${widget.businessId}/sale'),
            ),
            if (quotes.isEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Text(te ? 'ఇంకా quotations లేవు.' : 'No quotations yet.')),
            for (final q in quotes)
              ListTile(
                key: ValueKey('askodoxCrmQuote-${q['draft_id']}'),
                leading: const Icon(Icons.request_quote_outlined),
                title: Text('${q['title']}'),
                subtitle: Text([
                  askodoxCrmQuoteLabel('${q['status']}', te),
                  askodoxPaise(askodoxPosInt(q['estimate_paise'])),
                  if (q['lead_name'] != null) '${te ? 'Lead' : 'Lead'}: ${q['lead_name']}',
                  askodoxCrmWhen(q['made_at']),
                ].join(' · ')),
                trailing: const Icon(Icons.more_vert),
                onTap: () => _status(q),
              ),
          ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------- Complaints
class _CrmComplaints extends ConsumerStatefulWidget {
  const _CrmComplaints({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<_CrmComplaints> createState() => _CrmComplaintsState();
}

class _CrmComplaintsState extends ConsumerState<_CrmComplaints> {
  bool _all = false;
  late Future<List<AskodoxJson>> _list = _load();

  Future<List<AskodoxJson>> _load() =>
      ref.read(askodoxPosRepositoryProvider).crmComplaints(widget.businessId, status: _all ? '' : 'active');

  void _refresh() => setState(() => _list = _load());

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          ChoiceChip(
              label: Text(te ? 'Open ఉన్నవి' : 'Active'),
              selected: !_all,
              onSelected: (_) {
                _all = false;
                _refresh();
              }),
          const SizedBox(width: 6),
          ChoiceChip(
              label: Text(te ? 'అన్నీ' : 'All'),
              selected: _all,
              onSelected: (_) {
                _all = true;
                _refresh();
              }),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<AskodoxJson>>(
          future: _list,
          builder: (context, snap) {
            if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _refresh);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final items = snap.data!;
            if (items.isEmpty) return Center(child: Text(te ? 'Complaints ఏమీ లేవు.' : 'No complaints.'));
            return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              for (final c in items)
                ListTile(
                  key: ValueKey('askodoxCrmComplaint-${c['id']}'),
                  leading: Icon(Icons.report_problem_outlined,
                      color: c['priority'] == 'urgent' || c['priority'] == 'high' ? Theme.of(context).colorScheme.error : null),
                  title: Text('${c['subject']}'),
                  subtitle: Text('${c['name']} · ${askodoxCrmComplaintLabel('${c['status']}', te)} · ${c['priority']}'),
                  onTap: () async {
                    await context.push('/pos/${widget.businessId}/crm/complaint/${c['id']}');
                    if (mounted) _refresh();
                  },
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}

/// Add a complaint; returns its id.
Future<String?> askodoxCrmAddComplaintDialog(BuildContext context, WidgetRef ref, String businessId,
    {String? customerId, String customerName = ''}) async {
  final te = askodoxPosTe(context);
  final name = TextEditingController(text: customerName);
  final phone = TextEditingController();
  final subject = TextEditingController();
  final detail = TextEditingController();
  var priority = 'normal';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(te ? 'కొత్త Complaint' : 'New complaint'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (customerId == null) ...[
              AskodoxPosField(controller: name, label: te ? 'Customer పేరు' : 'Customer name', maxLength: 80),
              AskodoxPosField(controller: phone, number: true, decimal: false, label: te ? 'ఫోన్' : 'Phone', maxLength: 15),
            ],
            AskodoxPosField(
                controller: subject,
                label: te ? 'సమస్య (ఒక line)' : 'Problem (one line)',
                maxLength: 120,
                exampleEn: 'Table leg loose',
                exampleTe: 'Table కాలు వదులుగా ఉంది'),
            AskodoxPosField(controller: detail, label: te ? 'వివరాలు' : 'Details', maxLength: 1000),
            Wrap(spacing: 6, children: [
              for (final p in const ['low', 'normal', 'high', 'urgent'])
                ChoiceChip(
                  label: Text(switch (p) {
                    'low' => te ? 'తక్కువ' : 'Low',
                    'high' => te ? 'ఎక్కువ' : 'High',
                    'urgent' => te ? 'వెంటనే' : 'Urgent',
                    _ => te ? 'మామూలు' : 'Normal',
                  }),
                  selected: priority == p,
                  onSelected: (_) => setLocal(() => priority = p),
                ),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxCrmSaveComplaint'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(te ? 'Save చేయండి' : 'Save')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  try {
    final saved = await ref.read(askodoxPosRepositoryProvider).crmAddComplaint(businessId, {
      'subject': subject.text.trim(),
      'detail': detail.text.trim(),
      'priority': priority,
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      if (customerId != null) 'customer_id': customerId,
    });
    return '${saved['id']}';
  } on AskodoxPosException catch (e) {
    if (context.mounted) askodoxPosSnack(context, e.message(te));
    return null;
  }
}

class AskodoxPosCrmComplaintScreen extends ConsumerStatefulWidget {
  const AskodoxPosCrmComplaintScreen({super.key, required this.businessId, required this.complaintId});
  final String businessId;
  final String complaintId;

  @override
  ConsumerState<AskodoxPosCrmComplaintScreen> createState() => _AskodoxPosCrmComplaintScreenState();
}

class _AskodoxPosCrmComplaintScreenState extends ConsumerState<AskodoxPosCrmComplaintScreen> {
  late Future<AskodoxJson> _item = _load();

  Future<AskodoxJson> _load() => ref.read(askodoxPosRepositoryProvider).crmComplaint(widget.businessId, widget.complaintId);

  void _refresh() => setState(() => _item = _load());

  Future<void> _setStatus(String status) async {
    final te = askodoxPosTe(context);
    final body = <String, Object?>{'status': status};
    if (status == 'resolved' || status == 'closed') {
      final text = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(te ? 'ఎలా పరిష్కరించారు?' : 'How was it solved?'),
          content: AskodoxPosField(controller: text, label: te ? 'పరిష్కారం' : 'Resolution', maxLength: 500),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'Save చేయండి' : 'Save')),
          ],
        ),
      );
      if (ok != true) return;
      body['resolution'] = text.text.trim();
    }
    if (!mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).crmUpdateComplaint(widget.businessId, widget.complaintId, body);
      _refresh();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _followup() async {
    final te = askodoxPosTe(context);
    final when = await askodoxCrmPickWhen(context);
    if (when == null || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).crmAddFollowup(widget.businessId, {
        'complaint_id': widget.complaintId,
        'due_at': when,
        'note': te ? 'Complaint follow-up' : 'Complaint follow-up',
      });
      _refresh();
      if (mounted) askodoxPosSnack(context, te ? 'Reminder పెట్టాం.' : 'Reminder set.');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'Complaint' : 'Complaint')),
      body: FutureBuilder<AskodoxJson>(
        future: _item,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _refresh);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final c = snap.data!;
          final status = '${c['status']}';
          final customerId = '${c['customer_id'] ?? ''}';
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
            Text('${c['subject']}', style: Theme.of(context).textTheme.titleLarge),
            Text('${c['name']} · ${c['priority']} · ${askodoxCrmComplaintLabel(status, te)}'),
            if ('${c['detail'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${c['detail']}')),
            if ('${c['resolution'] ?? ''}'.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('${te ? 'పరిష్కారం' : 'Resolution'}: ${c['resolution']}')),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final s in const ['open', 'in_progress', 'resolved', 'closed'])
                ChoiceChip(
                  key: ValueKey('askodoxCrmComplaintStatus-$s'),
                  label: Text(askodoxCrmComplaintLabel(s, te)),
                  selected: status == s,
                  onSelected: s == status ? null : (_) => _setStatus(s),
                ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(onPressed: _followup, icon: const Icon(Icons.alarm_add), label: Text(te ? 'Reminder' : 'Reminder')),
              if (customerId.isNotEmpty)
                OutlinedButton.icon(
                    onPressed: () => context.push('/pos/${widget.businessId}/crm/customer/$customerId'),
                    icon: const Icon(Icons.history),
                    label: Text(te ? 'Customer history' : 'Customer history')),
              if (c['invoice_id'] != null)
                OutlinedButton.icon(
                    onPressed: () => context.push('/pos/${widget.businessId}/invoice/${c['invoice_id']}'),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(te ? 'Bill చూడండి' : 'Open bill')),
            ]),
            const Divider(height: 28),
            Text(te ? 'Timeline' : 'Timeline', style: Theme.of(context).textTheme.titleSmall),
            for (final t in askodoxPosList(c['timeline']))
              ListTile(dense: true, title: Text('${t['text']}'), subtitle: Text(askodoxCrmWhen(t['at']))),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------- Customer history
class AskodoxPosCrmCustomerScreen extends ConsumerStatefulWidget {
  const AskodoxPosCrmCustomerScreen({super.key, required this.businessId, required this.customerId});
  final String businessId;
  final String customerId;

  @override
  ConsumerState<AskodoxPosCrmCustomerScreen> createState() => _AskodoxPosCrmCustomerScreenState();
}

class _AskodoxPosCrmCustomerScreenState extends ConsumerState<AskodoxPosCrmCustomerScreen> {
  late Future<AskodoxJson> _data = _load();

  Future<AskodoxJson> _load() => ref.read(askodoxPosRepositoryProvider).crmCustomerHistory(widget.businessId, widget.customerId);

  void _refresh() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'Customer history' : 'Customer history')),
      body: FutureBuilder<AskodoxJson>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _refresh);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          final c = askodoxPosMap(d['customer']);
          final s = askodoxPosMap(d['summary']);
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
              Text('${c['name']}', style: Theme.of(context).textTheme.titleLarge),
              if ('${c['phone'] ?? ''}'.isNotEmpty) Text('${c['phone']}'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _CrmStat(te ? 'Bills' : 'Bills', '${s['bills'] ?? 0}'),
                _CrmStat(te ? 'మొత్తం కొన్నది' : 'Bought in all', askodoxPaise(askodoxPosInt(s['billed_paise']))),
                _CrmStat(te ? 'బాకీ' : 'Due', askodoxPaise(askodoxPosInt(s['due_paise']))),
                _CrmStat(te ? 'Open leads' : 'Open leads', '${s['open_leads'] ?? 0}'),
                _CrmStat(te ? 'Open complaints' : 'Open complaints', '${s['open_complaints'] ?? 0}'),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    key: const Key('askodoxCrmCustomerLead'),
                    onPressed: () async {
                      final id = await askodoxCrmAddLeadDialog(context, ref, widget.businessId,
                          customerId: widget.customerId, customerName: '${c['name']}');
                      if (id != null && mounted) _refresh();
                    },
                    icon: const Icon(Icons.trending_up),
                    label: Text(te ? 'కొత్త Lead' : 'New lead')),
                OutlinedButton.icon(
                    key: const Key('askodoxCrmCustomerComplaint'),
                    onPressed: () async {
                      final id = await askodoxCrmAddComplaintDialog(context, ref, widget.businessId,
                          customerId: widget.customerId, customerName: '${c['name']}');
                      if (id != null && mounted) _refresh();
                    },
                    icon: const Icon(Icons.report_problem_outlined),
                    label: Text(te ? 'Complaint' : 'Complaint')),
                OutlinedButton.icon(
                    onPressed: () => context.push('/pos/${widget.businessId}/customers/${widget.customerId}'),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: Text(te ? 'ఖాతా / బాకీ' : 'Account / dues')),
              ]),
              const Divider(height: 28),
              Text(te ? 'Bills' : 'Bills', style: Theme.of(context).textTheme.titleSmall),
              for (final b in askodoxPosList(d['invoices']).take(20))
                ListTile(
                  dense: true,
                  leading: Icon(b['doc_kind'] == 'invoice' ? Icons.receipt_long_outlined : Icons.undo, size: 20),
                  title: Text('${b['number']} · ${askodoxPaise(askodoxPosInt(b['total_paise']))}'),
                  subtitle: Text('${b['local_date']} · ${b['status']}'),
                  onTap: () => context.push('/pos/${widget.businessId}/invoice/${b['id']}'),
                ),
              Text(te ? 'Leads' : 'Leads', style: Theme.of(context).textTheme.titleSmall),
              for (final l in askodoxPosList(d['leads']))
                _CrmLeadTile(businessId: widget.businessId, lead: l, onBack: _refresh),
              Text(te ? 'Complaints' : 'Complaints', style: Theme.of(context).textTheme.titleSmall),
              for (final k in askodoxPosList(d['complaints']))
                ListTile(
                  dense: true,
                  title: Text('${k['subject']}'),
                  subtitle: Text(askodoxCrmComplaintLabel('${k['status']}', te)),
                  onTap: () => context.push('/pos/${widget.businessId}/crm/complaint/${k['id']}'),
                ),
              const Divider(height: 28),
              Text(te ? 'Timeline' : 'Timeline', style: Theme.of(context).textTheme.titleSmall),
              for (final t in askodoxPosList(d['timeline']).take(40))
                ListTile(dense: true, title: Text('${t['text']}'), subtitle: Text('${askodoxCrmWhen(t['at'])} · ${t['kind']}')),
            ]),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Reports
class _CrmReports extends ConsumerStatefulWidget {
  const _CrmReports({required this.businessId});
  final String businessId;

  @override
  ConsumerState<_CrmReports> createState() => _CrmReportsState();
}

class _CrmReportsState extends ConsumerState<_CrmReports> {
  late String _from = '${askodoxPosToday().substring(0, 8)}01';
  late String _to = askodoxPosToday();
  late Future<AskodoxJson> _data = _load();

  Future<AskodoxJson> _load() => ref.read(askodoxPosRepositoryProvider).crmReport(widget.businessId, _from, _to);

  Future<void> _range() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
        context: context, firstDate: DateTime(now.year - 1), lastDate: now, initialDateRange: DateTimeRange(start: DateTime.parse(_from), end: DateTime.parse(_to)));
    if (picked == null || !mounted) return;
    setState(() {
      _from = askodoxPosToday(picked.start);
      _to = askodoxPosToday(picked.end);
      _data = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return FutureBuilder<AskodoxJson>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: () => setState(() => _data = _load()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final r = snap.data!;
        final fu = askodoxPosMap(r['followups']);
        final comp = askodoxPosMap(r['complaints']);
        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          OutlinedButton.icon(
              key: const Key('askodoxCrmReportRange'),
              onPressed: _range,
              icon: const Icon(Icons.date_range),
              label: Text('$_from → $_to')),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _CrmStat(te ? 'Leads' : 'Leads', '${r['leads'] ?? 0}'),
            _CrmStat(te ? 'Won' : 'Won', '${r['won'] ?? 0}'),
            _CrmStat(te ? 'Conversion' : 'Conversion', r['conversion_pct'] == null ? '—' : '${r['conversion_pct']}%'),
            _CrmStat(te ? 'Win కి రోజులు' : 'Days to win', r['avg_days_to_win'] == null ? '—' : '${r['avg_days_to_win']}'),
            _CrmStat(te ? 'Follow-ups అయినవి' : 'Follow-ups done', '${fu['done'] ?? 0}'),
            _CrmStat(te ? 'ఆలస్యమైనవి' : 'Overdue', '${fu['overdue'] ?? 0}'),
            _CrmStat(te ? 'Complaints' : 'Complaints', '${comp['solved'] ?? 0}/${comp['raised'] ?? 0}'),
            _CrmStat(te ? 'పరిష్కారానికి గంటలు' : 'Hours to solve', comp['avg_hours_to_solve'] == null ? '—' : '${comp['avg_hours_to_solve']}'),
          ]),
          const Divider(height: 24),
          Text(te ? 'Source వారీగా' : 'By source', style: Theme.of(context).textTheme.titleSmall),
          for (final s in askodoxPosList(r['by_source']))
            ListTile(
              dense: true,
              title: Text(askodoxCrmSourceLabel('${s['source']}', te)),
              trailing: Text('${s['leads']} · won ${s['won'] ?? 0}${s['win_rate_pct'] == null ? '' : ' (${s['win_rate_pct']}%)'}'),
            ),
          if (askodoxPosList(r['lost_reasons']).isNotEmpty) ...[
            Text(te ? 'ఎందుకు పోయాయి' : 'Why leads were lost', style: Theme.of(context).textTheme.titleSmall),
            for (final l in askodoxPosList(r['lost_reasons']))
              ListTile(dense: true, title: Text('${l['reason']}'), trailing: Text('${l['count']}')),
          ],
          Text(te ? 'ఎక్కువ కొన్న customers' : 'Top customers', style: Theme.of(context).textTheme.titleSmall),
          for (final c in askodoxPosList(r['top_customers']))
            ListTile(
              dense: true,
              title: Text('${c['name'] ?? ''}'),
              trailing: Text('${c['bills']} · ${askodoxPaise(askodoxPosInt(c['billed_paise']))}'),
              onTap: () => context.push('/pos/${widget.businessId}/crm/customer/${c['customer_id']}'),
            ),
          Text(te ? 'బాకీ ఉన్నవాళ్ళు' : 'Dues', style: Theme.of(context).textTheme.titleSmall),
          for (final c in askodoxPosList(r['dues']))
            ListTile(
              dense: true,
              title: Text('${c['name']}'),
              trailing: Text(askodoxPaise(askodoxPosInt(c['due_paise']))),
              onTap: () => context.push('/pos/${widget.businessId}/crm/customer/${c['customer_id']}'),
            ),
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('${r['basis'] ?? ''}', style: Theme.of(context).textTheme.bodySmall)),
        ]);
      },
    );
  }
}
