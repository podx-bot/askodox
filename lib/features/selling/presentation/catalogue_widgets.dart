import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/media_picker.dart';
import '../data/catalogue_repository.dart';

const _labels = <String, Map<String, String>>{
  'en': {
    'categories': 'categories', 'items': 'items', 'select_all': 'Select all', 'set_prices': 'Set prices & publish',
    'price': 'Your price ₹', 'size': 'Size', 'in_stock': 'In stock', 'photo': 'Photo', 'photo_added': 'Photo added',
    'shop_name': 'Shop name', 'shop_address': 'Shop address', 'review': 'Review', 'publish': 'Publish',
    'back': 'Back', 'include': 'Include', 'details': 'Details', 'done': 'Done', 'draft': 'Draft: needs price or * detail', 'no_price_note': 'Items without a price are saved as drafts, not published.',
    'need_shop': 'Add your shop name and address.', 'photo_too_large': 'Photo too large -- take it again closer.',
    'will_publish': 'will be published', 'will_draft': 'saved as drafts (price or * detail missing)', 'selected': 'selected',
    'pick_categories': 'Pick the categories you sell, or say "all".',
  },
  'te': {
    'categories': 'విభాగాలు', 'items': 'వస్తువులు', 'select_all': 'అన్నీ ఎంచుకోండి', 'set_prices': 'ధరలు పెట్టి ప్రచురించండి',
    'price': 'మీ ధర ₹', 'size': 'సైజు', 'in_stock': 'స్టాక్ ఉంది', 'photo': 'ఫోటో', 'photo_added': 'ఫోటో జత చేశారు',
    'shop_name': 'షాప్ పేరు', 'shop_address': 'షాప్ చిరునామా', 'review': 'సమీక్షించండి', 'publish': 'ప్రచురించండి',
    'back': 'వెనక్కి', 'include': 'చేర్చండి', 'details': 'వివరాలు', 'done': 'అయింది', 'draft': 'డ్రాఫ్ట్: ధర లేదా * వివరం కావాలి', 'no_price_note': 'ధర లేని వస్తువులు డ్రాఫ్ట్‌లుగా సేవ్ అవుతాయి, ప్రచురించబడవు.',
    'need_shop': 'మీ షాప్ పేరు, చిరునామా ఇవ్వండి.', 'photo_too_large': 'ఫోటో చాలా పెద్దది -- మళ్లీ తీయండి.',
    'will_publish': 'ప్రచురించబడతాయి', 'will_draft': 'డ్రాఫ్ట్‌లుగా సేవ్ (ధర ఇంకా లేదు)', 'selected': 'ఎంచుకున్నారు',
    'pick_categories': 'మీరు అమ్మే విభాగాలు ఎంచుకోండి, లేదా "అన్నీ" అని చెప్పండి.',
  },
  'hi': {
    'categories': 'श्रेणियाँ', 'items': 'आइटम', 'select_all': 'सब चुनें', 'set_prices': 'दाम डालें और प्रकाशित करें',
    'price': 'आपका दाम ₹', 'size': 'साइज़', 'in_stock': 'स्टॉक में', 'photo': 'फ़ोटो', 'photo_added': 'फ़ोटो जोड़ी गई',
    'shop_name': 'दुकान का नाम', 'shop_address': 'दुकान का पता', 'review': 'जाँचें', 'publish': 'प्रकाशित करें',
    'back': 'वापस', 'include': 'शामिल करें', 'details': 'विवरण', 'done': 'हो गया', 'draft': 'ड्राफ़्ट: दाम या * विवरण चाहिए', 'no_price_note': 'बिना दाम वाले आइटम ड्राफ़्ट में सेव होंगे, प्रकाशित नहीं।',
    'need_shop': 'दुकान का नाम और पता डालें।', 'photo_too_large': 'फ़ोटो बहुत बड़ी है -- दोबारा लें।',
    'will_publish': 'प्रकाशित होंगे', 'will_draft': 'ड्राफ़्ट में (अभी दाम नहीं)', 'selected': 'चुने गए',
    'pick_categories': 'जो श्रेणियाँ आप बेचते हैं चुनें, या "सब" कहें।',
  },
};

String askodoxCatalogueLabel(String key, String lang) => _labels[lang]?[key] ?? _labels['en']![key] ?? key;

/// The ready-made catalogue inside the conversation: categories to pick
/// (or "all"), then the editor for the seller's own prices.
class AskodoxCatalogueCard extends StatelessWidget {
  const AskodoxCatalogueCard({
    super.key,
    required this.template,
    required this.selected,
    required this.lang,
    required this.onToggle,
    required this.onSelectAll,
    required this.onOpenEditor,
  });

  final AskodoxCatalogueTemplate template;
  final Set<String> selected;
  final String lang;
  final ValueChanged<String> onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onOpenEditor;

  @override
  Widget build(BuildContext context) {
    String l(String k) => askodoxCatalogueLabel(k, lang);
    final chosenItems = template.categories.where((c) => selected.contains(c.key)).fold(0, (s, c) => s + c.items.length);
    return Card(
      key: ValueKey('askodoxCatalogueCard-${template.key}'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.storefront_rounded, color: Color(0xFF6C4DFF)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(template.name(lang), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ]),
          Text('${template.categories.length} ${l('categories')} · ${template.itemCount} ${l('items')}',
              style: const TextStyle(color: Color(0xFF64748B))),
          const SizedBox(height: 6),
          Text(l('pick_categories'), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ActionChip(
              key: const Key('askodoxCatalogueSelectAll'),
              avatar: const Icon(Icons.done_all_rounded, size: 16),
              label: Text(l('select_all')),
              onPressed: onSelectAll,
            ),
            for (final c in template.categories)
              FilterChip(
                key: ValueKey('askodoxCatalogueCategory-${c.key}'),
                label: Text('${c.name(lang)} (${c.items.length})'),
                selected: selected.contains(c.key),
                onSelected: (_) => onToggle(c.key),
              ),
          ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('askodoxCatalogueOpenEditor'),
            onPressed: selected.isEmpty ? null : onOpenEditor,
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(selected.isEmpty ? l('set_prices') : '${l('set_prices')} ($chosenItems)'),
          ),
        ]),
      ),
    );
  }
}

/// Seller's review: include/exclude, size, own price, stock, photo, shop
/// details -> review -> publish. Pops the publish result.
class AskodoxCatalogueEditorSheet extends ConsumerStatefulWidget {
  const AskodoxCatalogueEditorSheet({
    super.key,
    required this.template,
    required this.categoryKeys,
    required this.lang,
    this.shopName,
    this.shopAddress,
  });

  final AskodoxCatalogueTemplate template;
  final Set<String> categoryKeys;
  final String lang;
  final String? shopName;
  final String? shopAddress;

  @override
  ConsumerState<AskodoxCatalogueEditorSheet> createState() => _AskodoxCatalogueEditorSheetState();
}

class _AskodoxCatalogueEditorSheetState extends ConsumerState<AskodoxCatalogueEditorSheet> {
  late final List<AskodoxCatalogueEntry> _entries = [
    for (final c in widget.template.categories)
      if (widget.categoryKeys.contains(c.key))
        for (final i in c.items) AskodoxCatalogueEntry(item: i, size: i.sizes.isEmpty ? '' : i.sizes.first),
  ];
  late final Set<String> _included = {for (final e in _entries) e.item.key};
  late final _shop = TextEditingController(text: widget.shopName ?? '');
  late final _address = TextEditingController(text: widget.shopAddress ?? '');
  bool _reviewing = false;
  bool _busy = false;
  String? _message;

  String _l(String k) => askodoxCatalogueLabel(k, widget.lang);

  List<AskodoxCatalogueEntry> get _chosen => [for (final e in _entries) if (_included.contains(e.item.key)) e];

  Future<void> _photo(AskodoxCatalogueEntry entry) async {
    final picked = await ref.read(askodoxMediaPickerProvider).pick('camera');
    if (picked.isEmpty || !mounted) return;
    final bytes = picked.first.bytes;
    if (bytes.length > 600 * 1024) {
      setState(() => _message = _l('photo_too_large'));
      return;
    }
    setState(() {
      entry.photoBase64 = base64Encode(bytes);
      _message = null;
    });
  }

  /// The item's category details (from the template): choices as chips,
  /// free text as fields; required ones are marked *. Nothing pre-filled.
  Future<void> _details(AskodoxCatalogueEntry e) async {
    final specs = widget.template.attributes;
    final controllers = {
      for (final a in specs)
        if (a.options.isEmpty) a.key: TextEditingController(text: e.attributes[a.key] ?? ''),
    };
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${e.item.name(widget.lang)} · ${e.size}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 8),
              for (final a in specs) ...[
                Text('${a.label(widget.lang)}${a.required ? ' *' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                if (a.options.isNotEmpty)
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final o in a.options)
                      ChoiceChip(
                        key: ValueKey('askodoxCatalogueAttr-${a.key}-$o'),
                        label: Text(o),
                        selected: e.attributes[a.key] == o,
                        onSelected: (on) => setSheet(() => on ? e.attributes[a.key] = o : e.attributes.remove(a.key)),
                      ),
                  ])
                else
                  TextField(
                    key: ValueKey('askodoxCatalogueAttr-${a.key}'),
                    controller: controllers[a.key],
                    maxLength: 80,
                    decoration: const InputDecoration(isDense: true, counterText: ''),
                    onChanged: (v) => e.attributes[a.key] = v,
                  ),
                const SizedBox(height: 10),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('askodoxCatalogueDetailsDone'),
                  onPressed: () => Navigator.pop(sheet),
                  child: Text(_l('done')),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _publish() async {
    if (_shop.text.trim().isEmpty || _address.text.trim().isEmpty) {
      setState(() => _message = _l('need_shop'));
      return;
    }
    setState(() => _busy = true);
    final result = await ref.read(askodoxCatalogueRepositoryProvider).publish(widget.template.key, _chosen,
        businessName: _shop.text, businessAddress: _address.text, language: widget.lang);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error == 'shop_details') {
      setState(() => _message = _l('need_shop'));
      return;
    }
    Navigator.pop(context, result);
  }

  Widget _row(AskodoxCatalogueEntry e) {
    final included = _included.contains(e.item.key);
    return Padding(
      key: ValueKey('askodoxCatalogueItem-${e.item.key}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Checkbox(
          value: included,
          onChanged: (v) => setState(() => v == true ? _included.add(e.item.key) : _included.remove(e.item.key)),
        ),
        Expanded(
          flex: 4,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.item.name(widget.lang), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (e.item.sizes.length > 1)
              DropdownButton<String>(
                value: e.size,
                isDense: true,
                items: [for (final s in e.item.sizes) DropdownMenuItem(value: s, child: Text(s))],
                onChanged: included ? (v) => setState(() => e.size = v ?? e.size) : null,
              )
            else
              Text(e.size, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ]),
        ),
        SizedBox(
          width: 86,
          child: TextFormField(
            key: ValueKey('askodoxCataloguePrice-${e.item.key}'),
            enabled: included,
            initialValue: e.price == null ? '' : e.price!.toStringAsFixed(0),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(isDense: true, labelText: _l('price')),
            onChanged: (v) => e.price = double.tryParse(v),
          ),
        ),
        if (widget.template.attributes.isNotEmpty)
          IconButton(
            key: ValueKey('askodoxCatalogueDetails-${e.item.key}'),
            tooltip: _l('details'),
            onPressed: included ? () => _details(e) : null,
            icon: Badge(
              isLabelVisible: e.attributes.values.any((v) => v.trim().isNotEmpty),
              label: Text('${e.attributes.values.where((v) => v.trim().isNotEmpty).length}'),
              child: Icon(Icons.tune_rounded,
                  color: included && e.price != null && !e.readyFor(widget.template.attributes)
                      ? const Color(0xFFB26A00)
                      : null),
            ),
          ),
        IconButton(
          tooltip: e.photoBase64 == null ? _l('photo') : _l('photo_added'),
          icon: Icon(e.photoBase64 == null ? Icons.add_a_photo_outlined : Icons.check_circle_rounded,
              color: e.photoBase64 == null ? null : const Color(0xFF0F7B3F)),
          onPressed: included ? () => _photo(e) : null,
        ),
        Switch(
          value: e.inStock,
          onChanged: included ? (v) => setState(() => e.inStock = v) : null,
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    // Published only with a price AND every required detail; the rest stay drafts.
    final priced = chosen.where((e) => e.readyFor(widget.template.attributes)).length;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .82,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.template.name(widget.lang), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            Text('${chosen.length} ${_l('selected')} · ${_l('in_stock')} ⇆',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
            const SizedBox(height: 6),
            Expanded(
              child: _reviewing
                  ? ListView(key: const Key('askodoxCatalogueReview'), children: [
                      Text('$priced ${_l('will_publish')}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${chosen.length - priced} ${_l('will_draft')}'),
                      const Divider(),
                      for (final e in chosen)
                        ListTile(
                          dense: true,
                          title: Text('${e.item.name(widget.lang)} · ${e.size}'),
                          trailing: Text(e.price == null ? '—' : '₹${e.price!.toStringAsFixed(0)}'),
                          subtitle: Text([
                            e.inStock ? _l('in_stock') : '—',
                            for (final a in widget.template.attributes)
                              if ((e.attributes[a.key] ?? '').trim().isNotEmpty)
                                '${a.label(widget.lang)}: ${e.attributes[a.key]}',
                            if (!e.readyFor(widget.template.attributes)) _l('draft'),
                          ].join(' · ')),
                        ),
                      const Divider(),
                      Text('${_shop.text} · ${_address.text}'),
                    ])
                  : ListView(children: [
                      for (final e in _entries) _row(e),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('askodoxCatalogueShopName'),
                        controller: _shop,
                        decoration: InputDecoration(labelText: _l('shop_name')),
                      ),
                      TextField(
                        key: const Key('askodoxCatalogueShopAddress'),
                        controller: _address,
                        decoration: InputDecoration(labelText: _l('shop_address')),
                      ),
                      const SizedBox(height: 6),
                      Text(_l('no_price_note'), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ]),
            ),
            if (_message != null)
              Text(_message!, key: const Key('askodoxCatalogueMessage'), style: const TextStyle(color: Color(0xFFB42318))),
            Row(children: [
              if (_reviewing) TextButton(onPressed: () => setState(() => _reviewing = false), child: Text(_l('back'))),
              const Spacer(),
              FilledButton(
                key: Key(_reviewing ? 'askodoxCataloguePublish' : 'askodoxCatalogueReviewButton'),
                onPressed: _busy || chosen.isEmpty
                    ? null
                    : _reviewing
                        ? _publish
                        : () {
                            if (_shop.text.trim().isEmpty || _address.text.trim().isEmpty) {
                              setState(() => _message = _l('need_shop'));
                              return;
                            }
                            setState(() {
                              _message = null;
                              _reviewing = true;
                            });
                          },
                child: Text(_reviewing ? _l('publish') : _l('review')),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
