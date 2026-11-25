import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 27): the shop's ready list `/pos/:id/catalogue`.
/// 1 which group (tiles with counts) -> 2 tick the items you sell (one list; ticks stay when you go back for another
/// group) -> 3 YOUR price for each ticked item (size + GST % when registered) -> Add. ASKODOX never fills a price.
/// Kind of business lives in ⋮ (settings permission). Pops `true` after adding, like the old page (`?full=1`).
class AskodoxCatalogueStepsScreen extends ConsumerStatefulWidget {
  const AskodoxCatalogueStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxCatalogueStepsScreen> createState() => _CatalogueStepsState();
}

const _rates = [0, 10, 25, 100, 150, 300, 500, 600, 1200, 1800, 2800, 4000];

String _n(Object? names, bool te) {
  final m = names is Map ? names : const {};
  return '${(te ? m['te'] : null) ?? m['en'] ?? ''}';
}

class _Picked {
  _Picked(this.item) : size = (item['sizes'] as List? ?? const []).isEmpty ? null : '${(item['sizes'] as List).first}';
  final AskodoxJson item;
  String? size;
  int? rate;
  final price = TextEditingController();
}

class _CatalogueStepsState extends ConsumerState<AskodoxCatalogueStepsScreen> {
  AskodoxJson? _data;
  Object? _error;
  int _step = 1;
  String? _cat;
  bool _busy = false;
  final _picked = <String, _Picked>{};

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);
  bool get _registered => '${_data?['registration_type']}' == 'regular';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final p in _picked.values) {
      p.price.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _repo.catalogue(widget.businessId);
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

  Future<void> _kindSheet() async {
    final te = _te;
    final d = _data;
    if (d == null) return;
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Text(te ? 'మీ వ్యాపార రకం' : 'Your kind of business', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text(te ? 'దాని ప్రకారం రెడీ లిస్ట్ మారుతుంది' : 'The ready list follows it', style: const TextStyle(color: askodoxStepMuted)),
          for (final c in askodoxPosList(d['choices']))
            ListTile(
              key: ValueKey('askodoxCatalogueStepsKind-${c['key']}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(d['template_key'] == c['key'] ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: askodoxStepGreen),
              title: Text(_n(c['name'], te), style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => Navigator.pop(ctx, '${c['key']}'),
            ),
        ]),
      ),
    );
    if (key == null || !mounted || key == d['template_key']) return;
    try {
      final out = await _repo.setCatalogueTemplate(widget.businessId, key);
      if (!mounted) return;
      setState(() {
        _data = out;
        for (final p in _picked.values) {
          p.price.dispose();
        }
        _picked.clear();
        _cat = null;
        _step = 1;
      });
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  void _toggle(AskodoxJson item) {
    if (item['in_shop'] == true) return;
    final key = '${item['key']}';
    setState(() {
      final old = _picked.remove(key);
      if (old == null) {
        _picked[key] = _Picked(item);
      } else {
        old.price.dispose();
      }
    });
  }

  Future<void> _add() async {
    final te = _te;
    final lines = <AskodoxJson>[];
    for (final p in _picked.values) {
      final paise = askodoxParsePaise(p.price.text);
      if (paise == null || paise <= 0) {
        askodoxPosSnack(context, te ? 'ప్రతి సరుకుకీ మీ ధర రాయండి.' : 'Type your price for every ticked item.');
        return;
      }
      if (_registered && p.rate == null) {
        askodoxPosSnack(context, te ? 'ప్రతి సరుకుకీ GST % ఎంచుకోండి.' : 'Choose the GST % for every ticked item.');
        return;
      }
      lines.add({
        'item_key': p.item['key'],
        if (p.size != null) 'size': p.size,
        'price_paise': paise,
        if (_registered) 'rate_bp': p.rate,
      });
    }
    setState(() => _busy = true);
    try {
      final out = await _repo.importCatalogue(widget.businessId, lines);
      final added = askodoxPosList(out['added']).length;
      final skipped = askodoxPosList(out['skipped']).length;
      if (!mounted) return;
      askodoxPosSnack(
          context,
          te
              ? '✓ $added సరుకులు చేర్చాం${skipped > 0 ? ', $skipped వదిలేశాం (ఇప్పటికే ఉన్నవి / ధర లేనివి)' : ''}.'
              : '✓ Added $added item(s)${skipped > 0 ? ', skipped $skipped (already in the shop / no price)' : ''}.');
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop(true);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'రెడీ లిస్ట్ నుండి చేర్చు' : 'Add from the ready list';
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull;
    final canSettings = business != null && askodoxPosCan(business, 'settings');
    final more = [
      if (canSettings)
        AskodoxStepMore('askodoxCatalogueStepsKind', te ? 'వ్యాపార రకం మార్చు' : 'Change kind of business', Icons.storefront_rounded, _kindSheet),
      AskodoxStepMore('askodoxCatalogueStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
          () => context.push('/pos/${widget.businessId}/catalogue?full=1')),
    ];
    if (_error != null) return AskodoxStepScaffold(title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    final d = _data;
    if (d == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    final cats = askodoxPosList(d['categories']);
    return switch (_step) {
      2 => _items(title, more, cats),
      3 => _prices(title, more),
      _ => _groups(title, more, cats),
    };
  }

  Widget _groups(String title, List<AskodoxStepMore> more, List<AskodoxJson> cats) {
    final te = _te;
    return AskodoxStepScaffold(
      key: const Key('askodoxCatalogueSteps'),
      title: title,
      step: 1,
      question: te ? 'ఏ రకం సరుకులు?' : 'Which kind of items?',
      hint: te ? 'బ్రాండ్‌లు, ధరలు మేము పెట్టము' : 'We never add brands or prices',
      more: more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        if (cats.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(te ? 'ఈ రకానికి రెడీ లిస్ట్ లేదు — ⋮ లో వ్యాపార రకం మార్చండి, లేదా సరుకులను మీరే చేర్చండి.'
                : 'No ready list for this kind — change the kind in ⋮, or add items yourself.'),
          ),
        for (final c in cats)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AskodoxStepChoice(
              key: ValueKey('askodoxCatalogueStepsGroup-${c['key']}'),
              icon: Icons.category_outlined,
              color: askodoxStepGreen,
              title: _n(c['name'], te),
              sub: '${askodoxPosList(c['items']).length} ${te ? 'సరుకులు' : 'items'}',
              badge: () {
                final n = askodoxPosList(c['items']).where((i) => _picked.containsKey('${i['key']}')).length;
                return n > 0 ? '$n ✓' : null;
              }(),
              onTap: () => setState(() {
                _cat = '${c['key']}';
                _step = 2;
              }),
            ),
          ),
      ]),
      bottom: _picked.isEmpty
          ? null
          : AskodoxStepBottom(
              buttonKey: const Key('askodoxCatalogueStepsPrices'),
              label: te ? '${_picked.length} సరుకులకు ధర రాయి' : 'Price ${_picked.length} item(s)',
              icon: Icons.currency_rupee_rounded,
              onPressed: () => setState(() => _step = 3),
            ),
    );
  }

  Widget _items(String title, List<AskodoxStepMore> more, List<AskodoxJson> cats) {
    final te = _te;
    final cat = cats.firstWhere((c) => '${c['key']}' == _cat, orElse: () => const {});
    return AskodoxStepScaffold(
      key: const Key('askodoxCatalogueSteps'),
      title: title,
      sub: _n(cat['name'], te),
      step: 2,
      question: te ? 'మీరు ఏవి అమ్ముతారు?' : 'Which do you sell?',
      hint: te ? 'నొక్కితే టిక్' : 'Tap to tick',
      onBack: () => setState(() => _step = 1),
      more: more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        for (final item in askodoxPosList(cat['items']))
          AskodoxStepPersonRow(
            key: ValueKey('askodoxCatalogueStepsItem-${item['key']}'),
            name: _n(item['name'], te),
            sub: item['in_shop'] == true ? (te ? 'మీ షాప్‌లో ఇప్పటికే ఉంది' : 'Already in your shop') : '${item['pos_unit'] ?? ''}',
            amount: item['in_shop'] == true ? '—' : (_picked.containsKey('${item['key']}') ? '✓' : '+'),
            amountColor: _picked.containsKey('${item['key']}') ? askodoxStepDone : askodoxStepMuted,
            onTap: () => _toggle(item),
          ),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxCatalogueStepsNext'),
        label: _picked.isEmpty ? (te ? 'సరుకులు టిక్ చేయండి' : 'Tick items') : (te ? '${_picked.length} సరుకులకు ధర రాయి' : 'Price ${_picked.length} item(s)'),
        icon: Icons.arrow_forward_rounded,
        onPressed: _picked.isEmpty ? null : () => setState(() => _step = 3),
      ),
    );
  }

  Widget _prices(String title, List<AskodoxStepMore> more) {
    final te = _te;
    return AskodoxStepScaffold(
      key: const Key('askodoxCatalogueSteps'),
      title: title,
      step: 3,
      question: te ? 'మీ ధర ఎంత?' : 'Your price?',
      hint: _registered ? (te ? 'ప్రతి సరుకుకీ ధర + GST %' : 'Price + GST % for each') : (te ? 'ప్రతి సరుకుకీ ఒక ధర' : 'One price for each'),
      onBack: () => setState(() => _step = _cat == null ? 1 : 2),
      more: more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        for (final e in _picked.entries) _priceRow(e.key, e.value, te),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxCatalogueStepsAdd'),
        label: te ? '${_picked.length} సరుకులు చేర్చు' : 'Add ${_picked.length} item(s)',
        icon: Icons.check_rounded,
        busy: _busy,
        onPressed: _busy || _picked.isEmpty ? null : _add,
      ),
    );
  }

  Widget _priceRow(String key, _Picked p, bool te) {
    final sizes = [for (final s in (p.item['sizes'] as List? ?? const [])) '$s'];
    return Container(
      key: ValueKey('askodoxCatalogueStepsPriceRow-$key'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: askodoxStepLine), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_n(p.item['name'], te), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        if (sizes.length > 1)
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final s in sizes)
              ChoiceChip(
                  key: ValueKey('askodoxCatalogueStepsSize-$key-$s'),
                  label: Text(s),
                  selected: p.size == s,
                  onSelected: (_) => setState(() => p.size = s)),
          ]),
        const SizedBox(height: 8),
        TextField(
          key: ValueKey('askodoxCatalogueStepsPrice-$key'),
          controller: p.price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            labelText: te ? 'ఒక ${p.item['pos_unit']}${p.size == null ? '' : ' (${p.size})'} ధర ₹' : 'Price ₹ for one ${p.item['pos_unit']}${p.size == null ? '' : ' (${p.size})'}',
            border: const OutlineInputBorder(),
          ),
        ),
        if (_registered) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: ValueKey('askodoxCatalogueStepsRate-$key'),
            initialValue: p.rate,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'GST %', border: OutlineInputBorder(), isDense: true),
            items: [for (final r in _rates) DropdownMenuItem(value: r, child: Text(askodoxRate(r)))],
            onChanged: (v) => setState(() => p.rate = v),
          ),
        ],
      ]),
    );
  }
}
