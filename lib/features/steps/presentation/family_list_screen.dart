import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../home/application/conversation_archive.dart' show AskodoxChatRequest, askodoxChatRequestProvider;
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import '../domain/one_touch_rules.dart';
import '../domain/step_logic.dart' show askodoxTenDigits;
import 'step_kit.dart';

/// Family shopping list `/me/family-list` (owner 2026-11-25, "ఒక్క టచ్" buyer list): ONE list the whole home shares.
/// Top = how many things are still needed + the people (add by number), middle = the list (tap = bought ✓; ⋮ on a row =
/// edit / not now / delete), bottom = mic + "Add". ⋮ on top: find them nearby (chat), clear bought ones, rename.
class AskodoxFamilyListScreen extends ConsumerStatefulWidget {
  const AskodoxFamilyListScreen({super.key});

  @override
  ConsumerState<AskodoxFamilyListScreen> createState() => _FamilyListState();
}

class _FamilyListState extends ConsumerState<AskodoxFamilyListScreen> {
  AskodoxJson? _list;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);
  String get _id => '${_list?['id'] ?? ''}';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final lists = await _repo.familyLists();
      _list = lists.isEmpty ? null : lists.first;
      _error = null;
    } on AskodoxPosException catch (e) {
      _error = e.kind;
      if (mounted) askodoxPosSnack(context, e.message(_te));
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _run(Future<AskodoxJson> Function() call) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final out = await call();
      if (mounted && out['id'] != null) setState(() => _list = out);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add([String? spoken]) async {
    final te = _te;
    var text = spoken;
    if (text == null) {
      final box = TextEditingController();
      text = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(te ? 'ఏం కావాలి?' : 'What is needed?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('askodoxFamilyAddBox'),
              controller: box,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: te ? 'ఉదా: 2 కిలో చక్కెర, పాలు, సబ్బు' : 'e.g. 2 kg sugar, milk, soap',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('askodoxFamilyAddSave'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: () => Navigator.pop(ctx, box.text),
              child: Text(te ? 'చేర్చు' : 'Add'),
            ),
          ]),
        ),
      );
    }
    final items = askodoxFamilyItemsFrom(text ?? '');
    if (items.isEmpty || _id.isEmpty) return;
    await _run(() => _repo.familyAdd(_id, items));
  }

  Future<void> _addPerson() async {
    final te = _te;
    final phone = TextEditingController();
    final name = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'ఇంట్లో వాళ్ళని చేర్చండి' : 'Add someone from home', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(te ? 'వాళ్ళు ASKODOX లో ఈ నంబర్‌తో సైన్ ఇన్ అయితే లిస్ట్ కనిపిస్తుంది.' : 'They see the list when they sign in to ASKODOX with this number.',
              style: const TextStyle(color: askodoxStepMuted)),
          const SizedBox(height: 10),
          TextField(
            key: const Key('askodoxFamilyPersonPhone'),
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: te ? 'మొబైల్ నంబర్' : 'Mobile number', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('askodoxFamilyPersonName'),
            controller: name,
            decoration: InputDecoration(labelText: te ? 'పేరు (అమ్మ, నాన్న...)' : 'Name (Amma, Nanna...)', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('askodoxFamilyPersonSave'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(te ? 'చేర్చు' : 'Add'),
          ),
        ]),
      ),
    );
    if (ok != true || !mounted) return;
    final digits = askodoxTenDigits(phone.text);
    if (digits.isEmpty) {
      askodoxPosSnack(context, te ? '10 అంకెల మొబైల్ నంబర్ ఇవ్వండి' : 'Give a 10-digit mobile number');
      return;
    }
    await _run(() => _repo.familyAddPerson(_id, digits, name.text.trim()));
  }

  Future<void> _person(AskodoxJson m) async {
    final te = _te;
    final me = m['me'] == true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(me ? (te ? 'లిస్ట్ నుంచి వెళ్ళిపోవాలా?' : 'Leave this list?') : '${m['label']} ${m['phone']}'.trim()),
        content: Text(me
            ? (te ? 'మీరు చేర్చిన వస్తువులు మిగతావాళ్ళకి అలాగే ఉంటాయి.' : 'Things you added stay for the others.')
            : (te ? 'ఈ వ్యక్తిని లిస్ట్ నుంచి తీసేయాలా?' : 'Take this person out of the list?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(te ? 'వద్దు' : 'No')),
          TextButton(
              key: const Key('askodoxFamilyPersonRemoveYes'),
              onPressed: () => Navigator.pop(d, true),
              child: Text(me ? (te ? 'వెళ్ళిపో' : 'Leave') : (te ? 'తీసేయి' : 'Remove'))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _repo.familyRemovePerson(_id, me ? 'me' : '${m['ref']}');
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _edit(AskodoxJson item) async {
    final te = _te;
    final box = TextEditingController(text: '${item['text']}');
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? 'మార్చు' : 'Edit'),
        content: TextField(key: const Key('askodoxFamilyEditBox'), controller: box, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(te ? 'వద్దు' : 'Cancel')),
          TextButton(key: const Key('askodoxFamilyEditSave'), onPressed: () => Navigator.pop(d, box.text), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    await _run(() => _repo.familyItem(_id, '${item['id']}', {'text': text.trim()}));
  }

  void _nearby() {
    final open = [for (final i in askodoxPosList(_list?['items'])) if (i['state'] == 'open') '${i['text']}'];
    if (open.isEmpty) return;
    ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(askodoxFamilyNearbyAsk(open, _te));
    context.go('/');
  }

  Future<void> _rename() async {
    final te = _te;
    final box = TextEditingController(text: '${_list?['name'] ?? ''}');
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? 'లిస్ట్ పేరు' : 'List name'),
        content: TextField(controller: box, autofocus: true, maxLength: 40),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(te ? 'వద్దు' : 'Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, box.text), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    if (text == null) return;
    await _run(() => _repo.familyRename(_id, text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final name = '${_list?['name'] ?? ''}'.trim();
    final title = name.isNotEmpty ? name : (te ? 'ఇంటి షాపింగ్ లిస్ట్' : 'Family shopping list');
    final more = [
      AskodoxStepMore('askodoxFamilyNearby', te ? 'దగ్గర్లో ఎక్కడ దొరుకుతాయి' : 'Find these nearby', Icons.near_me_rounded, _nearby),
      AskodoxStepMore('askodoxFamilyClearDone', te ? 'కొన్నవి తీసేయి' : 'Clear bought ones', Icons.cleaning_services_rounded,
          () => unawaited(_run(() => _repo.familyClearDone(_id)))),
      AskodoxStepMore('askodoxFamilyRename', te ? 'లిస్ట్ పేరు మార్చు' : 'Rename list', Icons.edit_rounded, () => unawaited(_rename())),
    ];
    if (!_loaded) return AskodoxStepScaffold(title: title, body: const Center(child: CircularProgressIndicator()));
    if (_list == null) {
      return AskodoxStepScaffold(
        title: title,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error == 'sign_in' ? (te ? 'లిస్ట్ కోసం సైన్ ఇన్ చేయండి.' : 'Sign in to use the list.') : (te ? 'లిస్ట్ తెరవలేదు.' : 'Could not open the list.'),
                textAlign: TextAlign.center),
          ),
        ),
        bottom: AskodoxStepBottom(label: te ? 'మళ్ళీ' : 'Try again', onPressed: () => unawaited(_load())),
      );
    }
    final items = askodoxPosList(_list!['items']);
    final members = askodoxPosList(_list!['members']);
    final open = askodoxPosInt(_list!['open']);
    return AskodoxStepScaffold(
      key: const Key('askodoxFamilyList'),
      title: title,
      more: more,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
          AskodoxStepBigNumber('$open',
              label: open == 0 ? (te ? 'అన్నీ ఉన్నాయి ✓' : 'Nothing needed ✓') : (te ? 'కావాల్సినవి' : 'Still needed'), size: 44),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final m in members)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InputChip(
                    key: ValueKey('askodoxFamilyPerson-${m['ref']}'),
                    avatar: Icon(m['joined'] == true ? Icons.person_rounded : Icons.hourglass_top_rounded, size: 18),
                    label: Text(m['me'] == true
                        ? (te ? 'నేను' : 'Me')
                        : ('${m['label']}'.isNotEmpty ? '${m['label']}' : '${m['phone']}')),
                    onPressed: () => unawaited(_person(m)),
                  ),
                ),
              ActionChip(
                key: const Key('askodoxFamilyAddPerson'),
                avatar: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(te ? 'ఇంట్లో వాళ్ళు' : 'Add family'),
                onPressed: () => unawaited(_addPerson()),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(te ? 'మైక్ నొక్కి "చక్కెర, పాలు" అని చెప్పండి — లిస్ట్‌లో పడతాయి.' : 'Tap the mic and say "sugar, milk" — they go on the list.',
                  textAlign: TextAlign.center, style: const TextStyle(color: askodoxStepMuted)),
            ),
          for (final i in items) _row(i),
        ]),
      ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxFamilyAdd'),
        label: te ? 'చేర్చు' : 'Add',
        icon: Icons.add_rounded,
        busy: _busy,
        onSpoken: (words) => unawaited(_add(words)),
        onPressed: () => unawaited(_add()),
      ),
    );
  }

  Widget _row(AskodoxJson i) {
    final te = _te;
    final state = '${i['state']}';
    final done = state == 'done';
    final paused = state == 'paused';
    final who = done ? '${i['done_by']}' : '${i['added_by']}';
    final sub = done
        ? (who == 'me' ? (te ? 'నేను కొన్నా' : 'I bought it') : (te ? '$who కొన్నారు' : 'Bought by $who'))
        : paused
            ? (te ? 'ఇప్పుడు వద్దు' : 'Not now')
            : (who == 'me' || who.isEmpty ? '' : (te ? '$who చేర్చారు' : 'Added by $who'));
    return Opacity(
      opacity: paused ? 0.5 : 1,
      child: ListTile(
        key: ValueKey('askodoxFamilyItem-${i['id']}'),
        contentPadding: EdgeInsets.zero,
        leading: Checkbox(
          value: done,
          onChanged: (v) => unawaited(_run(() => _repo.familyItem(_id, '${i['id']}', {'state': v == true ? 'done' : 'open'}))),
        ),
        title: Text('${i['text']}${'${i['qty']}'.isEmpty ? '' : ' · ${i['qty']}'}',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? askodoxStepMuted : askodoxStepInk)),
        subtitle: sub.isEmpty ? null : Text(sub),
        onTap: () => unawaited(_run(() => _repo.familyItem(_id, '${i['id']}', {'state': done ? 'open' : 'done'}))),
        trailing: PopupMenuButton<String>(
          key: ValueKey('askodoxFamilyItemMenu-${i['id']}'),
          onSelected: (v) => switch (v) {
            'edit' => unawaited(_edit(i)),
            'pause' => unawaited(_run(() => _repo.familyItem(_id, '${i['id']}', {'state': paused ? 'open' : 'paused'}))),
            _ => unawaited(_run(() => _repo.familyItemDelete(_id, '${i['id']}'))),
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text(te ? 'మార్చు' : 'Edit')),
            PopupMenuItem(value: 'pause', child: Text(paused ? (te ? 'మళ్ళీ కావాలి' : 'Needed again') : (te ? 'ఇప్పుడు వద్దు' : 'Not now'))),
            PopupMenuItem(value: 'delete', child: Text(te ? 'తీసేయి' : 'Delete')),
          ],
        ),
      ),
    );
  }
}
