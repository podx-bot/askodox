import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 16): the shop's menu `/desk/:id/menu`. Top = how many items, middle = ONE list
/// (tap = out today / back, today only, change name and price, remove), bottom = ONE big button that adds items in 2 steps
/// (say or type them with prices -> check -> save). Menu photos, shelf photos, AI sections and the full edit (section,
/// veg / non-veg) stay on the old page in the menu ⋮ (`?full=1`).
class AskodoxDeskMenuStepsScreen extends ConsumerStatefulWidget {
  const AskodoxDeskMenuStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxDeskMenuStepsScreen> createState() => _DeskMenuState();
}

class _DeskMenuState extends ConsumerState<AskodoxDeskMenuStepsScreen> {
  List<AskodoxJson>? _items;
  Object? _error;
  int _step = 0; // 0 = the list, 1 = say / type, 2 = check, 3 = done
  final _text = TextEditingController();
  final _search = TextEditingController();
  final _editName = TextEditingController();
  final _editPrice = TextEditingController();
  List<AskodoxJson> _preview = const [];
  bool _gst = false;
  int _rateBp = 0;
  bool _busy = false;
  String _saved = '';

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _text.dispose();
    _search.dispose();
    _editName.dispose();
    _editPrice.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await _repo.deskMenu(widget.businessId);
      if (mounted) {
        setState(() {
          _items = askodoxPosList(m['items']);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _items == null) setState(() => _error = e);
    }
  }

  Future<bool> _do(Future<Object?> Function() action) async {
    try {
      await action();
      return true;
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
      return false;
    }
  }

  String _rupees(int paise) => askodoxPaise(paise);

  Future<void> _item(AskodoxJson m) async {
    final te = _te;
    final id = '${m['id']}';
    final on = m['available'] == true;
    final today = m['today_only_flag'] == true;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text(_rupees(askodoxPosInt(m['price_paise'])), style: const TextStyle(color: askodoxStepMuted)),
            const SizedBox(height: 12),
            FilledButton(
                key: Key('askodoxDeskMenuStepsAvail-$id'),
                style: FilledButton.styleFrom(backgroundColor: on ? askodoxStepWarn : askodoxStepGreen, minimumSize: const Size.fromHeight(54)),
                onPressed: () => Navigator.pop(ctx, 'avail'),
                child: Text(on ? (te ? 'ఈ రోజు అయిపోయింది' : 'Finished for today') : (te ? 'మళ్లీ ఉంది' : 'Back on the menu'))),
            const SizedBox(height: 10),
            FilledButton(
                key: Key('askodoxDeskMenuStepsEdit-$id'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: () => Navigator.pop(ctx, 'edit'),
                child: Text(te ? 'పేరు / రేటు మార్చు' : 'Change name / price')),
            const SizedBox(height: 10),
            OutlinedButton(
                key: Key('askodoxDeskMenuStepsToday-$id'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => Navigator.pop(ctx, 'today'),
                child: Text(today ? (te ? 'రోజూ ఉంచు' : 'Keep daily') : (te ? 'ఈ రోజు మాత్రమే' : 'Today only'))),
            const SizedBox(height: 10),
            OutlinedButton(
                key: Key('askodoxDeskMenuStepsRemove-$id'),
                style: OutlinedButton.styleFrom(foregroundColor: askodoxStepBad, minimumSize: const Size.fromHeight(50)),
                onPressed: () => Navigator.pop(ctx, 'remove'),
                child: Text(te ? 'తీసేయి' : 'Remove')),
          ]),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'avail') {
      await _do(() => _repo.deskAvailability(widget.businessId, id, !on));
      await _load();
    } else if (action == 'today') {
      await _do(() => _repo.deskTodayOnly(widget.businessId, id, !today));
      await _load();
    } else if (action == 'edit') {
      await _editItem(m);
    } else if (action == 'remove') {
      await _do(() => _repo.updateProduct(widget.businessId, id, {'active': false}));
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(te ? '"${m['name']}" తీసేశాం' : '"${m['name']}" removed'),
        action: SnackBarAction(
          label: te ? 'తిరిగి తెచ్చు' : 'Undo',
          onPressed: () => unawaited(() async {
            await _do(() => _repo.updateProduct(widget.businessId, id, {'active': true}));
            await _load();
          }()),
        ),
      ));
    }
  }

  Future<void> _editItem(AskodoxJson m) async {
    final te = _te;
    final paise = askodoxPosInt(m['price_paise']);
    _editName.text = '${m['name']}';
    _editPrice.text = (paise / 100).toStringAsFixed(paise % 100 == 0 ? 0 : 2);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'ఐటమ్ మార్చండి' : 'Change item'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('askodoxDeskMenuStepsName'), controller: _editName, decoration: InputDecoration(labelText: te ? 'పేరు' : 'Name')),
          TextField(
              key: const Key('askodoxDeskMenuStepsPrice'),
              controller: _editPrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: te ? 'రేటు (₹)' : 'Price (₹)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(key: const Key('askodoxDeskMenuStepsEditSave'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = _editName.text.trim();
    final rupees = double.tryParse(_editPrice.text.trim());
    if (name.isEmpty || rupees == null || rupees < 0) return;
    await _do(() => _repo.updateProduct(widget.businessId, '${m['id']}', {'name': name, 'price_paise': (rupees * 100).round()}));
    await _load();
  }

  Future<void> _check() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final ok = await _do(() async {
      final out = await _repo.deskMenuParse(widget.businessId, _text.text);
      if (!mounted) return null;
      setState(() {
        _preview = askodoxPosList(out['items']);
        _gst = out['gst'] == true;
      });
      return null;
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok && _preview.isNotEmpty) {
        _step = 2;
      } else if (ok) {
        askodoxPosSnack(context, _te ? 'ఐటమ్స్ కనపడలేదు. పేరు, రేటు ఇలా చెప్పండి: ఇడ్లీ 30' : 'No items found. Say them like: Idli 30');
      }
    });
  }

  Future<void> _editPreviewRow(int i) async {
    final te = _te;
    final row = _preview[i];
    final paise = askodoxPosInt(row['price_paise']);
    _editName.text = '${row['name']}';
    _editPrice.text = paise > 0 ? (paise / 100).toStringAsFixed(paise % 100 == 0 ? 0 : 2) : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'ఐటమ్ సరిచేయండి' : 'Fix the item'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('askodoxDeskMenuStepsPvName'), controller: _editName, decoration: InputDecoration(labelText: te ? 'పేరు' : 'Name')),
          TextField(
              key: const Key('askodoxDeskMenuStepsPvPrice'),
              controller: _editPrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: te ? 'రేటు (₹)' : 'Price (₹)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(key: const Key('askodoxDeskMenuStepsPvSave'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సరే' : 'OK')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = _editName.text.trim();
    final rupees = double.tryParse(_editPrice.text.trim());
    if (name.isEmpty) return;
    setState(() {
      final next = [..._preview];
      next[i] = {...row, 'name': name, 'price_paise': rupees == null ? 0 : (rupees * 100).round()};
      _preview = next;
    });
  }

  Future<void> _save() async {
    final te = _te;
    final ready = [for (final m in _preview) if (askodoxPosInt(m['price_paise']) > 0) m];
    if (ready.isEmpty) {
      askodoxPosSnack(context, te ? 'ఏ ఐటమ్ కీ రేటు లేదు. రేట్లు రాయండి.' : 'No item has a price yet. Add the prices.');
      return;
    }
    setState(() => _busy = true);
    AskodoxJson? out;
    final ok = await _do(() async {
      out = await _repo.deskMenuImport(widget.businessId, ready, rateBp: _rateBp);
      return null;
    });
    if (!mounted) return;
    if (ok) {
      final skipped = _preview.length - ready.length;
      _saved = te ? '${out?['created'] ?? 0} కొత్త, ${out?['updated'] ?? 0} మార్పు' : '${out?['created'] ?? 0} new, ${out?['updated'] ?? 0} updated';
      if (skipped > 0) {
        askodoxPosSnack(context, te ? '$skipped ఐటమ్‌లకు రేటు లేదు, వదిలేశాను.' : '$skipped items had no price and were left out.');
      }
      _preview = const [];
      _text.clear();
      await _load();
    }
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) _step = 3;
      });
    }
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    return [
      AskodoxStepMore('askodoxDeskMenuStepsFull', te ? 'ఫోటోతో, AI తో సర్దు, పూర్తి మార్పు (పాత పేజీ)' : 'Photos, AI sections, full edit (old page)', Icons.menu_book_rounded,
          () => context.push('/desk/${widget.businessId}/menu?full=1')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'మెనూ' : 'Menu';
    if (_step == 1) {
      return AskodoxStepScaffold(
        key: const Key('askodoxDeskMenuSteps1'),
        title: title,
        step: 1,
        total: 2,
        question: te ? 'ఏ ఐటమ్స్ చేర్చాలి?' : 'Which items do you add?',
        hint: te ? 'పేరు, రేటుతో చెప్పండి లేదా రాయండి. ఉదా: ఇడ్లీ 30, దోస 50. నిర్ధారించే వరకు ఏదీ సేవ్ కాదు.' : 'Say or type name and price. Like: Idli 30, Dosa 50. Nothing is saved before you check.',
        onBack: () => setState(() => _step = 0),
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          TextField(
              key: const Key('askodoxDeskMenuStepsText'),
              controller: _text,
              minLines: 4,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(border: const OutlineInputBorder(), hintText: te ? 'ఇడ్లీ 30\nదోస 50\nఈ రోజు మాత్రమే: పూరీ 40' : 'Idli 30\nDosa 50\nToday only: Puri 40')),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxDeskMenuStepsCheck'),
          label: te ? 'చూడండి' : 'Check',
          icon: Icons.arrow_forward_rounded,
          busy: _busy,
          onSpoken: (words) {
            setState(() => _text.text = _text.text.trim().isEmpty ? words : '${_text.text.trim()}\n$words');
            unawaited(_check());
          },
          onPressed: _text.text.trim().isEmpty ? null : _check,
        ),
      );
    }
    if (_step == 2) {
      final ready = _preview.where((m) => askodoxPosInt(m['price_paise']) > 0).length;
      return AskodoxStepScaffold(
        key: const Key('askodoxDeskMenuSteps2'),
        title: title,
        step: 2,
        total: 2,
        question: te ? '${_preview.length} ఐటమ్స్ సరిగ్గా ఉన్నాయా?' : 'Are these ${_preview.length} items right?',
        hint: te ? 'ఐటమ్ నొక్కి సరిచేయండి. రేటు లేనివి సేవ్ కావు.' : 'Tap an item to fix it. Items without a price are not saved.',
        onBack: () => setState(() => _step = 1),
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          for (final (i, m) in _preview.indexed)
            AskodoxStepPersonRow(
              key: Key('askodoxDeskMenuStepsPv-$i'),
              name: '${m['name']}',
              sub: m['today_only'] == true ? (te ? 'ఈ రోజు మాత్రమే' : 'Today only') : '',
              amount: askodoxPosInt(m['price_paise']) > 0 ? _rupees(askodoxPosInt(m['price_paise'])) : (te ? 'రేటు?' : 'Price?'),
              amountColor: askodoxPosInt(m['price_paise']) > 0 ? askodoxStepInk : askodoxStepBad,
              onTap: () => _editPreviewRow(i),
            ),
          if (_gst) ...[
            const SizedBox(height: 10),
            Text(te ? 'ఈ ఐటమ్స్‌కి GST % (మీరే ఎంచుకోండి)' : 'GST % for these items (your choice)', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final bp in const [0, 500, 1200, 1800])
                ChoiceChip(
                  key: Key('askodoxDeskMenuStepsGst-$bp'),
                  label: Text('${bp ~/ 100}%'),
                  selected: _rateBp == bp,
                  onSelected: (_) => setState(() => _rateBp = bp),
                ),
            ]),
          ],
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxDeskMenuStepsSave'),
          label: te ? 'మెనూలో సేవ్' : 'Save to the menu',
          icon: Icons.check_rounded,
          busy: _busy,
          onPressed: ready == 0 ? null : _save,
        ),
      );
    }
    if (_step == 3) {
      return AskodoxStepScaffold(
        key: const Key('askodoxDeskMenuSteps3'),
        title: title,
        step: 2,
        total: 2,
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
          const Center(child: AskodoxStepDoneMark()),
          const SizedBox(height: 26),
          AskodoxStepBigNumber(_saved, label: te ? 'మెనూలో సేవ్ అయింది' : 'Saved to the menu', size: 30),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxDeskMenuStepsDone'),
          label: te ? 'మెనూకి' : 'Back to the menu',
          icon: Icons.check_rounded,
          onPressed: () => setState(() => _step = 0),
        ),
      );
    }
    if (_error != null) {
      return AskodoxStepScaffold(title: title, body: AskodoxPosError(error: _error!, onRetry: _load));
    }
    final items = _items;
    if (items == null) return AskodoxStepScaffold(title: title, body: const Center(child: CircularProgressIndicator()));
    final q = _search.text.trim().toLowerCase();
    final shown = [for (final m in items) if (q.isEmpty || '${m['name']}'.toLowerCase().contains(q) || '#${m['item_no']}' == q) m];
    final out = items.where((m) => m['available'] != true).length;
    return AskodoxStepScaffold(
      key: const Key('askodoxDeskMenuSteps'),
      title: title,
      more: _more(),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: AskodoxStepBigNumber('${items.length}',
              label: out > 0 ? (te ? 'ఐటమ్స్ · $out ఈ రోజు లేవు' : 'items · $out out today') : (te ? 'ఐటమ్స్' : 'items')),
        ),
        if (items.length > 6)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AskodoxStepSearch(
              controller: _search,
              fieldKey: const Key('askodoxDeskMenuStepsSearch'),
              hint: te ? 'ఐటమ్ వెతకండి' : 'Find an item',
              onChanged: (_) => setState(() {}),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(te ? 'ఇంకా ఐటమ్స్ లేవు. కింద బటన్ నొక్కండి.' : 'No items yet. Tap the button below.'))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                  for (final m in shown)
                    AskodoxStepPersonRow(
                      key: Key('askodoxDeskMenuStepsItem-${m['id']}'),
                      name: '${m['name']}',
                      sub: [
                        if (askodoxPosInt(m['item_no']) > 0) '#${m['item_no']}',
                        if ('${m['menu_group'] ?? ''}'.isNotEmpty) '${m['menu_group']}',
                        if (m['available'] != true) te ? 'ఈ రోజు లేదు' : 'Out today',
                        if (m['today_only_flag'] == true) te ? 'ఈ రోజు మాత్రమే' : 'Today only',
                      ].join(' · '),
                      amount: _rupees(askodoxPosInt(m['price_paise'])),
                      amountColor: m['available'] == true ? askodoxStepInk : askodoxStepMuted,
                      onTap: () => _item(m),
                    ),
                ]),
        ),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxDeskMenuStepsAdd'),
        label: te ? 'ఐటమ్స్ చేర్చు' : 'Add items',
        icon: Icons.add_rounded,
        onPressed: () => setState(() => _step = 1),
      ),
    );
  }
}
