import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme/askodox_look.dart';
import '../../shared/widgets/estimate_note.dart';
import '../native_video/video_commerce.dart' show askodoxShareTextProvider;
import 'kitchen_logic.dart';
import 'kitchen_store.dart';

/// Kitchen stock (design "kitchen stock"): the person's own home items with what is left, a "finished" button, a
/// buy list of what runs low, and the month's grocery spend the person noted. Phone only; nothing is preset.
class AskodoxKitchenScreen extends ConsumerStatefulWidget {
  const AskodoxKitchenScreen({super.key});

  @override
  ConsumerState<AskodoxKitchenScreen> createState() => _AskodoxKitchenScreenState();
}

class _AskodoxKitchenScreenState extends ConsumerState<AskodoxKitchenScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _low = TextEditingController();
  final _spend = TextEditingController();
  String _unit = 'kg';
  String _editId = '';
  bool _adding = false;

  @override
  void dispose() {
    for (final c in [_name, _amount, _low, _spend]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _te => Localizations.localeOf(context).languageCode == 'te';

  void _open(AskodoxKitchenItem? i) {
    _name.text = i?.name ?? '';
    _amount.text = i == null ? '' : askodoxKitchenShown(i.milli);
    _low.text = i == null || i.lowMilli == 0 ? '' : askodoxKitchenShown(i.lowMilli);
    setState(() {
      _unit = i?.unit ?? 'kg';
      _editId = i?.id ?? '';
      _adding = true;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final milli = _amount.text.trim().isEmpty ? 0 : askodoxKitchenParseAmount(_amount.text);
    final low = _low.text.trim().isEmpty ? 0 : askodoxKitchenParseAmount(_low.text);
    if (name.isEmpty || milli == null || low == null) return;
    await ref.read(askodoxKitchenProvider.notifier).saveItem(AskodoxKitchenItem(
        id: _editId.isEmpty ? 'k_${ref.read(askodoxKitchenClockProvider)().microsecondsSinceEpoch}' : _editId,
        name: name, unit: _unit, milli: milli, lowMilli: low));
    if (mounted) setState(() => _adding = false);
  }

  Future<void> _addSpend() async {
    final paise = askodoxKitchenParsePaise(_spend.text);
    if (paise == null) return;
    final d = ref.read(askodoxKitchenClockProvider)();
    final day = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await ref.read(askodoxKitchenProvider.notifier).addSpend(AskodoxKitchenSpend(day: day, paise: paise));
    _spend.clear();
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final state = ref.watch(askodoxKitchenProvider);
    return PopScope(
      canPop: !_adding,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _adding = false);
      },
      child: Scaffold(
        key: const Key('askodoxKitchen'),
        appBar: AppBar(title: Text(te ? 'వంటగది స్టాక్' : 'Kitchen stock')),
        body: SafeArea(
          child: !state.loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: _adding ? _form(te) : _main(te, state.book)),
        ),
      ),
    );
  }

  List<Widget> _main(bool te, AskodoxKitchenBook book) {
    final ctl = ref.read(askodoxKitchenProvider.notifier);
    final buy = askodoxKitchenBuyList(book.items);
    final month = askodoxKitchenMonthSpend(book.spends, ref.read(askodoxKitchenClockProvider)());
    final items = [...book.items]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [
      Text(te ? 'మీ ఇంటి లెక్క మీరే పెట్టండి' : 'Put in your own home figures',
          style: const TextStyle(color: AskodoxLook.muted)),
      const SizedBox(height: 8),
      if (items.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
                te
                    ? 'ఇంట్లో ఉన్న సరుకులు ఒక్కొక్కటిగా చేర్చండి. ఎంత ఉందో రాయండి. తక్కువైనవి ఆటోగా కొనుగోలు లిస్ట్‌కి వెళ్తాయి.'
                    : 'Add what is in the kitchen, one by one, with how much there is. What runs low goes to the buy list by itself.',
                key: const Key('askodoxKitchenEmpty')),
          ),
        ),
      for (final i in items)
        Card(
          key: ValueKey('askodoxKitchenItem-${i.id}'),
          child: ListTile(
            onTap: () => _open(i),
            title: Text(i.name),
            subtitle: Text(i.finished ? (te ? 'అయిపోయింది' : 'Finished') : (askodoxKitchenLow(i) ? (te ? 'తక్కువ' : 'Running low') : ''),
                style: const TextStyle(color: AskodoxLook.accentText)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  key: ValueKey('askodoxKitchenMinus-${i.id}'),
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => ctl.adjust(i.id, -askodoxKitchenStep(i.unit))),
              Text('${askodoxKitchenShown(i.milli)} ${i.unit}',
                  key: ValueKey('askodoxKitchenAmount-${i.id}'), style: const TextStyle(fontWeight: FontWeight.w800)),
              IconButton(
                  key: ValueKey('askodoxKitchenPlus-${i.id}'),
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => ctl.adjust(i.id, askodoxKitchenStep(i.unit))),
              IconButton(
                  key: ValueKey('askodoxKitchenFinish-${i.id}'),
                  tooltip: te ? 'అయిపోయింది' : 'Finished',
                  icon: const Icon(Icons.remove_shopping_cart_outlined),
                  onPressed: () => ctl.finish(i.id)),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      FilledButton.icon(
          key: const Key('askodoxKitchenAdd'),
          onPressed: () => _open(null),
          icon: const Icon(Icons.add),
          label: Text(te ? 'సరుకు చేర్చు' : 'Add an item')),
      const SizedBox(height: 16),
      Text(te ? 'కొనుగోలు లిస్ట్' : 'Buy list', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      if (buy.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(te ? 'ఇప్పుడు కొనాల్సినవి ఏవీ గుర్తించలేదు.' : 'Nothing to buy right now.', key: const Key('askodoxKitchenBuyEmpty')),
        ),
      for (final i in buy) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• ${i.name}', key: ValueKey('askodoxKitchenBuy-${i.id}'))),
      if (buy.isNotEmpty)
        TextButton.icon(
            key: const Key('askodoxKitchenShare'),
            onPressed: () => ref.read(askodoxShareTextProvider)(askodoxKitchenBuyText(book.items, te), subject: te ? 'కొనుగోలు లిస్ట్' : 'Buy list'),
            icon: const Icon(Icons.share_rounded),
            label: Text(te ? 'లిస్ట్ పంపు' : 'Share the list')),
      const SizedBox(height: 16),
      Text(te ? 'ఈ నెల కిరాణా ఖర్చు' : 'Groceries this month', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      Text(askodoxKitchenRupees(month),
          key: const Key('askodoxKitchenMonth'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, fontFeatures: AskodoxLook.figures)),
      Row(children: [
        Expanded(
            child: TextField(
                key: const Key('askodoxKitchenSpend'),
                controller: _spend,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(hintText: te ? 'ఈ రోజు ఖర్చు ₹' : 'Spent today ₹'))),
        const SizedBox(width: 8),
        FilledButton(key: const Key('askodoxKitchenSpendAdd'), onPressed: _addSpend, child: Text(te ? 'చేర్చు' : 'Add')),
      ]),
      const SizedBox(height: 12),
      Text(
          te
              ? 'కుటుంబంలో ఎవరైనా వాడినా స్టాక్ మార్చొచ్చు. ఈ లిస్ట్ ఈ ఫోన్‌లో మీ ఖాతాలో మాత్రమే ఉంటుంది.'
              : 'Anyone at home can change the stock. This list stays on this phone, in your account only.',
          style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted)),
      const SizedBox(height: 8),
      const AskodoxEstimateNote(),
    ];
  }

  List<Widget> _form(bool te) => [
        TextField(key: const Key('askodoxKitchenName'), controller: _name, decoration: InputDecoration(labelText: te ? 'సరుకు పేరు' : 'Item name')),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final u in askodoxKitchenUnits)
            ChoiceChip(key: ValueKey('askodoxKitchenUnit-$u'), label: Text(u), selected: _unit == u, onSelected: (_) => setState(() => _unit = u)),
        ]),
        const SizedBox(height: 10),
        TextField(
            key: const Key('askodoxKitchenQty'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: te ? 'ఇప్పుడు ఎంత ఉంది' : 'How much is there now')),
        const SizedBox(height: 10),
        TextField(
            key: const Key('askodoxKitchenLow'),
            controller: _low,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: te ? 'ఇంత కంటే తక్కువైతే లిస్ట్‌కి చేర్చు (మీరే పెట్టండి)' : 'Put on the list at or below (your own level)')),
        const SizedBox(height: 16),
        FilledButton(key: const Key('askodoxKitchenSave'), onPressed: _save, child: Text(te ? 'సేవ్ చేయి' : 'Save')),
        if (_editId.isNotEmpty)
          TextButton(
              key: const Key('askodoxKitchenRemove'),
              onPressed: () async {
                await ref.read(askodoxKitchenProvider.notifier).removeItem(_editId);
                if (mounted) setState(() => _adding = false);
              },
              child: Text(te ? 'తీసేయి' : 'Remove')),
      ];
}
