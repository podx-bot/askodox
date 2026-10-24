import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/media_picker.dart';
import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import 'pos_common.dart';

/// An item's photo, keyed "business|product|photo_at" so a new photo is fetched
/// once and an item without one never calls the server.
final askodoxPosPhotoProvider = FutureProvider.family<Uint8List?, String>((ref, key) async {
  final parts = key.split('|');
  if (parts.length < 3 || parts[2].isEmpty || parts[2] == 'null') return null;
  try {
    final out = await ref.read(askodoxPosRepositoryProvider).photo(parts[0], parts[1]);
    final data = '${out['image_base64'] ?? ''}';
    return data.isEmpty ? null : base64Decode(data);
  } catch (_) {
    return null;
  }
});

String askodoxPosPhotoKey(String businessId, AskodoxJson product) =>
    '$businessId|${product['id']}|${product['photo_at'] ?? ''}';

/// One picture tile on the bill screen (the item's photo, else its first letter).
class AskodoxPosProductTile extends ConsumerWidget {
  const AskodoxPosProductTile({
    super.key,
    required this.businessId,
    required this.product,
    required this.priceText,
    required this.onTap,
    this.inCartMilli = 0,
  });

  final String businessId;
  final AskodoxJson product;
  final String priceText;
  final VoidCallback onTap;
  final int inCartMilli;

  static const _colors = [
    Color(0xFFDBEAFE), Color(0xFFDCFCE7), Color(0xFFFEF3C7), Color(0xFFFCE7F3),
    Color(0xFFE0E7FF), Color(0xFFCCFBF1), Color(0xFFFFEDD5), Color(0xFFF3E8FF),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    final name = te && '${product['name_te'] ?? ''}'.isNotEmpty ? '${product['name_te']}' : '${product['name']}';
    final photo = ref.watch(askodoxPosPhotoProvider(askodoxPosPhotoKey(businessId, product))).valueOrNull;
    final color = _colors[name.hashCode.abs() % _colors.length];
    final stock = product['stock_milli'];
    final low = product['low_stock'] == true;
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              photo != null
                  ? Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true)
                  : Container(
                      color: color,
                      alignment: Alignment.center,
                      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF1F2937))),
                    ),
              if (inCartMilli > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(10)),
                    child: Text(askodoxQty(inCartMilli, ''),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              Text(priceText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
              if (stock != null)
                Text('${te ? 'స్టాక్' : 'Stock'} ${askodoxQty(askodoxPosInt(stock), '${product['unit']}')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: low ? const Color(0xFFB91C1C) : const Color(0xFF6B7280))),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Picks one photo, shrinks it to at most 240 px wide (PNG stays under the 300 KB server cap) and returns PNG bytes as base64 (null when cancelled).
Future<String?> askodoxPosPickPhoto(WidgetRef ref, String source) async {
  final picked = await ref.read(askodoxMediaPickerProvider).pick(source);
  final photo = picked.where((p) => p.isImage).firstOrNull;
  if (photo == null) return null;
  return askodoxPosShrinkPhoto(photo.bytes);
}

Future<String?> askodoxPosShrinkPhoto(Uint8List bytes, {int width = 240}) async {
  try {
    final probe = await ui.instantiateImageCodec(bytes);
    final first = await probe.getNextFrame();
    final w = first.image.width;
    first.image.dispose();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: w > width ? width : null);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) return null;
    return base64Encode(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// Photo + "rate by quantity" + least quantity for one item (item details page).
class AskodoxPosRatesCard extends ConsumerStatefulWidget {
  const AskodoxPosRatesCard({super.key, required this.businessId, required this.product, required this.onSaved});
  final String businessId;
  final AskodoxJson product;
  final VoidCallback onSaved;

  @override
  ConsumerState<AskodoxPosRatesCard> createState() => _AskodoxPosRatesCardState();
}

class _TierRow {
  _TierRow(String qty, String total)
      : qty = TextEditingController(text: qty),
        total = TextEditingController(text: total);
  final TextEditingController qty;
  final TextEditingController total;
}

class _AskodoxPosRatesCardState extends ConsumerState<AskodoxPosRatesCard> {
  late bool _sameRate;
  final _rows = <_TierRow>[];
  final _minimum = TextEditingController();
  bool _busy = false;

  String get _unit => '${widget.product['unit'] ?? ''}';

  @override
  void initState() {
    super.initState();
    final tiers = askodoxPosList(widget.product['tiers']);
    _sameRate = tiers.isEmpty;
    for (final t in tiers) {
      final qty = askodoxPosInt(t['min_qty_milli']);
      final total = askodoxRoundDiv(askodoxPosInt(t['price_paise']) * qty, 1000);
      _rows.add(_TierRow(_plain(qty), askodoxPaise(total, symbol: false).replaceAll(',', '')));
    }
    final min = widget.product['min_qty_milli'];
    _minimum.text = min == null || askodoxPosInt(min) <= 0 ? '' : _plain(askodoxPosInt(min));
  }

  static String _plain(int milli) {
    final v = milli / 1000;
    return v == v.roundToDouble() ? '${v.round()}' : '$v';
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.qty.dispose();
      r.total.dispose();
    }
    _minimum.dispose();
    super.dispose();
  }

  void _addRow() {
    // A useful first row: a quarter of a kilo / litre, else empty.
    final first = _rows.isEmpty && (_unit == 'kg' || _unit == 'l');
    _rows.add(_TierRow(first ? '0.25' : '', ''));
  }

  Future<void> _save() async {
    final te = askodoxPosTe(context);
    final tiers = <AskodoxJson>[];
    if (!_sameRate) {
      for (final r in _rows) {
        if (r.qty.text.trim().isEmpty && r.total.text.trim().isEmpty) continue;
        final qty = askodoxParseMilli(r.qty.text);
        final total = askodoxParsePaise(r.total.text);
        if (qty == null || qty <= 0 || total == null || total <= 0) {
          askodoxPosSnack(context, te ? 'ప్రతి వరుసలో పరిమాణం, ఆ పరిమాణానికి మొత్తం ధర రాయండి.' : 'Each row needs a quantity and the price for that quantity.');
          return;
        }
        tiers.add({'min_qty_milli': qty, 'price_paise': askodoxRoundDiv(total * 1000, qty)});
      }
    }
    final minText = _minimum.text.trim();
    final minimum = minText.isEmpty ? null : askodoxParseMilli(minText);
    if (minText.isNotEmpty && (minimum == null || minimum <= 0)) {
      askodoxPosSnack(context, te ? 'కనీస పరిమాణం సరిగ్గా రాయండి.' : 'Type the least quantity as a number.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).setPricing(widget.businessId, '${widget.product['id']}', tiers, minimum);
      if (!mounted) return;
      askodoxPosSnack(context, te ? 'ధరలు సేవ్ అయ్యాయి.' : 'Rates saved.');
      widget.onSaved();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo(String source) async {
    final te = askodoxPosTe(context);
    final data = await askodoxPosPickPhoto(ref, source);
    if (data == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).setPhoto(widget.businessId, '${widget.product['id']}', data);
      if (!mounted) return;
      askodoxPosSnack(context, te ? 'ఫోటో సేవ్ అయింది.' : 'Photo saved.');
      widget.onSaved();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final p = widget.product;
    final price = askodoxPaise(askodoxPosInt(p['price_paise']));
    final photo = ref.watch(askodoxPosPhotoProvider(askodoxPosPhotoKey(widget.businessId, p))).valueOrNull;
    return Card(
      key: const Key('askodoxPosRatesCard'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: photo != null
                    ? Image.memory(photo, fit: BoxFit.cover)
                    : Container(color: const Color(0xFFF3F4F6), child: const Icon(Icons.image_outlined)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                OutlinedButton.icon(
                  key: const Key('askodoxPosPhotoCamera'),
                  onPressed: _busy ? null : () => _photo('camera'),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(te ? 'ఫోటో తీయండి' : 'Take photo'),
                ),
                OutlinedButton.icon(
                  key: const Key('askodoxPosPhotoGallery'),
                  onPressed: _busy ? null : () => _photo('gallery'),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(te ? 'గ్యాలరీ' : 'Gallery'),
                ),
              ]),
            ),
          ]),
          const Divider(height: 22),
          Text(te ? 'పరిమాణం బట్టి ధర' : 'Rate by quantity', style: const TextStyle(fontWeight: FontWeight.w800)),
          RadioGroup<bool>(
            groupValue: _sameRate,
            onChanged: (v) => setState(() {
              _sameRate = v ?? true;
              if (!_sameRate && _rows.isEmpty) _addRow();
            }),
            child: Column(children: [
              RadioListTile<bool>(
                key: const Key('askodoxPosSameRate'),
                contentPadding: EdgeInsets.zero,
                value: true,
                title: Text(te ? 'ఒకే ధర — $price / $_unit నుండి లెక్క' : 'One rate — work it out from $price / $_unit'),
              ),
              RadioListTile<bool>(
                key: const Key('askodoxPosTieredRate'),
                contentPadding: EdgeInsets.zero,
                value: false,
                title: Text(te ? 'పరిమాణం బట్టి వేరే ధరలు (పావు కిలో, కిలో, 10 కిలోలు…)' : 'Different rates by quantity (¼ kg, 1 kg, 10 kg…)'),
              ),
            ]),
          ),
          if (!_sameRate) ...[
            Text(
                te
                    ? 'ఎంత పరిమాణానికి ఎంత ధరో రాయండి. ఎక్కువ కొంటే ఆ వరుసలోని రేటు వాడుతుంది.'
                    : 'Write the price for each quantity. Larger amounts use the rate of the biggest row they reach.',
                style: const TextStyle(fontSize: 12)),
            for (var i = 0; i < _rows.length; i++)
              Row(key: ValueKey('askodoxPosTier-$i'), children: [
                Expanded(
                  child: AskodoxPosField(
                    key: ValueKey('askodoxPosTierQty-$i'),
                    controller: _rows[i].qty,
                    number: true,
                    label: te ? 'పరిమాణం ($_unit)' : 'Quantity ($_unit)',
                    guideEn: 'How much the customer buys for this rate, in $_unit. A quarter kilo is 0.25.',
                    guideTe: 'ఈ ధరకు కస్టమర్ ఎంత కొంటారో ($_unit లో). పావు కిలో = 0.25.',
                    exampleEn: '0.25 · 1 · 10 · 100',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AskodoxPosField(
                    key: ValueKey('askodoxPosTierTotal-$i'),
                    controller: _rows[i].total,
                    number: true,
                    label: te ? 'ఆ పరిమాణానికి ధర (₹)' : 'Price for that (₹)',
                    guideEn: 'The total price for that quantity, not per unit. Example: ¼ kg for ₹45.',
                    guideTe: 'ఆ పరిమాణానికి మొత్తం ధర (ఒక్క యూనిట్ ధర కాదు). ఉదా: పావు కిలో ₹45.',
                    exampleEn: '45',
                  ),
                ),
                IconButton(
                  key: ValueKey('askodoxPosTierRemove-$i'),
                  onPressed: () => setState(() => _rows.removeAt(i)),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ]),
            if (_rows.length < 12)
              TextButton.icon(
                key: const Key('askodoxPosTierAdd'),
                onPressed: () => setState(_addRow),
                icon: const Icon(Icons.add),
                label: Text(te ? 'ఇంకో పరిమాణం' : 'Add a quantity'),
              ),
          ],
          AskodoxPosField(
            key: const Key('askodoxPosMinQty'),
            controller: _minimum,
            number: true,
            label: te ? 'కనీసం ఎంత అమ్ముతారు ($_unit, ఖాళీ = ఎంతైనా)' : 'Least you sell ($_unit, empty = any)',
            guideEn: 'The smallest amount you sell of this item. The bill refuses less. Leave empty to sell any amount.',
            guideTe: 'ఈ సరుకు కనీసం ఎంత అమ్ముతారో. అంతకంటే తక్కువ బిల్లులో రాదు. ఎంతైనా అమ్మితే ఖాళీగా ఉంచండి.',
            exampleEn: '0.25',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              key: const Key('askodoxPosRatesSave'),
              onPressed: _busy ? null : _save,
              child: Text(te ? 'ధరలు సేవ్' : 'Save rates'),
            ),
          ),
        ]),
      ),
    );
  }
}
