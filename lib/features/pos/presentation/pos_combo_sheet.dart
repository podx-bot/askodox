import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import 'pos_common.dart';

/// Combo offers (owner 2026-11-20): 2-6 of the shop's own items for one price. The bill takes the saving off by itself
/// when all of a combo's items are on it (counter, table, parcel and delivery orders).
Future<void> askodoxShowCombos(BuildContext context, WidgetRef ref, String businessId, List<AskodoxJson> products) async {
  final te = askodoxPosTe(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => _CombosSheet(businessId: businessId, products: products, te: te),
  );
}

class _CombosSheet extends ConsumerStatefulWidget {
  const _CombosSheet({required this.businessId, required this.products, required this.te});
  final String businessId;
  final List<AskodoxJson> products;
  final bool te;

  @override
  ConsumerState<_CombosSheet> createState() => _CombosSheetState();
}

class _CombosSheetState extends ConsumerState<_CombosSheet> {
  List<AskodoxJson>? _combos;
  bool _adding = false;
  final _name = TextEditingController();
  final _price = TextEditingController();
  final Set<String> _picked = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final combos = await ref.read(askodoxPosRepositoryProvider).combos(widget.businessId);
      if (mounted) setState(() => _combos = combos);
    } on AskodoxPosException catch (e) {
      if (mounted) {
        setState(() {
          _combos = const [];
          _error = e.message(widget.te);
        });
      }
    }
  }

  Future<void> _save(List<AskodoxJson> next) async {
    try {
      final saved = await ref.read(askodoxPosRepositoryProvider).saveCombos(widget.businessId, next);
      if (!mounted) return;
      setState(() {
        _combos = saved;
        _adding = false;
        _error = null;
        _name.clear();
        _price.clear();
        _picked.clear();
      });
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e.message(widget.te));
    }
  }

  String _itemName(String id) {
    for (final p in widget.products) {
      if ('${p['id']}' == id) return '${p['name']}';
    }
    return '?';
  }

  int _itemsTotal(Iterable<String> ids) {
    var sum = 0;
    for (final p in widget.products) {
      if (ids.contains('${p['id']}')) sum += askodoxPosInt(p['price_paise']);
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final combos = _combos;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
          child: ListView(shrinkWrap: true, children: [
            Text(te ? 'కాంబో ఆఫర్లు' : 'Combo offers', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(
                te
                    ? 'రెండు మూడు ఐటమ్స్ కలిపి ఒక ధర. బిల్లులో అవన్నీ ఉంటే తగ్గింపు దానంతట అదే పడుతుంది.'
                    : 'A few items together for one price. The bill takes the saving off by itself when all of them are on it.',
                style: const TextStyle(fontSize: 12.5)),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(color: Color(0xFFB42318)))),
            if (combos == null)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else ...[
              for (final c in combos)
                ListTile(
                  key: ValueKey('askodoxPosCombo-${c['id']}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.local_offer_outlined),
                  title: Text('${c['name']} · ${askodoxPaise(askodoxPosInt(c['price_paise']))}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([for (final i in (c['items'] as List? ?? const [])) _itemName('$i')].join(' + ')),
                  trailing: IconButton(
                    tooltip: te ? 'తీసేయి' : 'Remove',
                    onPressed: () => _save([for (final x in combos) if (x['id'] != c['id']) x]),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              if (!_adding)
                OutlinedButton.icon(
                  key: const Key('askodoxPosComboAdd'),
                  onPressed: () => setState(() => _adding = true),
                  icon: const Icon(Icons.add),
                  label: Text(te ? 'కొత్త కాంబో' : 'New combo'),
                )
              else ...[
                const SizedBox(height: 8),
                TextField(
                    key: const Key('askodoxPosComboName'),
                    controller: _name,
                    decoration: InputDecoration(
                        labelText: te ? 'కాంబో పేరు' : 'Combo name', isDense: true, border: const OutlineInputBorder())),
                const SizedBox(height: 8),
                Text(te ? 'ఐటమ్స్ ఎంచుకోండి (2-6)' : 'Choose the items (2-6)', style: const TextStyle(fontWeight: FontWeight.w700)),
                Wrap(spacing: 6, children: [
                  for (final p in widget.products)
                    FilterChip(
                      key: ValueKey('askodoxPosComboItem-${p['id']}'),
                      label: Text('${p['name']}'),
                      selected: _picked.contains('${p['id']}'),
                      onSelected: (on) => setState(() => on ? _picked.add('${p['id']}') : _picked.remove('${p['id']}')),
                    ),
                ]),
                const SizedBox(height: 8),
                TextField(
                    key: const Key('askodoxPosComboPrice'),
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: te ? 'కాంబో ధర ₹' : 'Combo price ₹',
                        helperText: _picked.isEmpty
                            ? null
                            : '${te ? 'విడిగా' : 'Separately'}: ${askodoxPaise(_itemsTotal(_picked))}',
                        isDense: true,
                        border: const OutlineInputBorder())),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('askodoxPosComboSave'),
                  onPressed: () {
                    final price = askodoxParsePaise(_price.text);
                    if (_name.text.trim().isEmpty || _picked.length < 2 || _picked.length > 6 || price == null || price <= 0) {
                      setState(() => _error = te ? 'పేరు, 2-6 ఐటమ్స్, ధర కావాలి.' : 'A name, 2-6 items and the price are needed.');
                      return;
                    }
                    _save([
                      ...combos,
                      {'name': _name.text.trim(), 'items': _picked.toList(), 'price_paise': price},
                    ]);
                  },
                  child: Text(te ? 'కాంబో సేవ్ చేయి' : 'Save combo'),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}
