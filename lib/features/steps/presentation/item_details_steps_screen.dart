import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/askodox_field_guide.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import '../../selling/data/catalogue_repository.dart';
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 36): one item's details `/pos/:id/item/:pid`.
/// Top = ONE number (required details still missing), middle = ONE list of the details this kind of shop asks for
/// (tap = a sheet with the choices or a box, the guide text and an example), bottom = ONE big Save.
/// What the item's own name already says fills EMPTY details by itself (marked "check"); "fill from my words", the
/// online price, rates by quantity, photos and units live in ⋮ / the old page (`?full=1`).
class AskodoxItemDetailsStepsScreen extends ConsumerStatefulWidget {
  const AskodoxItemDetailsStepsScreen({super.key, required this.businessId, required this.productId});
  final String businessId;
  final String productId;

  @override
  ConsumerState<AskodoxItemDetailsStepsScreen> createState() => _ItemDetailsStepsState();
}

class _ItemDetailsStepsState extends ConsumerState<AskodoxItemDetailsStepsScreen> {
  AskodoxJson? _product;
  List<AskodoxJson> _specs = const [];
  final _values = <String, String>{};
  final _prefilled = <String>{};
  List<String> _missing = const [];
  String? _templateKey;
  Object? _error;
  bool _busy = false;
  final _box = TextEditingController();
  final _words = TextEditingController();

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _box.dispose();
    _words.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final product = await _repo.product(widget.businessId, widget.productId);
      final catalogue = await _repo.catalogue(widget.businessId);
      if (!mounted) return;
      setState(() {
        _product = product;
        _specs = askodoxPosList(catalogue['attributes']);
        final saved = askodoxPosMap(product['attributes']);
        _values
          ..clear()
          ..addAll({for (final e in saved.entries) e.key: '${e.value ?? ''}'});
        _templateKey = catalogue['template_key'] == null ? null : '${catalogue['template_key']}';
        _missing = _computeMissing();
        _error = null;
      });
      await _smartFill('${product['name']} ${product['name_te'] ?? ''}', quiet: true);
    } catch (e) {
      if (mounted && _product == null) setState(() => _error = e);
    }
  }

  bool _visible(AskodoxJson spec) {
    final dep = spec['depends_on'];
    if (dep is! Map) return true;
    final current = _values['${dep['key']}'] ?? '';
    return (dep['values'] as List? ?? const []).map((e) => '$e').contains(current);
  }

  List<String> _computeMissing() => [
        for (final s in _specs)
          if (s['required'] == true && _visible(s) && (_values['${s['key']}'] ?? '').trim().isEmpty) '${s['key']}',
      ];

  /// Fills only EMPTY details from the seller's own words; nothing is guessed (the server reads only the words).
  Future<void> _smartFill(String text, {bool quiet = false}) async {
    final key = _templateKey;
    if (key == null || text.trim().isEmpty) return;
    final te = _te;
    try {
      final out = await ref.read(askodoxCatalogueRepositoryProvider).smartFill(key, text);
      if (!mounted || out == null) return;
      var filled = 0;
      setState(() {
        for (final s in _specs) {
          final k = '${s['key']}';
          final v = out.values[k];
          if (v == null || v.isEmpty || (_values[k] ?? '').trim().isNotEmpty) continue;
          _values[k] = v;
          _prefilled.add(k);
          filled++;
        }
        _missing = _computeMissing();
      });
      if (!quiet) {
        askodoxPosSnack(
            context,
            filled == 0
                ? (te ? 'కొత్తగా నింపేది ఏదీ దొరకలేదు.' : 'Nothing new to fill from that.')
                : (te ? '$filled వివరాలు నింపాం — సరిచూసి సేవ్ చేయండి.' : 'Filled $filled detail(s) — check and save.'));
      }
    } catch (_) {
      // a convenience only: the seller can always type
    }
  }

  String _label(AskodoxJson spec) {
    final label = askodoxPosMap(spec['label']);
    final key = '${spec['key']}';
    return '${(_te ? label['te'] : null) ?? label['en'] ?? key}${spec['unit'] == null ? '' : ' (${spec['unit']})'}';
  }

  Future<void> _edit(AskodoxJson spec) async {
    final te = _te;
    final key = '${spec['key']}';
    final guide = askodoxAttributeGuide(spec);
    final isChoice = '${spec['kind']}' == 'choice';
    final multi = spec['multi'] == true;
    final options = [for (final o in (spec['options'] as List? ?? const [])) '$o'];
    final chosen = (_values[key] ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    _box.text = _values[key] ?? '';
    final out = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_label(spec), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(te ? guide.te : guide.en, style: const TextStyle(color: askodoxStepMuted)),
              const SizedBox(height: 12),
              if (isChoice)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final o in options)
                    FilterChip(
                      key: ValueKey('askodoxItemDetailsStepsOption-$key-$o'),
                      label: Text(o, style: const TextStyle(fontSize: 16)),
                      selected: chosen.contains(o),
                      onSelected: (on) => setSheet(() {
                        if (!multi) chosen.clear();
                        on ? chosen.add(o) : chosen.remove(o);
                      }),
                    ),
                ])
              else
                TextField(
                  key: ValueKey('askodoxItemDetailsStepsBox-$key'),
                  controller: _box,
                  autofocus: true,
                  keyboardType: '${spec['kind']}' == 'number' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                      border: const OutlineInputBorder(), hintText: te ? guide.exampleTe : guide.exampleEn),
                ),
              const SizedBox(height: 12),
              FilledButton(
                key: ValueKey('askodoxItemDetailsStepsOk-$key'),
                style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen, minimumSize: const Size.fromHeight(54)),
                onPressed: () => Navigator.pop(ctx, isChoice ? chosen.join(', ') : _box.text.trim()),
                child: Text(te ? 'సరే' : 'OK'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (out == null || !mounted) return;
    setState(() {
      _values[key] = out;
      _prefilled.remove(key);
      _missing = _computeMissing();
    });
  }

  Future<void> _fillFromWords() async {
    final te = _te;
    _words.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(te ? 'మీ మాటల్లో చెప్పండి' : 'Say it in your words'),
        content: TextField(
            key: const Key('askodoxItemDetailsStepsWords'),
            controller: _words,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
                border: const OutlineInputBorder(), hintText: te ? 'ఉదా: కాటన్ షర్ట్, నీలం, M సైజు' : 'e.g. cotton shirt, blue, size M')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(te ? 'నింపు' : 'Fill')),
        ],
      ),
    );
    if (ok == true && mounted) await _smartFill(_words.text);
  }

  Future<void> _save() async {
    final te = _te;
    final values = <String, Object?>{};
    for (final s in _specs) {
      final key = '${s['key']}';
      if (!_visible(s)) continue;
      final v = (_values[key] ?? '').trim();
      if (v.isNotEmpty) values[key] = v;
    }
    setState(() => _busy = true);
    try {
      final out = await _repo.setAttributes(widget.businessId, widget.productId, values);
      if (!mounted) return;
      setState(() {
        _missing = [for (final m in askodoxPosList(out['missing'])) '$m'];
        _prefilled.clear();
      });
      askodoxPosSnack(
          context,
          _missing.isEmpty
              ? (te ? '✓ సేవ్ అయింది.' : '✓ Saved.')
              : (te ? 'సేవ్ అయింది — ఇంకా ${_missing.length} తప్పనిసరి వివరాలు కావాలి.' : 'Saved — ${_missing.length} required detail(s) still missing.'));
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final p = _product;
    final title = te ? 'సరుకు వివరాలు' : 'Item details';
    final more = [
      AskodoxStepMore('askodoxItemDetailsStepsFill', te ? 'నా మాటలతో నింపు' : 'Fill from my words', Icons.auto_fix_high_rounded, _fillFromWords),
      AskodoxStepMore('askodoxItemDetailsStepsFull', te ? 'ఆన్‌లైన్ ధర, రేట్లు, ఫోటో, యూనిట్లు (పాత పేజీ)' : 'Online price, rates, photo, units (old page)',
          Icons.menu_book_rounded, () => context.push('/pos/${widget.businessId}/item/${widget.productId}?full=1').then((_) => _load())),
    ];
    if (_error != null) return AskodoxStepScaffold(title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    if (p == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    final visible = _specs.where(_visible).toList();
    return AskodoxStepScaffold(
      key: const Key('askodoxItemDetailsSteps'),
      title: title,
      sub: '${te && '${p['name_te'] ?? ''}'.isNotEmpty ? p['name_te'] : p['name']}',
      more: more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        AskodoxStepBigNumber('${_missing.length}',
            key: const Key('askodoxItemDetailsStepsMissing'),
            label: _missing.isEmpty ? (te ? 'తప్పనిసరి వివరాలు అన్నీ ఉన్నాయి ✓' : 'All required details are in ✓') : (te ? 'తప్పనిసరి వివరాలు కావాలి' : 'Required details missing'),
            color: _missing.isEmpty ? askodoxStepDone : askodoxStepWarn),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(te ? 'ఈ రకం షాప్‌కి అదనపు వివరాలు లేవు.' : 'This kind of shop asks no extra details.', textAlign: TextAlign.center),
          ),
        for (final s in visible)
          AskodoxStepPersonRow(
            key: ValueKey('askodoxItemDetailsStepsRow-${s['key']}'),
            name: _label(s),
            sub: (_values['${s['key']}'] ?? '').isEmpty
                ? (s['required'] == true ? (te ? 'కావాలి' : 'Needed') : (te ? 'ఖాళీ' : 'Empty'))
                : '${_values['${s['key']}']}${_prefilled.contains('${s['key']}') ? (te ? ' · ఆటోగా నింపాం, సరిచూడండి' : ' · filled for you, check') : ''}',
            amount: _missing.contains('${s['key']}') ? '!' : ((_values['${s['key']}'] ?? '').isEmpty ? '+' : '✓'),
            amountColor: _missing.contains('${s['key']}') ? askodoxStepWarn : askodoxStepDone,
            onTap: () => _edit(s),
          ),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxItemDetailsStepsSave'),
        label: te ? 'సేవ్' : 'Save',
        icon: Icons.check_rounded,
        busy: _busy,
        onPressed: _busy ? null : _save,
      ),
    );
  }
}
