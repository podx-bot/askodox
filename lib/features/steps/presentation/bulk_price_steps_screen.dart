import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/delivery_jobs_screens.dart' show askodoxRupee;
import '../../pos/presentation/pos_common.dart';
import '../domain/one_touch_rules.dart';
import '../domain/step_logic.dart';
import 'step_kit.dart';

/// Bulk price change `/pos/:id/prices` (owner 2026-11-25, "ఒక్క టచ్" seller list): change many prices in 3 steps --
/// (1) which items: all / sections / picked, (2) how: up or down by % or ₹, or one price, (3) old -> new list, then ✓.
/// The server writes them in one go (old bills keep their prices). Rates by quantity, pack prices and a separate online
/// price are not changed; step 3 says how many items have them.
class AskodoxBulkPriceStepsScreen extends ConsumerStatefulWidget {
  const AskodoxBulkPriceStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBulkPriceStepsScreen> createState() => _BulkPriceState();
}

class _BulkPriceState extends ConsumerState<AskodoxBulkPriceStepsScreen> {
  int _step = 1;
  List<AskodoxJson> _items = const [];
  bool _loaded = false;
  String _scope = 'all'; // all | groups | items
  final Set<String> _groups = {};
  final Set<String> _picked = {};
  String _mode = 'up_percent';
  String _value = '';
  int _round = 100;
  AskodoxJson? _preview;
  AskodoxJson? _done;
  bool _busy = false;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      _items = await _repo.products(widget.businessId);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    }
    if (mounted) setState(() => _loaded = true);
  }

  List<String> get _sections {
    final out = <String>{};
    for (final i in _items) {
      final g = '${i['menu_group'] ?? ''}'.trim();
      if (g.isNotEmpty) out.add(g);
    }
    return out.toList()..sort();
  }

  int get _chosenCount => switch (_scope) {
        'groups' => _items.where((i) => _groups.contains('${i['menu_group'] ?? ''}'.trim())).length,
        'items' => _picked.length,
        _ => _items.length,
      };

  AskodoxJson get _body => {
        'scope': _scope,
        'groups': _groups.toList(),
        'product_ids': _picked.toList(),
        'mode': _mode,
        'value': int.tryParse(_value) ?? 0,
        'round_paise': _round,
      };

  Future<void> _toPreview() async {
    setState(() => _busy = true);
    try {
      final out = await _repo.bulkPrice(widget.businessId, _body);
      if (mounted) {
        setState(() {
          _preview = out;
          _step = 3;
        });
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final out = await _repo.bulkPrice(widget.businessId, _body, apply: true);
      if (mounted) setState(() => _done = out);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() => setState(() {
        _step -= 1;
        if (_step < 3) _preview = null;
      });

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'ధరలు ఒకేసారి మార్చు' : 'Change prices at once';
    final more = [
      AskodoxStepMore('askodoxBulkPriceItems', te ? 'ఐటమ్స్ పేజీ' : 'Items page', Icons.inventory_2_rounded,
          () => context.push('/pos/${widget.businessId}/catalogue')),
    ];
    if (!_loaded) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    if (_done != null) return _finished(title);
    return switch (_step) {
      1 => _which(title, more),
      2 => _how(title, more),
      _ => _check(title, more),
    };
  }

  // ---------------------------------------------------------------------------------------------- 1. which items
  Widget _which(String title, List<AskodoxStepMore> more) {
    final te = _te;
    final sections = _sections;
    return AskodoxStepScaffold(
      key: const Key('askodoxBulkPriceSteps'),
      title: title,
      step: 1,
      more: more,
      question: te ? 'ఏ ఐటమ్స్ ధరలు మార్చాలి?' : 'Which items?',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        if (_items.isEmpty)
          Padding(
              padding: const EdgeInsets.all(24),
              child: Text(te ? 'ఇంకా ఐటమ్స్ లేవు.' : 'No items yet.', textAlign: TextAlign.center)),
        AskodoxStepChoice(
          key: const Key('askodoxBulkPriceScope-all'),
          icon: Icons.select_all_rounded,
          color: askodoxStepGreen,
          title: te ? 'అన్నీ' : 'All items',
          sub: te ? '${_items.length} ఐటమ్స్' : '${_items.length} items',
          selected: _scope == 'all',
          onTap: () => setState(() => _scope = 'all'),
        ),
        if (sections.isNotEmpty) ...[
          const SizedBox(height: 10),
          AskodoxStepChoice(
            key: const Key('askodoxBulkPriceScope-groups'),
            icon: Icons.view_list_rounded,
            color: askodoxStepInfo,
            title: te ? 'విభాగాలు' : 'Sections',
            sub: te ? 'టిఫిన్, డ్రింక్స్ లాంటివి' : 'Like tiffin, drinks',
            selected: _scope == 'groups',
            onTap: () => setState(() => _scope = 'groups'),
          ),
          if (_scope == 'groups')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final g in sections)
                  FilterChip(
                    key: ValueKey('askodoxBulkPriceGroup-$g'),
                    label: Text(g, style: const TextStyle(fontWeight: FontWeight.w800)),
                    selected: _groups.contains(g),
                    onSelected: (on) => setState(() => on ? _groups.add(g) : _groups.remove(g)),
                  ),
              ]),
            ),
        ],
        const SizedBox(height: 10),
        AskodoxStepChoice(
          key: const Key('askodoxBulkPriceScope-items'),
          icon: Icons.checklist_rounded,
          color: askodoxStepWarn,
          title: te ? 'నేను ఎంచుకుంటా' : 'I pick them',
          sub: te ? 'టిక్ చేయండి' : 'Tick the items',
          selected: _scope == 'items',
          onTap: () => setState(() => _scope = 'items'),
        ),
        if (_scope == 'items')
          for (final i in _items)
            CheckboxListTile(
              key: ValueKey('askodoxBulkPricePick-${i['id']}'),
              contentPadding: EdgeInsets.zero,
              value: _picked.contains('${i['id']}'),
              title: Text('${i['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              secondary: Text(askodoxRupee(i['price_paise']), style: const TextStyle(fontWeight: FontWeight.w800)),
              onChanged: (v) => setState(() => v == true ? _picked.add('${i['id']}') : _picked.remove('${i['id']}')),
            ),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxBulkPriceNext1'),
        label: te ? '$_chosenCount ఐటమ్స్ · తర్వాత' : '$_chosenCount items · Next',
        icon: Icons.arrow_forward_rounded,
        onPressed: _chosenCount == 0 ? null : () => setState(() => _step = 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------------------------- 2. how
  Widget _how(String title, List<AskodoxStepMore> more) {
    final te = _te;
    final value = int.tryParse(_value) ?? 0;
    final percent = _mode.endsWith('percent');
    final ok = askodoxBulkValueOk(_mode, value);
    String label(String m) => switch (m) {
          'up_percent' => te ? '% పెంచు' : '% up',
          'down_percent' => te ? '% తగ్గించు' : '% down',
          'up_rupees' => te ? '₹ పెంచు' : '₹ up',
          'down_rupees' => te ? '₹ తగ్గించు' : '₹ down',
          _ => te ? 'ఒకే ధర' : 'One price',
        };
    final sample = _items.isEmpty ? null : _items.first;
    return AskodoxStepScaffold(
      title: title,
      step: 2,
      more: more,
      onBack: _back,
      question: te ? 'ఎలా మార్చాలి?' : 'How?',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final m in askodoxBulkPriceModes)
            ChoiceChip(
              key: ValueKey('askodoxBulkPriceMode-$m'),
              label: Text(label(m), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              selected: _mode == m,
              onSelected: (_) => setState(() => _mode = m),
            ),
        ]),
        const SizedBox(height: 12),
        AskodoxStepBigNumber(percent ? '$value%' : askodoxRupee(value * 100),
            label: label(_mode), color: ok || value == 0 ? askodoxStepInk : askodoxStepBad, size: 48),
        if (sample != null && ok)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${sample['name']}: ${askodoxRupee(sample['price_paise'])} → '
              '${askodoxRupee(askodoxBulkNewPrice(askodoxPosInt(sample['price_paise']), _mode, value, _round))}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: askodoxStepMuted, fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
          for (final r in const [100, 500, 1000, 0])
            ChoiceChip(
              key: ValueKey('askodoxBulkPriceRound-$r'),
              label: Text(r == 0 ? (te ? 'రౌండ్ వద్దు' : 'No rounding') : (te ? '₹${r ~/ 100} కి రౌండ్' : 'Round to ₹${r ~/ 100}')),
              selected: _round == r,
              onSelected: (_) => setState(() => _round = r),
            ),
        ]),
        const SizedBox(height: 10),
        AskodoxStepKeypad(onKey: (k) => setState(() => _value = askodoxKeypadPress(_value, k, maxDigits: percent ? 3 : 6))),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxBulkPriceNext2'),
        label: te ? 'కొత్త ధరలు చూడు' : 'See new prices',
        icon: Icons.arrow_forward_rounded,
        busy: _busy,
        onPressed: ok ? _toPreview : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------------------------- 3. check + ✓
  Widget _check(String title, List<AskodoxStepMore> more) {
    final te = _te;
    final p = _preview ?? const {};
    final lines = askodoxPosList(p['items']);
    final changing = askodoxPosInt(p['changing']);
    final untouched = askodoxPosMap(p['not_changed']);
    final notes = <String>[
      if (askodoxPosInt(untouched['tiers']) > 0)
        te ? '${untouched['tiers']} ఐటమ్స్‌కి క్వాంటిటీ రేట్లు ఉన్నాయి — అవి మారవు' : '${untouched['tiers']} items have quantity rates — not changed',
      if (askodoxPosInt(untouched['packs']) > 0)
        te ? '${untouched['packs']} ఐటమ్స్‌కి ప్యాక్ ధరలు — అవి మారవు' : '${untouched['packs']} items have pack prices — not changed',
      if (askodoxPosInt(untouched['online_price']) > 0)
        te ? '${untouched['online_price']} ఐటమ్స్ ఆన్‌లైన్ ధర వేరు — అది మారదు' : '${untouched['online_price']} items have their own online price — not changed',
    ];
    return AskodoxStepScaffold(
      title: title,
      step: 3,
      more: more,
      onBack: _back,
      question: te ? '$changing ధరలు మారతాయి. సరేనా?' : '$changing prices will change. OK?',
      hint: te ? 'పాత బిల్లులు మారవు' : 'Old bills stay as they are',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        for (final n in notes)
          Padding(padding: const EdgeInsets.only(bottom: 6), child: AskodoxStepPill(n, kind: 'warn')),
        for (final l in lines)
          ListTile(
            key: ValueKey('askodoxBulkPriceLine-${l['id']}'),
            contentPadding: EdgeInsets.zero,
            title: Text('${l['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: '${l['group']}'.isEmpty ? null : Text('${l['group']}'),
            trailing: Text.rich(TextSpan(children: [
              TextSpan(
                  text: askodoxRupee(l['old_paise']),
                  style: const TextStyle(color: askodoxStepMuted, decoration: TextDecoration.lineThrough)),
              const TextSpan(text: '  →  '),
              TextSpan(
                  text: askodoxRupee(l['new_paise']),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: l['changes'] == true ? askodoxStepGreenDark : askodoxStepMuted)),
            ])),
          ),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxBulkPriceApply'),
        label: te ? 'ధరలు మార్చు ✓' : 'Change prices ✓',
        busy: _busy,
        onPressed: changing == 0 ? null : _apply,
      ),
    );
  }

  Widget _finished(String title) {
    final te = _te;
    final n = askodoxPosInt(_done?['changed']);
    return AskodoxStepScaffold(
      title: title,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const AskodoxStepDoneMark(),
          const SizedBox(height: 16),
          Text(te ? '$n ధరలు మారాయి' : '$n prices changed',
              key: const Key('askodoxBulkPriceDone'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: askodoxStepInk)),
          const SizedBox(height: 6),
          Text(te ? 'కొత్త బిల్లుల నుంచి కొత్త ధరలు' : 'New bills use the new prices',
              style: const TextStyle(color: askodoxStepMuted)),
        ]),
      ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxBulkPriceClose'),
        label: te ? 'అయింది' : 'Done',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
