import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../devices/data/device_repository.dart';
import '../../guide/in_app_guide.dart' show askodoxGuideSpeakerProvider;
import '../../home/presentation/question_mic.dart';
import '../data/pos_hardware.dart';
import '../data/pos_printer.dart';
import '../data/pos_raster.dart';
import '../data/pos_repository.dart';
import '../domain/escpos.dart';
import '../domain/pos_commands.dart';
import '../domain/pos_money.dart';
import '../domain/pos_pricing.dart';
import '../domain/pos_scale.dart';
import '../domain/pos_tax.dart';
import 'pos_common.dart';
import 'pos_restaurant_screens.dart' show AskodoxPosDraftsScreen;
import 'pos_order_review.dart';
import 'pos_tiles.dart';

class AskodoxCartLine {
  AskodoxCartLine({required this.product, required this.qtyMilli, required this.pricePaise, this.override = false,
      this.discountPaise = 0, this.grossMilli, this.tareMilli, this.fromScale = false, this.pack, this.serials = const []});
  final AskodoxJson product;

  /// A selling unit other than the base unit (e.g. 'box'); [qtyMilli] and [pricePaise] are per pack.
  final String? pack;

  /// Serial / IMEI numbers of the pieces sold (one per piece).
  final List<String> serials;
  int qtyMilli;
  int pricePaise;
  bool override;
  int discountPaise;
  int? grossMilli;
  int? tareMilli;

  /// The weight came from a Bluetooth scale (still unverified for trade use).
  bool fromScale;

  String get unit => pack ?? '${product['unit']}';

  AskodoxLineInput get taxInput => AskodoxLineInput(
        qtyMilli: qtyMilli,
        unitPricePaise: pricePaise,
        discountPaise: discountPaise,
        rateBp: askodoxPosInt(product['rate_bp']),
        cessBp: askodoxPosInt(product['cess_bp']),
        priceIncludesTax: product['price_includes_tax'] == true,
        category: '${product['category'] ?? 'taxable'}',
      );

  AskodoxJson toRequest() => {
        'product_id': product['id'],
        if (grossMilli != null || fromScale)
          'weight': {'gross_milli': grossMilli ?? qtyMilli, 'tare_milli': tareMilli ?? 0, 'source': fromScale ? 'scale' : 'typed'}
        else
          'qty_milli': qtyMilli,
        if (override) 'unit_price_paise': pricePaise,
        if (discountPaise > 0) 'discount_paise': discountPaise,
        if (pack != null) 'pack': pack,
        if (serials.isNotEmpty) 'serials': serials,
      };
}

/// Price of one [pack] of [product]: the pack's own price, else base price x factor.
int askodoxPackPrice(AskodoxJson product, AskodoxJson pack) => pack['price_paise'] != null
    ? askodoxPosInt(pack['price_paise'])
    : askodoxRoundDiv(askodoxPosInt(product['price_paise']) * askodoxPosInt(pack['factor_milli']), 1000);

const _weighed = {'kg', 'g', 'l', 'ml'};

/// The counter: find items (name / barcode / Telugu name / typed command),
/// build the bill, take payment, issue. The bill number and final amounts come
/// from the server; without internet the sale is kept on this phone with this
/// device's own bill number and sent later.
class AskodoxPosSaleScreen extends ConsumerStatefulWidget {
  const AskodoxPosSaleScreen({super.key, required this.businessId, this.leadId, this.customerId});
  final String businessId;

  /// Opened from a Business CRM lead: a quotation made here is linked to that lead.
  final String? leadId;

  /// Opened for a known customer (CRM): the bill / quotation starts with them picked.
  final String? customerId;

  @override
  ConsumerState<AskodoxPosSaleScreen> createState() => _AskodoxPosSaleScreenState();
}

class _AskodoxPosSaleScreenState extends ConsumerState<AskodoxPosSaleScreen> {
  final _search = TextEditingController();
  final _command = TextEditingController();
  List<AskodoxJson> _products = const [];
  final List<AskodoxCartLine> _cart = [];
  AskodoxJson? _customer;
  Map<String, int> _customerPrices = const {};
  bool _loading = true;
  bool _issuing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    ref.read(askodoxPosQueueProvider).ensureSeries(widget.businessId).catchError((_) => <String, Object?>{});
  }

  @override
  void dispose() {
    _search.dispose();
    _command.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(askodoxPosRepositoryProvider).products(widget.businessId);
      Object? shopDefault;
      try {
        shopDefault = (await ref.read(askodoxPosRepositoryProvider).business(widget.businessId))['online_default'];
      } catch (_) {}
      // "Online only" items are offered in ASKODOX, not at the counter.
      final counter = [for (final p in list) if (askodoxPosChannel(p, shopDefault) != 'online') p];
      if (mounted) setState(() => _products = counter);
      final customerId = widget.customerId;
      if (customerId != null && customerId.isNotEmpty) {
        final full = await ref.read(askodoxPosRepositoryProvider).customer(widget.businessId, customerId);
        if (mounted) {
          setState(() {
            _customer = full;
            _customerPrices = {for (final e in askodoxPosMap(full['prices']).entries) e.key: askodoxPosInt(e.value)};
          });
        }
      }
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e.message(askodoxPosTe(context)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _priceFor(AskodoxJson p) => _customerPrices['${p['id']}'] ?? askodoxPosInt(p['price_paise']);

  List<AskodoxJson> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products
        .where((p) => '${p['name']}'.toLowerCase().contains(q) || '${p['name_te']}'.contains(q) || '${p['barcode']}' == q ||
            '${p['sku']}'.toLowerCase() == q)
        .toList();
  }

  /// Lines priced by the item (no typed price, no pack, no customer rate) follow the shop's rate by quantity.
  void _repriceLines() {
    for (final l in _cart) {
      if (l.override || l.pack != null) continue;
      final id = '${l.product['id']}';
      l.pricePaise = _customerPrices[id] ?? askodoxTierPrice(l.product, l.qtyMilli) ?? askodoxPosInt(l.product['price_paise']);
    }
  }

  void _addLine(AskodoxJson product, int qtyMilli,
      {int? price, int? gross, int? tare, bool fromScale = false, AskodoxJson? pack, List<String> serials = const []}) {
    final minimum = pack == null ? askodoxMinQty(product) : null;
    if (minimum != null) {
      final already = _cart
          .where((l) => l.product['id'] == product['id'] && l.pack == null)
          .fold<int>(0, (sum, l) => sum + l.qtyMilli);
      if (already + qtyMilli < minimum) {
        final te = askodoxPosTe(context);
        askodoxPosSnack(
            context,
            te
                ? '${product['name']}: కనీసం ${askodoxQty(minimum, '${product['unit']}')} అమ్ముతారు.'
                : '${product['name']}: the least you sell is ${askodoxQty(minimum, '${product['unit']}')}.');
        return;
      }
    }
    setState(() {
      final listed = pack != null ? askodoxPackPrice(product, pack) : _priceFor(product);
      final packName = pack == null ? null : '${pack['name']}';
      final existing = _cart.where((l) => l.product['id'] == product['id'] && l.grossMilli == null && gross == null &&
          !l.fromScale && !fromScale && l.pack == packName && l.serials.isEmpty && serials.isEmpty &&
          (price == null || price == l.pricePaise));
      if (existing.isNotEmpty) {
        existing.first.qtyMilli += qtyMilli;
      } else {
        _cart.add(AskodoxCartLine(product: product, qtyMilli: qtyMilli, pricePaise: price ?? listed,
            override: price != null && price != listed, grossMilli: gross, tareMilli: tare, fromScale: fromScale,
            pack: packName, serials: serials));
      }
      _repriceLines();
    });
  }

  /// Opens the right picker: serial items -> choose serials; items with packs -> unit + qty; else qty / weight.
  Future<void> _choose(AskodoxJson product) async {
    if (product['track_serials'] == true) return _pickSerials(product);
    final packs = askodoxPosList(product['packs']);
    if (packs.isNotEmpty && !_weighed.contains(product['unit'])) return _pickUnit(product, packs);
    return _pickQty(product);
  }

  Future<void> _pickUnit(AskodoxJson product, List<AskodoxJson> packs, {String? initial}) async {
    final te = askodoxPosTe(context);
    final qty = TextEditingController(text: '1');
    String chosen = initial ?? '${product['unit']}';
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${product['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, children: [
              ChoiceChip(
                  label: Text('${product['unit']} · ${askodoxPaise(_priceFor(product))}'),
                  selected: chosen == product['unit'],
                  onSelected: (_) => setLocal(() => chosen = '${product['unit']}')),
              for (final p in packs)
                ChoiceChip(
                  key: ValueKey('askodoxPosPack-${p['name']}'),
                  label: Text('${p['name']} (${askodoxQty(askodoxPosInt(p['factor_milli']), '${product['unit']}')}) · ${askodoxPaise(askodoxPackPrice(product, p))}'),
                  selected: chosen == p['name'],
                  onSelected: (_) => setLocal(() => chosen = '${p['name']}'),
                ),
            ]),
            AskodoxPosField(controller: qty, number: true, label: te ? 'సంఖ్య' : 'Quantity'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(
              key: const Key('askodoxPosUnitOk'),
              onPressed: () {
                final q = askodoxParseMilli(qty.text);
                if (q == null || q <= 0) return;
                Navigator.pop(ctx, (q, chosen));
              },
              child: Text(te ? 'జోడించు' : 'Add'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final pack = packs.where((p) => p['name'] == result.$2).firstOrNull;
    _addLine(product, result.$1, pack: pack);
  }

  /// Serial / IMEI items: pick the exact pieces sold (from stock, or typed / scanned).
  Future<void> _pickSerials(AskodoxJson product) async {
    final te = askodoxPosTe(context);
    List<String> inStock;
    try {
      inStock = await ref.read(askodoxPosRepositoryProvider).serialsInStock(widget.businessId, '${product['id']}');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (!mounted) return;
    final taken = {for (final l in _cart) ...l.serials};
    final available = inStock.where((s) => !taken.contains(s)).toList();
    final chosen = <String>{};
    final typed = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${product['name']} · ${product['serial_kind'] == 'imei' ? 'IMEI' : (te ? 'సీరియల్' : 'serial')}'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: AskodoxPosField(controller: typed, label: te ? 'టైప్ / స్కాన్' : 'Type / scan')),
                IconButton(
                  onPressed: () {
                    final v = typed.text.trim().toUpperCase();
                    if (v.isEmpty) return;
                    setLocal(() {
                      if (available.contains(v)) chosen.add(v);
                      typed.clear();
                    });
                  },
                  icon: const Icon(Icons.add),
                ),
              ]),
              if (available.isEmpty) Text(te ? 'స్టాక్‌లో సీరియల్స్ లేవు (కొనుగోలు బిల్లుతో నమోదు చేయండి).' : 'No serials in stock (record them on a purchase bill).'),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final s in available)
                    CheckboxListTile(
                      key: ValueKey('askodoxPosSerial-$s'),
                      dense: true,
                      value: chosen.contains(s),
                      title: Text(s),
                      onChanged: (v) => setLocal(() => v == true ? chosen.add(s) : chosen.remove(s)),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(
              key: const Key('askodoxPosSerialsOk'),
              onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, chosen.toList()),
              child: Text(te ? '${chosen.length} జోడించు' : 'Add ${chosen.length}'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty) return;
    _addLine(product, result.length * 1000, serials: result);
  }

  Future<void> _pickQty(AskodoxJson product) async {
    final te = askodoxPosTe(context);
    final unit = '${product['unit']}';
    final weighed = _weighed.contains(unit);
    final scaleable = unit == 'kg' || unit == 'g';
    final qty = TextEditingController(text: weighed ? '' : '1');
    final tare = TextEditingController();
    var fromScale = false;
    var reading = false;
    String? scaleNote;
    final result = await showDialog<(int, int?, int?, bool)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${product['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            AskodoxPosField(
                controller: qty,
                number: true,
                onChanged: (_) => setLocal(() => fromScale = false),
                label: weighed ? (te ? 'బరువు ($unit)' : 'Weight ($unit)') : (te ? 'సంఖ్య' : 'Quantity')),
            if (weighed)
              AskodoxPosField(controller: tare, number: true, label: te ? 'ట్రే / డబ్బా బరువు (తీసేస్తాం)' : 'Tare — container weight (subtracted)'),
            if (scaleable)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('askodoxPosReadScale'),
                  onPressed: reading
                      ? null
                      : () async {
                          setLocal(() {
                            reading = true;
                            scaleNote = null;
                          });
                          final outcome = await _readScale(unit);
                          if (!ctx.mounted) return;
                          setLocal(() {
                            reading = false;
                            if (outcome.$1 != null) {
                              qty.text = askodoxQty(outcome.$1!, '');
                              fromScale = true;
                            }
                            scaleNote = outcome.$2;
                          });
                        },
                  icon: const Icon(Icons.scale_outlined),
                  label: Text(reading ? (te ? 'చదువుతోంది…' : 'Reading…') : (te ? 'తూకం యంత్రం నుండి' : 'Read from scale')),
                ),
              ),
            if (scaleNote != null) Text(scaleNote!, key: const Key('askodoxPosScaleNote'), style: const TextStyle(fontSize: 11.5)),
            if (weighed)
              Text(
                  te
                      ? 'కెమెరా బరువు కొలవదు. తూకం యంత్రం చూపిన సంఖ్య సరిచూసుకోండి.'
                      : 'The camera never measures weight. Check the number against the scale display.',
                  style: const TextStyle(fontSize: 11.5)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(
              key: const Key('askodoxPosQtyOk'),
              onPressed: () {
                final q = askodoxParseMilli(qty.text);
                final t = tare.text.trim().isEmpty ? 0 : askodoxParseMilli(tare.text);
                if (q == null || q <= 0 || t == null || t >= q) return;
                Navigator.pop(ctx, (q - t, weighed && t > 0 ? q : null, weighed && t > 0 ? t : null, fromScale));
              },
              child: Text(te ? 'జోడించు' : 'Add'),
            ),
          ],
        ),
      ),
    );
    if (result != null) _addLine(product, result.$1, gross: result.$2, tare: result.$3, fromScale: result.$4);
  }

  /// One settled weight from the first paired standard BLE scale: (milli in the item's unit, note).
  Future<(int?, String?)> _readScale(String itemUnit) async {
    final te = askodoxPosTe(context);
    List<AskodoxSavedDevice> devices;
    try {
      devices = await ref.read(askodoxDeviceRepositoryProvider).list();
    } on AskodoxDeviceException catch (e) {
      return (null, e.message(te));
    } catch (e) {
      debugPrint('askodox.pos.scale device list failed: $e');
      return (null, te ? 'పరికరాల జాబితా రాలేదు.' : 'Could not load your devices.');
    }
    final scale = devices.where((d) => d.capabilities.contains('read_weight') && d.localId != null).firstOrNull;
    if (scale == null) {
      return (null, te ? 'ముందు Devices లో బ్లూటూత్ తూకం యంత్రం జోడించండి (ఈ ఫోన్‌లో).' : 'Add a Bluetooth scale in Devices first (on this phone).');
    }
    try {
      final milli = await ref.read(askodoxScaleReaderProvider).readItemMilli(scale.localId!, itemUnit);
      return (milli, te ? '${scale.name} నుండి — తూకం యంత్రంతో సరిచూడండి.' : 'From ${scale.name} — check it against the scale.');
    } on AskodoxScaleException catch (e) {
      return (null, e.message(te));
    } catch (e) {
      debugPrint('askodox.pos.scale read failed: $e');
      return (null, te ? 'తూకం యంత్రం చదవలేకపోయాను. బరువు టైప్ చేయండి.' : 'Could not read the scale. Type the weight.');
    }
  }

  Future<void> _scanBarcode() async {
    final te = askodoxPosTe(context);
    String? code;
    try {
      code = await ref.read(askodoxBarcodeScannerProvider).scan(context);
    } on AskodoxScanException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (code == null || !mounted) return;
    await _handleBarcode(code);
  }

  /// A barcode from the camera, or typed by a keyboard-style scanner (ends with Enter).
  Future<void> _handleBarcode(String code) async {
    final te = askodoxPosTe(context);
    final clean = askodoxCleanBarcode(code);
    for (final p in _products) {
      for (final pack in askodoxPosList(p['packs'])) {
        if (askodoxCleanBarcode('${pack['barcode'] ?? ''}') == clean && clean.isNotEmpty) {
          _addLine(p, 1000, pack: pack);
          askodoxPosSnack(context, te ? '${p['name']} (${pack['name']}) జోడించాం.' : 'Added ${p['name']} (${pack['name']}).');
          return;
        }
      }
    }
    final found = askodoxProductsByBarcode(code, _products);
    if (found.length == 1) {
      final p = found.single;
      if (_weighed.contains(p['unit']) || p['track_serials'] == true || askodoxPosList(p['packs']).isNotEmpty) {
        await _choose(p);
      } else {
        _addLine(p, 1000);
        askodoxPosSnack(context, te ? '${p['name']} జోడించాం.' : 'Added ${p['name']}.');
      }
      return;
    }
    _search.text = askodoxCleanBarcode(code);
    setState(() {});
    askodoxPosSnack(
        context,
        found.isEmpty
            ? (te ? 'బార్‌కోడ్ $code ఉన్న సరుకు లేదు. Items లో జోడించండి.' : 'No item has barcode $code. Add it in Items.')
            : (te ? 'ఒకే బార్‌కోడ్‌తో ${found.length} సరుకులు — ఒకటి ఎంచుకోండి.' : '${found.length} items share this barcode — pick one.'));
  }

  Future<void> _runCommand() async {
    final te = askodoxPosTe(context);
    final items = [
      for (final p in _products)
        AskodoxPosItemRef(id: '${p['id']}', name: '${p['name']}', nameTe: '${p['name_te'] ?? ''}', unit: '${p['unit']}'),
    ];
    final order = askodoxParsePosOrder(_command.text, items);
    if (order.length > 1) {
      await _reviewOrder(order);
      return;
    }
    final cmd = askodoxParsePosCommand(_command.text, items);
    if (cmd.kind == AskodoxPosCommandKind.unknown || cmd.needsChoice || (cmd.item == null && cmd.kind != AskodoxPosCommandKind.clear &&
        cmd.kind != AskodoxPosCommandKind.checkout && cmd.kind != AskodoxPosCommandKind.discount)) {
      askodoxPosSnack(context, cmd.needsChoice
          ? (te ? 'ఒకటి కంటే ఎక్కువ సరుకులు సరిపోయాయి: ${cmd.candidates.map((c) => c.name).join(', ')}' : 'More than one item matches: ${cmd.candidates.map((c) => c.name).join(', ')}')
          : (te ? 'అర్థం కాలేదు. ఉదా: "2 kg chicken" / "అర కిలో చికెన్"' : 'Not understood. Try "2 kg chicken" or "remove chicken".'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('askodoxPosConfirmCommand'),
        content: Text(cmd.describe(te)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'No')),
          FilledButton(key: const Key('askodoxPosConfirmYes'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'అవును' : 'Yes')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _command.clear();
    switch (cmd.kind) {
      case AskodoxPosCommandKind.add:
        final product = _products.firstWhere((p) => p['id'] == cmd.item!.id);
        _addLine(product, cmd.qtyMilli ?? 1000, price: cmd.pricePaise);
      case AskodoxPosCommandKind.remove:
        setState(() => _cart.removeWhere((l) => l.product['id'] == cmd.item!.id));
      case AskodoxPosCommandKind.clear:
        setState(_cart.clear);
      case AskodoxPosCommandKind.discount:
        _applyDiscount(cmd);
      case AskodoxPosCommandKind.checkout:
        await _pay();
      case AskodoxPosCommandKind.unknown:
        break;
    }
  }

  /// Several items in one sentence: review every line (rates by quantity applied), read back, then add.
  Future<void> _reviewOrder(List<({String phrase, AskodoxPosCommand command})> order) async {
    final result = await showModalBottomSheet<AskodoxPosOrderResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AskodoxPosOrderReviewSheet(
        order: order,
        products: _products,
        customerPrices: _customerPrices,
        speak: ref.read(askodoxGuideSpeakerProvider),
      ),
    );
    if (result == null || result.lines.isEmpty || !mounted) return;
    _command.clear();
    for (final line in result.lines) {
      _addLine(line.product, line.qtyMilli, price: line.pricePaise);
    }
    if (result.pay && mounted) await _pay();
  }

  void _applyDiscount(AskodoxPosCommand cmd) {
    if (_cart.isEmpty) return;
    setState(() {
      if (cmd.discountBp != null) {
        for (final l in _cart) {
          final gross = askodoxRoundDiv(l.qtyMilli * l.pricePaise, 1000);
          l.discountPaise = askodoxRoundDiv(gross * cmd.discountBp!, 10000);
        }
      } else {
        // a rupee discount goes on the last line (never more than that line's value)
        final l = _cart.last;
        final gross = askodoxRoundDiv(l.qtyMilli * l.pricePaise, 1000);
        l.discountPaise = (cmd.discountPaise ?? 0).clamp(0, gross);
      }
    });
  }

  AskodoxInvoicePreview? _preview(AskodoxJson business) {
    if (_cart.isEmpty) return null;
    try {
      return askodoxInvoicePreview([for (final l in _cart) l.taxInput],
          registrationType: '${business['registration_type']}', businessState: '${business['state_code']}');
    } on AskodoxTaxException {
      return null;
    }
  }

  Future<void> _chooseCustomer() async {
    final te = askodoxPosTe(context);
    final repo = ref.read(askodoxPosRepositoryProvider);
    List<AskodoxJson> list;
    try {
      list = await repo.customers(widget.businessId);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<AskodoxJson?>(
      context: context,
      builder: (ctx) => ListView(children: [
        ListTile(title: Text(te ? 'వాక్-ఇన్ కస్టమర్' : 'Walk-in customer'), onTap: () => Navigator.pop(ctx, <String, Object?>{})),
        for (final c in list)
          ListTile(
            title: Text('${c['name']}'),
            subtitle: Text('${c['gstin'] ?? ''} ${te ? 'బాకీ' : 'due'} ${askodoxPaise(askodoxPosInt(c['balance_paise']))}'),
            onTap: () => Navigator.pop(ctx, c),
          ),
      ]),
    );
    if (picked == null) return;
    if (picked.isEmpty) {
      setState(() {
        _customer = null;
        _customerPrices = const {};
        _repriceLines();
      });
      return;
    }
    try {
      final full = await repo.customer(widget.businessId, '${picked['id']}');
      if (!mounted) return;
      setState(() {
        _customer = full;
        _customerPrices = {for (final e in askodoxPosMap(full['prices']).entries) e.key: askodoxPosInt(e.value)};
        _repriceLines();
      });
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  AskodoxJson _cartPayload() => {
        'customer_id': _customer?['id'],
        if (widget.leadId != null) 'lead_id': widget.leadId,
        'lines': [
          for (final l in _cart)
            {
              'product_id': l.product['id'],
              'qty_milli': l.qtyMilli,
              'price_paise': l.pricePaise,
              'override': l.override,
              'discount_paise': l.discountPaise,
              'gross_milli': l.grossMilli,
              'tare_milli': l.tareMilli,
              'from_scale': l.fromScale,
              'pack': l.pack,
              'serials': l.serials,
            },
        ],
      };

  /// Hold = park this cart to finish later; quotation = the same, plus a text the
  /// customer can receive. Neither is an invoice (no number, no stock, no tax record).
  Future<void> _saveDraft(String kind) async {
    final te = askodoxPosTe(context);
    final business = ref.read(askodoxPosBusinessProvider(widget.businessId)).valueOrNull;
    final preview = business == null ? null : _preview(business);
    final title = '${_customer?['name'] ?? (te ? 'వాక్-ఇన్' : 'Walk-in')} · ${_cart.length} ${te ? 'ఐటమ్స్' : 'items'}'
        '${preview == null ? '' : ' · ${askodoxPaise(preview.totalPaise)}'}';
    try {
      await ref.read(askodoxPosRepositoryProvider).saveDraft(widget.businessId, {
        'kind': kind,
        'title': title,
        // The estimate only feeds the CRM pipeline; the bill at purchase is final.
        'payload': {..._cartPayload(), if (kind == 'quotation' && preview != null) 'estimate_paise': preview.totalPaise},
      });
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (!mounted) return;
    if (kind == 'hold') {
      setState(() {
        _cart.clear();
        _customer = null;
        _customerPrices = const {};
      });
      askodoxPosSnack(context, te ? 'బిల్లు ఆపాం.' : 'Bill held.');
      return;
    }
    if (widget.leadId != null && mounted) {
      askodoxPosSnack(context, te ? 'Quotation lead కి link అయింది.' : 'Quotation linked to the lead.');
    }
    if (preview == null || business == null) return;
    final text = [
      '${business['name']}',
      'QUOTATION (not a tax invoice) · ${askodoxPosToday()}',
      for (var i = 0; i < _cart.length; i++)
        '${_cart[i].product['name']}  ${askodoxQty(_cart[i].qtyMilli, _cart[i].unit)} x ${askodoxPaise(_cart[i].pricePaise)} = ${askodoxPaise(preview.lines[i].totalPaise)}',
      if (preview.taxPaise > 0) 'GST ${askodoxPaise(preview.taxPaise)}',
      'Total ${askodoxPaise(preview.totalPaise)}',
      'Prices may change; the bill at purchase is final.',
    ].join('\n');
    try {
      await const MethodChannel('com.askodox.app/device').invokeMethod<bool>('shareText', <String, Object?>{'text': text, 'title': 'Quotation'});
    } catch (_) {}
  }

  Future<void> _resume() async {
    final draft = await Navigator.of(context).push<AskodoxJson>(
        MaterialPageRoute(builder: (_) => AskodoxPosDraftsScreen(businessId: widget.businessId)));
    if (draft == null || !mounted) return;
    final payload = askodoxPosMap(draft['payload']);
    final byId = {for (final p in _products) '${p['id']}': p};
    final restored = <AskodoxCartLine>[];
    var missing = 0;
    for (final l in askodoxPosList(payload['lines'])) {
      final product = byId['${l['product_id']}'];
      if (product == null) {
        missing += 1;
        continue;
      }
      // Today's price unless a manager had changed it on purpose (the server re-checks the role).
      final override = l['override'] == true;
      restored.add(AskodoxCartLine(
        product: product,
        qtyMilli: askodoxPosInt(l['qty_milli']),
        pricePaise: override ? askodoxPosInt(l['price_paise']) : askodoxPosInt(product['price_paise']),
        override: override,
        discountPaise: askodoxPosInt(l['discount_paise']),
        grossMilli: l['gross_milli'] == null ? null : askodoxPosInt(l['gross_milli']),
        tareMilli: l['tare_milli'] == null ? null : askodoxPosInt(l['tare_milli']),
        fromScale: l['from_scale'] == true,
        pack: l['pack'] == null ? null : '${l['pack']}',
        serials: [for (final s in (l['serials'] as List? ?? const [])) '$s'],
      ));
    }
    setState(() {
      _cart
        ..clear()
        ..addAll(restored);
    });
    if (draft['kind'] == 'hold') {
      try {
        await ref.read(askodoxPosRepositoryProvider).deleteDraft(widget.businessId, '${draft['id']}');
      } catch (_) {}
    }
    if (missing > 0 && mounted) {
      askodoxPosSnack(context, askodoxPosTe(context) ? '$missing ఐటమ్స్ ఇప్పుడు మెనూలో లేవు.' : '$missing items are no longer active.');
    }
  }

  Future<void> _pay() async {
    final business = ref.read(askodoxPosBusinessProvider(widget.businessId)).valueOrNull;
    if (business == null) return;
    final preview = _preview(business);
    if (preview == null) return;
    final te = askodoxPosTe(context);
    final payments = await showModalBottomSheet<List<AskodoxJson>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AskodoxPosPaymentSheet(total: preview.totalPaise, allowCredit: _customer != null, te: te),
    );
    if (payments == null || !mounted) return;
    await _issue(business, preview, payments);
  }

  Future<void> _issue(AskodoxJson business, AskodoxInvoicePreview preview, List<AskodoxJson> payments) async {
    final te = askodoxPosTe(context);
    final repo = ref.read(askodoxPosRepositoryProvider);
    final queue = ref.read(askodoxPosQueueProvider);
    final body = <String, Object?>{
      'client_txn_id': askodoxNewTxnId(),
      'lines': [for (final l in _cart) l.toRequest()],
      if (_customer != null) 'customer_id': _customer!['id'],
      'payments': payments,
    };
    setState(() {
      _issuing = true;
      _error = null;
    });
    try {
      final invoice = await repo.createInvoice(widget.businessId, body);
      if (!mounted) return;
      setState(_cart.clear);
      context.push('/pos/${widget.businessId}/invoice/${invoice['id']}');
    } on AskodoxPosException catch (e) {
      if (!e.retryable) {
        if (mounted) setState(() => _error = e.message(te));
        return;
      }
      final now = DateTime.now();
      final number = await queue.takeNumber(widget.businessId, askodoxFinancialYear(now));
      if (number == null) {
        if (mounted) {
          setState(() => _error = te
              ? 'ఇంటర్నెట్ లేదు, ఈ ఫోన్‌కి బిల్లు నంబర్ సిరీస్ ఇంకా లేదు. ఒకసారి ఇంటర్నెట్‌తో ఈ స్క్రీన్ తెరవండి.'
              : 'No internet, and this phone has no bill-number series yet. Open this screen once while online.');
        }
        return;
      }
      final offset = now.timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final hh = offset.inHours.abs().toString().padLeft(2, '0');
      final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      await queue.add(widget.businessId, {
        ...body,
        'offline': true,
        'issued_at': '${now.toIso8601String().split('.').first}$sign$hh:$mm',
        'device_id': await queue.deviceId(),
        'invoice_number': number,
      });
      if (!mounted) return;
      final local = _localInvoice(business, preview, number, payments);
      setState(_cart.clear);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const Key('askodoxPosOfflineIssued'),
          title: Text(te ? 'ఆఫ్‌లైన్ బిల్లు $number' : 'Offline bill $number'),
          content: Text(te
              ? 'ఈ ఫోన్‌లో దాచాం; ఇంటర్నెట్ వచ్చాక సర్వర్‌కి పంపుతాం. UPI/కార్డ్ డబ్బు మీరు నిర్ధారించినది మాత్రమే — బ్యాంక్ నిర్ధారణ కాదు.'
              : 'Kept on this phone and sent when the internet is back. UPI / card amounts are what you confirmed — not bank-verified.'),
          actions: [
            TextButton(onPressed: () => askodoxPrintInvoice(ctx, ref, local), child: Text(te ? 'ప్రింట్' : 'Print')),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  AskodoxJson _localInvoice(AskodoxJson business, AskodoxInvoicePreview preview, String number, List<AskodoxJson> payments) => {
        'number': number,
        'local_date': askodoxPosToday(),
        'title': switch (preview.documentType) {
          'tax_invoice' => 'Tax Invoice',
          'bill_of_supply' => 'Bill of Supply',
          _ => 'Bill',
        },
        'business_snapshot': {'name': business['name'], 'address': business['address'], 'gstin': business['gstin']},
        'customer_snapshot': {'name': _customer?['name'] ?? 'Walk-in customer', 'gstin': _customer?['gstin']},
        'lines': [
          for (var i = 0; i < _cart.length; i++)
            {
              'name': _cart[i].product['name'],
              'unit': _cart[i].unit,
              'qty_milli': _cart[i].qtyMilli,
              'unit_price_paise': _cart[i].pricePaise,
              'total_paise': preview.lines[i].totalPaise,
              'hsn_sac': _cart[i].product['hsn_sac'],
            },
        ],
        'totals': {
          'taxable_paise': preview.taxablePaise,
          'cgst_paise': preview.cgstPaise,
          'sgst_paise': preview.sgstPaise,
          'igst_paise': preview.igstPaise,
          'cess_paise': preview.cessPaise,
          'grand_total_paise': preview.totalPaise,
          'state_tax_label': preview.stateTaxLabel,
        },
        'payments': payments,
        'balance_paise': preview.totalPaise - payments.fold<int>(0, (a, p) => a + askodoxPosInt(p['amount_paise'])),
      };

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull;
    final preview = business == null ? null : _preview(business);
    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'కొత్త బిల్లు' : 'New bill'),
        actions: [
          IconButton(
            key: const Key('askodoxPosHold'),
            tooltip: te ? 'బిల్లు ఆపు' : 'Hold bill',
            onPressed: _cart.isEmpty ? null : () => _saveDraft('hold'),
            icon: const Icon(Icons.pause_circle_outline),
          ),
          IconButton(
            key: const Key('askodoxPosQuote'),
            tooltip: te ? 'కొటేషన్' : 'Quotation',
            onPressed: _cart.isEmpty ? null : () => _saveDraft('quotation'),
            icon: const Icon(Icons.request_quote_outlined),
          ),
          IconButton(
            key: const Key('askodoxPosHeld'),
            tooltip: te ? 'ఆపిన బిల్లులు' : 'Held bills',
            onPressed: _resume,
            icon: const Icon(Icons.history),
          ),
          TextButton.icon(
            key: const Key('askodoxPosCustomer'),
            onPressed: _chooseCustomer,
            icon: const Icon(Icons.person_outline),
            label: Text(_customer == null ? (te ? 'వాక్-ఇన్' : 'Walk-in') : '${_customer!['name']}'),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                key: const Key('askodoxPosCommand'),
                controller: _command,
                onSubmitted: (_) => _runCommand(),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: AskodoxQuestionMic(
                    lang: te ? 'te' : 'en',
                    onText: (text) {
                      _command.text = text;
                      _runCommand();
                    },
                  ),
                  hintText: te ? '"10 కిలో కంది పప్పు, పావు కిలో జీడిపప్పు"' : '"10 kg dal, 60 samosa, ¼ kg cashew"',
                ),
              ),
            ),
            IconButton(key: const Key('askodoxPosCommandGo'), onPressed: _runCommand, icon: const Icon(Icons.send)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            key: const Key('askodoxPosSearch'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            onSubmitted: (text) {
              final code = askodoxCleanBarcode(text);
              final packHit = code.isNotEmpty &&
                  _products.any((p) => askodoxPosList(p['packs']).any((k) => askodoxCleanBarcode('${k['barcode'] ?? ''}') == code));
              if (packHit || askodoxProductsByBarcode(text, _products).length == 1) {
                _search.clear();
                _handleBarcode(text);
              }
            },
            decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  key: const Key('askodoxPosScan'),
                  tooltip: te ? 'బార్‌కోడ్ స్కాన్' : 'Scan barcode',
                  onPressed: _scanBarcode,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
                hintText: te ? 'పేరు / బార్‌కోడ్' : 'Name / barcode'),
          ),
        ),
        Expanded(
          flex: 3,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _products.isEmpty
                  ? Center(
                      child: TextButton(
                        onPressed: () => context.push('/pos/${widget.businessId}/items'),
                        child: Text(te ? 'ముందు సరుకులు జోడించండి' : 'Add your items first'),
                      ),
                    )
                  : LayoutBuilder(builder: (context, box) {
                      // Picture tiles, like a counter POS: wider screens get more columns.
                      final columns = (box.maxWidth / 112).floor().clamp(3, 8);
                      final visible = _visible;
                      final inCart = <Object?, int>{};
                      for (final l in _cart) {
                        inCart[l.product['id']] = (inCart[l.product['id']] ?? 0) + l.qtyMilli;
                      }
                      return GridView.builder(
                        key: const Key('askodoxPosProducts'),
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.78),
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final p = visible[i];
                          return AskodoxPosProductTile(
                            key: ValueKey('askodoxPosProduct-${p['id']}'),
                            businessId: widget.businessId,
                            product: p,
                            priceText: '${askodoxPaise(_priceFor(p))}/${p['unit']}${askodoxPosList(p['tiers']).isEmpty ? '' : ' ▾'}',
                            inCartMilli: inCart[p['id']] ?? 0,
                            onTap: () => _choose(p),
                          );
                        },
                      );
                    }),
        ),
        const Divider(height: 1),
        Expanded(
          flex: 3,
          child: ListView(key: const Key('askodoxPosCart'), children: [
            for (var i = 0; i < _cart.length; i++)
              ListTile(
                key: ValueKey('askodoxPosCartLine-$i'),
                dense: true,
                title: Text('${_cart[i].product['name']}'),
                subtitle: Text([
                  '${askodoxQty(_cart[i].qtyMilli, _cart[i].unit)} × ${askodoxPaise(_cart[i].pricePaise)}',
                  if (_cart[i].grossMilli != null)
                    '(${askodoxQty(_cart[i].grossMilli!, '')} − ${askodoxQty(_cart[i].tareMilli ?? 0, '')} ${te ? 'ట్రే' : 'tare'})',
                  if (_cart[i].discountPaise > 0) '− ${askodoxPaise(_cart[i].discountPaise)}',
                  if (_cart[i].override) (te ? 'ధర మార్పు (మేనేజర్)' : 'price changed (manager)'),
                  if (_cart[i].fromScale) (te ? '· తూకం యంత్రం' : '· from scale'),
                  if (_cart[i].serials.isNotEmpty) '· ${_cart[i].serials.join(', ')}',
                ].join(' ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (preview != null && i < preview.lines.length) Text(askodoxPaise(preview.lines[i].totalPaise)),
                  IconButton(
                    key: ValueKey('askodoxPosRemove-$i'),
                    onPressed: () => setState(() => _cart.removeAt(i)),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ]),
              ),
          ]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_error!, key: const Key('askodoxPosSaleError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(preview == null ? '₹0.00' : askodoxPaise(preview.totalPaise),
                      key: const Key('askodoxPosTotal'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  if (preview != null && preview.taxPaise > 0)
                    Text('${te ? 'పన్ను' : 'Tax'} ${askodoxPaise(preview.taxPaise)} · ${te ? 'అంచనా; సర్వర్ బిల్లు అంతిమం' : 'preview; the server bill is final'}',
                        style: const TextStyle(fontSize: 11)),
                ]),
              ),
              FilledButton.icon(
                key: const Key('askodoxPosPay'),
                onPressed: _cart.isEmpty || _issuing ? null : _pay,
                icon: const Icon(Icons.payments_outlined),
                label: Text(_issuing ? (te ? 'బిల్లు…' : 'Billing…') : (te ? 'చెల్లింపు' : 'Pay')),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class AskodoxPosPaymentSheet extends StatefulWidget {
  const AskodoxPosPaymentSheet({super.key, required this.total, required this.allowCredit, required this.te});
  final int total;
  final bool allowCredit;
  final bool te;

  @override
  State<AskodoxPosPaymentSheet> createState() => AskodoxPosPaymentSheetState();
}

class AskodoxPosPaymentSheetState extends State<AskodoxPosPaymentSheet> {
  final List<AskodoxJson> _payments = [];
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String _method = 'cash';

  int get _paid => _payments.fold(0, (a, p) => a + askodoxPosInt(p['amount_paise']));
  int get _left => widget.total - _paid;

  @override
  void initState() {
    super.initState();
    _amount.text = askodoxPaise(widget.total, symbol: false).replaceAll(',', '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _add() {
    final paise = askodoxParsePaise(_amount.text);
    if (paise == null || paise <= 0 || paise > _left) return;
    setState(() {
      _payments.add({'method': _method, 'amount_paise': paise, 'reference': _reference.text.trim()});
      _amount.text = askodoxPaise(_left, symbol: false).replaceAll(',', '');
      _reference.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final labels = {
      'cash': te ? 'నగదు' : 'Cash',
      'upi': 'UPI',
      'card': te ? 'కార్డ్' : 'Card',
      'bank_transfer': te ? 'బ్యాంక్' : 'Bank',
      'cheque': te ? 'చెక్' : 'Cheque',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${te ? 'మొత్తం' : 'Total'} ${askodoxPaise(widget.total)} · ${te ? 'మిగిలింది' : 'left'} ${askodoxPaise(_left)}',
            key: const Key('askodoxPosLeft'), style: const TextStyle(fontWeight: FontWeight.w800)),
        Wrap(spacing: 6, children: [
          for (final e in labels.entries)
            ChoiceChip(label: Text(e.value), selected: _method == e.key, onSelected: (_) => setState(() => _method = e.key)),
        ]),
        AskodoxPosField(controller: _amount, number: true, label: te ? 'మొత్తం (₹)' : 'Amount (₹)'),
        if (_method != 'cash') AskodoxPosField(controller: _reference, label: te ? 'రిఫరెన్స్ (UTR మొదలైనవి)' : 'Reference (UTR etc.)'),
        if (_method == 'upi' || _method == 'card')
          Text(
            te
                ? 'QR చూపించడం = డబ్బు అందినట్టు కాదు. మీ ఫోన్ / బ్యాంక్‌లో వచ్చిందని చూసి మాత్రమే జోడించండి.'
                : 'Showing a QR is not payment. Add this only after you see the money arrive in your bank / UPI app.',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFFB45309)),
          ),
        Row(children: [
          OutlinedButton(key: const Key('askodoxPosAddPayment'), onPressed: _add, child: Text(te ? 'చెల్లింపు జోడించు' : 'Add payment')),
          const Spacer(),
          for (final p in _payments) Padding(padding: const EdgeInsets.only(left: 4), child: Chip(label: Text('${labels[p['method']]} ${askodoxPaise(askodoxPosInt(p['amount_paise']))}'))),
        ]),
        if (_left > 0 && widget.allowCredit)
          Text(te ? 'మిగిలినది కస్టమర్ ఖాతాలో బాకీగా ఉంటుంది.' : 'The rest goes on the customer\'s credit account.', style: const TextStyle(fontSize: 12)),
        if (_left > 0 && !widget.allowCredit)
          Text(te ? 'బాకీ పెట్టాలంటే ముందు కస్టమర్‌ని ఎంచుకోండి.' : 'To leave a balance, choose a customer first.', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('askodoxPosIssue'),
            onPressed: _left == 0 || widget.allowCredit ? () => Navigator.pop(context, _payments) : null,
            child: Text(te ? 'బిల్లు ఇవ్వు' : 'Issue bill'),
          ),
        ),
      ]),
    );
  }
}

/// Prints [invoice] on the saved printer (plain-text ESC/POS). Hardware result is
/// reported exactly as the printer link answered.
Future<void> askodoxPrintInvoice(BuildContext context, WidgetRef ref, AskodoxJson invoice) async {
  final te = askodoxPosTe(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final printer = await AskodoxSavedPrinter.load();
  if (printer == null) {
    messenger?.showSnackBar(SnackBar(content: Text(te ? 'ముందు ప్రింటర్ ఎంచుకోండి.' : 'Choose a printer first (Printer).')));
    return;
  }
  try {
    final bytes = askodoxInvoiceNeedsRaster(invoice)
        ? await askodoxRasterReceipt(
            askodoxReceiptLines(invoice, columns: askodoxReceiptColumns(printer.paperMm), asciiOnly: false),
            paperMm: printer.paperMm)
        : askodoxReceiptBytes(invoice, paperMm: printer.paperMm);
    await ref.read(askodoxPrinterTransportProvider).write(printer.id, bytes);
    messenger?.showSnackBar(SnackBar(content: Text(te ? 'ప్రింటర్‌కి పంపాం.' : 'Sent to the printer.')));
  } on AskodoxPrinterException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message(te))));
  }
}
