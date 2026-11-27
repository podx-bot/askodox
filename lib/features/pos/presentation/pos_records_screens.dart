import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/media_picker.dart';
import '../../devices/data/ble_gateway.dart';
import '../data/pos_hardware.dart';
import '../data/pos_invoice_pdf.dart';
import '../data/pos_printer.dart';
import '../data/pos_repository.dart';
import '../domain/escpos.dart';
import '../domain/pos_item_icons.dart';
import '../domain/pos_money.dart';
import '../domain/pos_pricing.dart';
import '../domain/pos_scale.dart';
import '../domain/pos_staff_tools.dart';
import 'my_payment_alerts_screen.dart' show askodoxStaffRoleLabel;
import '../../../shared/widgets/askodox_field_guide.dart';
import 'pos_advance_screens.dart';
import 'pos_combo_sheet.dart';
import 'pos_common.dart';
import 'pos_sale_screen.dart' show askodoxPrintInvoice;

const _device = MethodChannel('com.askodox.app/device');

// ------------------------------------------------------------------ items
class AskodoxPosItemsScreen extends ConsumerStatefulWidget {
  const AskodoxPosItemsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosItemsScreen> createState() => _AskodoxPosItemsScreenState();
}

class _AskodoxPosItemsScreenState extends ConsumerState<AskodoxPosItemsScreen> {
  late Future<List<AskodoxJson>> _items;
  AskodoxJson? _online;

  @override
  void initState() {
    super.initState();
    _items = ref.read(askodoxPosRepositoryProvider).products(widget.businessId);
    _loadOnline();
  }

  void _reload() {
    setState(() {
      _items = ref.read(askodoxPosRepositoryProvider).products(widget.businessId);
    });
    _loadOnline();
  }

  Future<void> _loadOnline() async {
    try {
      final s = await ref.read(askodoxPosRepositoryProvider).onlineStatus(widget.businessId);
      if (mounted) setState(() => _online = s);
    } catch (_) {
      // Older server / offline: the channel controls simply stay hidden.
    }
  }

  AskodoxJson? _onlineItem(Object? id) {
    for (final i in askodoxPosList(_online?['items'])) {
      if (i['product_id'] == id) return i;
    }
    return null;
  }

  String _stateText(String state, bool te) => switch (state) {
        'live' => te ? 'ASKODOX లో కనిపిస్తోంది' : 'Showing in ASKODOX',
        'needs_review' => te ? 'స్టాఫ్ పరిశీలన తర్వాత కనిపిస్తుంది' : 'Shows after staff review',
        'blocked' => te ? 'ఆన్‌లైన్‌లో పెట్టలేం' : 'Cannot be listed online',
        'hidden' => te ? 'ఆన్‌లైన్‌లో దాచాం' : 'Hidden online',
        _ => te ? 'ఆన్‌లైన్‌లో లేదు' : 'Not online',
      };

  Future<void> _setDefault(String channel) async {
    final te = askodoxPosTe(context);
    try {
      final s = await ref.read(askodoxPosRepositoryProvider).setOnlineDefault(widget.businessId, channel);
      if (mounted) setState(() => _online = s);
      if (s['syncing'] == true && channel != 'pos') {
        // Saved at once; the listings go online in the background -- read the states again shortly.
        if (mounted) askodoxPosSnack(context, te ? 'సేవ్ అయింది. ఐటమ్‌లు ఆన్‌లైన్‌లోకి వెళ్తున్నాయి…' : 'Saved. Items are going online…');
        for (final wait in const [4, 12]) {
          await Future<void>.delayed(Duration(seconds: wait));
          if (!mounted) return;
          try {
            final again = await ref.read(askodoxPosRepositoryProvider).onlineStatus(widget.businessId);
            if (mounted) setState(() => _online = again);
          } on AskodoxPosException {
            return;
          }
        }
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  /// Where one item is offered: shop default / POS only / Online only / Both.
  Future<void> _channel(AskodoxJson p) async {
    final te = askodoxPosTe(context);
    final info = _onlineItem(p['id']);
    final current = '${p['channel'] ?? 'default'}';
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          if (info != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text([
                _stateText('${info['state']}', te),
                ...askodoxPosList(info['reasons']).map((r) => '$r'),
              ].join(' · '), key: const Key('askodoxPosChannelState')),
            ),
          for (final (value, label) in [
            ('default', '${te ? 'షాప్ డిఫాల్ట్' : 'Shop default'} (${askodoxPosChannelLabel('${_online?['default'] ?? 'pos'}', te)})'),
            ('pos', askodoxPosChannelLabel('pos', te)),
            ('online', askodoxPosChannelLabel('online', te)),
            ('both', askodoxPosChannelLabel('both', te)),
          ])
            ListTile(
              key: ValueKey('askodoxPosChannelPick-$value'),
              leading: Icon(value == current ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(label),
              onTap: () => Navigator.pop(ctx, value),
            ),
        ]),
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    try {
      final s = await ref
          .read(askodoxPosRepositoryProvider)
          .setOnlineChannel(widget.businessId, '${p['id']}', picked == 'default' ? null : picked);
      if (mounted) setState(() => _online = s);
      _reload();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  /// Selling / buying units of an item: e.g. 1 box = 12 pcs at its own price and barcode.
  Future<void> _units(AskodoxJson p) async {
    final te = askodoxPosTe(context);
    final name = TextEditingController();
    final factor = TextEditingController();
    final price = TextEditingController();
    final barcode = TextEditingController();
    final packs = askodoxPosList(p['packs']);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${p['name']} · ${te ? 'యూనిట్లు' : 'units'}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${te ? 'ప్రాథమిక యూనిట్' : 'Base unit'}: ${p['unit']}'),
            for (final k in packs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('1 ${k['name']} = ${askodoxQty(askodoxPosInt(k['factor_milli']), '${p['unit']}')}'),
                subtitle: Text(k['price_paise'] == null ? (te ? 'ధర: లెక్క ప్రకారం' : 'price: computed') : askodoxPaise(askodoxPosInt(k['price_paise']))),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => Navigator.pop(ctx, 'remove:${k['name']}')),
              ),
            const Divider(),
            Text(te ? 'కొత్త యూనిట్' : 'Add a unit', style: const TextStyle(fontWeight: FontWeight.w700)),
            AskodoxPosField(controller: name, label: te ? 'పేరు (box, bag, case)' : 'Name (box, bag, case)', maxLength: 20),
            AskodoxPosField(controller: factor, number: true, label: te ? 'ఒక దానిలో ఎన్ని ${p['unit']}' : 'How many ${p['unit']} in one'),
            AskodoxPosField(controller: price, number: true, label: te ? 'దాని ధర ₹ (ఖాళీ = లెక్క)' : 'Its price ₹ (empty = computed)'),
            AskodoxPosField(controller: barcode, label: te ? 'దాని బార్‌కోడ్ (ఐచ్ఛికం)' : 'Its barcode (optional)', maxLength: 64),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'మూసివేయి' : 'Close')),
          FilledButton(key: const Key('askodoxPosSavePack'), onPressed: () => Navigator.pop(ctx, 'add'), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    if (action == null || !mounted) return;
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      if (action.startsWith('remove:')) {
        await repo.setPack(widget.businessId, '${p['id']}', {'name': action.substring(7), 'remove': true});
      } else {
        final f = askodoxParseMilli(factor.text);
        if (name.text.trim().isEmpty || f == null || f <= 0) {
          askodoxPosSnack(context, te ? 'పేరు, సంఖ్య నమోదు చేయండి.' : 'Enter the name and how many.');
          return;
        }
        await repo.setPack(widget.businessId, '${p['id']}', {
          'name': name.text.trim().toLowerCase(),
          'factor_milli': f,
          if (askodoxParsePaise(price.text) != null) 'price_paise': askodoxParsePaise(price.text),
          'barcode': barcode.text.trim(),
        });
      }
      _reload();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  /// Counter offer on an item (owner 2026-11-19): 1 + 1, 2 + 1 ... or a percentage off. The bill screen applies it
  /// by itself as that line's discount.
  Future<void> _offer(AskodoxJson p) async {
    final te = askodoxPosTe(context);
    final current = p['offer'] is Map ? p['offer'] as Map : const {};
    var kind = '${current['kind'] ?? 'none'}';
    final buy = TextEditingController(text: '${current['buy'] ?? 1}');
    final free = TextEditingController(text: '${current['free'] ?? 1}');
    final percent = TextEditingController(text: current['bp'] is num ? '${(current['bp'] as num) / 100}' : '10');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${p['name']} · ${te ? 'ఆఫర్' : 'Offer'}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, children: [
              for (final (value, en, tel) in const [('none', 'No offer', 'ఆఫర్ లేదు'), ('bxgy', 'Buy + free', 'కొంటే ఉచితం'), ('percent', '% off', '% తగ్గింపు')])
                ChoiceChip(
                    key: ValueKey('askodoxPosOfferKind-$value'),
                    label: Text(te ? tel : en),
                    selected: kind == value,
                    onSelected: (_) => setLocal(() => kind = value)),
            ]),
            if (kind == 'bxgy')
              Row(children: [
                Expanded(
                    child: TextField(
                        key: const Key('askodoxPosOfferBuy'),
                        controller: buy,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: te ? 'ఎన్ని కొంటే' : 'Buy'))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        key: const Key('askodoxPosOfferFree'),
                        controller: free,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: te ? 'ఎన్ని ఉచితం' : 'Free'))),
              ]),
            if (kind == 'percent')
              TextField(
                  key: const Key('askodoxPosOfferPercent'),
                  controller: percent,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: te ? 'తగ్గింపు %' : 'Discount %')),
            const SizedBox(height: 8),
            Text(
                te
                    ? 'కౌంటర్ బిల్లులో ఈ ఐటమ్ వేసినప్పుడు తగ్గింపు దానంతట అదే పడుతుంది.'
                    : 'On a counter bill the discount is applied to this item by itself.',
                style: const TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
            FilledButton(key: const Key('askodoxPosOfferSave'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final Map<String, Object?> offer = switch (kind) {
      'bxgy' => {'kind': 'bxgy', 'buy': int.tryParse(buy.text.trim()) ?? 0, 'free': int.tryParse(free.text.trim()) ?? 0},
      'percent' => {'kind': 'percent', 'bp': ((double.tryParse(percent.text.trim()) ?? 0) * 100).round()},
      _ => <String, Object?>{},
    };
    try {
      await ref.read(askodoxPosRepositoryProvider).updateProduct(widget.businessId, '${p['id']}', {'offer': offer});
      if (mounted) _reload();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _stock(AskodoxJson p) async {
    final te = askodoxPosTe(context);
    final qty = TextEditingController();
    final reason = TextEditingController();
    var kind = 'purchase';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${p['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: kind,
              items: [
                DropdownMenuItem(value: 'purchase', child: Text(te ? 'కొనుగోలు (+)' : 'Purchase (+)')),
                DropdownMenuItem(value: 'wastage', child: Text(te ? 'పాడైనది (−)' : 'Wastage (−)')),
                DropdownMenuItem(value: 'count', child: Text(te ? 'లెక్కించిన స్టాక్' : 'Counted stock')),
              ],
              onChanged: (v) => setLocal(() => kind = v ?? kind),
            ),
            AskodoxPosField(controller: qty, number: true, label: '${te ? 'పరిమాణం' : 'Quantity'} (${p['unit']})'),
            AskodoxPosField(controller: reason, label: te ? 'కారణం' : 'Reason'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      ),
    );
    final milli = askodoxParseMilli(qty.text);
    final why = reason.text.trim();
    if (ok != true || milli == null || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).stock(widget.businessId,
          {'product_id': p['id'], 'kind': kind, 'qty_milli': milli, 'reason': why, 'client_txn_id': askodoxNewTxnId()});
      _reload();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'సరుకులు' : 'Items'), actions: [
        IconButton(
          key: const Key('askodoxPosOpenCombos'),
          tooltip: te ? 'కాంబో ఆఫర్లు' : 'Combo offers',
          onPressed: () async {
            final items = await _items;
            if (context.mounted) await askodoxShowCombos(context, ref, widget.businessId, items);
          },
          icon: const Icon(Icons.local_offer_outlined),
        ),
        TextButton.icon(
          key: const Key('askodoxPosOpenCatalogue'),
          onPressed: () async {
            final added = await context.push<bool>('/pos/${widget.businessId}/catalogue');
            if (added == true) _reload();
          },
          icon: const Icon(Icons.playlist_add_check),
          label: Text(te ? 'రెడీ లిస్ట్' : 'Ready list'),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('askodoxPosAddItem'),
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => AskodoxPosItemForm(businessId: widget.businessId)));
          if (added == true) _reload();
        },
        icon: const Icon(Icons.add),
        label: Text(te ? 'సరుకు' : 'Item'),
      ),
      body: FutureBuilder<List<AskodoxJson>>(
        future: _items,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) return Center(child: Text(te ? 'ఇంకా సరుకులు లేవు.' : 'No items yet.'));
          final online = _online;
          final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull;
          final canSettings = business != null && askodoxPosCan(business, 'settings');
          return ListView(key: const Key('askodoxPosItems'), children: [
            if (online != null)
              Card(
                key: const Key('askodoxPosOnlineCard'),
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(te ? 'సరుకులు ఎక్కడ అమ్మాలి?' : 'Where do you sell these items?',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      te
                          ? 'POS మాత్రమే = షాప్ కౌంటర్‌లో. ఆన్‌లైన్ = ASKODOX లో కస్టమర్లకు కనిపిస్తుంది. రెండూ = రెండింటిలో. ప్రతి సరుకుకీ విడిగా కూడా మార్చవచ్చు.'
                          : 'POS only = at your counter. Online = customers see it in ASKODOX. Both = both. You can change any single item too.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      key: const Key('askodoxPosOnlineDefault'),
                      segments: [
                        for (final c in const ['pos', 'online', 'both'])
                          ButtonSegment(value: c, label: Text(askodoxPosChannelLabel(c, te))),
                      ],
                      selected: {'${online['default'] ?? 'pos'}'},
                      onSelectionChanged: canSettings ? (v) => _setDefault(v.first) : null,
                    ),
                  ]),
                ),
              ),
            for (final p in items)
              ListTile(
                key: ValueKey('askodoxPosItem-${p['id']}'),
                leading: Text(askodoxItemIcon('${p['name'] ?? ''}', nameTe: '${p['name_te'] ?? ''}', category: '${p['category'] ?? ''}'),
                    style: const TextStyle(fontSize: 26)),
                title: Text('${askodoxPosInt(p['item_no']) > 0 ? '${p['item_no']}. ' : ''}${p['name']}'
                    '${'${p['name_te'] ?? ''}'.isEmpty ? '' : ' · ${p['name_te']}'}'),
                subtitle: Text([
                  '${askodoxPaise(askodoxPosInt(p['price_paise']))}/${p['unit']}',
                  '${te ? 'GST' : 'GST'} ${askodoxRate(askodoxPosInt(p['rate_bp']))}${p['price_includes_tax'] == true ? (te ? ' కలిపి' : ' incl.') : ''}',
                  if ('${p['hsn_sac'] ?? ''}'.isNotEmpty) 'HSN ${p['hsn_sac']}',
                  if (p['stock_milli'] != null) '${te ? 'స్టాక్' : 'stock'} ${askodoxQty(askodoxPosInt(p['stock_milli']), '${p['unit']}')}',
                  if (p['low_stock'] == true) (te ? 'తక్కువ స్టాక్' : 'LOW'),
                  if (askodoxOfferLabel(p, te).isNotEmpty) '🏷 ${askodoxOfferLabel(p, te)}',
                ].join(' · ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (online != null)
                    ActionChip(
                      key: ValueKey('askodoxPosItemChannel-${p['id']}'),
                      avatar: Icon(
                          askodoxPosChannel(p, online['default']) == 'pos'
                              ? Icons.storefront_outlined
                              : '${_onlineItem(p['id'])?['state']}' == 'live'
                                  ? Icons.public
                                  : Icons.public_off_outlined,
                          size: 16),
                      label: Text(askodoxPosChannelLabel(askodoxPosChannel(p, online['default']), te),
                          style: const TextStyle(fontSize: 11.5)),
                      onPressed: () => _channel(p),
                    ),
                  IconButton(
                      key: ValueKey('askodoxPosItemOffer-${p['id']}'),
                      tooltip: te ? 'ఆఫర్' : 'Offer',
                      onPressed: () => _offer(p),
                      icon: Icon(Icons.local_offer_outlined, color: p['offer'] == null ? null : const Color(0xFF7CD3A2))),
                  if (p['track_stock'] == true && p['track_serials'] != true)
                    IconButton(onPressed: () => _stock(p), icon: const Icon(Icons.inventory_outlined)),
                ]),
                onTap: () async {
                  final next = await context.push<String>('/pos/${widget.businessId}/item/${p['id']}');
                  if (next == 'units') {
                    await _units(p);
                  } else {
                    _reload();
                  }
                },
              ),
          ]);
        },
      ),
    );
  }
}

class AskodoxPosItemForm extends ConsumerStatefulWidget {
  const AskodoxPosItemForm({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosItemForm> createState() => _AskodoxPosItemFormState();
}

class _AskodoxPosItemFormState extends ConsumerState<AskodoxPosItemForm> {
  final _name = TextEditingController();
  final _nameTe = TextEditingController();
  final _price = TextEditingController();
  final _hsn = TextEditingController();
  final _barcode = TextEditingController();
  final _opening = TextEditingController();
  String _unit = 'pcs';
  int _rate = 0;
  String _category = 'taxable';
  bool _inclusive = true;
  bool _track = false;
  bool _batches = false;
  bool _serials = false;
  bool _imei = false;
  bool _busy = false;
  String? _error;

  static const _units = ['pcs', 'kg', 'g', 'l', 'ml', 'm', 'dozen', 'box', 'plate', 'hour', 'service', 'pack'];
  static const _rates = [0, 10, 25, 100, 150, 300, 500, 600, 1200, 1800, 2800, 4000];

  @override
  void dispose() {
    for (final c in [_name, _nameTe, _price, _hsn, _barcode, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _readingPhoto = false;
  String _photoExpiry = '';

  /// Owner 2026-11-19: a photo of the packet fills the name, the MRP, the barcode; nothing is typed that the pack shows.
  Future<void> _fromPhoto(String source) async {
    final te = askodoxPosTe(context);
    final picked = (await ref.read(askodoxMediaPickerProvider).pick(source)).where((a) => a.isImage).toList();
    if (picked.isEmpty || !mounted) return;
    if (picked.any((a) => a.bytes.length > 4400000)) {
      askodoxPosSnack(context, te ? 'ఫోటో చాలా పెద్దది. చిన్న ఫోటో వాడండి.' : 'That photo is too large. Use a smaller one.');
      return;
    }
    setState(() => _readingPhoto = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).productPhoto(widget.businessId, [
        for (final a in picked.take(2)) {'data': base64Encode(a.bytes), 'mime': a.mimeType},
      ]);
      if (!mounted) return;
      if (out['read'] != true) {
        askodoxPosSnack(context, te ? 'ఫోటో నుంచి చదవలేకపోయాను. పేరు కనిపించేలా మళ్ళీ తీయండి.' : 'Could not read that photo. Take it again with the name visible.');
        return;
      }
      setState(() {
        _name.text = '${out['name'] ?? ''}';
        final paise = out['price_paise'];
        if (paise is num) _price.text = paise % 100 == 0 ? '${paise ~/ 100}' : (paise / 100).toStringAsFixed(2);
        if ('${out['barcode'] ?? ''}'.isNotEmpty) _barcode.text = '${out['barcode']}';
        if (_units.contains('${out['unit']}')) _unit = '${out['unit']}';
        _photoExpiry = '${out['expiry_date'] ?? ''}';
        if (_photoExpiry.isNotEmpty) _batches = true; // an item with an expiry date is kept by batch
      });
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _readingPhoto = false);
    }
  }

  // Owner 2026-11-24: a scanned barcode fills the item -- from a shop on ASKODOX that sells the same pack (never its
  // selling price), else open data. The MRP printed on the pack becomes the price only when the box is empty.
  String _masterPhotoRef = '';
  String _barcodeNote = '';

  Future<void> _fillFromBarcode(bool te) async {
    final code = _barcode.text.trim();
    if (code.length < 8) return;
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).barcodeLookup(widget.businessId, code);
      if (!mounted) return;
      final item = askodoxPosMap(out['item']);
      if (out['found'] != true || item.isEmpty) {
        setState(() => _barcodeNote = te ? 'ఈ బార్‌కోడ్ ఇంకా ఎక్కడా లేదు. పేరు రాయండి.' : 'This barcode is new. Type the name.');
        return;
      }
      setState(() {
        if (_name.text.trim().isEmpty) _name.text = '${item['name'] ?? ''}';
        if (_nameTe.text.trim().isEmpty) _nameTe.text = '${item['name_te'] ?? ''}';
        final mrp = item['mrp_paise'];
        if (_price.text.trim().isEmpty && mrp is num && mrp > 0) {
          _price.text = mrp % 100 == 0 ? '${mrp ~/ 100}' : (mrp / 100).toStringAsFixed(2);
        }
        _masterPhotoRef = '${item['photo'] ?? ''}';
        final credit = '${item['credit'] ?? ''}';
        _barcodeNote = te
            ? 'బార్‌కోడ్‌తో నింపాను${credit.isEmpty ? '' : ' ($credit)'}. ఒకసారి చూడండి.'
            : 'Filled from the barcode${credit.isEmpty ? '' : ' ($credit)'}. Check once.';
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final te = askodoxPosTe(context);
    final price = askodoxParsePaise(_price.text);
    if (_name.text.trim().isEmpty || price == null) {
      setState(() => _error = te ? 'పేరు, ధర తప్పనిసరి.' : 'Name and price are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref.read(askodoxPosRepositoryProvider).addProduct(widget.businessId, {
        'name': _name.text.trim(),
        'name_te': _nameTe.text.trim(),
        'unit': _unit,
        'price_paise': price,
        'price_includes_tax': _inclusive,
        'rate_bp': _rate,
        'category': _category,
        'hsn_sac': _hsn.text.trim(),
        'barcode': _barcode.text.trim(),
        'track_stock': _track || _batches || _serials,
        'track_batches': _batches,
        'track_serials': _serials,
        if (_serials) 'serial_kind': _imei ? 'imei' : '',
        if (_track && !_batches && !_serials) 'opening_stock_milli': askodoxParseMilli(_opening.text) ?? 0,
      });
      final made = '${created['id'] ?? ''}';
      if (_masterPhotoRef.isNotEmpty && made.isNotEmpty) {
        try {  // the pack photo comes along (best effort; the item is already saved)
          final repo = ref.read(askodoxPosRepositoryProvider);
          final photo = await repo.masterPhoto(_masterPhotoRef);
          final data = '${photo['image_base64'] ?? ''}';
          if (data.isNotEmpty) await repo.setPhoto(widget.businessId, made, data);
        } catch (_) {}
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final categories = {
      'taxable': te ? 'పన్ను వర్తించేది' : 'Taxable',
      'exempt': te ? 'మినహాయింపు (exempt)' : 'Exempt',
      'nil_rated': te ? 'నిల్ రేటు' : 'Nil rated',
      'non_gst': te ? 'GST కాదు' : 'Non-GST',
      'zero_rated_lut': te ? 'ఎగుమతి (LUT)' : 'Zero-rated export (LUT)',
    };
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'కొత్త సరుకు' : 'New item')),
      body: ListView(key: const Key('askodoxPosItemForm'), padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              key: const Key('askodoxPosItemPhoto'),
              onPressed: _readingPhoto || _busy ? null : () => _fromPhoto('camera'),
              icon: _readingPhoto
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_camera_outlined),
              label: Text(_readingPhoto
                  ? (te ? 'చదువుతున్నాను…' : 'Reading…')
                  : (te ? 'ప్యాకెట్ ఫోటో తీయండి — పేరు, ధర నిండుతాయి' : 'Photo of the packet — fills name and price')),
            ),
          ),
          IconButton(
            key: const Key('askodoxPosItemPhotoGallery'),
            tooltip: te ? 'గ్యాలరీ' : 'Gallery',
            onPressed: _readingPhoto || _busy ? null : () => _fromPhoto('photos'),
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ]),
        if (_photoExpiry.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                te
                    ? 'ప్యాకెట్ మీద ఎక్స్‌పైరీ: $_photoExpiry. స్టాక్ (కొనుగోలు బిల్లు) చేర్చేటప్పుడు ఈ తేదీ పెట్టండి; దగ్గరపడితే ASKODOX చెబుతుంది.'
                    : 'Expiry on the pack: $_photoExpiry. Enter it when you add the stock (purchase bill); ASKODOX warns you before it expires.',
                key: const Key('askodoxPosItemPhotoExpiry'),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFFB9E6A))),
          ),
        const SizedBox(height: 12),
        AskodoxPosField(controller: _name, label: te ? 'పేరు (ఇంగ్లీష్)' : 'Name', maxLength: 80,
            guideEn: 'The item name customers know, with the size if it matters. It is printed on the bill and shown online.',
            guideTe: 'కస్టమర్లకు తెలిసిన సరుకు పేరు, అవసరమైతే సైజుతో. ఇది బిల్లులో, ఆన్‌లైన్‌లో కనిపిస్తుంది.',
            exampleEn: 'Sona Masoori rice 25 kg', exampleTe: 'Sona Masoori rice 25 kg'),
        AskodoxPosField(controller: _nameTe, label: te ? 'తెలుగు పేరు' : 'Telugu name (optional)', maxLength: 80,
            guideEn: 'The same name in Telugu, so you can search it in Telugu at the counter. Optional.',
            guideTe: 'అదే పేరు తెలుగులో — కౌంటర్‌లో తెలుగులో వెతకడానికి. ఐచ్ఛికం.',
            exampleEn: 'సోనా మసూరి బియ్యం 25 కిలో', exampleTe: 'సోనా మసూరి బియ్యం 25 కిలో'),
        Row(children: [
          Expanded(
              child: AskodoxPosField(controller: _price, number: true, label: te ? 'అమ్మకం ధర (₹)' : 'Selling price (₹)',
                  guideEn: 'Your selling price for ONE unit (the unit next to it). You can set a different online price later.',
                  guideTe: 'ఒక్క యూనిట్‌కి మీ అమ్మకం ధర (పక్కన ఉన్న యూనిట్). ఆన్‌లైన్ ధర తర్వాత విడిగా పెట్టొచ్చు.',
                  exampleEn: '1450', exampleTe: '1450')),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _unit,
              decoration: InputDecoration(labelText: te ? 'యూనిట్' : 'Unit', border: const OutlineInputBorder(), isDense: true),
              items: [for (final u in _units) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: (v) => setState(() => _unit = v ?? _unit),
            ),
          ),
        ]),
        DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          decoration: InputDecoration(labelText: te ? 'పన్ను రకం' : 'Tax type', border: const OutlineInputBorder(), isDense: true),
          items: [for (final e in categories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 10),
        if (_category == 'taxable')
          DropdownButtonFormField<int>(
            key: const Key('askodoxPosRate'),
            initialValue: _rate,
            decoration: InputDecoration(
                labelText: te ? 'GST రేటు (మీ వర్గీకరణ)' : 'GST rate (your classification)',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: const AskodoxFieldGuideButton(
                    titleEn: 'GST rate', titleTe: 'GST రేటు',
                    en: 'The GST % for this item from your own classification (your accountant / supplier bill). ASKODOX never chooses it for you.',
                    te: 'మీ వర్గీకరణ ప్రకారం ఈ సరుకు GST % (మీ అకౌంటెంట్ / సప్లయర్ బిల్లు). ASKODOX మీ తరఫున ఎంచుకోదు.')),
            items: [for (final r in _rates) DropdownMenuItem(value: r, child: Text(askodoxRate(r)))],
            onChanged: (v) => setState(() => _rate = v ?? _rate),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _inclusive,
          onChanged: (v) => setState(() => _inclusive = v),
          title: Text(te ? 'ధరలో GST కలిసి ఉంది' : 'Price includes GST'),
        ),
        AskodoxPosField(controller: _hsn, number: true, decimal: false, label: 'HSN / SAC', maxLength: 8,
            hint: te ? 'మీ అకౌంటెంట్ ఇచ్చిన కోడ్' : 'Code from your own classification',
            guideEn: 'The 4, 6 or 8 digit tax code for this item. Take it from your accountant or your supplier\'s bill — ASKODOX never guesses it. Not needed if you are not GST registered.',
            guideTe: 'ఈ సరుకు 4, 6 లేదా 8 అంకెల పన్ను కోడ్. మీ అకౌంటెంట్ నుండి లేదా సప్లయర్ బిల్లు నుండి తీసుకోండి — ASKODOX ఊహించదు. GST లేనివారికి అవసరం లేదు.'),
        Row(children: [
          Expanded(
              child: AskodoxPosField(controller: _barcode, label: te ? 'బార్‌కోడ్ (ఐచ్ఛికం)' : 'Barcode (optional)', maxLength: 64,
                  guideEn: 'The number under the bars on the pack. Tap the scan button to read it from a photo. Optional.',
                  guideTe: 'ప్యాక్‌పై గీతల కింద ఉన్న నంబర్. ఫోటో నుండి చదవడానికి స్కాన్ బటన్ నొక్కండి. ఐచ్ఛికం.')),
          IconButton(
            key: const Key('askodoxPosItemScan'),
            tooltip: te ? 'బార్‌కోడ్ స్కాన్' : 'Scan barcode',
            onPressed: () async {
              try {
                final code = await ref.read(askodoxBarcodeScannerProvider).scan(context);
                if (code != null && mounted) {
                  setState(() => _barcode.text = askodoxCleanBarcode(code));
                  unawaited(_fillFromBarcode(te));
                }
              } on AskodoxScanException catch (e) {
                if (context.mounted) askodoxPosSnack(context, e.message(te));
              }
            },
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            key: const Key('askodoxPosItemBarcodeFill'),
            tooltip: te ? 'బార్‌కోడ్‌తో నింపు' : 'Fill from the barcode',
            onPressed: () => _fillFromBarcode(te),
            icon: const Icon(Icons.auto_fix_high_outlined),
          ),
        ]),
        if (_barcodeNote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(_barcodeNote, key: const Key('askodoxPosItemBarcodeNote'), style: const TextStyle(fontSize: 12.5)),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _track,
          onChanged: (v) => setState(() => _track = v),
          title: Text(te ? 'స్టాక్ లెక్క పెట్టు' : 'Track stock'),
        ),
        SwitchListTile(
          key: const Key('askodoxPosTrackBatches'),
          contentPadding: EdgeInsets.zero,
          value: _batches,
          onChanged: (v) => setState(() => _batches = v),
          title: Text(te ? 'బ్యాచ్ / ఎక్స్‌పైరీ లెక్క (మందులు మొదలైనవి)' : 'Track batch / expiry (medicines etc.)'),
          subtitle: Text(te ? 'స్టాక్ కొనుగోలు బిల్లుతో బ్యాచ్ వారీగా వస్తుంది; ఎక్స్‌పైర్ అయినది అమ్మకానికి రాదు.' : 'Stock comes in per batch through purchase bills; expired stock is never sold.'),
        ),
        SwitchListTile(
          key: const Key('askodoxPosTrackSerials'),
          contentPadding: EdgeInsets.zero,
          value: _serials,
          onChanged: (v) => setState(() => _serials = v),
          title: Text(te ? 'సీరియల్ / IMEI ప్రతి పీస్‌కి (మొబైల్స్, ఎలక్ట్రానిక్స్)' : 'Serial / IMEI per piece (mobiles, electronics)'),
          subtitle: Text(te ? 'కొనుగోలు బిల్లుతో నంబర్లు వస్తాయి; అమ్మేటప్పుడు ఏ పీస్ అమ్మారో ఎంచుకోవాలి.' : 'Numbers come in on purchase bills; each sale picks the exact pieces.'),
        ),
        if (_serials)
          CheckboxListTile(
            key: const Key('askodoxPosImei'),
            contentPadding: EdgeInsets.zero,
            value: _imei,
            onChanged: (v) => setState(() => _imei = v ?? false),
            title: Text(te ? 'ఇవి IMEI నంబర్లు (15 అంకెలు, చెక్ అంకెతో పరీక్ష)' : 'These are IMEIs (15 digits, check digit verified)'),
          ),
        if (_track && !_batches && !_serials) AskodoxPosField(controller: _opening, number: true, label: te ? 'ప్రస్తుత స్టాక్' : 'Opening stock ($_unit)'),
        if (_error != null) Text(_error!, key: const Key('askodoxPosItemError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        FilledButton(key: const Key('askodoxPosSaveItem'), onPressed: _busy ? null : _save, child: Text(te ? 'సేవ్' : 'Save')),
      ]),
    );
  }
}

// -------------------------------------------------------------- customers
class AskodoxPosCustomersScreen extends ConsumerStatefulWidget {
  const AskodoxPosCustomersScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosCustomersScreen> createState() => _AskodoxPosCustomersScreenState();
}

class _AskodoxPosCustomersScreenState extends ConsumerState<AskodoxPosCustomersScreen> {
  late Future<List<AskodoxJson>> _list;

  @override
  void initState() {
    super.initState();
    _list = ref.read(askodoxPosRepositoryProvider).customers(widget.businessId);
  }

  void _reload() => setState(() {
    _list = ref.read(askodoxPosRepositoryProvider).customers(widget.businessId);
  });

  Future<void> _add() async {
    final te = askodoxPosTe(context);
    final name = TextEditingController();
    final phone = TextEditingController();
    final gstin = TextEditingController();
    final address = TextEditingController();
    final limit = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'కొత్త కస్టమర్' : 'New customer'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AskodoxPosField(controller: name, label: te ? 'పేరు' : 'Name'),
            AskodoxPosField(controller: phone, number: true, decimal: false, label: te ? 'ఫోన్' : 'Phone'),
            AskodoxPosField(controller: gstin, label: 'GSTIN (B2B)', maxLength: 15),
            AskodoxPosField(controller: address, label: te ? 'చిరునామా' : 'Address'),
            AskodoxPosField(controller: limit, number: true, label: te ? 'బాకీ పరిమితి ₹ (ఐచ్ఛికం)' : 'Credit limit ₹ (optional)'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    final body = {
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      if (gstin.text.trim().isNotEmpty) 'gstin': gstin.text.trim().toUpperCase(),
      'address': address.text.trim(),
      'credit_limit_paise': askodoxParsePaise(limit.text) ?? 0,
    };
    if (ok != true || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).addCustomer(widget.businessId, body);
      _reload();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'కస్టమర్లు & ఖాతా' : 'Customers & credit')),
      floatingActionButton: FloatingActionButton(key: const Key('askodoxPosAddCustomer'), onPressed: _add, child: const Icon(Icons.person_add_alt)),
      body: FutureBuilder<List<AskodoxJson>>(
        future: _list,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(key: const Key('askodoxPosCustomers'), children: [
            AskodoxCustomerSuggestions(businessId: widget.businessId, onSaved: _reload),
            for (final c in snap.data!)
              ListTile(
                key: ValueKey('askodoxPosCustomerRow-${c['id']}'),
                title: Text('${c['name']}'),
                subtitle: Text('${c['gstin'] ?? 'B2C'}'),
                trailing: Text(askodoxPaise(askodoxPosInt(c['balance_paise'])),
                    style: TextStyle(fontWeight: FontWeight.w800, color: askodoxPosInt(c['balance_paise']) > 0 ? const Color(0xFFFEA195) : null)),
                onTap: () async {
                  await context.push('/pos/${widget.businessId}/customers/${c['id']}');
                  if (mounted) _reload();
                },
              ),
          ]);
        },
      ),
    );
  }
}

/// "Save these?" (owner 2026-11-24): people who ordered or got a bill, one row each, side by side chips -- ✓ saves to
/// the customer list, ✕ never shows that number again. Hidden when there is nobody to suggest.
class AskodoxCustomerSuggestions extends ConsumerStatefulWidget {
  const AskodoxCustomerSuggestions({super.key, required this.businessId, this.onSaved});
  final String businessId;
  final VoidCallback? onSaved;

  @override
  ConsumerState<AskodoxCustomerSuggestions> createState() => _AskodoxCustomerSuggestionsState();
}

class _AskodoxCustomerSuggestionsState extends ConsumerState<AskodoxCustomerSuggestions> {
  List<AskodoxJson> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(askodoxPosRepositoryProvider).customerSuggestions(widget.businessId);
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      // Suggestions are extra: no network = no strip.
    }
  }

  Future<void> _save(AskodoxJson row) async {
    final te = askodoxPosTe(context);
    final phone = '${row['phone']}';
    final name = '${row['name'] ?? ''}'.trim().isEmpty ? phone : '${row['name']}';
    try {
      await ref.read(askodoxPosRepositoryProvider).addCustomer(widget.businessId, {'name': name, 'phone': phone});
      if (!mounted) return;
      setState(() => _rows = [for (final r in _rows) if ('${r['phone']}' != phone) r]);
      askodoxPosSnack(context, te ? '✓ $name కస్టమర్ లిస్ట్‌లో చేరారు.' : '✓ $name saved to the customer list.');
      widget.onSaved?.call();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _skip(AskodoxJson row) async {
    final phone = '${row['phone']}';
    setState(() => _rows = [for (final r in _rows) if ('${r['phone']}' != phone) r]);
    try {
      await ref.read(askodoxPosRepositoryProvider).skipCustomerSuggestion(widget.businessId, phone);
    } catch (_) {
      // Shown again next time: harmless.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) return const SizedBox.shrink();
    final te = askodoxPosTe(context);
    return Card(
      key: const Key('askodoxCustomerSuggestions'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(te ? 'వీళ్ళని కస్టమర్ లిస్ట్‌లో చేర్చాలా? (${_rows.length})' : 'Save these customers? (${_rows.length})',
              style: Theme.of(context).textTheme.titleSmall),
          Text(te ? 'మీ షాప్‌లో ఆర్డర్ చేసినవాళ్ళు / బిల్లు పంపినవాళ్ళు.' : 'People who ordered or got a bill from you.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final r = _rows[i];
                final phone = '${r['phone']}';
                final name = '${r['name'] ?? ''}'.trim();
                return DecoratedBox(
                  key: ValueKey('askodoxCustomerSuggestion-$phone'),
                  decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(name.isEmpty ? '••${phone.substring(phone.length - 4)}' : name,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(te ? '${r['times']} సార్లు' : '${r['times']} times', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                    IconButton(
                        key: ValueKey('askodoxCustomerSuggestionSave-$phone'),
                        tooltip: te ? 'చేర్చు' : 'Save',
                        onPressed: () => _save(r),
                        icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF75D48B))),
                    IconButton(
                        key: ValueKey('askodoxCustomerSuggestionSkip-$phone'),
                        tooltip: te ? 'వద్దు' : 'No',
                        onPressed: () => _skip(r),
                        icon: const Icon(Icons.close_rounded)),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class AskodoxPosCustomerScreen extends ConsumerStatefulWidget {
  const AskodoxPosCustomerScreen({super.key, required this.businessId, required this.customerId});
  final String businessId;
  final String customerId;

  @override
  ConsumerState<AskodoxPosCustomerScreen> createState() => _AskodoxPosCustomerScreenState();
}

class _AskodoxPosCustomerScreenState extends ConsumerState<AskodoxPosCustomerScreen> {
  late String _month;
  late Future<AskodoxJson> _statement;

  @override
  void initState() {
    super.initState();
    _month = askodoxPosToday().substring(0, 7);
    _load();
  }

  void _load() => _statement = ref.read(askodoxPosRepositoryProvider).statement(widget.businessId, widget.customerId, _month);

  void _shiftMonth(int delta) {
    final y = int.parse(_month.substring(0, 4));
    final m = int.parse(_month.substring(5)) + delta;
    final d = DateTime(y, m);
    setState(() {
      _month = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      _load();
    });
  }

  Future<void> _collect() async {
    final te = askodoxPosTe(context);
    final amount = TextEditingController();
    final reference = TextEditingController();
    var method = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(te ? 'డబ్బు వచ్చింది' : 'Money received'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, children: [
              for (final m in ['cash', 'upi', 'bank_transfer', 'cheque'])
                ChoiceChip(label: Text(m), selected: method == m, onSelected: (_) => setLocal(() => method = m)),
            ]),
            AskodoxPosField(controller: amount, number: true, label: te ? 'మొత్తం (₹)' : 'Amount (₹)'),
            AskodoxPosField(controller: reference, label: te ? 'రిఫరెన్స్' : 'Reference'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      ),
    );
    final paise = askodoxParsePaise(amount.text);
    final ref0 = reference.text.trim();
    if (ok != true || paise == null || paise <= 0 || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).collect(widget.businessId, widget.customerId,
          {'client_txn_id': askodoxNewTxnId(), 'method': method, 'amount_paise': paise, 'reference': ref0});
      setState(_load);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _share(AskodoxJson st) async {
    final lines = <String>[
      '${askodoxPosMap(st['customer'])['name']} — ${st['month']}',
      'Opening: ${askodoxPaise(askodoxPosInt(st['opening_paise']))}',
      for (final e in askodoxPosList(st['entries']))
        '${e['local_date']} ${e['kind']} ${e['note']}  ${askodoxPosInt(e['debit_paise']) > 0 ? '+${askodoxPaise(askodoxPosInt(e['debit_paise']))}' : '-${askodoxPaise(askodoxPosInt(e['credit_paise']))}'}  = ${askodoxPaise(askodoxPosInt(e['balance_paise']))}',
      'Closing balance: ${askodoxPaise(askodoxPosInt(st['closing_paise']))}',
    ];
    try {
      await _device.invokeMethod<bool>('shareText', <String, Object?>{'text': lines.join('\n'), 'title': 'Statement'});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఖాతా స్టేట్‌మెంట్' : 'Account statement'), actions: [
        // Business CRM: everything about this customer (bills, leads, quotations, complaints, notes).
        IconButton(
            key: const Key('askodoxPosCustomerCrm'),
            tooltip: te ? 'Customer history (CRM)' : 'Customer history (CRM)',
            onPressed: () => context.push('/pos/${widget.businessId}/crm/customer/${widget.customerId}'),
            icon: const Icon(Icons.history)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          key: const Key('askodoxPosCollect'), onPressed: _collect, icon: const Icon(Icons.currency_rupee), label: Text(te ? 'జమ' : 'Received')),
      body: FutureBuilder<AskodoxJson>(
        future: _statement,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: () => setState(_load));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final st = snap.data!;
          return ListView(key: const Key('askodoxPosStatement'), padding: const EdgeInsets.all(12), children: [
            Text('${askodoxPosMap(st['customer'])['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            AskodoxPosCustomerAdvanceCard(businessId: widget.businessId, customerId: widget.customerId),
            Row(children: [
              IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
              Text(_month, style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
              const Spacer(),
              IconButton(onPressed: () => _share(st), icon: const Icon(Icons.share_outlined)),
            ]),
            ListTile(dense: true, title: Text(te ? 'మొదటి బాకీ' : 'Opening balance'), trailing: Text(askodoxPaise(askodoxPosInt(st['opening_paise'])))),
            for (final e in askodoxPosList(st['entries']))
              ListTile(
                dense: true,
                title: Text('${e['local_date']} · ${e['kind']}'),
                subtitle: Text('${e['note']}'),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(askodoxPosInt(e['debit_paise']) > 0
                      ? '+${askodoxPaise(askodoxPosInt(e['debit_paise']))}'
                      : '−${askodoxPaise(askodoxPosInt(e['credit_paise']))}'),
                  Text(askodoxPaise(askodoxPosInt(e['balance_paise'])), style: const TextStyle(fontSize: 11)),
                ]),
              ),
            ListTile(
              key: const Key('askodoxPosClosing'),
              title: Text(te ? 'చివరి బాకీ' : 'Closing balance', style: const TextStyle(fontWeight: FontWeight.w800)),
              trailing: Text(askodoxPaise(askodoxPosInt(st['closing_paise'])), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]);
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ bills
class AskodoxPosInvoicesScreen extends ConsumerWidget {
  const AskodoxPosInvoicesScreen({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బిల్లులు' : 'Bills')),
      body: FutureBuilder<List<AskodoxJson>>(
        future: ref.read(askodoxPosRepositoryProvider).invoices(businessId),
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(key: const Key('askodoxPosInvoices'), children: [
            for (final i in snap.data!)
              ListTile(
                key: ValueKey('askodoxPosInvoiceRow-${i['id']}'),
                title: Text('${i['number']} · ${i['customer_name']}'),
                subtitle: Text('${i['local_date']} · ${i['document_type']}${i['status'] == 'cancelled' ? (te ? ' · రద్దు' : ' · CANCELLED') : ''}'),
                trailing: Text(askodoxPaise(askodoxPosInt(i['grand_total_paise']))),
                onTap: () => context.push('/pos/$businessId/invoice/${i['id']}'),
              ),
          ]);
        },
      ),
    );
  }
}

class AskodoxPosInvoiceScreen extends ConsumerStatefulWidget {
  const AskodoxPosInvoiceScreen({super.key, required this.businessId, required this.invoiceId, this.fresh = false});
  final String businessId;
  final String invoiceId;

  /// Just issued at the counter: "Next bill" is the main button (owner 2026-11-19, fast counters).
  final bool fresh;

  @override
  ConsumerState<AskodoxPosInvoiceScreen> createState() => _AskodoxPosInvoiceScreenState();
}

class _AskodoxPosInvoiceScreenState extends ConsumerState<AskodoxPosInvoiceScreen> {
  late Future<AskodoxJson> _invoice;

  @override
  void initState() {
    super.initState();
    _invoice = ref.read(askodoxPosRepositoryProvider).invoice(widget.businessId, widget.invoiceId);
  }

  void _reload() => setState(() {
    _invoice = ref.read(askodoxPosRepositoryProvider).invoice(widget.businessId, widget.invoiceId);
  });

  Future<String?> _reason(String title) async {
    final te = askodoxPosTe(context);
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: AskodoxPosField(controller: c, label: te ? 'కారణం' : 'Reason'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'అవును' : 'Yes')),
        ],
      ),
    );
    final text = c.text.trim();
    return ok == true && text.isNotEmpty ? text : null;
  }

  Future<void> _creditAll(AskodoxJson invoice) async {
    final te = askodoxPosTe(context);
    final reason = await _reason(te ? 'మొత్తం బిల్లు రిటర్న్ (క్రెడిట్ నోట్)' : 'Return the whole bill (credit note)');
    if (reason == null || !mounted) return;
    final lines = [
      for (final l in askodoxPosList(invoice['lines'])) {'line_no': l['line_no'], 'qty_milli': l['qty_milli']},
    ];
    final total = askodoxPosInt(askodoxPosMap(invoice['totals'])['grand_total_paise']);
    final refund = invoice['customer_id'] == null ? {'method': 'cash', 'amount_paise': total} : null;
    try {
      final note = await ref.read(askodoxPosRepositoryProvider).creditNote(widget.businessId, widget.invoiceId, {
        'client_txn_id': askodoxNewTxnId(),
        'reason': reason,
        'lines': lines,
        if (refund != null) 'refund': refund,
      });
      if (mounted) context.pushReplacement('/pos/${widget.businessId}/invoice/${note['id']}');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  /// Back to an empty counter: the sale screen that issued this bill when it is underneath, else a new one.
  void _nextBill() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/pos/${widget.businessId}/sale');
    }
  }

  Future<void> _cancel() async {
    final te = askodoxPosTe(context);
    final reason = await _reason(te ? 'ఈ బిల్లు రద్దు చేయాలా? (రికార్డు ఉంటుంది)' : 'Cancel this bill? (the record stays)');
    if (reason == null || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).cancel(widget.businessId, widget.invoiceId, reason);
      _reload();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull ?? const <String, Object?>{};
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బిల్లు' : 'Bill')),
      body: FutureBuilder<AskodoxJson>(
        future: _invoice,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final inv = snap.data!;
          final receipt = askodoxReceiptLines(inv, columns: 32, asciiOnly: false);
          final isInvoice = inv['doc_kind'] == 'invoice' && inv['status'] == 'issued';
          return ListView(key: const Key('askodoxPosInvoice'), padding: const EdgeInsets.all(12), children: [
            if (inv['status'] == 'cancelled')
              Text('${te ? 'రద్దు' : 'CANCELLED'}: ${inv['cancel_reason']}', style: const TextStyle(color: Color(0xFFFEA195), fontWeight: FontWeight.w800)),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(receipt.join('\n'), key: const Key('askodoxPosReceipt'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
            for (final p in askodoxPosList(inv['payments']))
              if (p['verification'] == 'cashier_confirmed')
                Text(te ? '${p['method']}: క్యాషియర్ నమోదు చేశారు' : '${p['method']}: entered by the cashier',
                    style: const TextStyle(fontSize: 11.5)),
            // Owner 2026-11-19: the bill is already saved with its number, so the cashier moves on with one tap.
            // Print / PDF / Share sit on ONE equal row; Return and Cancel (rare) live under "more".
            if (widget.fresh && inv['status'] == 'issued') ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('askodoxPosNextBill'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => _nextBill(),
                icon: const Icon(Icons.add_circle_outline),
                label: Text(te ? 'తర్వాతి బిల్లు' : 'Next bill', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('askodoxPosPrint'),
                  onPressed: () => askodoxPrintInvoice(context, ref, inv, businessId: widget.businessId),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(te ? 'ప్రింట్' : 'Print'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('askodoxPosSharePdf'),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await askodoxShareInvoicePdf(inv);
                    if (!ok) {
                      messenger.showSnackBar(SnackBar(
                          content: Text(te ? 'PDF పంపలేకపోయాను (యాప్ అప్‌డేట్ చేయండి).' : 'Could not share the PDF (update the app).')));
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('askodoxPosShare'),
                  onPressed: () async {
                    try {
                      await _device.invokeMethod<bool>('shareText', <String, Object?>{'text': receipt.join('\n'), 'title': '${inv['number']}'});
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.share_outlined),
                  label: Text(te ? 'షేర్' : 'Share'),
                ),
              ),
              if (isInvoice && (askodoxPosCan(business, 'return') || askodoxPosCan(business, 'cancel')))
                PopupMenuButton<String>(
                  key: const Key('askodoxPosMore'),
                  tooltip: te ? 'మరిన్ని' : 'More',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) => v == 'return' ? _creditAll(inv) : _cancel(),
                  itemBuilder: (_) => [
                    if (askodoxPosCan(business, 'return'))
                      PopupMenuItem(
                          key: const Key('askodoxPosReturn'),
                          value: 'return',
                          child: Text(te ? 'రిటర్న్ / క్రెడిట్ నోట్' : 'Return / credit note')),
                    if (askodoxPosCan(business, 'cancel'))
                      PopupMenuItem(key: const Key('askodoxPosCancel'), value: 'cancel', child: Text(te ? 'బిల్లు రద్దు' : 'Cancel bill')),
                  ],
                ),
            ]),
          ]);
        },
      ),
    );
  }
}

// -------------------------------------------------------------- day close
class AskodoxPosDayScreen extends ConsumerStatefulWidget {
  const AskodoxPosDayScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosDayScreen> createState() => _AskodoxPosDayScreenState();
}

class _AskodoxPosDayScreenState extends ConsumerState<AskodoxPosDayScreen> {
  final _float = TextEditingController();
  final _counted = TextEditingController();
  late Future<AskodoxJson> _day;
  final _date = askodoxPosToday();

  @override
  void initState() {
    super.initState();
    _day = ref.read(askodoxPosRepositoryProvider).day(widget.businessId, _date);
  }

  @override
  void dispose() {
    _float.dispose();
    _counted.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final te = askodoxPosTe(context);
    final counted = askodoxParsePaise(_counted.text);
    if (counted == null) {
      askodoxPosSnack(context, te ? 'డ్రాలో ఉన్న నగదు నమోదు చేయండి.' : 'Enter the cash counted in the drawer.');
      return;
    }
    try {
      final day = await ref.read(askodoxPosRepositoryProvider).closeDay(widget.businessId,
          {'local_date': _date, 'opening_float_paise': askodoxParsePaise(_float.text) ?? 0, 'counted_cash_paise': counted});
      if (mounted) setState(() => _day = Future.value(day));
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text('${te ? 'రోజు ముగింపు' : 'Day close'} · $_date')),
      body: FutureBuilder<AskodoxJson>(
        future: _day,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          final closed = d['closed'] == null ? null : askodoxPosMap(d['closed']);
          return ListView(key: const Key('askodoxPosDay'), padding: const EdgeInsets.all(12), children: [
            ListTile(title: Text(te ? 'బిల్లులు' : 'Bills'), trailing: Text('${d['invoices']}')),
            ListTile(title: Text(te ? 'అమ్మకాలు' : 'Sales'), trailing: Text(askodoxPaise(askodoxPosInt(d['sales_paise'])))),
            ListTile(title: Text(te ? 'పన్ను' : 'Tax'), trailing: Text(askodoxPaise(askodoxPosInt(d['tax_paise'])))),
            ListTile(title: Text(te ? 'క్రెడిట్ నోట్లు' : 'Credit notes'), trailing: Text(askodoxPaise(askodoxPosInt(d['credit_notes_paise'])))),
            for (final e in askodoxPosMap(d['payments']).entries)
              ListTile(dense: true, title: Text(e.key), trailing: Text(askodoxPaise(askodoxPosInt(askodoxPosMap(e.value)['net_paise'])))),
            Text('${d['note']}', style: const TextStyle(fontSize: 11.5)),
            const Divider(),
            if (closed != null) ...[
              Text(te ? 'ఈ రోజు ముగిసింది (మార్చలేం).' : 'This day is closed (final).', key: const Key('askodoxPosDayClosed'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              ListTile(title: Text(te ? 'ఉండాల్సిన నగదు' : 'Expected cash'), trailing: Text(askodoxPaise(askodoxPosInt(closed['expected_cash_paise'])))),
              ListTile(title: Text(te ? 'లెక్కించిన నగదు' : 'Counted cash'), trailing: Text(askodoxPaise(askodoxPosInt(closed['counted_cash_paise'])))),
              ListTile(title: Text(te ? 'తేడా' : 'Difference'), trailing: Text(askodoxPaise(askodoxPosInt(closed['difference_paise'])))),
            ] else ...[
              AskodoxPosField(controller: _float, number: true, label: te ? 'ఉదయం డ్రాలో పెట్టిన నగదు (₹)' : 'Opening cash in drawer (₹)'),
              AskodoxPosField(controller: _counted, number: true, label: te ? 'ఇప్పుడు లెక్కించిన నగదు (₹)' : 'Cash counted now (₹)'),
              FilledButton(key: const Key('askodoxPosCloseDay'), onPressed: _close, child: Text(te ? 'రోజు ముగించు' : 'Close the day')),
            ],
          ]);
        },
      ),
    );
  }
}

// ------------------------------------------------------------------- GST
class AskodoxPosGstScreen extends ConsumerStatefulWidget {
  const AskodoxPosGstScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosGstScreen> createState() => _AskodoxPosGstScreenState();
}

class _AskodoxPosGstScreenState extends ConsumerState<AskodoxPosGstScreen> {
  late String _month;
  late Future<AskodoxJson> _report;

  @override
  void initState() {
    super.initState();
    _month = askodoxPosToday().substring(0, 7);
    _load();
  }

  void _load() {
    final y = int.parse(_month.substring(0, 4));
    final m = int.parse(_month.substring(5));
    final last = DateTime(y, m + 1, 0).day;
    _report = ref.read(askodoxPosRepositoryProvider).gstReport(widget.businessId, '$_month-01', '$_month-${last.toString().padLeft(2, '0')}');
  }

  void _shift(int delta) {
    final d = DateTime(int.parse(_month.substring(0, 4)), int.parse(_month.substring(5)) + delta);
    setState(() {
      _month = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      _load();
    });
  }

  Widget _row(String label, AskodoxJson r) => ListTile(
        dense: true,
        title: Text(label),
        subtitle: Text('CGST ${askodoxPaise(askodoxPosInt(r['cgst_paise']))} · SGST/UTGST ${askodoxPaise(askodoxPosInt(r['sgst_paise']))} · '
            'IGST ${askodoxPaise(askodoxPosInt(r['igst_paise']))} · Cess ${askodoxPaise(askodoxPosInt(r['cess_paise']))}'),
        trailing: Text(askodoxPaise(askodoxPosInt(r['taxable_paise']))),
      );

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'GST సారాంశం' : 'GST summary')),
      body: FutureBuilder<AskodoxJson>(
        future: _report,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: () => setState(_load));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final r = snap.data!;
          return ListView(key: const Key('askodoxPosGst'), padding: const EdgeInsets.all(12), children: [
            Row(children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Text(_month, style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ]),
            Text('${r['disclaimer']}', key: const Key('askodoxPosGstDisclaimer'), style: const TextStyle(fontSize: 12, color: Color(0xFFFB9E6A))),
            Text(te ? 'రేటు వారీగా (పన్ను విధించదగిన విలువ)' : 'By rate (taxable value)', style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final row in askodoxPosList(r['by_rate'])) _row('${askodoxRate(askodoxPosInt(row['rate_bp']))} · ${row['category']}', row),
            _row('B2B', askodoxPosMap(r['b2b'])),
            _row('B2C', askodoxPosMap(r['b2c'])),
            Text('HSN', style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final row in askodoxPosList(r['hsn'])) _row('${row['hsn_sac']} · ${askodoxQty(askodoxPosInt(row['qty_milli']), '${row['unit']}')}', row),
            Text('${te ? 'రద్దైన బిల్లులు' : 'Cancelled bills'}: ${r['cancelled_count']}'),
          ]);
        },
      ),
    );
  }
}

// ----------------------------------------------------------------- staff (owner 2026-11-17: who accepts orders)
/// The shop's people on ONE list: add (name, phone, role, may accept orders), and on every row ✏ edit, ⏸ pause / ▶
/// resume, 🗑 remove (asked first; a removed person can be brought back). A new order rings only the owner and the
/// people allowed to accept; nothing is ever accepted by itself.
class AskodoxPosStaffScreen extends ConsumerStatefulWidget {
  const AskodoxPosStaffScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosStaffScreen> createState() => _AskodoxPosStaffScreenState();
}

const _staffRoles = ['manager', 'cashier', 'waiter', 'kitchen', 'accountant', 'attendant', 'delivery'];

class _AskodoxPosStaffScreenState extends ConsumerState<AskodoxPosStaffScreen> {
  List<AskodoxJson>? _members;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(askodoxPosRepositoryProvider).members(widget.businessId);
      if (mounted) {
        setState(() {
          _members = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _do(Future<Object?> Function() action, String done) async {
    final te = askodoxPosTe(context);
    try {
      await action();
      await _load();
      if (mounted && done.isNotEmpty) askodoxPosSnack(context, done);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  /// Add (m == null) or edit one person: name, phone (new only), role, may accept orders.
  Future<void> _edit(AskodoxJson? m) async {
    final te = askodoxPosTe(context);
    final name = TextEditingController(text: '${m?['label'] ?? ''}');
    final phone = TextEditingController();
    var role = '${m?['role'] ?? 'waiter'}';
    var accepts = m == null ? true : m['accepts_orders'] == true;
    // Owner 2026-11-20: what this person can open -- a new person starts with payment sound (+ their one job screen).
    var tools = <String>{
      ...(m == null
          ? askodoxStaffStartTools(role)
          : (m['tools'] as List?)?.map((e) => '$e') ?? askodoxStaffToolsFor(role)),
    };
    var toolsTouched = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(m == null ? (te ? 'కొత్త వ్యక్తిని చేర్చు' : 'Add a person') : (te ? 'మార్చు' : 'Edit'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextField(
              key: const Key('askodoxStaffName'),
              controller: name,
              maxLength: 40,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'పేరు' : 'Name'),
            ),
            if (m == null)
              TextField(
                key: const Key('askodoxStaffPhone'),
                controller: phone,
                keyboardType: TextInputType.phone,
                maxLength: 13,
                decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'ఫోన్ నంబర్ (10 అంకెలు)' : 'Phone number (10 digits)'),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${te ? 'ఫోన్' : 'Phone'}: ••••${m['phone_last4']}', style: const TextStyle(color: Color(0xFFB4BED1))),
              ),
            Text(te ? 'పాత్ర' : 'Role', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in _staffRoles)
                ChoiceChip(
                  key: Key('askodoxStaffRole-$r'),
                  label: Text(askodoxStaffRoleLabel(r, te)),
                  selected: role == r,
                  onSelected: (_) => setInner(() {
                    role = r;
                    if (!toolsTouched) {
                      tools = {...(m == null ? askodoxStaffStartTools(r) : askodoxStaffToolsFor(r).where(tools.contains))};
                    } else {
                      tools = tools.where(askodoxStaffToolsFor(r).contains).toSet();
                    }
                  }),
                ),
            ]),
            const SizedBox(height: 10),
            Text(te ? 'వీళ్లు ఏవి తెరవచ్చు? (మీరు టిక్ చేసినవి మాత్రమే)' : 'What can they open? (only what you tick)',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in askodoxStaffTools)
                if (askodoxStaffToolsFor(role).contains(t.$1))
                  FilterChip(
                    key: Key('askodoxStaffTool-${t.$1}'),
                    label: Text(te ? t.$3 : t.$2),
                    selected: tools.contains(t.$1),
                    onSelected: (on) => setInner(() {
                      toolsTouched = true;
                      on ? tools.add(t.$1) : tools.remove(t.$1);
                    }),
                  ),
            ]),
            CheckboxListTile(
              key: const Key('askodoxStaffAccepts'),
              contentPadding: EdgeInsets.zero,
              value: accepts,
              onChanged: (v) => setInner(() => accepts = v ?? false),
              title: Text(te ? 'ఆర్డర్లు ఒప్పుకోవచ్చు' : 'May accept orders', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(te ? 'కొత్త ఆర్డర్ వస్తే వీళ్ల ఫోన్ మోగుతుంది' : 'Their phone rings for a new order'),
            ),
            FilledButton(
              key: const Key('askodoxPosSaveMember'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(m == null ? (te ? 'చేర్చు' : 'Add') : (te ? 'సేవ్' : 'Save')),
            ),
          ]),
        ),
      ),
    );
    final label = name.text.trim();
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    name.dispose();
    phone.dispose();
    if (ok != true || !mounted) return;
    final repo = ref.read(askodoxPosRepositoryProvider);
    if (m == null) {
      if (digits.length < 10) {
        askodoxPosSnack(context, te ? '10 అంకెల నంబర్ రాయండి.' : 'Enter a 10 digit number.');
        return;
      }
      await _do(
          () => repo.setMember(widget.businessId, digits.substring(digits.length - 10), role,
              label: label, acceptsOrders: accepts, tools: tools.toList()),
          te ? 'చేర్చాం. వాళ్లు అదే నంబర్‌తో ASKODOX లో సైన్ ఇన్ చేయాలి.' : 'Added. They sign in to ASKODOX with that number.');
    } else {
      await _do(
          () => repo.editMember(widget.businessId, '${m['phone_last4']}',
              role: role, label: label, acceptsOrders: accepts, tools: tools.toList()),
          te ? 'సేవ్ అయింది' : 'Saved');
    }
  }

  Future<void> _remove(AskodoxJson m) async {
    final te = askodoxPosTe(context);
    final who = '${m['label'] ?? ''}'.isNotEmpty ? '${m['label']}' : '••${m['phone_last4']}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? '$who ని తీసేయాలా?' : 'Remove $who?'),
        content: Text(te ? 'ఈ షాప్ వాళ్లకి కనపడదు. పాత బిల్లుల్లో పేరు అలాగే ఉంటుంది. తర్వాత తిరిగి తేవచ్చు.' : 'They lose this shop. Old bills keep the name. You can bring them back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(key: const Key('askodoxStaffRemoveYes'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'తీసేయి' : 'Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await _do(() => ref.read(askodoxPosRepositoryProvider).removeMember(widget.businessId, '${m['phone_last4']}'), '');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(te ? '$who ని తీసేశాం' : '$who removed'),
      action: SnackBarAction(label: te ? 'తిరిగి తెచ్చు' : 'Undo', onPressed: () => unawaited(_restore(m))),
    ));
  }

  Future<void> _restore(AskodoxJson m) => _do(
      () => ref.read(askodoxPosRepositoryProvider).editMember(widget.businessId, '${m['phone_last4']}', role: '${m['role']}'),
      askodoxPosTe(context) ? 'తిరిగి వచ్చారు' : 'Back on the team');

  Widget _person(AskodoxJson m, bool te) {
    final owner = m['role'] == 'owner';
    final active = m['active'] == true;
    final paused = m['paused'] == true;
    final accepts = m['accepts_orders'] == true;
    final name = '${m['label'] ?? ''}'.isNotEmpty ? '${m['label']}' : (owner ? (te ? 'మీరు' : 'You') : '••${m['phone_last4']}');
    final status = !active
        ? (te ? 'తీసేశారు' : 'Removed', const Color(0xFFB1B9C8))
        : paused
            ? (te ? 'ఆపారు (Pause)' : 'Paused', const Color(0xFFFB9E6A))
            : accepts
                ? (te ? 'ఆర్డర్లు ఒప్పుకోవచ్చు' : 'Accepts orders', const Color(0xFF7CD3A2))
                : (te ? 'ఆర్డర్లు ఒప్పుకోరు' : 'Does not accept orders', const Color(0xFFB4BED1));
    Widget btn(String key, IconData icon, String tip, VoidCallback onTap, {Color bg = const Color(0xFF1F2432), Color fg = const Color(0xFFF7F9FC)}) =>
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: Key(key),
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Tooltip(message: tip, child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20, color: fg))),
            ),
          ),
        );
    return Padding(
      key: Key('askodoxStaffRow-${m['phone_last4']}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        CircleAvatar(radius: 20, child: Text(name.characters.first, style: const TextStyle(fontWeight: FontWeight.w800))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: active ? null : const Color(0xFFB1B9C8))),
            Text('${askodoxStaffRoleLabel('${m['role']}', te)} · ••••${m['phone_last4']}', style: const TextStyle(fontSize: 12, color: Color(0xFFB4BED1))),
            Text(owner ? (te ? 'ఎప్పుడూ ఒప్పుకోవచ్చు' : 'Always accepts') : status.$1,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: owner ? const Color(0xFF7CD3A2) : status.$2)),
          ]),
        ),
        if (!owner && active) ...[
          btn('askodoxStaffEdit-${m['phone_last4']}', Icons.edit_outlined, te ? 'మార్చు' : 'Edit', () => unawaited(_edit(m))),
          btn('askodoxStaffPause-${m['phone_last4']}', paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              paused ? (te ? 'మళ్లీ మొదలుపెట్టు' : 'Resume') : (te ? 'ఆపు' : 'Pause'),
              () => unawaited(_do(
                  () => ref.read(askodoxPosRepositoryProvider).editMember(widget.businessId, '${m['phone_last4']}', paused: !paused),
                  paused ? (te ? 'మళ్లీ మొదలైంది' : 'Resumed') : (te ? 'ఆపాం — ఆర్డర్లు రావు' : 'Paused — no orders reach them')))),
          btn('askodoxStaffRemove-${m['phone_last4']}', Icons.delete_outline, te ? 'తీసేయి' : 'Remove', () => unawaited(_remove(m)),
              bg: const Color(0xFF402526), fg: const Color(0xFFFEA195)),
        ],
        if (!owner && !active)
          TextButton(key: Key('askodoxStaffRestore-${m['phone_last4']}'), onPressed: () => unawaited(_restore(m)), child: Text(te ? 'తిరిగి తెచ్చు' : 'Bring back')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final rows = _members ?? const <AskodoxJson>[];
    final current = [for (final m in rows) if (m['active'] == true) m]..sort((a, b) => (a['role'] == 'owner' ? 0 : 1).compareTo(b['role'] == 'owner' ? 0 : 1));
    final removed = [for (final m in rows) if (m['active'] != true) m];
    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'సిబ్బంది · ఆర్డర్ ఒప్పుకునేది ఎవరు' : 'Staff · who accepts orders'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              key: const Key('askodoxStaffAdd'),
              onPressed: () => unawaited(_edit(null)),
              icon: const Icon(Icons.add),
              label: Text(te ? 'చేర్చు' : 'Add'),
            ),
          ),
        ],
      ),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : _members == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(key: const Key('askodoxPosStaff'), padding: const EdgeInsets.all(14), children: [
                    Text(
                        te
                            ? 'కొత్త ఆర్డర్ వస్తే "ఆర్డర్లు ఒప్పుకోవచ్చు" ఉన్నవాళ్ల ఫోన్లలో మోగుతుంది. ఎవరో ఒకరు నొక్కితే చాలు. ఎవరినీ అనుమతించకపోతే మీరొక్కరే. ఆటోమేటిక్‌గా ఒప్పుకోవడం ఉండదు.'
                            : 'A new order rings the people who "accept orders"; one tap from any of them is enough. Allow nobody and it is only you. Nothing is accepted by itself.',
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFFB4BED1))),
                    const SizedBox(height: 8),
                    // Owner 2026-11-24: Staff and "who accepts orders / who hears each step" are ONE page.
                    Card(
                      color: const Color(0xFF2F2A3E),
                      child: ListTile(
                        key: const Key('askodoxStaffOrderAlerts'),
                        leading: const Icon(Icons.notifications_active_rounded, color: Color(0xFFBCACFB)),
                        title: Text(te ? 'ఆర్డర్ అలర్ట్స్: ఏ స్టెప్ ఎవరికి వినిపించాలి' : 'Order alerts: who hears each step',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(te ? 'కొత్త ఆర్డర్, వంట అయింది, డెలివరీ — ఒక్కో స్టెప్‌కి ఎవరో ఎంచుకోండి.' : 'New order, ready, delivery — choose people per step.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/desk/${widget.businessId}/settings'),
                      ),
                    ),
                    Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Column(children: [for (final m in current) _person(m, te)]))),
                    if (removed.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(te ? 'తీసేసినవాళ్లు' : 'Removed', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Column(children: [for (final m in removed) _person(m, te)]))),
                    ],
                    const SizedBox(height: 8),
                    Text(te ? 'వాళ్లు అదే నంబర్‌తో ASKODOX లో సైన్ ఇన్ చేస్తే ఈ షాప్ కనిపిస్తుంది.' : 'They see this shop after signing in to ASKODOX with that number.',
                        style: const TextStyle(fontSize: 12)),
                  ]),
                ),
    );
  }
}

// --------------------------------------------------------------- printer
class AskodoxPosPrinterScreen extends ConsumerStatefulWidget {
  const AskodoxPosPrinterScreen({super.key});

  @override
  ConsumerState<AskodoxPosPrinterScreen> createState() => _AskodoxPosPrinterScreenState();
}

class _AskodoxPosPrinterScreenState extends ConsumerState<AskodoxPosPrinterScreen> {
  AskodoxSavedPrinter? _saved;
  List<AskodoxBleDevice> _found = const [];
  List<AskodoxNativePrinter> _native = const [];
  bool _scanning = false;
  int _paper = 58;
  String? _message;

  @override
  void initState() {
    super.initState();
    AskodoxSavedPrinter.load().then((p) {
      if (mounted && p != null) {
        setState(() {
          _saved = p;
          _paper = p.paperMm;
        });
      }
    });
  }

  Future<void> _scan() async {
    final te = askodoxPosTe(context);
    final ble = ref.read(askodoxBleGatewayProvider);
    setState(() {
      _scanning = true;
      _message = null;
    });
    try {
      if (!await ble.isOn()) await ble.requestTurnOn();
      final found = await ble.scan(const Duration(seconds: 8));
      if (mounted) setState(() => _found = found);
    } on AskodoxBleException catch (e) {
      if (mounted) {
        setState(() => _message = e.code == 'permission_denied'
            ? (te ? 'బ్లూటూత్ అనుమతి ఇవ్వలేదు.' : 'Bluetooth permission was not given.')
            : (te ? 'స్కాన్ విఫలమైంది.' : 'The scan failed.'));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _listNative(bool usb) async {
    final te = askodoxPosTe(context);
    final native = ref.read(askodoxNativePrintersProvider);
    setState(() => _message = null);
    try {
      final rows = usb ? await native.usb() : await native.paired();
      if (!mounted) return;
      setState(() {
        _native = rows;
        if (rows.isEmpty) {
          _message = usb
              ? (te ? 'USB ప్రింటర్ కనిపించలేదు (OTG కేబుల్‌తో కనెక్ట్ చేయండి).' : 'No USB printer found (connect it with an OTG cable).')
              : (te ? 'జత చేసిన పరికరాలు లేవు. ఫోన్ బ్లూటూత్ సెట్టింగ్స్‌లో ప్రింటర్‌ని జత చేయండి.' : 'No paired devices. Pair the printer in the phone\'s Bluetooth settings.');
        }
      });
    } on AskodoxPrinterException catch (e) {
      if (mounted) setState(() => _message = e.message(te));
    }
  }

  Future<void> _chooseNative(AskodoxNativePrinter d) async {
    final p = AskodoxSavedPrinter(id: d.id, name: d.name, paperMm: _paper);
    await p.save();
    if (mounted) setState(() => _saved = p);
  }

  Future<void> _choose(AskodoxBleDevice d) async {
    final p = AskodoxSavedPrinter(id: d.id, name: d.name.isEmpty ? d.id : d.name, paperMm: _paper);
    await p.save();
    if (mounted) setState(() => _saved = p);
  }

  Future<void> _test() async {
    final te = askodoxPosTe(context);
    final p = _saved;
    if (p == null) return;
    final bytes = (AskodoxEscPos().init().align(1).bold(true).text('ASKODOX test print').bold(false).text('Paper ${p.paperMm} mm')
          ..text('-' * askodoxReceiptColumns(p.paperMm))
          ..feed(3)
          ..cut())
        .bytes();
    try {
      await ref.read(askodoxPrinterTransportProvider).write(p.id, bytes);
      if (mounted) setState(() => _message = te ? 'పంపాం — పేపర్ మీద వచ్చిందా చూడండి.' : 'Sent — check that it printed.');
    } on AskodoxPrinterException catch (e) {
      if (mounted) setState(() => _message = e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ప్రింటర్' : 'Printer')),
      body: ListView(key: const Key('askodoxPosPrinter'), padding: const EdgeInsets.all(12), children: [
        Text(
          te
              ? 'ESC/POS థర్మల్ ప్రింటర్లు: బ్లూటూత్ LE, క్లాసిక్ బ్లూటూత్ (ముందు ఫోన్ సెట్టింగ్స్‌లో జత చేయండి), USB (OTG). Wi-Fi ప్రింటర్లు ఇంకా లేవు. ఏ మోడల్ ఇంకా నిజంగా పరీక్షించలేదు. తెలుగు పేర్లు చిత్రంగా ప్రింట్ అవుతాయి (ఇంకా ప్రింటర్‌పై పరీక్షించలేదు).'
              : 'ESC/POS thermal printers: Bluetooth LE, Classic Bluetooth (pair it in phone settings first) and USB (OTG). Wi-Fi printers are not supported yet. No model has been tested yet. Telugu names print as an image (not tested on a printer yet).',
          key: const Key('askodoxPosPrinterLimits'),
          style: const TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))],
          selected: {_paper},
          onSelectionChanged: (s) async {
            setState(() => _paper = s.first);
            final p = _saved;
            if (p != null) {
              final updated = AskodoxSavedPrinter(id: p.id, name: p.name, paperMm: s.first);
              await updated.save();
              if (mounted) setState(() => _saved = updated);
            }
          },
        ),
        if (_saved != null)
          ListTile(
            key: const Key('askodoxPosSavedPrinter'),
            leading: const Icon(Icons.print),
            title: Text(_saved!.name),
            subtitle: Text('${_saved!.paperMm} mm · ${switch (askodoxPrinterLink(_saved!.id)) {
              'classic' => te ? 'క్లాసిక్ బ్లూటూత్' : 'Classic Bluetooth',
              'usb' => 'USB',
              _ => 'Bluetooth LE',
            }}'),
            trailing: TextButton(onPressed: _test, child: Text(te ? 'టెస్ట్ ప్రింట్' : 'Test print')),
          ),
        FilledButton.icon(
          key: const Key('askodoxPosPrinterScan'),
          onPressed: _scanning ? null : _scan,
          icon: const Icon(Icons.bluetooth_searching),
          label: Text(_scanning ? (te ? 'వెతుకుతోంది…' : 'Scanning…') : (te ? 'BLE ప్రింటర్ వెతుకు' : 'Find BLE printer')),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('askodoxPosPrinterPaired'),
              onPressed: () => _listNative(false),
              icon: const Icon(Icons.bluetooth_connected),
              label: Text(te ? 'జత చేసినవి' : 'Paired'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('askodoxPosPrinterUsb'),
              onPressed: () => _listNative(true),
              icon: const Icon(Icons.usb),
              label: const Text('USB'),
            ),
          ),
        ]),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!)),
        for (final d in _found)
          ListTile(
            key: ValueKey('askodoxPosPrinterFound-${d.id}'),
            title: Text(d.name.isEmpty ? (te ? 'పేరు లేని పరికరం' : 'Unnamed device') : d.name),
            subtitle: Text('RSSI ${d.rssi}'),
            onTap: () => _choose(d),
          ),
        for (final d in _native)
          ListTile(
            key: ValueKey('askodoxPosPrinterNative-${d.id}'),
            leading: Icon(d.kind == 'usb' ? Icons.usb : Icons.bluetooth),
            title: Text(d.name),
            subtitle: Text(d.hint ? (te ? 'ప్రింటర్‌లా కనిపిస్తోంది' : 'Looks like a printer') : d.id.split(':').skip(1).join(':')),
            onTap: () => _chooseNative(d),
          ),
      ]),
    );
  }
}
