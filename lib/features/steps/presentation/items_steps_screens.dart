import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_item_icons.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_combo_sheet.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_records_screens.dart' show AskodoxPosItemForm;
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 13): the shop's items `/pos/:id/items`. Top = how many items (and how many are
/// low), middle = ONE list with a search (tap = that item's own page), bottom = ONE big button (add an item). Ready
/// list, combos, where to sell and the old page (per-item offer / stock / online switches) are in the header menu.
class AskodoxItemsStepsScreen extends ConsumerStatefulWidget {
  const AskodoxItemsStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxItemsStepsScreen> createState() => _ItemsState();
}

class _ItemsState extends ConsumerState<AskodoxItemsStepsScreen> {
  List<AskodoxJson>? _items;
  AskodoxJson? _online;
  Object? _error;
  final _search = TextEditingController();
  String _q = '';

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
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.products(widget.businessId);
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _items == null) setState(() => _error = e);
    }
    try {
      final s = await _repo.onlineStatus(widget.businessId);
      if (mounted) setState(() => _online = s);
    } catch (_) {
      // Older server / offline: the "where to sell" row stays hidden.
    }
  }

  Future<void> _add() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AskodoxPosItemForm(businessId: widget.businessId)));
    if (added == true) await _load();
  }

  Future<void> _where() async {
    final te = _te;
    final online = _online;
    if (online == null) return;
    final current = '${online['default'] ?? 'pos'}';
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(te ? 'సరుకులు ఎక్కడ అమ్మాలి?' : 'Where do you sell these items?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            for (final c in const ['pos', 'online', 'both'])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AskodoxStepChoice(
                  key: Key('askodoxItemsStepsWhere-$c'),
                  icon: c == 'pos' ? Icons.storefront_outlined : Icons.public,
                  color: askodoxStepGreen,
                  title: askodoxPosChannelLabel(c, te),
                  sub: '',
                  selected: c == current,
                  onTap: () => Navigator.pop(ctx, c),
                ),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    try {
      final s = await _repo.setOnlineDefault(widget.businessId, picked);
      if (mounted) setState(() => _online = s);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'సరుకులు' : 'Items';
    final items = _items;
    if (items == null) {
      return AskodoxStepScaffold(
          key: const Key('askodoxItemsSteps'),
          title: title,
          body: _error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull;
    final canSettings = business != null && askodoxPosCan(business, 'settings');
    final low = items.where((p) => p['low_stock'] == true).length;
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final p in items)
        if (q.isEmpty || '${p['name']} ${p['name_te'] ?? ''} ${p['item_no'] ?? ''}'.toLowerCase().contains(q)) p
    ];
    return AskodoxStepScaffold(
      key: const Key('askodoxItemsSteps'),
      title: title,
      more: [
        AskodoxStepMore('askodoxItemsStepsCatalogue', te ? 'రెడీ లిస్ట్' : 'Ready list', Icons.playlist_add_check, () async {
          final added = await context.push<bool>('/pos/${widget.businessId}/catalogue');
          if (added == true) await _load();
        }),
        AskodoxStepMore('askodoxItemsStepsCombos', te ? 'కాంబో ఆఫర్లు' : 'Combo offers', Icons.local_offer_outlined,
            () => askodoxShowCombos(context, ref, widget.businessId, items)),
        if (_online != null && canSettings) AskodoxStepMore('askodoxItemsStepsWhere', te ? 'ఎక్కడ అమ్మాలి' : 'Where to sell', Icons.public, _where),
        AskodoxStepMore('askodoxItemsStepsFull', te ? 'పాత పేజీ (ఆఫర్ / స్టాక్ / ఆన్‌లైన్)' : 'Old page (offer / stock / online)', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/items?full=1')),
      ],
      body: items.isEmpty
          ? Center(child: Text(te ? 'ఇంకా సరుకులు లేవు.' : 'No items yet.', key: const Key('askodoxItemsStepsEmpty')))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                AskodoxStepBigNumber('${items.length}',
                    label: low > 0 ? (te ? 'సరుకులు · $low తక్కువ స్టాక్' : 'items · $low low on stock') : (te ? 'సరుకులు' : 'items'), size: 44),
                const SizedBox(height: 10),
                AskodoxStepSearch(
                    fieldKey: const Key('askodoxItemsStepsSearch'),
                    controller: _search,
                    hint: te ? 'పేరు లేదా నంబర్' : 'Name or number',
                    onChanged: (v) => setState(() => _q = v)),
                const SizedBox(height: 8),
                for (final p in shown)
                  AskodoxStepPersonRow(
                    key: ValueKey('askodoxItemsStepsItem-${p['id']}'),
                    name: '${askodoxItemIcon('${p['name'] ?? ''}', nameTe: '${p['name_te'] ?? ''}', category: '${p['category'] ?? ''}')} '
                        '${askodoxPosInt(p['item_no']) > 0 ? '${p['item_no']}. ' : ''}${p['name']}',
                    sub: [
                      if (p['stock_milli'] != null) '${te ? 'స్టాక్' : 'stock'} ${askodoxQty(askodoxPosInt(p['stock_milli']), '${p['unit']}')}',
                      if (p['low_stock'] == true) (te ? 'తక్కువ' : 'LOW'),
                    ].join(' · '),
                    // a bought item with no selling price (owner 2026-11-26): never "₹0"
                    amount: p['buy_only'] == true
                        ? (te ? 'కొన్నది' : 'bought')
                        : '${askodoxPaise(askodoxPosInt(p['price_paise']))}/${p['unit']}',
                    amountColor: p['low_stock'] == true ? askodoxStepBad : askodoxStepInk,
                    onTap: () async {
                      await context.push<String>('/pos/${widget.businessId}/item/${p['id']}');
                      await _load();
                    },
                  ),
              ]),
            ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxItemsStepsAdd'),
        label: te ? 'సరుకు చేర్చు' : 'Add an item',
        icon: Icons.add_rounded,
        onPressed: _add,
      ),
    );
  }
}
