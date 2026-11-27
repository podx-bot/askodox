import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme/askodox_look.dart';
import '../../shared/widgets/estimate_note.dart';
import '../pos/data/pos_repository.dart';
import 'memberships_logic.dart';

/// Term memberships + attendance (owner 2026-11-27, design canvas gym screens): for every business that sells time by
/// the term -- a gym, a class, a pool, a library. Reminders and messages are DRAFTS the owner sends from his own
/// WhatsApp; a fee is a record of what the shop received.
final askodoxMembersProvider = FutureProvider.autoDispose.family<AskodoxJson, String>(
    (ref, shop) => ref.watch(askodoxPosRepositoryProvider).termMembers(shop));
final askodoxMembersAttendanceProvider = FutureProvider.autoDispose.family<AskodoxJson, String>(
    (ref, shop) => ref.watch(askodoxPosRepositoryProvider).termAttendance(shop));
final askodoxMembersReportProvider = FutureProvider.autoDispose.family<AskodoxJson, String>(
    (ref, shop) => ref.watch(askodoxPosRepositoryProvider).termReport(shop));
final askodoxMyMembershipsProvider = FutureProvider.autoDispose<List<AskodoxJson>>(
    (ref) => ref.watch(askodoxPosRepositoryProvider).myMemberships());

bool _te(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

void _say(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

String _problem(Object error, bool te) =>
    error is AskodoxPosException ? error.message(te) : (te ? 'ఇంటర్నెట్ చూసి మళ్ళీ నొక్కండి' : 'Check the internet and tap again');

Future<void> _openDraft(BuildContext context, Object? url) async {
  final te = _te(context);
  final link = Uri.tryParse('${url ?? ''}');
  final opened = link != null && link.hasScheme && await launchUrl(link, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) _say(context, te ? 'WhatsApp తెరవలేకపోయాం' : 'Could not open WhatsApp');
}

Widget _failed(Object error, bool te, VoidCallback again) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_problem(error, te), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: again, child: Text(te ? 'మళ్ళీ' : 'Try again')),
        ]),
      ),
    );

Widget _number(String label, Object? value, {Color color = AskodoxLook.text}) => Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(children: [
            Text('${askodoxTermInt(value)}',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color, fontFeatures: AskodoxLook.figures)),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted)),
          ]),
        ),
      ),
    );

const _draftNoteTe = 'ASKODOX డ్రాఫ్ట్ చేస్తుంది · మీరు పంపితేనే వెళ్తుంది';
const _draftNoteEn = 'ASKODOX drafts · it goes only when you send it';

Widget _draftNote(bool te) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(te ? _draftNoteTe : _draftNoteEn,
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted)),
    );

// ------------------------------------------------------------------------------------------------ members
class AskodoxMembersScreen extends ConsumerWidget {
  const AskodoxMembersScreen({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = _te(context);
    final state = ref.watch(askodoxMembersProvider(businessId));
    void reload() => ref.invalidate(askodoxMembersProvider(businessId));
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'సభ్యులు & హాజరు' : 'Members & attendance')),
      body: SafeArea(
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _failed(error, te, reload),
          data: (data) {
            final counts = askodoxPosMap(data['counts']);
            final ending = askodoxPosList(data['ending']);
            final members = askodoxPosList(data['members']);
            final terms = [for (final t in (data['terms'] is List ? data['terms'] as List : const [1, 3, 6, 12])) askodoxTermInt(t)];
            return ListView(key: const Key('askodoxMembers'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              Row(children: [
                _number(te ? 'సభ్యులు' : 'Members', counts['members']),
                const SizedBox(width: 8),
                _number(te ? 'ఈ నెల ముగిసేవి' : 'Ending this month', counts['ending_this_month'], color: AskodoxLook.accentText),
                const SizedBox(width: 8),
                _number(te ? 'ఫీజు రావాలి' : 'Fee to come', counts['fee_due'], color: AskodoxLook.accentText),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('askodoxMembersNew'),
                    onPressed: () async {
                      final added = await showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => AskodoxTermMemberSheet(businessId: businessId, terms: terms));
                      if (added == true) reload();
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(te ? 'కొత్త సభ్యుడు' : 'New member'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('askodoxMembersAttendance'),
                    onPressed: () => context.push('/biz/$businessId/members/attendance'),
                    icon: const Icon(Icons.how_to_reg_rounded),
                    label: Text(te ? 'ఈ రోజు హాజరు (${askodoxTermInt(counts['came_today'])})' : 'Today (${askodoxTermInt(counts['came_today'])})'),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('askodoxMembersReport'),
                  onPressed: () => context.push('/biz/$businessId/members/report'),
                  child: Text(te ? 'ఈ నెల రిపోర్ట్' : 'This month report'),
                ),
              ),
              if (ending.isNotEmpty) ...[
                Text(te ? 'ఫీజు ముగుస్తున్నవారు' : 'Fee ending',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                for (final m in ending) _row(context, ref, m, te, terms, reminder: true),
                const SizedBox(height: 12),
              ],
              Text(te ? 'అందరు సభ్యులు' : 'All members', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              if (members.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(te ? 'మొదటి సభ్యుడిని చేర్చండి. ముగింపు తేదీ ASKODOX లెక్కిస్తుంది.' : 'Add the first member. ASKODOX works out the end day.',
                      key: const Key('askodoxMembersEmpty'), textAlign: TextAlign.center),
                ),
              for (final m in members) _row(context, ref, m, te, terms),
              _draftNote(te),
              const SizedBox(height: 8),
              const AskodoxEstimateNote(),
            ]);
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, AskodoxJson m, bool te, List<int> terms, {bool reminder = false}) {
    final state = '${m['state'] ?? ''}';
    final id = '${m['id']}';
    return Card(
      key: ValueKey(reminder ? 'askodoxMemberEnding-$id' : 'askodoxMember-$id'),
      child: ListTile(
        title: Text('${m['name'] ?? ''}'),
        subtitle: Text('${askodoxTermStateText(state, askodoxTermInt(m['days_left']), te)} · ${askodoxDayText(m['end_date'])}'),
        trailing: reminder && m['whatsapp_url'] != null
            ? FilledButton(
                key: ValueKey('askodoxMemberRemind-$id'),
                onPressed: () => _openDraft(context, m['whatsapp_url']),
                child: Text(te ? 'రిమైండర్' : 'Remind'),
              )
            : Text(askodoxTermRupees(m['fee_paise']), style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: () async {
          final changed = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AskodoxTermRenewSheet(businessId: businessId, member: m, terms: terms));
          if (changed == true) ref.invalidate(askodoxMembersProvider(businessId));
        },
      ),
    );
  }
}

Widget _termChips(List<int> terms, int picked, bool te, ValueChanged<int> onPick, String keyPrefix) => Wrap(spacing: 8, children: [
      for (final t in terms)
        ChoiceChip(
          key: ValueKey('$keyPrefix-$t'),
          label: Text(askodoxTermMonthsText(t, te)),
          selected: picked == t,
          onSelected: (_) => onPick(t),
        ),
    ]);

/// New member: name, phone, the term, the fee -> the end day shows by itself.
class AskodoxTermMemberSheet extends ConsumerStatefulWidget {
  const AskodoxTermMemberSheet({super.key, required this.businessId, required this.terms});
  final String businessId;
  final List<int> terms;

  @override
  ConsumerState<AskodoxTermMemberSheet> createState() => _AskodoxTermMemberSheetState();
}

class _AskodoxTermMemberSheetState extends ConsumerState<AskodoxTermMemberSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _fee = TextEditingController();
  int _months = 1;
  bool _paid = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _fee.dispose();
    super.dispose();
  }

  Future<void> _save(bool te) async {
    final fee = askodoxTermPaise(_fee.text);
    if (_name.text.trim().isEmpty || fee <= 0) {
      _say(context, te ? 'పేరు, ఫీజు చెప్పండి' : 'Give the name and the fee');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).addTermMember(widget.businessId,
          {'name': _name.text.trim(), 'phone': _phone.text.trim(), 'months': _months, 'fee_paise': fee, 'paid': _paid});
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _say(context, _problem(error, te));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    final end = askodoxTermEnd(DateTime.now(), _months);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'కొత్త సభ్యుడు' : 'New member', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
              key: const Key('askodoxTermName'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: te ? 'పేరు' : 'Name')),
          const SizedBox(height: 8),
          TextField(
              key: const Key('askodoxTermPhone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: te ? 'ఫోన్ (రిమైండర్ కోసం)' : 'Phone (for the reminder)')),
          const SizedBox(height: 12),
          _termChips(widget.terms, _months, te, (t) => setState(() => _months = t), 'askodoxTermMonths'),
          const SizedBox(height: 8),
          TextField(
              key: const Key('askodoxTermFee'),
              controller: _fee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: te ? 'ఫీజు ₹' : 'Fee ₹')),
          const SizedBox(height: 8),
          Text('${te ? 'ముగింపు తేదీ' : 'Ends on'}: ${askodoxDayText(askodoxIsoDay(end))}',
              key: const Key('askodoxTermEnd'), style: const TextStyle(color: AskodoxLook.muted)),
          SwitchListTile(
            key: const Key('askodoxTermPaid'),
            contentPadding: EdgeInsets.zero,
            title: Text(te ? 'ఫీజు ఇప్పుడే అందింది' : 'The fee is received now'),
            value: _paid,
            onChanged: (v) => setState(() => _paid = v),
          ),
          FilledButton(
            key: const Key('askodoxTermSave'),
            onPressed: _busy ? null : () => _save(te),
            child: Text(te ? 'సేవ్ చేయి' : 'Save'),
          ),
        ]),
      ),
    );
  }
}

/// One member: fee received (the end day moves on), came today, stop.
class AskodoxTermRenewSheet extends ConsumerStatefulWidget {
  const AskodoxTermRenewSheet({super.key, required this.businessId, required this.member, required this.terms});
  final String businessId;
  final AskodoxJson member;
  final List<int> terms;

  @override
  ConsumerState<AskodoxTermRenewSheet> createState() => _AskodoxTermRenewSheetState();
}

class _AskodoxTermRenewSheetState extends ConsumerState<AskodoxTermRenewSheet> {
  late final TextEditingController _fee;
  late int _months;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final months = askodoxTermInt(widget.member['months']);
    _months = months < 1 ? 1 : (months > 36 ? 36 : months);
    final paise = askodoxTermInt(widget.member['fee_paise']);
    _fee = TextEditingController(text: paise % 100 == 0 ? '${paise ~/ 100}' : (paise / 100).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AskodoxPosRepository repo) work, String done) async {
    final te = _te(context);
    setState(() => _busy = true);
    try {
      await work(ref.read(askodoxPosRepositoryProvider));
      if (!mounted) return;
      _say(context, done);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _say(context, _problem(error, te));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    final id = '${widget.member['id']}';
    final stopped = '${widget.member['status']}' == 'stopped';
    final terms = {...widget.terms, _months}.toList()..sort();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.member['name'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text('${te ? 'ముగింపు' : 'Ends'}: ${askodoxDayText(widget.member['end_date'])}',
              style: const TextStyle(color: AskodoxLook.muted)),
          const SizedBox(height: 12),
          _termChips(terms, _months, te, (t) => setState(() => _months = t), 'askodoxRenewMonths'),
          const SizedBox(height: 8),
          TextField(
              key: const Key('askodoxRenewFee'),
              controller: _fee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: te ? 'అందిన ఫీజు ₹' : 'Fee received ₹')),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('askodoxRenewSave'),
            onPressed: _busy
                ? null
                : () {
                    final amount = askodoxTermPaise(_fee.text);
                    if (amount <= 0) {
                      _say(context, te ? 'ఫీజు చెప్పండి' : 'Give the fee');
                      return;
                    }
                    _run((repo) => repo.renewTermMember(widget.businessId, id, {'months': _months, 'amount_paise': amount}),
                        te ? 'ఫీజు నమోదైంది. ముగింపు తేదీ ముందుకు జరిగింది.' : 'Fee recorded. The end day moved on.');
                  },
            child: Text(te ? 'ఫీజు అందింది · రెన్యూ' : 'Fee received · renew'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('askodoxRenewCame'),
            onPressed: _busy
                ? null
                : () => _run((repo) => repo.termVisit(widget.businessId, id, true), te ? 'హాజరు పడింది' : 'Marked as came today'),
            child: Text(te ? 'ఈ రోజు వచ్చారు' : 'Came today'),
          ),
          TextButton(
            key: const Key('askodoxRenewStop'),
            onPressed: _busy
                ? null
                : () => _run((repo) => repo.termMemberStatus(widget.businessId, id, stopped ? 'active' : 'stopped'),
                    stopped ? (te ? 'మళ్ళీ చేర్చాం' : 'Active again') : (te ? 'ఆపాం' : 'Stopped')),
            child: Text(stopped ? (te ? 'మళ్ళీ చేర్చు' : 'Make active again') : (te ? 'ఈ సభ్యత్వం ఆపు' : 'Stop this membership')),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ attendance
class AskodoxMembersAttendanceScreen extends ConsumerWidget {
  const AskodoxMembersAttendanceScreen({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = _te(context);
    final state = ref.watch(askodoxMembersAttendanceProvider(businessId));
    void reload() => ref.invalidate(askodoxMembersAttendanceProvider(businessId));
    Future<void> mark(String id, bool came) async {
      try {
        await ref.read(askodoxPosRepositoryProvider).termVisit(businessId, id, came);
        reload();
      } catch (error) {
        if (context.mounted) _say(context, _problem(error, te));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఈ రోజు హాజరు' : 'Today\'s attendance')),
      body: SafeArea(
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _failed(error, te, reload),
          data: (data) {
            final came = askodoxPosList(data['came']);
            final waiting = askodoxPosList(data['waiting']);
            final absent = askodoxPosList(data['absent']);
            return ListView(key: const Key('askodoxAttendance'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              Row(children: [
                _number(te ? 'ఈ రోజు వచ్చినవారు' : 'Came today', data['came_count'], color: AskodoxLook.good),
                const SizedBox(width: 8),
                _number(te ? 'వారంగా దూరంగా ఉన్నవారు' : 'Away for a week', absent.length, color: AskodoxLook.accentText),
              ]),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Text(te ? 'ఈ రోజు కౌంటర్ కోడ్' : 'Today\'s counter code',
                        style: const TextStyle(fontSize: 13, color: AskodoxLook.muted)),
                    Text('${data['code'] ?? ''}',
                        key: const Key('askodoxAttendanceCode'),
                        style: const TextStyle(
                            fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 8, color: AskodoxLook.accentText,
                            fontFeatures: AskodoxLook.figures)),
                    Text(
                        te
                            ? 'సభ్యుడు తన ASKODOX లో "నా సభ్యత్వాలు" తెరిచి ఈ కోడ్ టైప్ చేస్తే హాజరు పడుతుంది. రోజూ మారుతుంది.'
                            : 'A member opens "My memberships" in ASKODOX and types this code. It changes every day.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted)),
                  ]),
                ),
              ),
              if (came.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(te ? 'వచ్చినవారు' : 'Came', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                for (final c in came)
                  ListTile(
                    key: ValueKey('askodoxCame-${c['member_id']}'),
                    dense: true,
                    leading: const Icon(Icons.check_circle_rounded, color: AskodoxLook.good),
                    title: Text('${c['name'] ?? ''}'),
                    trailing: TextButton(
                        onPressed: () => mark('${c['member_id']}', false), child: Text(te ? 'తీసేయి' : 'Undo')),
                  ),
              ],
              if (waiting.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(te ? 'నొక్కి హాజరు వేయండి' : 'Tap to mark', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final w in waiting)
                    ActionChip(
                        key: ValueKey('askodoxWaiting-${w['id']}'),
                        label: Text('${w['name'] ?? ''}'),
                        onPressed: () => mark('${w['id']}', true)),
                ]),
              ],
              if (absent.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(te ? 'వారం రోజులుగా దూరంగా ఉన్నవారు' : 'Away for a week',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                for (final a in absent)
                  Card(
                    key: ValueKey('askodoxAbsent-${a['id']}'),
                    child: ListTile(
                      title: Text('${a['name'] ?? ''}'),
                      subtitle: Text(te ? '${askodoxTermInt(a['days'])} రోజులు' : '${askodoxTermInt(a['days'])} days'),
                      trailing: '${a['whatsapp_url'] ?? ''}'.isEmpty
                          ? null
                          : OutlinedButton(
                              onPressed: () => _openDraft(context, a['whatsapp_url']), child: Text(te ? 'మెసేజ్' : 'Message')),
                    ),
                  ),
              ],
              _draftNote(te),
            ]);
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ report
class AskodoxMembersReportScreen extends ConsumerWidget {
  const AskodoxMembersReportScreen({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = _te(context);
    final state = ref.watch(askodoxMembersReportProvider(businessId));
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఈ నెల రిపోర్ట్' : 'This month report')),
      body: SafeArea(
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _failed(error, te, () => ref.invalidate(askodoxMembersReportProvider(businessId))),
          data: (data) {
            final weeks = [for (final w in (data['weeks_paise'] is List ? data['weeks_paise'] as List : const [])) askodoxTermInt(w)];
            final left = askodoxPosList(data['left_members']);
            return ListView(key: const Key('askodoxMembersReportList'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              Row(children: [
                _number(te ? 'కొత్త' : 'New', data['new'], color: AskodoxLook.good),
                const SizedBox(width: 8),
                _number(te ? 'రెన్యూ' : 'Renewed', data['renewed'], color: AskodoxLook.good),
                const SizedBox(width: 8),
                _number(te ? 'వదిలినవారు' : 'Left', data['left'], color: AskodoxLook.accentText),
              ]),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(te ? 'ఈ నెల వసూలైనది' : 'Collected this month',
                        style: const TextStyle(fontSize: 13, color: AskodoxLook.muted)),
                    Text(askodoxTermRupees(data['collected_paise']),
                        key: const Key('askodoxMembersCollected'),
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: AskodoxLook.figures)),
                    const SizedBox(height: 8),
                    for (var i = 0; i < weeks.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(te ? 'వారం ${i + 1}' : 'Week ${i + 1}', style: const TextStyle(color: AskodoxLook.muted)),
                          Text(askodoxTermRupees(weeks[i]), style: const TextStyle(fontFeatures: AskodoxLook.figures)),
                        ]),
                      ),
                  ]),
                ),
              ),
              if (left.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(te ? 'వదిలినవారికి "తిరిగి రండి" మెసేజ్' : '"Come back" message for those who left',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                for (final m in left)
                  Card(
                    key: ValueKey('askodoxLeft-${m['id']}'),
                    child: ListTile(
                      title: Text('${m['name'] ?? ''}'),
                      subtitle: Text(askodoxDayText(m['end_date'])),
                      trailing: '${m['whatsapp_url'] ?? ''}'.isEmpty
                          ? null
                          : OutlinedButton(
                              onPressed: () => _openDraft(context, m['whatsapp_url']),
                              child: Text(te ? 'డ్రాఫ్ట్ చూడు' : 'See the draft')),
                    ),
                  ),
              ],
              _draftNote(te),
              const SizedBox(height: 8),
              const AskodoxEstimateNote(),
            ]);
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ the member's own
class AskodoxMyMembershipsScreen extends ConsumerStatefulWidget {
  const AskodoxMyMembershipsScreen({super.key});

  @override
  ConsumerState<AskodoxMyMembershipsScreen> createState() => _AskodoxMyMembershipsScreenState();
}

class _AskodoxMyMembershipsScreenState extends ConsumerState<AskodoxMyMembershipsScreen> {
  final _codes = <String, TextEditingController>{};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _codes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _checkIn(String shop, bool te) async {
    final code = _codes[shop]?.text.trim() ?? '';
    if (code.length != 4) {
      _say(context, te ? 'కౌంటర్ దగ్గర ఉన్న 4 అంకెల కోడ్ టైప్ చేయండి' : 'Type the 4-digit code shown at the counter');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).membershipCheckIn(shop, code);
      if (!mounted) return;
      _say(context, te ? 'హాజరు పడింది' : 'You are marked as came today');
      ref.invalidate(askodoxMyMembershipsProvider);
    } catch (error) {
      if (mounted) _say(context, _problem(error, te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    final state = ref.watch(askodoxMyMembershipsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'నా సభ్యత్వాలు' : 'My memberships')),
      body: SafeArea(
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _failed(error, te, () => ref.invalidate(askodoxMyMembershipsProvider)),
          data: (rows) {
            if (rows.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                      te
                          ? 'జిమ్, క్లాస్ లాంటి చోట మీ నంబర్‌తో చేరితే మీ సభ్యత్వం ఇక్కడ కనిపిస్తుంది.'
                          : 'When a gym or a class adds you with your number, your membership shows here.',
                      key: const Key('askodoxMyMembershipsEmpty'),
                      textAlign: TextAlign.center),
                ),
              );
            }
            return ListView(key: const Key('askodoxMyMemberships'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              for (final m in rows) _card(m, te),
            ]);
          },
        ),
      ),
    );
  }

  Widget _card(AskodoxJson m, bool te) {
    final shop = '${m['business_id']}';
    final days = askodoxTermInt(m['days_left']);
    final came = m['came_today'] == true;
    final code = _codes.putIfAbsent(shop, TextEditingController.new);
    return Card(
      key: ValueKey('askodoxMyMembership-$shop'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${m['shop'] ?? ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text(
              days >= 0
                  ? (te ? '${askodoxDayText(m['end_date'])} వరకు · $days రోజులు మిగిలాయి' : 'Until ${askodoxDayText(m['end_date'])} · $days days left')
                  : (te ? '${askodoxDayText(m['end_date'])} తో ముగిసింది' : 'Ended on ${askodoxDayText(m['end_date'])}'),
              style: const TextStyle(color: AskodoxLook.muted)),
          const SizedBox(height: 10),
          if (came)
            Row(children: [
              const Icon(Icons.check_circle_rounded, color: AskodoxLook.good),
              const SizedBox(width: 8),
              Text(te ? 'ఈ రోజు హాజరు పడింది' : 'Marked as came today'),
            ])
          else
            Row(children: [
              Expanded(
                child: TextField(
                  key: ValueKey('askodoxMyMembershipCode-$shop'),
                  controller: code,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: InputDecoration(labelText: te ? 'కౌంటర్ కోడ్' : 'Counter code', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: ValueKey('askodoxMyMembershipCame-$shop'),
                onPressed: _busy ? null : () => _checkIn(shop, te),
                child: Text(te ? 'నేను వచ్చాను' : 'I came'),
              ),
            ]),
        ]),
      ),
    );
  }
}
