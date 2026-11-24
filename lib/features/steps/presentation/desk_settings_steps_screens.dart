import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/my_payment_alerts_screen.dart' show askodoxStaffRoleLabel;
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_desk_manage_screens.dart' show askodoxDeskSteps;
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 15): the order desk settings `/desk/:id/settings`. Top = ONE question (who hears
/// each step of an order), middle = ONE list (four steps, tap = pick the people), bottom = ONE big button (the staff page).
/// Table asks (water / gravy / the bill ...) and the welcome words are two more small screens reached from the menu ⋮; the
/// old page stays at `?full=1`.
class AskodoxDeskSettingsStepsScreen extends ConsumerStatefulWidget {
  const AskodoxDeskSettingsStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxDeskSettingsStepsScreen> createState() => _DeskSettingsState();
}

class _DeskSettingsState extends ConsumerState<AskodoxDeskSettingsStepsScreen> {
  AskodoxJson? _data;
  Object? _error;
  List<AskodoxJson> _quick = const [];
  AskodoxJson? _welcome;
  String _view = 'main'; // main / table / welcome
  final _custom = TextEditingController();
  final _hello = TextEditingController();
  final _again = TextEditingController();
  final _thanks = TextEditingController();
  bool _busy = false;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadWelcome());
  }

  @override
  void dispose() {
    _custom.dispose();
    _hello.dispose();
    _again.dispose();
    _thanks.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _repo.deskSettings(widget.businessId);
      final q = await _repo.deskRequestSettings(widget.businessId);
      if (mounted) {
        setState(() {
          _data = d;
          _quick = askodoxPosList(q['requests']);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _data == null) setState(() => _error = e);
    }
  }

  Future<void> _loadWelcome() async {
    try {
      final w = await _repo.welcomeSettings(widget.businessId);
      if (!mounted) return;
      setState(() {
        _welcome = w;
        _hello.text = '${w['hello'] ?? ''}';
        _again.text = '${w['again'] ?? ''}';
        _thanks.text = '${w['thanks'] ?? ''}';
      });
    } catch (_) {}
  }

  Future<void> _guard(Future<Object?> Function() action) async {
    try {
      await action();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    }
  }

  Future<void> _toggle(String step, String id, bool on) => _guard(() async {
        final routing = askodoxPosMap(_data?['routing']);
        final now = <String>{for (final x in (routing[step] as List? ?? const [])) '$x'};
        on ? now.add(id) : now.remove(id);
        final d = await _repo.deskSettingsSave(widget.businessId, routing: {step: now.toList()});
        if (mounted) setState(() => _data = d);
        return null;
      });

  Future<void> _saveQuick({List<String>? off, List<AskodoxJson>? custom}) => _guard(() async {
        final q = await _repo.deskRequestSettingsSave(widget.businessId, off: off, custom: custom);
        if (mounted) setState(() => _quick = askodoxPosList(q['requests']));
        return null;
      });

  List<String> get _offKeys => [for (final r in _quick) if (r['custom'] != true && r['enabled'] != true) '${r['key']}'];
  List<AskodoxJson> get _customRows => [for (final r in _quick) if (r['custom'] == true) {'key': r['key'], 'en': r['en'], 'te': r['te']}];

  Future<void> _addQuick() async {
    final text = _custom.text.trim();
    if (text.isEmpty) return;
    _custom.clear();
    await _saveQuick(custom: [..._customRows, {'en': text, 'te': text}]);
  }

  Future<void> _saveWelcome({bool? enabled}) async {
    setState(() => _busy = true);
    await _guard(() async {
      final w = await _repo.saveWelcome(widget.businessId, {
        if (enabled != null) 'enabled': enabled,
        'hello': _hello.text.trim(),
        'again': _again.text.trim(),
        'thanks': _thanks.text.trim(),
      });
      if (mounted) {
        setState(() => _welcome = w);
        askodoxPosSnack(context, _te ? 'సేవ్ అయింది ✓' : 'Saved ✓');
      }
      return null;
    });
    if (mounted) setState(() => _busy = false);
  }

  List<String> _chosenNames(String step, List<AskodoxJson> people, AskodoxJson routing) {
    final chosen = ((routing[step] as List?) ?? const []).map((e) => '$e').toSet();
    return [
      for (final p in people)
        if (chosen.contains('${p['id']}')) p['you'] == true ? (_te ? 'మీరు' : 'You') : '${p['label']}',
    ];
  }

  Future<void> _pickPeople((String, String, String) step, List<AskodoxJson> people) async {
    final te = _te;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final chosen = ((askodoxPosMap(_data?['routing'])[step.$1] as List?) ?? const []).map((e) => '$e').toSet();
        return SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Text(te ? step.$3 : step.$2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            Text(te ? 'ఎవరినీ ఎంచుకోకపోతే ఆ పాత్ర ఉన్నవాళ్లకి వెళ్తుంది.' : 'Choose nobody and the people of that role are told.',
                style: const TextStyle(color: askodoxStepMuted)),
            const SizedBox(height: 6),
            for (final p in people)
              CheckboxListTile(
                key: Key('askodoxDeskStepsRoute-${step.$1}-${p['id']}'),
                contentPadding: EdgeInsets.zero,
                value: chosen.contains('${p['id']}'),
                title: Text(p['you'] == true ? (te ? 'మీరు' : 'You') : '${p['label']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(askodoxStaffRoleLabel('${p['role']}', te)),
                onChanged: (v) async {
                  await _toggle(step.$1, '${p['id']}', v ?? false);
                  setSheet(() {});
                },
              ),
          ]),
        );
      }),
    );
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    return [
      if (_view != 'main')
        AskodoxStepMore('askodoxDeskStepsMoreAlerts', te ? 'ఏ స్టెప్ ఎవరికి' : 'Who hears each step', Icons.notifications_active_rounded,
            () => setState(() => _view = 'main')),
      if (_view != 'table')
        AskodoxStepMore('askodoxDeskStepsMoreTable', te ? 'టేబుల్ దగ్గర అడిగేవి' : 'What a table can ask for', Icons.room_service_outlined,
            () => setState(() => _view = 'table')),
      if (_view != 'welcome')
        AskodoxStepMore('askodoxDeskStepsMoreWelcome', te ? 'స్వాగతం / ధన్యవాదాలు మాటలు' : 'Welcome / thank-you words', Icons.waving_hand_outlined,
            () => setState(() => _view = 'welcome')),
      AskodoxStepMore('askodoxDeskStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
          () => context.push('/desk/${widget.businessId}/settings?full=1')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'ఆర్డర్ అలర్ట్స్' : 'Order alerts';
    if (_error != null) {
      return AskodoxStepScaffold(
        title: title,
        body: AskodoxPosError(error: _error!, onRetry: _load),
      );
    }
    if (_data == null) {
      return AskodoxStepScaffold(title: title, body: const Center(child: CircularProgressIndicator()));
    }
    if (_view == 'table') return _table(title);
    if (_view == 'welcome') return _welcomeView(title);
    final people = askodoxPosList(_data?['people']);
    final routing = askodoxPosMap(_data?['routing']);
    return AskodoxStepScaffold(
      key: const Key('askodoxDeskSettingsSteps'),
      title: title,
      question: te ? 'ఏ స్టెప్ ఎవరికి వినిపించాలి?' : 'Who hears each step?',
      hint: te ? 'ఎవరినీ ఎంచుకోకపోతే ఆ పాత్ర ఉన్నవాళ్లకి (మీకు కూడా) వెళ్తుంది.' : 'Choose nobody and the people of that role (and you) are told.',
      more: _more(),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        for (final step in askodoxDeskSteps)
          Builder(builder: (context) {
            final names = _chosenNames(step.$1, people, routing);
            return AskodoxStepPersonRow(
              key: Key('askodoxDeskStepsPick-${step.$1}'),
              name: te ? step.$3 : step.$2,
              sub: names.isEmpty ? (te ? 'పాత్ర ప్రకారం' : 'By role') : names.join(', '),
              amount: names.isEmpty ? (te ? 'పాత్ర' : 'Role') : '${names.length}',
              amountColor: names.isEmpty ? askodoxStepMuted : askodoxStepGreen,
              onTap: () => _pickPeople(step, people),
            );
          }),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxDeskStepsStaff'),
        label: te ? 'సిబ్బంది' : 'Staff',
        icon: Icons.people_alt_outlined,
        onPressed: () async {
          await context.push('/pos/${widget.businessId}/staff');
          if (mounted) await _load();
        },
      ),
    );
  }

  Widget _table(String title) {
    final te = _te;
    return AskodoxStepScaffold(
      key: const Key('askodoxDeskStepsTable'),
      title: title,
      question: te ? 'టేబుల్ దగ్గర ఏవి అడగవచ్చు?' : 'What can a table ask for?',
      hint: te
          ? 'ఆర్డర్ అంగీకరించాక కస్టమర్ నీళ్లు, గ్రేవీ, బిల్ లాంటివి అడుగుతారు. వెయిటర్‌కి టేబుల్ పేరుతో వెళ్తుంది.'
          : 'After you accept the order the customer can ask for water, gravy, the bill... The waiter gets it with the table name.',
      onBack: () => setState(() => _view = 'main'),
      more: _more(),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        for (final r in _quick)
          if (r['custom'] != true)
            SwitchListTile(
              key: Key('askodoxDeskStepsReq-${r['key']}'),
              contentPadding: EdgeInsets.zero,
              value: r['enabled'] == true,
              title: Text(te ? '${r['te']}' : '${r['en']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              onChanged: (v) {
                final off = _offKeys.toSet();
                v ? off.remove('${r['key']}') : off.add('${r['key']}');
                _saveQuick(off: off.toList());
              },
            )
          else
            ListTile(
              key: Key('askodoxDeskStepsReq-${r['key']}'),
              contentPadding: EdgeInsets.zero,
              title: Text('${r['en']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: IconButton(
                  tooltip: te ? 'తీసేయి' : 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _saveQuick(custom: [for (final c in _customRows) if (c['key'] != r['key']) c])),
            ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('askodoxDeskStepsReqAdd'),
          controller: _custom,
          onSubmitted: (_) => _addQuick(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: te ? 'మీ సొంతది చేర్చండి (ఉదా: అప్పడం)' : 'Add your own (e.g. Papad)',
            suffixIcon: IconButton(key: const Key('askodoxDeskStepsReqAddBtn'), icon: const Icon(Icons.add), onPressed: _addQuick),
          ),
        ),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxDeskStepsTableDone'),
        label: te ? 'సరే' : 'Done',
        icon: Icons.check_rounded,
        onPressed: () => setState(() => _view = 'main'),
      ),
    );
  }

  Widget _welcomeView(String title) {
    final te = _te;
    final w = _welcome;
    final defaults = askodoxPosMap(w?['defaults']);
    final on = w?['enabled'] == true;
    Widget box(String key, TextEditingController c, String label) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(
            key: Key('askodoxDeskStepsWelcome-$key'),
            controller: c,
            enabled: on,
            maxLength: 160,
            decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: label,
                hintText: '${defaults[key] ?? ''}',
                hintMaxLines: 2,
                counterText: ''),
          ),
        );
    return AskodoxStepScaffold(
      key: const Key('askodoxDeskStepsWelcome'),
      title: title,
      question: te ? 'కస్టమర్‌కి ఏం చెప్పాలి?' : 'What do you say to the customer?',
      hint: te ? '{name} = కస్టమర్ పేరు, {shop} = షాప్ పేరు. ఖాళీ = బూడిద రంగు మాట.' : '{name} = the customer, {shop} = your shop. Empty = the grey text.',
      onBack: () => setState(() => _view = 'main'),
      more: _more(),
      body: w == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
              SwitchListTile(
                key: const Key('askodoxDeskStepsWelcomeOn'),
                contentPadding: EdgeInsets.zero,
                value: on,
                title: Text(te ? '🙏 స్వాగతం / ధన్యవాదాలు' : '🙏 Welcome / thank you', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(te ? 'QR స్కాన్ చేయగానే స్వాగతం, ఆర్డర్ అయ్యాక ధన్యవాదాలు.' : 'A welcome on the QR scan, a thank you after the order.'),
                onChanged: (v) => _saveWelcome(enabled: v),
              ),
              box('hello', _hello, te ? 'మొదటిసారి వచ్చినవారికి' : 'First visit'),
              box('again', _again, te ? 'మళ్ళీ వచ్చినవారికి' : 'Returning customer'),
              box('thanks', _thanks, te ? 'చివర్లో ధన్యవాదాలు' : 'Thank you at the end'),
            ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxDeskStepsWelcomeSave'),
        label: te ? 'సేవ్' : 'Save',
        icon: Icons.check_rounded,
        busy: _busy,
        onPressed: on ? () => _saveWelcome() : null,
      ),
    );
  }
}
