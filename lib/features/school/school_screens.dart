import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme/askodox_look.dart';
import '../../shared/widgets/estimate_note.dart';
import '../pos/data/pos_repository.dart';
import 'school_logic.dart';

/// School / tuition / college register (owner 2026-11-28, design canvas "ఈరోజు చూడాల్సినవి"): ONE page that shows only
/// the problems of today (class not marked, absent in a row, someone not on the parent's list took a child, a sick
/// child to ask after), and under it the classes. Every message is a DRAFT the owner sends from his own WhatsApp.
final askodoxSchoolTodayProvider = FutureProvider.autoDispose.family<AskodoxJson, String>(
    (ref, shop) => ref.watch(askodoxPosRepositoryProvider).schoolToday(shop));
final askodoxSchoolClassesProvider = FutureProvider.autoDispose.family<AskodoxJson, String>(
    (ref, shop) => ref.watch(askodoxPosRepositoryProvider).schoolClasses(shop));
final askodoxSchoolReportProvider = FutureProvider.autoDispose.family<AskodoxJson, String>(
    (ref, shop) => ref.watch(askodoxPosRepositoryProvider).schoolReport(shop));

bool _te(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

void _say(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

String _problem(Object error, bool te) =>
    error is AskodoxPosException ? error.message(te) : (te ? 'ఇంటర్నెట్ చూసి మళ్ళీ నొక్కండి' : 'Check the internet and tap again');

Future<void> _open(BuildContext context, Object? url) async {
  final te = _te(context);
  final link = Uri.tryParse('${url ?? ''}');
  final opened = link != null && link.hasScheme && await launchUrl(link, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) _say(context, te ? 'తెరవలేకపోయాం' : 'Could not open it');
}

class AskodoxSchoolScreen extends ConsumerWidget {
  const AskodoxSchoolScreen({super.key, required this.businessId});
  final String businessId;

  void _reload(WidgetRef ref) {
    ref.invalidate(askodoxSchoolTodayProvider(businessId));
    ref.invalidate(askodoxSchoolClassesProvider(businessId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = _te(context);
    final today = ref.watch(askodoxSchoolTodayProvider(businessId));
    final classes = ref.watch(askodoxSchoolClassesProvider(businessId));
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'క్లాసులు & హాజరు' : 'Classes & attendance')),
      body: SafeArea(
        child: today.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_problem(error, te), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => _reload(ref), child: Text(te ? 'మళ్ళీ' : 'Try again')),
            ]),
          )),
          data: (data) {
            final problems = askodoxPosList(data['problems']);
            final list = classes.valueOrNull;
            final classRows = askodoxPosList(list?['classes']);
            return ListView(key: const Key('askodoxSchool'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              Text(te ? 'ఈరోజు చూడాల్సినవి' : 'To look at today', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (problems.isEmpty)
                Card(
                  key: const Key('askodoxSchoolAllClear'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        classRows.isEmpty
                            ? (te ? 'మొదట క్లాస్ చేర్చండి, తర్వాత పిల్లలను.' : 'Add a class first, then the students.')
                            : (te ? 'ఈరోజు చూడాల్సిన సమస్య ఏదీ లేదు.' : 'Nothing needs you today.'),
                        style: const TextStyle(color: AskodoxLook.good, fontWeight: FontWeight.w700)),
                  ),
                ),
              for (final p in problems) _problemCard(context, p, te, ref),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: Text(te ? 'క్లాసులు' : 'Classes', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                TextButton.icon(
                  key: const Key('askodoxSchoolAddClass'),
                  onPressed: () async {
                    final ok = await showModalBottomSheet<bool>(
                        context: context, isScrollControlled: true, builder: (_) => _ClassSheet(businessId: businessId));
                    if (ok == true) _reload(ref);
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(te ? 'క్లాస్' : 'Class'),
                ),
              ]),
              for (final c in classRows) _classTile(context, ref, c, te),
              const SizedBox(height: 12),
              const _DraftNote(),
              const SizedBox(height: 8),
              const AskodoxEstimateNote(),
            ]);
          },
        ),
      ),
    );
  }

  Widget _problemCard(BuildContext context, AskodoxJson p, bool te, WidgetRef ref) {
    final key = '${p['key']}';
    final items = askodoxPosList(p['items']);
    return Card(
      key: ValueKey('askodoxSchoolProblem-$key'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${askodoxSchoolProblemTitle(key, te)} · ${askodoxSchoolInt(p['count'])}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: AskodoxLook.accentText)),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(child: Text(askodoxSchoolItemText(key, item, te))),
                if (item['whatsapp_url'] != null && '${item['whatsapp_url']}'.isNotEmpty)
                  TextButton(onPressed: () => _open(context, item['whatsapp_url']), child: Text(te ? 'పంపు' : 'Send')),
                if (item['call_parent'] != null && '${item['call_parent']}'.isNotEmpty)
                  TextButton(onPressed: () => _open(context, item['call_parent']), child: Text(te ? 'ఫోన్' : 'Call')),
                if (key == 'health_follow_up' && item['health_id'] != null)
                  TextButton(
                    key: ValueKey('askodoxSchoolRecovered-${item['health_id']}'),
                    onPressed: () async {
                      try {
                        await ref.read(askodoxPosRepositoryProvider).schoolRecovered(businessId, '${item['health_id']}');
                        _reload(ref);
                      } catch (error) {
                        if (context.mounted) _say(context, _problem(error, te));
                      }
                    },
                    child: Text(te ? 'బాగుంది' : 'Fine now'),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _classTile(BuildContext context, WidgetRef ref, AskodoxJson c, bool te) {
    final students = askodoxPosList(c['students']);
    final id = '${c['id']}';
    return Card(
      key: ValueKey('askodoxSchoolClass-$id'),
      child: ExpansionTile(
        title: Text('${c['name'] ?? ''}'),
        subtitle: Text(
            '${students.length} ${te ? 'మంది' : 'students'} · ${c['marked_today'] == true ? (te ? 'ఈరోజు హాజరు వేశారు' : 'marked today') : (te ? 'హాజరు వేయలేదు' : 'not marked')}'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  key: ValueKey('askodoxSchoolMark-$id'),
                  onPressed: students.isEmpty
                      ? null
                      : () async {
                          final ok = await showModalBottomSheet<bool>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => _RegisterSheet(businessId: businessId, classRow: c));
                          if (ok == true) _reload(ref);
                        },
                  icon: const Icon(Icons.how_to_reg_rounded),
                  label: Text(te ? 'హాజరు వేయి' : 'Mark today'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: ValueKey('askodoxSchoolAddStudent-$id'),
                onPressed: () async {
                  final ok = await showModalBottomSheet<bool>(
                      context: context, isScrollControlled: true, builder: (_) => _StudentSheet(businessId: businessId, classId: id));
                  if (ok == true) _reload(ref);
                },
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(te ? 'విద్యార్థి' : 'Student'),
              ),
            ]),
          ),
          for (final s in students)
            ListTile(
              key: ValueKey('askodoxSchoolStudent-${s['id']}'),
              title: Text('${s['name'] ?? ''}'),
              subtitle: Text('${s['parent_name'] ?? ''}${s['hostel'] == true ? (te ? ' · హాస్టల్' : ' · hostel') : ''}'),
              trailing: const Icon(Icons.more_horiz_rounded),
              onTap: () async {
                final ok = await showModalBottomSheet<bool>(
                    context: context, isScrollControlled: true, builder: (_) => _StudentActionSheet(businessId: businessId, student: s));
                if (ok == true) _reload(ref);
              },
            ),
        ],
      ),
    );
  }
}

class _DraftNote extends StatelessWidget {
  const _DraftNote();

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    return Text(te ? 'ASKODOX డ్రాఫ్ట్ చేస్తుంది · మీరు పంపితేనే వెళ్తుంది' : 'ASKODOX drafts · it goes only when you send it',
        textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted));
  }
}

class _ClassSheet extends ConsumerStatefulWidget {
  const _ClassSheet({required this.businessId});
  final String businessId;

  @override
  ConsumerState<_ClassSheet> createState() => _ClassSheetState();
}

class _ClassSheetState extends ConsumerState<_ClassSheet> {
  final _name = TextEditingController();
  final _teacher = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    super.dispose();
  }

  Future<void> _save(bool te) async {
    if (_name.text.trim().isEmpty) {
      _say(context, te ? 'క్లాస్ పేరు చెప్పండి' : 'Give the class name');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).schoolAddClass(widget.businessId, {'name': _name.text.trim(), 'teacher': _teacher.text.trim()});
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
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'కొత్త క్లాస్' : 'New class', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(key: const Key('askodoxSchoolClassName'), controller: _name, decoration: InputDecoration(labelText: te ? 'క్లాస్ (ఉదా: 5-A)' : 'Class (e.g. 5-A)')),
          const SizedBox(height: 8),
          TextField(key: const Key('askodoxSchoolTeacher'), controller: _teacher, decoration: InputDecoration(labelText: te ? 'టీచర్' : 'Teacher')),
          const SizedBox(height: 12),
          FilledButton(key: const Key('askodoxSchoolClassSave'), onPressed: _busy ? null : () => _save(te), child: Text(te ? 'సేవ్ చేయి' : 'Save')),
        ]),
      ),
    );
  }
}

class _StudentSheet extends ConsumerStatefulWidget {
  const _StudentSheet({required this.businessId, required this.classId});
  final String businessId;
  final String classId;

  @override
  ConsumerState<_StudentSheet> createState() => _StudentSheetState();
}

class _StudentSheetState extends ConsumerState<_StudentSheet> {
  final _name = TextEditingController();
  final _parent = TextEditingController();
  final _phone = TextEditingController();
  final _pickup = TextEditingController();
  bool _hostel = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _parent.dispose();
    _phone.dispose();
    _pickup.dispose();
    super.dispose();
  }

  Future<void> _save(bool te) async {
    if (_name.text.trim().isEmpty) {
      _say(context, te ? 'పేరు చెప్పండి' : 'Give the name');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).schoolAddStudent(widget.businessId, {
        'class_id': widget.classId,
        'name': _name.text.trim(),
        'parent_name': _parent.text.trim(),
        'parent_phone': _phone.text.trim(),
        'hostel': _hostel,
        'pickups': [
          for (final n in _pickup.text.split(',')) if (n.trim().isNotEmpty) {'name': n.trim()}
        ],
      });
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
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'కొత్త విద్యార్థి' : 'New student', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(key: const Key('askodoxSchoolStudentName'), controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: te ? 'పేరు' : 'Name')),
          const SizedBox(height: 8),
          TextField(key: const Key('askodoxSchoolParentName'), controller: _parent, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: te ? 'తల్లి / తండ్రి పేరు' : 'Parent name')),
          const SizedBox(height: 8),
          TextField(key: const Key('askodoxSchoolParentPhone'), controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: te ? 'తల్లిదండ్రుల ఫోన్' : 'Parent phone')),
          const SizedBox(height: 8),
          TextField(
              key: const Key('askodoxSchoolPickups'),
              controller: _pickup,
              decoration: InputDecoration(
                  labelText: te ? 'తీసుకెళ్ళేవారి పేర్లు (కామాతో)' : 'Who may take the child (commas)',
                  helperText: te ? 'తల్లిదండ్రులు ఇచ్చిన పేర్లు మాత్రమే' : 'Only names the parent gave')),
          SwitchListTile(key: const Key('askodoxSchoolHostel'), contentPadding: EdgeInsets.zero, title: Text(te ? 'హాస్టల్ లో ఉంటాడు/ఉంటుంది' : 'Stays in the hostel'), value: _hostel, onChanged: (v) => setState(() => _hostel = v)),
          FilledButton(key: const Key('askodoxSchoolStudentSave'), onPressed: _busy ? null : () => _save(te), child: Text(te ? 'సేవ్ చేయి' : 'Save')),
        ]),
      ),
    );
  }
}

/// Everyone is present; tap the ones who did not come, then save.
class _RegisterSheet extends ConsumerStatefulWidget {
  const _RegisterSheet({required this.businessId, required this.classRow});
  final String businessId;
  final AskodoxJson classRow;

  @override
  ConsumerState<_RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends ConsumerState<_RegisterSheet> {
  final Set<String> _absent = {};
  bool _busy = false;

  Future<void> _save(bool te) async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(askodoxPosRepositoryProvider).schoolRegister(widget.businessId, '${widget.classRow['id']}', _absent.toList());
      if (mounted) {
        _say(context, askodoxSchoolSavedText(askodoxSchoolInt(result['present']), askodoxSchoolInt(result['absent']), te));
        Navigator.of(context).pop(true);
      }
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
    final students = askodoxPosList(widget.classRow['students']);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.classRow['name']} · ${te ? 'ఈరోజు హాజరు' : 'Today'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(te ? 'రానివారిని మాత్రమే నొక్కండి' : 'Tap only those who did not come', style: const TextStyle(color: AskodoxLook.muted)),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final s in students)
                CheckboxListTile(
                  key: ValueKey('askodoxSchoolAbsent-${s['id']}'),
                  title: Text('${s['name']}'),
                  subtitle: Text(_absent.contains('${s['id']}') ? (te ? 'రాలేదు' : 'Absent') : (te ? 'వచ్చారు' : 'Present')),
                  value: _absent.contains('${s['id']}'),
                  onChanged: (v) => setState(() => v == true ? _absent.add('${s['id']}') : _absent.remove('${s['id']}')),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          FilledButton(key: const Key('askodoxSchoolRegisterSave'), onPressed: _busy ? null : () => _save(te), child: Text(te ? 'సేవ్ చేయి' : 'Save')),
        ]),
      ),
    );
  }
}

/// One student: out at the gate (who takes the child) or into the health room.
class _StudentActionSheet extends ConsumerStatefulWidget {
  const _StudentActionSheet({required this.businessId, required this.student});
  final String businessId;
  final AskodoxJson student;

  @override
  ConsumerState<_StudentActionSheet> createState() => _StudentActionSheetState();
}

class _StudentActionSheetState extends ConsumerState<_StudentActionSheet> {
  final _who = TextEditingController();
  final _complaint = TextEditingController();
  String _kind = 'pickup';
  String _outcome = 'room';
  bool _busy = false;

  @override
  void dispose() {
    _who.dispose();
    _complaint.dispose();
    super.dispose();
  }

  Future<void> _gate(bool te) async {
    if (_who.text.trim().isEmpty) {
      _say(context, te ? 'ఎవరు తీసుకెళ్తున్నారో చెప్పండి' : 'Say who is taking the child');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(askodoxPosRepositoryProvider).schoolGate(widget.businessId, '${widget.student['id']}', {'kind': _kind, 'who_name': _who.text.trim()});
      if (!mounted) return;
      if (result['listed'] == false) {
        await _warn(result, te);
      } else {
        _say(context, te ? 'నమోదైంది' : 'Noted');
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _say(context, _problem(error, te));
      }
    }
  }

  Future<void> _warn(AskodoxJson result, bool te) => showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          key: const Key('askodoxSchoolUnlisted'),
          title: Text(te ? 'జాబితాలో లేరు' : 'Not on the list'),
          content: Text(te ? 'ఈ పేరు తల్లిదండ్రులు ఇచ్చిన జాబితాలో లేదు. పిల్లను పంపే ముందు తల్లిదండ్రులకు ఫోన్ చేయండి.' : 'This name is not on the parent\'s list. Call the parent before the child leaves.'),
          actions: [
            if (result['call_parent'] != null)
              TextButton(onPressed: () => _open(dialog, result['call_parent']), child: Text(te ? 'ఫోన్ చేయి' : 'Call parent')),
            TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(te ? 'సరే' : 'OK')),
          ],
        ),
      );

  Future<void> _sick(bool te) async {
    if (_complaint.text.trim().isEmpty) {
      _say(context, te ? 'ఏమైందో చెప్పండి' : 'Say what is wrong');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).schoolSick(widget.businessId, '${widget.student['id']}', {'complaint': _complaint.text.trim(), 'outcome': _outcome});
      if (mounted) {
        _say(context, te ? 'నమోదైంది' : 'Noted');
        Navigator.of(context).pop(true);
      }
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
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.student['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(te ? 'గేట్: బయటకు' : 'Gate: going out', style: const TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            for (final k in const ['pickup', 'early'])
              ChoiceChip(
                key: ValueKey('askodoxSchoolGateKind-$k'),
                label: Text(askodoxSchoolGateKindText(k, te)),
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ]),
          TextField(key: const Key('askodoxSchoolGateWho'), controller: _who, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: te ? 'ఎవరు తీసుకెళ్తున్నారు' : 'Who is taking the child')),
          const SizedBox(height: 8),
          FilledButton(key: const Key('askodoxSchoolGateSave'), onPressed: _busy ? null : () => _gate(te), child: Text(te ? 'బయటకు పంపు' : 'Let out')),
          const Divider(height: 28),
          Text(te ? 'హెల్త్ రూమ్' : 'Health room', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextField(key: const Key('askodoxSchoolSickWhat'), controller: _complaint, decoration: InputDecoration(labelText: te ? 'ఏమైంది (ఉదా: జ్వరం)' : 'What is wrong (e.g. fever)')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final o in const ['room', 'home', 'hospital'])
              ChoiceChip(
                key: ValueKey('askodoxSchoolOutcome-$o'),
                label: Text(askodoxSchoolOutcomeText(o, te)),
                selected: _outcome == o,
                onSelected: (_) => setState(() => _outcome = o),
              ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton(key: const Key('askodoxSchoolSickSave'), onPressed: _busy ? null : () => _sick(te), child: Text(te ? 'నమోదు చేయి' : 'Save')),
        ]),
      ),
    );
  }
}
