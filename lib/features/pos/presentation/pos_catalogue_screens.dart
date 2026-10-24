import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/askodox_field_guide.dart';
import '../../home/presentation/question_mic.dart';
import '../../selling/data/catalogue_repository.dart';
import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import 'pos_common.dart';
import 'pos_tiles.dart';

String _n(Object? names, bool te) {
  final m = names is Map ? names : const {};
  return '${(te ? m['te'] : null) ?? m['en'] ?? ''}';
}

const _rates = [0, 10, 25, 100, 150, 300, 500, 600, 1200, 1800, 2800, 4000];

// ---------------------------------------------------------------- ready-made list
/// Pick items from the shop's ready-made catalogue: tick, choose the size, type
/// YOUR price (and GST % when registered). Nothing is added without a price.
class AskodoxPosCatalogueScreen extends ConsumerStatefulWidget {
  const AskodoxPosCatalogueScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosCatalogueScreen> createState() => _AskodoxPosCatalogueScreenState();
}

class _Pick {
  _Pick(this.item) : size = (item['sizes'] as List? ?? const []).isEmpty ? null : '${(item['sizes'] as List).first}';
  final AskodoxJson item;
  String? size;
  int? rate;
  final price = TextEditingController();
}

class _AskodoxPosCatalogueScreenState extends ConsumerState<AskodoxPosCatalogueScreen> {
  AskodoxJson? _data;
  Object? _error;
  bool _busy = false;
  final _picked = <String, _Pick>{};

  @override
  void initState() {
    super.initState();
    _load();
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
      final d = await ref.read(askodoxPosRepositoryProvider).catalogue(widget.businessId);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _setTemplate(String? key) async {
    final te = askodoxPosTe(context);
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).setCatalogueTemplate(widget.businessId, key);
      if (mounted) {
        setState(() {
          _data = d;
          _picked.clear();
        });
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  bool get _registered => '${_data?['registration_type']}' == 'regular';

  Future<void> _add() async {
    final te = askodoxPosTe(context);
    final lines = <AskodoxJson>[];
    for (final p in _picked.values) {
      final paise = askodoxParsePaise(p.price.text);
      if (paise == null || paise <= 0) {
        askodoxPosSnack(context, te ? 'ఎంచుకున్న ప్రతి సరుకుకీ మీ ధర రాయండి.' : 'Type your price for every ticked item.');
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
      final out = await ref.read(askodoxPosRepositoryProvider).importCatalogue(widget.businessId, lines);
      final added = askodoxPosList(out['added']).length;
      final skipped = askodoxPosList(out['skipped']).length;
      if (!mounted) return;
      askodoxPosSnack(
          context,
          te
              ? '$added సరుకులు చేర్చాం${skipped > 0 ? ', $skipped వదిలేశాం (ఇప్పటికే ఉన్నవి / ధర లేనివి)' : ''}.'
              : 'Added $added item(s)${skipped > 0 ? ', skipped $skipped (already in the shop / no price)' : ''}.');
      if (context.mounted) context.pop(true);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(AskodoxJson item, bool te) {
    final key = '${item['key']}';
    final pick = _picked[key];
    final sizes = [for (final s in (item['sizes'] as List? ?? const [])) '$s'];
    return Card(
      key: ValueKey('askodoxPosCatalogueItem-$key'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CheckboxListTile(
            key: ValueKey('askodoxPosCataloguePick-$key'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: pick != null,
            onChanged: item['in_shop'] == true
                ? null
                : (v) => setState(() {
                      if (v == true) {
                        _picked[key] = _Pick(item);
                      } else {
                        _picked.remove(key)?.price.dispose();
                      }
                    }),
            title: Text(_n(item['name'], te), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(item['in_shop'] == true
                ? (te ? 'మీ షాప్‌లో ఇప్పటికే ఉంది' : 'Already in your shop')
                : '${te ? 'యూనిట్' : 'Unit'}: ${item['pos_unit']}'),
          ),
          if (pick != null) ...[
            if (sizes.length > 1)
              Wrap(spacing: 6, children: [
                for (final s in sizes)
                  ChoiceChip(
                      key: ValueKey('askodoxPosCatalogueSize-$key-$s'),
                      label: Text(s),
                      selected: pick.size == s,
                      onSelected: (_) => setState(() => pick.size = s)),
              ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: AskodoxPosField(
                  key: ValueKey('askodoxPosCataloguePrice-$key'),
                  controller: pick.price,
                  number: true,
                  label: te ? 'మీ ధర (₹)' : 'Your price (₹)',
                  guideEn: 'Your own selling price for one ${item['pos_unit']}${pick.size == null ? '' : ' (${pick.size})'}. ASKODOX never fills prices in.',
                  guideTe: 'ఒక ${item['pos_unit']}${pick.size == null ? '' : ' (${pick.size})'} కి మీ అమ్మకం ధర. ASKODOX ధరలు నింపదు.',
                ),
              ),
              if (_registered) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('askodoxPosCatalogueRate-$key'),
                    initialValue: pick.rate,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'GST %', border: OutlineInputBorder(), isDense: true),
                    items: [for (final r in _rates) DropdownMenuItem(value: r, child: Text(askodoxRate(r)))],
                    onChanged: (v) => setState(() => pick.rate = v),
                  ),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final d = _data;
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull;
    final canSettings = business != null && askodoxPosCan(business, 'settings');
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'రెడీమేడ్ లిస్ట్ నుండి చేర్చు' : 'Add from the ready list')),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  key: const Key('askodoxPosCatalogueAdd'),
                  onPressed: _busy ? null : _add,
                  child: Text(te ? '${_picked.length} సరుకులు చేర్చు' : 'Add ${_picked.length} item(s)'),
                ),
              ),
            ),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(key: const Key('askodoxPosCatalogue'), padding: const EdgeInsets.all(12), children: [
                  Text(
                    te
                        ? 'మీ వ్యాపారానికి తగిన సరుకుల లిస్ట్. టిక్ చేసి, సైజు ఎంచుకుని, మీ ధర రాయండి. బ్రాండ్‌లు, ధరలు మేము పెట్టము.'
                        : 'A ready list for your kind of shop. Tick, choose the size and type your price. We never add brands or prices.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: const Key('askodoxPosCatalogueTemplate'),
                    initialValue: d['template_key'] as String?,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: te ? 'మీ వ్యాపార రకం' : 'Your kind of business',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: const AskodoxFieldGuideButton(
                        titleEn: 'Kind of business', titleTe: 'వ్యాపార రకం',
                        en: 'Choose what your shop mostly sells. It decides the ready item list and the details (size, colour, brand …) each item asks for.',
                        te: 'మీ షాప్ ఎక్కువగా ఏం అమ్ముతుందో ఎంచుకోండి. దాని ప్రకారం రెడీ లిస్ట్, ప్రతి సరుకు అడిగే వివరాలు (సైజు, రంగు, బ్రాండ్ …) వస్తాయి.',
                      ),
                    ),
                    items: [
                      for (final c in askodoxPosList(d['choices']))
                        DropdownMenuItem(value: '${c['key']}', child: Text(_n(c['name'], te))),
                    ],
                    onChanged: canSettings ? _setTemplate : null,
                  ),
                  if (askodoxPosList(d['categories']).isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(te ? 'ఈ రకానికి రెడీ లిస్ట్ లేదు — సరుకులను మీరే చేర్చండి.' : 'No ready list for this kind yet — add items yourself.'),
                    ),
                  for (final cat in askodoxPosList(d['categories']))
                    ExpansionTile(
                      key: ValueKey('askodoxPosCatalogueCategory-${cat['key']}'),
                      tilePadding: EdgeInsets.zero,
                      title: Text(_n(cat['name'], te), style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${askodoxPosList(cat['items']).length} ${te ? 'సరుకులు' : 'items'}'),
                      children: [for (final item in askodoxPosList(cat['items'])) _row(item, te)],
                    ),
                ]),
    );
  }
}

// ---------------------------------------------------------------- item details
/// One item's details (the catalogue's attributes, with a guide on each),
/// online price, and where it is sold. Missing REQUIRED details are marked.
class AskodoxPosItemDetailsScreen extends ConsumerStatefulWidget {
  const AskodoxPosItemDetailsScreen({super.key, required this.businessId, required this.productId});
  final String businessId;
  final String productId;

  @override
  ConsumerState<AskodoxPosItemDetailsScreen> createState() => _AskodoxPosItemDetailsScreenState();
}

class _AskodoxPosItemDetailsScreenState extends ConsumerState<AskodoxPosItemDetailsScreen> {
  AskodoxJson? _product;
  List<AskodoxJson> _specs = const [];
  final _values = <String, Object?>{};
  final _text = <String, TextEditingController>{};
  final _onlinePrice = TextEditingController();
  bool _samePrice = true;
  List<String> _missing = const [];
  Object? _error;
  bool _busy = false;
  String? _templateKey;
  final _prefilled = <String>{};
  final _describe = TextEditingController();
  bool _filling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    _onlinePrice.dispose();
    _describe.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final product = await repo.product(widget.businessId, widget.productId);
      final catalogue = await repo.catalogue(widget.businessId);
      if (!mounted) return;
      setState(() {
        _product = product;
        _specs = askodoxPosList(catalogue['attributes']);
        final saved = askodoxPosMap(product['attributes']);
        _values
          ..clear()
          ..addAll(saved);
        for (final s in _specs) {
          if ('${s['kind']}' != 'choice') {
            _text.putIfAbsent('${s['key']}', TextEditingController.new).text = '${saved[s['key']] ?? ''}';
          }
        }
        final online = product['online_price_paise'];
        _samePrice = online == null;
        _onlinePrice.text = online == null ? '' : askodoxPaise(askodoxPosInt(online), symbol: false);
        _missing = [
          for (final s in _specs)
            if (s['required'] == true && _visible(s) && '${saved[s['key']] ?? ''}'.isEmpty) '${s['key']}',
        ];
        _error = null;
        _templateKey = catalogue['template_key'] == null ? null : '${catalogue['template_key']}';
      });
      // Pre-fill: whatever the item's own name already says (size, weight, type ...) goes into EMPTY boxes.
      await _smartFill('${product['name']} ${product['name_te'] ?? ''}', quiet: true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Fills only EMPTY details from the seller's own words (the item name, or what they typed / said).
  /// Nothing is guessed: the server reads only what the words say; each filled box is marked "check".
  Future<void> _smartFill(String text, {bool quiet = false}) async {
    final key = _templateKey;
    final te = askodoxPosTe(context);
    if (key == null || text.trim().isEmpty) return;
    setState(() => _filling = true);
    try {
      final out = await ref.read(askodoxCatalogueRepositoryProvider).smartFill(key, text);
      if (!mounted || out == null) return;
      var filled = 0;
      setState(() {
        for (final s in _specs) {
          final k = '${s['key']}';
          final value = out.values[k];
          if (value == null || value.isEmpty) continue;
          final isChoice = '${s['kind']}' == 'choice';
          final current = isChoice ? '${_values[k] ?? ''}' : (_text[k]?.text ?? '');
          if (current.trim().isNotEmpty) continue; // never overwrite what the seller wrote
          if (isChoice) {
            _values[k] = value;
          } else {
            _text.putIfAbsent(k, TextEditingController.new).text = value;
          }
          _prefilled.add(k);
          filled++;
        }
      });
      if (!quiet) {
        askodoxPosSnack(
            context,
            filled == 0
                ? (te ? 'కొత్తగా నింపేది ఏదీ దొరకలేదు.' : 'Nothing new to fill from that.')
                : (te ? '$filled వివరాలు నింపాం — సరిచూసి సేవ్ చేయండి.' : 'Filled $filled detail(s) — check and save.'));
      }
    } catch (_) {
      // Pre-fill is a convenience: the seller can always type.
    } finally {
      if (mounted) setState(() => _filling = false);
    }
  }

  bool _visible(AskodoxJson spec) {
    final dep = spec['depends_on'];
    if (dep is! Map) return true;
    final current = '${_values[dep['key']] ?? ''}';
    return (dep['values'] as List? ?? const []).map((e) => '$e').contains(current);
  }

  Future<void> _save() async {
    final te = askodoxPosTe(context);
    final values = <String, Object?>{};
    for (final s in _specs) {
      final key = '${s['key']}';
      if (!_visible(s)) continue;
      final v = '${s['kind']}' == 'choice' ? _values[key] : _text[key]?.text.trim();
      if (v != null && '$v'.isNotEmpty) values[key] = v;
    }
    setState(() => _busy = true);
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final out = await repo.setAttributes(widget.businessId, widget.productId, values);
      final online = _samePrice ? null : askodoxParsePaise(_onlinePrice.text);
      if (!_samePrice && (online == null || online <= 0)) {
        if (mounted) askodoxPosSnack(context, te ? 'ఆన్‌లైన్ ధర రాయండి.' : 'Type the online price.');
      } else if (online != _product?['online_price_paise']) {
        await repo.setOnlinePrice(widget.businessId, widget.productId, online);
      }
      if (!mounted) return;
      setState(() => _missing = [for (final m in askodoxPosList(out['missing'])) '$m']);
      askodoxPosSnack(
          context,
          _missing.isEmpty
              ? (te ? 'సేవ్ అయింది.' : 'Saved.')
              : (te ? 'సేవ్ అయింది — ఇంకా ${_missing.length} తప్పనిసరి వివరాలు కావాలి.' : 'Saved — ${_missing.length} required detail(s) still missing.'));
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(AskodoxJson spec, bool te) {
    final key = '${spec['key']}';
    final label = askodoxPosMap(spec['label']);
    final title = '${(te ? label['te'] : null) ?? label['en'] ?? key}${spec['unit'] == null ? '' : ' (${spec['unit']})'}';
    final guide = askodoxAttributeGuide(spec);
    final missing = _missing.contains(key);
    // No "?" icon: tapping the name explains it; text boxes get help from the guide when the person stops.
    final header = Row(children: [
      Expanded(
        child: InkWell(
          key: ValueKey('askodoxPosAttrGuide-$key'),
          onTap: () => askodoxShowFieldGuide(context,
              title: te ? '${label['te'] ?? label['en'] ?? key}' : '${label['en'] ?? key}',
              text: te ? guide.te : guide.en,
              example: te ? guide.exampleTe : guide.exampleEn),
          child: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted)),
        ),
      ),
      if (_prefilled.contains(key))
        Container(
          key: ValueKey('askodoxPosAttrPrefilled-$key'),
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(6)),
          child: Text(te ? 'ఆటోగా నింపాం — సరిచూడండి' : 'Filled for you — check',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF047857))),
        ),
      if (spec['required'] == true)
        Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
              color: missing ? const Color(0xFFFEE2E2) : const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
          child: Text(missing ? (te ? 'కావాలి' : 'Needed') : (te ? 'తప్పనిసరి' : 'Required'),
              style: TextStyle(fontSize: 10.5, color: missing ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8))),
        ),
    ]);
    if ('${spec['kind']}' == 'choice') {
      final options = [for (final o in (spec['options'] as List? ?? const [])) '$o'];
      final multi = spec['multi'] == true;
      final chosen = '${_values[key] ?? ''}'.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      return Padding(
        key: ValueKey('askodoxPosAttr-$key'),
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          header,
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final o in options)
              FilterChip(
                key: ValueKey('askodoxPosAttrOption-$key-$o'),
                label: Text(o),
                selected: chosen.contains(o),
                onSelected: (on) => setState(() {
                  if (multi) {
                    on ? chosen.add(o) : chosen.remove(o);
                    _values[key] = chosen.join(', ');
                  } else {
                    _values[key] = on ? o : '';
                  }
                }),
              ),
          ]),
        ]),
      );
    }
    return Padding(
      key: ValueKey('askodoxPosAttr-$key'),
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header,
        AskodoxPosField(
          controller: _text.putIfAbsent(key, TextEditingController.new),
          number: '${spec['kind']}' == 'number',
          label: title,
          guideEn: guide.en,
          guideTe: guide.te,
          exampleEn: guide.exampleEn,
          exampleTe: guide.exampleTe,
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final p = _product;
    final groups = <String, List<AskodoxJson>>{};
    for (final s in _specs.where(_visible)) {
      groups.putIfAbsent('${s['group'] ?? 'Details'}', () => []).add(s);
    }
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'సరుకు వివరాలు' : 'Item details')),
      bottomNavigationBar: p == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  key: const Key('askodoxPosItemDetailsSave'),
                  onPressed: _busy ? null : _save,
                  child: Text(te ? 'సేవ్' : 'Save'),
                ),
              ),
            ),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : p == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(key: const Key('askodoxPosItemDetails'), padding: const EdgeInsets.all(14), children: [
                  Text('${p['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('${askodoxPaise(askodoxPosInt(p['price_paise']))} / ${p['unit']}'),
                  if (_missing.isNotEmpty)
                    Container(
                      key: const Key('askodoxPosItemMissing'),
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(10)),
                      child: Text(te
                          ? '${_missing.length} తప్పనిసరి వివరాలు లేవు — "కావాలి" అని ఉన్నవి నింపండి. ఏ వివరం పేరు నొక్కినా ఏం రాయాలో చెబుతుంది.'
                          : '${_missing.length} required detail(s) missing — fill the ones marked "Needed". Tap the name of a detail to see what to write.'),
                    ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        InkWell(
                          key: const Key('askodoxPosOnlinePriceGuide'),
                          onTap: () => askodoxShowFieldGuide(context,
                              title: te ? 'ఆన్‌లైన్ ధర' : 'Online price',
                              text: te
                                  ? 'ASKODOX లో కస్టమర్లు చూసే ధర. షాప్ ధరకే ఉంచొచ్చు, లేదా వేరేది పెట్టొచ్చు (ఉదా: డెలివరీ ఖర్చు కోసం). ఓనర్ / మేనేజర్ మాత్రమే మార్చగలరు.'
                                  : 'The price customers see in ASKODOX. Keep it the same as your shop price, or set a different one (for example to cover delivery). Only owners / managers can change it.'),
                          child: Text(te ? 'ఆన్‌లైన్ ధర' : 'Online price',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  decoration: TextDecoration.underline,
                                  decorationStyle: TextDecorationStyle.dotted)),
                        ),
                        SwitchListTile(
                          key: const Key('askodoxPosSamePrice'),
                          contentPadding: EdgeInsets.zero,
                          value: _samePrice,
                          onChanged: (v) => setState(() => _samePrice = v),
                          title: Text(te ? 'షాప్ ధరే ఆన్‌లైన్‌లో కూడా' : 'Same as the shop price'),
                        ),
                        if (!_samePrice)
                          AskodoxPosField(
                            key: const Key('askodoxPosOnlinePrice'),
                            controller: _onlinePrice,
                            number: true,
                            label: te ? 'ఆన్‌లైన్ ధర (₹)' : 'Online price (₹)',
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AskodoxPosRatesCard(
                    key: ValueKey('rates-${p['updated_at']}-${p['photo_at']}-${askodoxPosList(p['tiers']).length}'),
                    businessId: widget.businessId,
                    product: p,
                    onSaved: _load,
                  ),
                  if (_specs.isNotEmpty && _templateKey != null)
                    Card(
                      key: const Key('askodoxPosDescribeCard'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(te ? 'మాటల్లో చెప్పండి — మేమే నింపుతాం' : 'Say it in your words — we fill the boxes',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          Row(children: [
                            Expanded(
                              child: AskodoxPosField(
                                key: const Key('askodoxPosDescribe'),
                                controller: _describe,
                                label: te ? 'ఈ సరుకు గురించి (టైప్ లేదా మైక్)' : 'About this item (type or mic)',
                                hint: te ? 'ఉదా: 1 కిలో ప్యాకెట్, బాస్మతి, 2 ఏళ్ల పాతది' : 'e.g. 1 kg packet, basmati, aged 2 years',
                              ),
                            ),
                            AskodoxQuestionMic(
                              lang: te ? 'te' : 'en',
                              onText: (text) {
                                _describe.text = text;
                                _smartFill(text);
                              },
                            ),
                          ]),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: const Key('askodoxPosSmartFill'),
                              onPressed: _filling ? null : () => _smartFill(_describe.text),
                              icon: const Icon(Icons.auto_fix_high),
                              label: Text(te ? 'ఖాళీ బాక్సులు నింపు' : 'Fill the empty boxes'),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  if (_specs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(te
                          ? 'మీ వ్యాపార రకం ఎంచుకుంటే (రెడీ లిస్ట్ పేజీలో) ఇక్కడ వివరాలు వస్తాయి.'
                          : 'Choose your kind of business (on the ready-list page) to get details here.'),
                    ),
                  for (final entry in groups.entries) ...[
                    const SizedBox(height: 12),
                    Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 6),
                    for (final spec in entry.value) _field(spec, te),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('askodoxPosItemUnits'),
                    onPressed: () => context.pop('units'),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text(te ? 'యూనిట్లు (బాక్స్ / పీస్)' : 'Units (box / pieces)'),
                  ),
                ]),
    );
  }
}
