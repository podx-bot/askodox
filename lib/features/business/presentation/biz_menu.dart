import '../../../config/theme/askodox_look.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart' show askodoxPaise, askodoxParsePaise;
import '../../pos/presentation/pos_common.dart';
import 'biz_hub.dart';

/// Menu & items group (owner 2026-11-18): sections as buttons -> one section's items (photo, price, sold today,
/// on / off) -> one item as buttons. "AI తో సర్దు" reads the names in parts at once and shows a preview first.

final askodoxBizMenuProvider = FutureProvider.autoDispose.family<List<AskodoxJson>, String>(
    (ref, id) async => askodoxPosList((await ref.watch(askodoxPosRepositoryProvider).deskMenu(id))['items']));

String askodoxSectionOf(AskodoxJson item) => '${item['menu_group'] ?? ''}'.trim();

/// Sections in menu order; items without one come last as ''.
List<String> askodoxMenuSections(List<AskodoxJson> items) {
  final out = <String>[];
  for (final it in items) {
    final s = askodoxSectionOf(it);
    if (s.isNotEmpty && !out.contains(s)) out.add(s);
  }
  if (items.any((it) => askodoxSectionOf(it).isEmpty)) out.add('');
  return out;
}

String _sectionName(String s, bool te) => s.isEmpty ? (te ? 'విభాగం లేనివి' : 'No section') : s;

const _sectionTones = ['orange', 'pink', 'blue', 'purple', 'green', 'teal', 'gray'];

/// The veg / non-veg / egg square printed on Indian menus.
class AskodoxFoodMark extends StatelessWidget {
  const AskodoxFoodMark(this.type, {super.key});
  final String type;

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      'veg' => const Color(0xFF7CD3A2),
      'egg' => const Color(0xFFFB9E6A),
      'nonveg' => const Color(0xFFFEA195),
      _ => null,
    };
    if (color == null) return const SizedBox(width: 0);
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(border: Border.all(color: color, width: 1.5), borderRadius: BorderRadius.circular(3)),
      alignment: Alignment.center,
      child: Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}

/// `/biz/:id/menu` -- the menu group: 4 buttons, one search box across all sections, the sections as buttons.
class AskodoxBizMenuScreen extends ConsumerStatefulWidget {
  const AskodoxBizMenuScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizMenuScreen> createState() => _AskodoxBizMenuScreenState();
}

class _AskodoxBizMenuScreenState extends ConsumerState<AskodoxBizMenuScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final id = widget.businessId;
    final menu = ref.watch(askodoxBizMenuProvider(id));
    final items = menu.valueOrNull ?? const <AskodoxJson>[];
    final q = _query.trim().toLowerCase();
    final found = q.isEmpty
        ? const <AskodoxJson>[]
        : items
            .where((it) => '${it['name']}'.toLowerCase().contains(q) || '${it['item_no'] ?? ''}' == q)
            .take(30)
            .toList();
    final sections = askodoxMenuSections(items);
    return AskodoxBizGroupScreen(
      businessId: id,
      groupId: 'menu',
      extra: [
        const SizedBox(height: 12),
        TextField(
          key: const Key('askodoxBizMenuSearch'),
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: te ? 'ఐటమ్ పేరు / నంబర్ — అన్ని విభాగాల్లో' : 'Item name / number — all sections',
            filled: true,
            fillColor: AskodoxLook.sheet,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
        ),
        if (q.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (found.isEmpty)
            Text(te ? 'ఏమీ దొరకలేదు.' : 'Nothing found.')
          else
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: [
                for (final it in found) AskodoxMenuItemRow(businessId: id, item: it),
              ]),
            ),
        ],
        AskodoxBizSection(te ? 'విభాగాలు — నొక్కితే ఆ మెనూ' : 'Sections — tap to open'),
        if (menu.isLoading && items.isEmpty) const Center(child: CircularProgressIndicator()),
        if (!menu.isLoading && items.isEmpty)
          Text(te ? 'ఇంకా ఐటమ్స్ లేవు. "ఐటమ్ చేర్చు" లేదా "మెనూ ఫోటో" నొక్కండి.' : 'No items yet. Tap "Add an item" or "Menu photo".'),
        AskodoxBizGrid(children: [
          for (final (i, s) in sections.indexed)
            AskodoxBizTile(
              key: Key('askodoxBizSection-$s'),
              icon: s.isEmpty ? Icons.help_outline : Icons.restaurant_menu,
              title: _sectionName(s, te),
              sub: te
                  ? '${items.where((it) => askodoxSectionOf(it) == s).length} ఐటమ్స్'
                  : '${items.where((it) => askodoxSectionOf(it) == s).length} items',
              tone: askodoxBizTones[s.isEmpty ? 'gray' : _sectionTones[i % _sectionTones.length]]!,
              minHeight: 74,
              onTap: () => context.push('/biz/$id/menu/section/${Uri.encodeComponent(s.isEmpty ? '-' : s)}'),
            ),
        ]),
      ],
    );
  }
}

/// One item line: photo square, veg mark, name, number + sold today, price, on / off switch.
class AskodoxMenuItemRow extends ConsumerStatefulWidget {
  const AskodoxMenuItemRow({super.key, required this.businessId, required this.item});
  final String businessId;
  final AskodoxJson item;

  @override
  ConsumerState<AskodoxMenuItemRow> createState() => _AskodoxMenuItemRowState();
}

class _AskodoxMenuItemRowState extends ConsumerState<AskodoxMenuItemRow> {
  bool? _on;
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    setState(() {
      _on = on;
      _busy = true;
    });
    try {
      await ref.read(askodoxPosRepositoryProvider).deskAvailability(widget.businessId, '${widget.item['id']}', on);
    } on AskodoxPosException catch (e) {
      if (mounted) {
        setState(() => _on = !on);
        askodoxPosSnack(context, e.message(askodoxPosTe(context)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final it = widget.item;
    final on = _on ?? it['available'] == true;
    final sold = askodoxPosInt(it['sold_today']);
    return InkWell(
      key: Key('askodoxMenuItem-${it['id']}'),
      onTap: () => context.push('/biz/${widget.businessId}/menu/item/${it['id']}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF1F2432)))),
        child: Row(children: [
          AskodoxProductThumb(businessId: widget.businessId, productId: '${it['id']}', hasPhoto: it['has_photo'] == true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                AskodoxFoodMark('${it['food_type'] ?? ''}'),
                Flexible(
                  child: Text('${it['name']}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: on ? null : const Color(0xFF9299A4),
                          decoration: on ? null : TextDecoration.lineThrough)),
                ),
              ]),
              Text(
                  [
                    if (it['item_no'] != null) '#${it['item_no']}',
                    te ? 'ఈ రోజు $sold అమ్మాం' : '$sold sold today',
                    if (!on) te ? 'ఈ రోజు లేదు' : 'off today',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFFB9C5D5))),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(askodoxPaise(askodoxPosInt(it['price_paise'])), style: const TextStyle(fontWeight: FontWeight.w900)),
            Switch(
              key: Key('askodoxMenuItemOn-${it['id']}'),
              value: on,
              onChanged: _busy ? null : _toggle,
            ),
          ]),
        ]),
      ),
    );
  }
}

/// The item's photo (fetched only when it has one), else a plain square.
class AskodoxProductThumb extends ConsumerStatefulWidget {
  const AskodoxProductThumb(
      {super.key, required this.businessId, required this.productId, required this.hasPhoto, this.size = 52});
  final String businessId;
  final String productId;
  final bool hasPhoto;
  final double size;

  @override
  ConsumerState<AskodoxProductThumb> createState() => _AskodoxProductThumbState();
}

final _thumbCache = <String, Uint8List>{};

class _AskodoxProductThumbState extends ConsumerState<AskodoxProductThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _thumbCache[widget.productId];
    if (_bytes == null && widget.hasPhoto) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).photo(widget.businessId, widget.productId);
      final bytes = base64Decode('${out['image_base64'] ?? ''}');
      if (bytes.isEmpty) return;
      _thumbCache[widget.productId] = bytes;
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: widget.size,
          height: widget.size,
          color: const Color(0xFF3F280D),
          child: _bytes == null
              ? const Icon(Icons.image_outlined, color: Color(0xFFFB9E6A))
              : Image.memory(_bytes!, fit: BoxFit.cover),
        ),
      );
}

/// `/biz/:id/menu/section/:name` -- one section's items, filter chips, add to this section.
class AskodoxBizSectionScreen extends ConsumerStatefulWidget {
  const AskodoxBizSectionScreen({super.key, required this.businessId, required this.section});
  final String businessId;

  /// '-' = items without a section.
  final String section;

  @override
  ConsumerState<AskodoxBizSectionScreen> createState() => _AskodoxBizSectionScreenState();
}

class _AskodoxBizSectionScreenState extends ConsumerState<AskodoxBizSectionScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final id = widget.businessId;
    final section = widget.section == '-' ? '' : widget.section;
    final menu = ref.watch(askodoxBizMenuProvider(id));
    final all = (menu.valueOrNull ?? const <AskodoxJson>[]).where((it) => askodoxSectionOf(it) == section).toList();
    final shown = all.where((it) => switch (_filter) {
          'veg' => it['food_type'] == 'veg',
          'nonveg' => it['food_type'] == 'nonveg' || it['food_type'] == 'egg',
          'off' => it['available'] != true,
          'top' => askodoxPosInt(it['sold_today']) > 0,
          _ => true,
        }).toList();
    if (_filter == 'top') shown.sort((a, b) => askodoxPosInt(b['sold_today']).compareTo(askodoxPosInt(a['sold_today'])));
    final group = te ? 'మెనూ & ఐటమ్స్' : 'Menu & items';
    return AskodoxBizScaffold(
      key: const Key('askodoxBizSectionPage'),
      businessId: id,
      tone: askodoxBizTones['menu']!,
      icon: Icons.restaurant_menu,
      title: '${_sectionName(section, te)} (${all.length})',
      trail: [group, _sectionName(section, te)],
      page: 'menu',
      onRefresh: () async => ref.invalidate(askodoxBizMenuProvider(id)),
      askHint: te ? '"ఎగ్ బిర్యానీ ధర 170" "వెజ్ బిర్యానీ ఈ రోజు లేదు"' : '"Egg biryani price 170"',
      children: [
        AskodoxBizGrid(children: [
          AskodoxBizTile(
            icon: Icons.add_circle_outline,
            title: te ? 'ఈ విభాగంలో చేర్చు' : 'Add to this section',
            sub: '',
            tone: askodoxBizTones['orange']!,
            minHeight: 60,
            onTap: () => context.push('/desk/$id/menu'),
          ),
          AskodoxBizTile(
            icon: Icons.auto_awesome,
            title: te ? 'AI తో సర్దు' : 'Sort with AI',
            sub: '',
            tone: askodoxBizTones['purple']!,
            minHeight: 60,
            onTap: () => context.push('/biz/$id/menu/sort'),
          ),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (key, en, tel) in [
              ('all', 'All ${all.length}', 'అన్నీ ${all.length}'),
              ('veg', 'Veg', 'వెజ్'),
              ('nonveg', 'Non-veg', 'నాన్-వెజ్'),
              ('off', 'Off today', 'లేనివి'),
              ('top', 'Most sold', 'ఎక్కువ అమ్మినవి'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  key: Key('askodoxSectionFilter-$key'),
                  label: Text(te ? tel : en),
                  selected: _filter == key,
                  onSelected: (_) => setState(() => _filter = key),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        if (menu.isLoading && all.isEmpty) const Center(child: CircularProgressIndicator()),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: [for (final it in shown) AskodoxMenuItemRow(businessId: id, item: it)]),
        ),
      ],
    );
  }
}

/// `/biz/:id/menu/item/:pid` -- one item as buttons: price, on / off, veg mark, section, GST & details.
class AskodoxBizItemScreen extends ConsumerStatefulWidget {
  const AskodoxBizItemScreen({super.key, required this.businessId, required this.productId});
  final String businessId;
  final String productId;

  @override
  ConsumerState<AskodoxBizItemScreen> createState() => _AskodoxBizItemScreenState();
}

class _AskodoxBizItemScreenState extends ConsumerState<AskodoxBizItemScreen> {
  bool _busy = false;

  Future<void> _change(AskodoxJson body) async {
    final te = askodoxPosTe(context);
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).updateProduct(widget.businessId, widget.productId, body);
      ref.invalidate(askodoxBizMenuProvider(widget.businessId));
      if (mounted) askodoxPosSnack(context, te ? 'సేవ్ అయింది ✓' : 'Saved ✓');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _price(AskodoxJson it) async {
    final te = askodoxPosTe(context);
    final c = TextEditingController(text: (askodoxPosInt(it['price_paise']) / 100).toStringAsFixed(0));
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'కొత్త ధర' : 'New price'),
        content: TextField(
          key: const Key('askodoxItemPriceBox'),
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '₹ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    c.dispose();
    final paise = askodoxParsePaise(value ?? '');
    if (paise != null && paise > 0) await _change({'price_paise': paise});
  }

  Future<void> _food() async {
    final te = askodoxPosTe(context);
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, en, tel) in [
            ('veg', 'Veg', 'వెజ్'),
            ('nonveg', 'Non-veg', 'నాన్-వెజ్'),
            ('egg', 'Egg', 'ఎగ్'),
            ('', 'Not food / no mark', 'గుర్తు లేదు'),
          ])
            ListTile(leading: AskodoxFoodMark(v), title: Text(te ? tel : en), onTap: () => Navigator.pop(ctx, v)),
        ]),
      ),
    );
    if (pick != null) await _change({'food_type': pick});
  }

  Future<void> _section(AskodoxJson it, List<String> sections) async {
    final te = askodoxPosTe(context);
    final c = TextEditingController(text: askodoxSectionOf(it));
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'ఏ విభాగం?' : 'Which section?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in sections.where((s) => s.isNotEmpty))
              ActionChip(label: Text(s), onPressed: () => Navigator.pop(ctx, s)),
          ]),
          const SizedBox(height: 8),
          TextField(controller: c, decoration: InputDecoration(labelText: te ? 'కొత్త విభాగం' : 'New section')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    c.dispose();
    if (value != null) await _change({'menu_group': value});
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final id = widget.businessId;
    final menu = ref.watch(askodoxBizMenuProvider(id));
    final items = menu.valueOrNull ?? const <AskodoxJson>[];
    final it = items.where((m) => '${m['id']}' == widget.productId).firstOrNull;
    final section = it == null ? '' : askodoxSectionOf(it);
    return AskodoxBizScaffold(
      key: const Key('askodoxBizItemPage'),
      businessId: id,
      tone: askodoxBizTones['menu']!,
      icon: Icons.restaurant_menu,
      title: '${it?['name'] ?? ''}',
      trail: [te ? 'మెనూ & ఐటమ్స్' : 'Menu & items', _sectionName(section, te), if (it?['item_no'] != null) '#${it!['item_no']}'],
      page: 'menu',
      askHint: te ? '"హాఫ్ ప్లేట్ 130 పెట్టు" "ఫోటో మార్చు"' : '"Make it 130"',
      children: it == null
          ? [if (menu.isLoading) const Center(child: CircularProgressIndicator()) else Text(te ? 'ఐటమ్ దొరకలేదు.' : 'Item not found.')]
          : [
              Center(
                child: AskodoxProductThumb(
                    businessId: id, productId: widget.productId, hasPhoto: it['has_photo'] == true, size: 140),
              ),
              const SizedBox(height: 10),
              AskodoxBizStrip(cells: [
                (te ? 'ధర' : 'Price', askodoxPaise(askodoxPosInt(it['price_paise'])), const Color(0xFFF7F9FC)),
                (te ? 'ఈ రోజు' : 'Today', te ? '${askodoxPosInt(it['sold_today'])} అమ్మాం' : '${askodoxPosInt(it['sold_today'])} sold',
                    const Color(0xFF7CD3A2)),
                (te ? 'స్థితి' : 'Status', it['available'] == true ? (te ? 'ఉంది' : 'On') : (te ? 'లేదు' : 'Off'),
                    it['available'] == true ? const Color(0xFF7CD3A2) : const Color(0xFFFEA195)),
              ]),
              AskodoxBizSection(te ? 'ఈ ఐటమ్ — బటన్లుగా' : 'This item'),
              AbsorbPointer(
                absorbing: _busy,
                child: AskodoxBizGrid(children: [
                  AskodoxBizTile(
                    key: const Key('askodoxItemPrice'),
                    icon: Icons.sell_outlined,
                    title: te ? 'ధర' : 'Price',
                    sub: askodoxPaise(askodoxPosInt(it['price_paise'])),
                    tone: askodoxBizTones['orange']!,
                    minHeight: 78,
                    onTap: () => _price(it),
                  ),
                  AskodoxBizTile(
                    key: const Key('askodoxItemToday'),
                    icon: Icons.toggle_on_outlined,
                    title: te ? 'ఈ రోజు ఉందా' : 'Available today',
                    sub: it['available'] == true ? (te ? 'ఆన్ — నొక్కితే ఆఫ్' : 'On — tap to turn off') : (te ? 'ఆఫ్ — నొక్కితే ఆన్' : 'Off — tap to turn on'),
                    tone: askodoxBizTones['green']!,
                    minHeight: 78,
                    onTap: () async {
                      await ref.read(askodoxPosRepositoryProvider).deskAvailability(id, widget.productId, it['available'] != true);
                      ref.invalidate(askodoxBizMenuProvider(id));
                    },
                  ),
                  AskodoxBizTile(
                    key: const Key('askodoxItemFood'),
                    icon: Icons.eco_outlined,
                    title: te ? 'వెజ్ / నాన్-వెజ్' : 'Veg / non-veg',
                    sub: switch ('${it['food_type'] ?? ''}') {
                      'veg' => te ? 'వెజ్' : 'Veg',
                      'nonveg' => te ? 'నాన్-వెజ్' : 'Non-veg',
                      'egg' => te ? 'ఎగ్' : 'Egg',
                      _ => te ? 'పెట్టలేదు' : 'Not set',
                    },
                    tone: askodoxBizTones['pink']!,
                    minHeight: 78,
                    onTap: _food,
                  ),
                  AskodoxBizTile(
                    key: const Key('askodoxItemSection'),
                    icon: Icons.folder_open_outlined,
                    title: te ? 'విభాగం' : 'Section',
                    sub: _sectionName(section, te),
                    tone: askodoxBizTones['blue']!,
                    minHeight: 78,
                    onTap: () => _section(it, askodoxMenuSections(items)),
                  ),
                  AskodoxBizTile(
                    key: const Key('askodoxItemDetails'),
                    icon: Icons.description_outlined,
                    title: te ? 'GST, ఫోటో & వివరాలు' : 'GST, photo & details',
                    sub: te ? 'HSN, స్టాక్, ఫోటో' : 'HSN, stock, photo',
                    tone: askodoxBizTones['gray']!,
                    minHeight: 78,
                    onTap: () => context.push('/pos/$id/item/${widget.productId}'),
                  ),
                ]),
              ),
            ],
    );
  }
}

/// `/biz/:id/menu/sort` -- AI reads the item names in parts AT THE SAME TIME, shows the sections with counts, the owner
/// opens any section to move an item, then saves. Nothing changes before "Save". The printed menu number ("68) ...")
/// is taken out of the name and becomes the item number.
class AskodoxBizMenuSortScreen extends ConsumerStatefulWidget {
  const AskodoxBizMenuSortScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizMenuSortScreen> createState() => _AskodoxBizMenuSortScreenState();
}

class _AskodoxBizMenuSortScreenState extends ConsumerState<AskodoxBizMenuSortScreen> {
  List<Map<String, Object?>>? _rows;
  List<String> _groups = const [];
  Object? _error;
  bool _saving = false;
  int _seconds = 0;
  Timer? _tick;
  String? _open;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _read({bool fresh = false}) async {
    setState(() {
      _error = null;
      _rows = null;
      _seconds = 0;
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      // Owner 2026-11-23: no "stay on this page". A reading already done (or running) is picked up; otherwise one is
      // started in the background and the page checks every 3 s -- leaving is fine, a notification says when ready.
      var out = fresh ? const <String, Object?>{} : await repo.menuSortState(widget.businessId);
      if (!mounted) return;
      if (fresh || out['status'] == 'none' || out['status'] == 'failed') {
        out = await repo.menuSortStart(widget.businessId, lang: askodoxPosTe(context) ? 'te' : 'en');
      }
      _seconds = askodoxPosInt(out['seconds']);
      while (mounted && out['status'] == 'running') {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        out = await repo.menuSortState(widget.businessId);
      }
      if (!mounted) return;
      if (out['status'] != 'done') {
        setState(() => _error = AskodoxPosException('failed',
            askodoxPosTe(context) ? 'మెనూ చదవలేకపోయా. ఒక నిమిషం తర్వాత మళ్ళీ ప్రయత్నించండి.' : 'Could not read the menu just now. Try again in a minute.'));
        return;
      }
      setState(() {
        _rows = [for (final r in askodoxPosList(out['items'])) Map<String, Object?>.of(r)];
        _groups = [for (final g in (out['groups'] as List? ?? const [])) '$g'];
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _tick?.cancel();
    }
  }

  Future<void> _save() async {
    final te = askodoxPosTe(context);
    final rows = _rows;
    if (rows == null) return;
    setState(() => _saving = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).menuSortApply(widget.businessId, [
        for (final r in rows)
          {
            'id': r['id'],
            'menu_group': r['menu_group'] ?? '',
            'food_type': r['food_type'] ?? '',
            if ('${r['name'] ?? ''}'.isNotEmpty) 'name': r['name'],
            if (r['item_no'] != null) 'item_no': r['item_no'],
          },
      ]);
      ref.invalidate(askodoxBizMenuProvider(widget.businessId));
      ref.invalidate(askodoxBizHubProvider(widget.businessId));
      if (!mounted) return;
      askodoxPosSnack(context, te ? '${out['saved']} ఐటమ్స్ సర్దాం ✓' : 'Sorted ${out['saved']} items ✓');
      context.pop();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final rows = _rows;
    final groups = [..._groups, if (rows != null && rows.any((r) => '${r['menu_group'] ?? ''}'.isEmpty)) ''];
    return AskodoxBizScaffold(
      key: const Key('askodoxBizMenuSort'),
      businessId: widget.businessId,
      tone: askodoxBizTones['menu']!,
      icon: Icons.auto_awesome,
      title: te ? 'AI తో సర్దు' : 'Sort with AI',
      trail: [te ? 'మెనూ & ఐటమ్స్' : 'Menu & items', te ? 'AI తో సర్దు' : 'Sort with AI'],
      page: 'menu',
      bottom: rows == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                        onPressed: _saving ? null : () => context.pop(), child: Text(te ? 'వద్దు' : 'Cancel')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('askodoxMenuSortSave'),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFCDBAFF), minimumSize: const Size.fromHeight(48)),
                      onPressed: _saving ? null : _save,
                      child: Text(te ? 'సేవ్ చేయి (${rows.length})' : 'Save (${rows.length})'),
                    ),
                  ),
                ]),
              ),
            ),
      children: [
        if (_error != null) ...[
          AskodoxPosError(error: _error!, onRetry: () => _read(fresh: true)),
        ] else if (rows == null) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(te ? 'AI మీ మెనూ చదువుతోంది — భాగాలుగా, ఒకేసారి' : 'AI is reading your menu — in parts, at the same time',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                    te
                        ? 'మీరు వేరే పని చేసుకోవచ్చు — అయ్యాక notification వస్తుంది. ($_seconds సె.)'
                        : 'You can do other work — a notification comes when it is ready. (${_seconds}s)',
                    key: const Key('askodoxMenuSortWaiting'), style: const TextStyle(color: Color(0xFFB9C5D5))),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: (_seconds / 90).clamp(0.05, 0.95), minHeight: 8, borderRadius: BorderRadius.circular(4)),
              ]),
            ),
          ),
        ] else ...[
          Text(
              te
                  ? '${rows.where((r) => r['changed'] == true).length} ఐటమ్స్ మారుతాయి. విభాగం నొక్కితే లోపలి ఐటమ్స్ మార్చవచ్చు.'
                  : '${rows.where((r) => r['changed'] == true).length} items change. Tap a section to move items.',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final g in groups)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(children: [
                ListTile(
                  key: Key('askodoxSortGroup-$g'),
                  title: Text(_sectionName(g, te), style: const TextStyle(fontWeight: FontWeight.w900)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(te
                        ? '${rows.where((r) => '${r['menu_group'] ?? ''}' == g).length} ఐటమ్స్'
                        : '${rows.where((r) => '${r['menu_group'] ?? ''}' == g).length} items'),
                    Icon(_open == g ? Icons.expand_less : Icons.expand_more),
                  ]),
                  onTap: () => setState(() => _open = _open == g ? null : g),
                ),
                if (_open == g)
                  for (final r in rows.where((r) => '${r['menu_group'] ?? ''}' == g))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                      child: Row(children: [
                        AskodoxFoodMark('${r['food_type'] ?? ''}'),
                        Expanded(
                          child: Text('${r['item_no'] != null ? '#${r['item_no']} ' : ''}${r['name']}',
                              style: TextStyle(fontWeight: r['changed'] == true ? FontWeight.w800 : FontWeight.w500)),
                        ),
                        DropdownButton<String>(
                          value: '${r['menu_group'] ?? ''}',
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final x in {...groups, '${r['menu_group'] ?? ''}'})
                              DropdownMenuItem(value: x, child: Text(_sectionName(x, te), overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() {
                            r['menu_group'] = v ?? '';
                            r['changed'] = true;
                          }),
                        ),
                      ]),
                    ),
              ]),
            ),
        ],
      ],
    );
  }
}
