import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_repository.dart';
import 'pos_common.dart';

/// Counter bill as the cashier's counter for EVERY order (owner 2026-11-24): "now" bills at once; a table, parcel or
/// delivery order goes to the kitchen through the front desk (`POST .../desk/orders`, source counter) -- the KOT, the
/// delivery person and the bill (split or together) then run from Live orders like any app order.
const askodoxCounterOrderKinds = <(String, String, String, IconData)>[
  ('now', 'Bill now', 'ఇప్పుడే బిల్', Icons.point_of_sale_rounded),
  ('dine_in', 'Table', 'టేబుల్', Icons.table_restaurant_rounded),
  ('takeaway', 'Parcel', 'పార్సిల్', Icons.takeout_dining_rounded),
  ('delivery', 'Delivery', 'డెలివరీ', Icons.delivery_dining_rounded),
];

/// The desk lines from the counter cart: whole pieces (the desk counts in pieces, max 50 each).
List<AskodoxJson> askodoxCounterDeskLines(List<({String productId, int qtyMilli})> cart) => [
      for (final line in cart)
        if (line.productId.isNotEmpty && line.qtyMilli > 0)
          {'product_id': line.productId, 'qty': (line.qtyMilli / 1000).clamp(0.001, 50).toDouble()},
    ];

/// Side-by-side order-type chips above the total.
class AskodoxCounterKindChips extends StatelessWidget {
  const AskodoxCounterKindChips({super.key, required this.kind, required this.onKind, this.food = true});
  final String kind;
  final ValueChanged<String> onKind;

  /// Tables only for shops that serve food.
  final bool food;

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        for (final (id, en, tel, icon) in askodoxCounterOrderKinds)
          if (food || id != 'dine_in')
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('askodoxCounterKind-$id'),
                avatar: Icon(icon, size: 16),
                label: Text(te ? tel : en),
                selected: kind == id,
                onSelected: (_) => onKind(id),
              ),
            ),
      ]),
    );
  }
}

/// Who / where for a table, parcel or delivery order; returns the desk payload extras (null = cancelled).
Future<AskodoxJson?> askodoxCounterOrderDetails(BuildContext context, WidgetRef ref, String businessId, String kind) async {
  final te = askodoxPosTe(context);
  List<AskodoxJson> tables = const [];
  if (kind == 'dine_in') {
    try {
      tables = await ref.read(askodoxPosRepositoryProvider).tables(businessId);
    } catch (_) {
      tables = const [];
    }
    if (!context.mounted) return null;
  }
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  String? table = tables.isEmpty ? null : '${tables.first['id']}';
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                switch (kind) {
                  'dine_in' => te ? 'ఏ టేబుల్?' : 'Which table?',
                  'delivery' => te ? 'ఎవరికి, ఎక్కడికి?' : 'For whom, where?',
                  _ => te ? 'పార్సిల్ ఎవరిది?' : 'Whose parcel?',
                },
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (kind == 'dine_in')
              tables.isEmpty
                  ? Text(te ? 'టేబుల్స్ ఇంకా పెట్టలేదు — టేబుల్స్ పేజీలో చేర్చండి.' : 'No tables yet — add them on the Tables page.')
                  : Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final t in tables)
                        ChoiceChip(
                          key: Key('askodoxCounterTable-${t['id']}'),
                          label: Text('${t['name'] ?? t['label'] ?? t['id']}'),
                          selected: table == '${t['id']}',
                          onSelected: (_) => setS(() => table = '${t['id']}'),
                        ),
                    ]),
            if (kind != 'dine_in') ...[
              TextField(
                  key: const Key('askodoxCounterName'),
                  controller: name,
                  decoration: InputDecoration(labelText: te ? 'పేరు' : 'Name', border: const OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(
                  key: const Key('askodoxCounterPhone'),
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: kind == 'delivery' ? (te ? 'ఫోన్ (డెలివరీ వ్యక్తి కాల్ చేస్తారు)' : 'Phone (the delivery person calls)') : (te ? 'ఫోన్ (ఐచ్ఛికం)' : 'Phone (optional)'),
                      border: const OutlineInputBorder())),
            ],
            if (kind == 'delivery') ...[
              const SizedBox(height: 8),
              TextField(
                  key: const Key('askodoxCounterAddress'),
                  controller: address,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: te ? 'చిరునామా' : 'Address', border: const OutlineInputBorder())),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('askodoxCounterSend'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: kind == 'dine_in' && table == null ? null : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.soup_kitchen_rounded),
              label: Text(te ? 'కిచెన్‌కి పంపు' : 'Send to kitchen'),
            ),
          ]),
        ),
      ),
    ),
  );
  final out = <String, Object?>{
    'kind': kind,
    if (table != null && kind == 'dine_in') 'table_id': table,
    'name': name.text.trim(),
    'phone': phone.text.trim(),
    'address': address.text.trim(),
  };
  name.dispose();
  phone.dispose();
  address.dispose();
  return ok == true ? out : null;
}
