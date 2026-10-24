import 'package:flutter/material.dart';

import '../data/pos_repository.dart';
import '../domain/pos_commands.dart';
import '../domain/pos_money.dart';
import '../domain/pos_pricing.dart';
import 'pos_common.dart';

/// One line the cashier approved from a spoken / typed order.
class AskodoxPosOrderLine {
  const AskodoxPosOrderLine({required this.product, required this.qtyMilli, this.pricePaise});
  final AskodoxJson product;
  final int qtyMilli;

  /// Only when the speaker named a price ("at 240"): a price change the server still checks.
  final int? pricePaise;
}

class AskodoxPosOrderResult {
  const AskodoxPosOrderResult(this.lines, {required this.pay});
  final List<AskodoxPosOrderLine> lines;
  final bool pay;
}

/// Reviews every item of a spoken order before anything enters the bill:
/// each line with its rate (rate by quantity applied), what was not found,
/// the total, "Read aloud", then Add or Add & pay. Nothing is added silently.
class AskodoxPosOrderReviewSheet extends StatefulWidget {
  const AskodoxPosOrderReviewSheet({
    super.key,
    required this.order,
    required this.products,
    required this.customerPrices,
    this.speak,
  });

  final List<({String phrase, AskodoxPosCommand command})> order;
  final List<AskodoxJson> products;
  final Map<String, int> customerPrices;

  /// Says the read-back (the guide's voice: Sarvam, else device TTS); null = no voice.
  final Future<void> Function(String text, String language)? speak;

  @override
  State<AskodoxPosOrderReviewSheet> createState() => _AskodoxPosOrderReviewSheetState();
}

class _Row {
  _Row(this.phrase, this.command);
  final String phrase;
  AskodoxPosCommand command;
  bool include = true;
}

class _AskodoxPosOrderReviewSheetState extends State<AskodoxPosOrderReviewSheet> {
  late final List<_Row> _rows = [for (final o in widget.order) _Row(o.phrase, o.command)];

  List<AskodoxPosItemRef> get _refs => [
        for (final p in widget.products)
          AskodoxPosItemRef(id: '${p['id']}', name: '${p['name']}', nameTe: '${p['name_te'] ?? ''}', unit: '${p['unit']}'),
      ];

  AskodoxJson? _product(String id) => widget.products.where((p) => '${p['id']}' == id).firstOrNull;

  int _rate(AskodoxJson product, int qty, int? spoken) =>
      spoken ??
      widget.customerPrices['${product['id']}'] ??
      askodoxTierPrice(product, qty) ??
      askodoxPosInt(product['price_paise']);

  bool _ready(_Row r) => r.command.kind == AskodoxPosCommandKind.add && r.command.item != null && r.command.qtyMilli != null;

  String? _problem(_Row r, bool te) {
    final c = r.command;
    if (c.needsChoice) return te ? 'ఏది? ఎంచుకోండి' : 'Which one? Pick';
    if (c.kind != AskodoxPosCommandKind.add || c.item == null) return te ? 'సరుకు దొరకలేదు' : 'Item not found';
    final p = _product(c.item!.id);
    final min = p == null ? null : askodoxMinQty(p);
    if (min != null && (c.qtyMilli ?? 0) < min) {
      return te ? 'కనీసం ${askodoxQty(min, c.item!.unit)}' : 'Least is ${askodoxQty(min, c.item!.unit)}';
    }
    return null;
  }

  int get _total {
    var sum = 0;
    for (final r in _rows) {
      if (!r.include || !_ready(r) || _problem(r, false) != null) continue;
      final p = _product(r.command.item!.id);
      if (p == null) continue;
      sum += askodoxRoundDiv(r.command.qtyMilli! * _rate(p, r.command.qtyMilli!, r.command.pricePaise), 1000);
    }
    return sum;
  }

  void _pick(_Row r, AskodoxPosItemRef item) {
    final again = askodoxParsePosCommand(r.phrase, [item]);
    setState(() => r.command = again.item != null ? again : AskodoxPosCommand(AskodoxPosCommandKind.unknown, query: r.phrase));
  }

  String _speech(bool te) {
    final parts = <String>[];
    for (final r in _rows) {
      if (!r.include || !_ready(r) || _problem(r, te) != null) continue;
      final item = r.command.item!;
      parts.add('${askodoxQty(r.command.qtyMilli!, item.unit)} ${te && item.nameTe.isNotEmpty ? item.nameTe : item.name}');
    }
    final total = askodoxPaise(_total).replaceAll('₹', '');
    return te ? '${parts.join(', ')}. మొత్తం $total రూపాయలు. సరేనా?' : '${parts.join(', ')}. Total $total rupees. Shall I add these?';
  }

  Future<void> _readAloud(bool te) async {
    try {
      await widget.speak?.call(_speech(te), te ? 'te' : 'en');
    } catch (_) {
      // No voice on this device: the list on screen is the read-back.
    }
  }

  void _finish(bool pay) {
    final lines = <AskodoxPosOrderLine>[];
    for (final r in _rows) {
      if (!r.include || !_ready(r) || _problem(r, false) != null) continue;
      final p = _product(r.command.item!.id);
      if (p != null) lines.add(AskodoxPosOrderLine(product: p, qtyMilli: r.command.qtyMilli!, pricePaise: r.command.pricePaise));
    }
    Navigator.pop(context, AskodoxPosOrderResult(lines, pay: pay));
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final good = _rows.where((r) => r.include && _ready(r) && _problem(r, te) == null).length;
    return SafeArea(
      child: Padding(
        key: const Key('askodoxPosMultiReview'),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text(te ? 'ఈ సరుకులు బిల్లులో వేయాలా?' : 'Add these to the bill?',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                key: const Key('askodoxPosMultiRead'),
                tooltip: te ? 'చదివి వినిపించు' : 'Read aloud',
                onPressed: () => _readAloud(te),
                icon: const Icon(Icons.volume_up_outlined),
              ),
            ]),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (var i = 0; i < _rows.length; i++) _line(i, te),
            ]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(children: [
              Expanded(
                child: Text('${te ? 'మొత్తం (పన్ను ముందు)' : 'Total (before tax)'} ${askodoxPaise(_total)}',
                    key: const Key('askodoxPosMultiTotal'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              OutlinedButton(
                key: const Key('askodoxPosMultiAdd'),
                onPressed: good == 0 ? null : () => _finish(false),
                child: Text(te ? 'జోడించు' : 'Add'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('askodoxPosMultiPay'),
                onPressed: good == 0 ? null : () => _finish(true),
                child: Text(te ? 'జోడించి బిల్లు' : 'Add & pay'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _line(int i, bool te) {
    final r = _rows[i];
    final problem = _problem(r, te);
    final c = r.command;
    if (c.needsChoice) {
      return ListTile(
        key: ValueKey('askodoxPosMultiLine-$i'),
        dense: true,
        leading: const Icon(Icons.help_outline, color: Color(0xFFB45309)),
        title: Text('"${r.phrase}" — $problem'),
        subtitle: Wrap(spacing: 6, children: [
          for (final cand in c.candidates)
            ActionChip(
              key: ValueKey('askodoxPosMultiPick-$i-${cand.id}'),
              label: Text(te && cand.nameTe.isNotEmpty ? cand.nameTe : cand.name),
              onPressed: () => _pick(r, cand),
            ),
        ]),
      );
    }
    if (problem != null) {
      return ListTile(
        key: ValueKey('askodoxPosMultiLine-$i'),
        dense: true,
        leading: const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
        title: Text('"${r.phrase}"'),
        subtitle: Text(problem, style: const TextStyle(color: Color(0xFFB91C1C))),
        trailing: c.item == null
            ? PopupMenuButton<AskodoxPosItemRef>(
                key: ValueKey('askodoxPosMultiChoose-$i'),
                tooltip: te ? 'సరుకు ఎంచుకోండి' : 'Choose the item',
                onSelected: (item) => _pick(r, item),
                itemBuilder: (_) => [
                  for (final ref in _refs) PopupMenuItem(value: ref, child: Text(te && ref.nameTe.isNotEmpty ? ref.nameTe : ref.name)),
                ],
                icon: const Icon(Icons.list),
              )
            : null,
      );
    }
    final p = _product(c.item!.id)!;
    final rate = _rate(p, c.qtyMilli!, c.pricePaise);
    final amount = askodoxRoundDiv(c.qtyMilli! * rate, 1000);
    final tier = c.pricePaise == null && widget.customerPrices['${p['id']}'] == null && askodoxTierPrice(p, c.qtyMilli!) != null;
    return CheckboxListTile(
      key: ValueKey('askodoxPosMultiLine-$i'),
      dense: true,
      value: r.include,
      onChanged: (v) => setState(() => r.include = v ?? false),
      title: Text('${askodoxQty(c.qtyMilli!, c.item!.unit)} ${te && c.item!.nameTe.isNotEmpty ? c.item!.nameTe : c.item!.name}'),
      subtitle: Text([
        '${askodoxPaise(rate)}/${c.item!.unit}',
        if (tier) (te ? '· పరిమాణం ధర' : '· quantity rate'),
        if (c.pricePaise != null) (te ? '· ధర మార్పు (మేనేజర్)' : '· price change (manager)'),
      ].join(' ')),
      secondary: Text(askodoxPaise(amount), style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
