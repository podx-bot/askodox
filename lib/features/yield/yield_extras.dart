import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme/askodox_look.dart';
import '../native_video/video_commerce.dart' show askodoxShareTextProvider;
import 'yield_math.dart';
import 'yield_store.dart';

/// Under the rate board (owner 2026-11-27, design "rate board" + "measure card"): the further forms the owner sells
/// (skinless, boneless ...) with the owner's own yield and rate; the measure card (what one plate / piece costs in
/// this item); and the selling rates as a message for customers. Every number is the owner's entry.
class AskodoxYieldExtras extends ConsumerWidget {
  const AskodoxYieldExtras({super.key, required this.businessId, required this.item, required this.cost, required this.sell});
  final String businessId;
  final String item;

  /// The newest lot's real cost of a sellable kg, and its selling rate.
  final int cost;
  final int sell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final book = ref.watch(askodoxYieldProvider).book(businessId);
    final forms = book.formsOf(item);
    final portions = book.portionsOf(item);
    Widget head(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head(te ? 'ఇతర రూపాలు (మీ యీల్డ్, మీ రేటు)' : 'Other forms (your yield, your rate)'),
      for (final f in forms) _formRow(context, ref, f, te),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('askodoxYieldFormAdd'),
          onPressed: () => _editForm(context, ref, null, te),
          icon: const Icon(Icons.add_rounded),
          label: Text(te ? 'రూపం చేర్చు (స్కిన్ లేకుండా, బోన్‌లెస్…)' : 'Add a form (skinless, boneless…)'),
        ),
      ),
      head(te ? 'కొలత కార్డ్ · ఒక ప్లేట్ / పీస్‌కి' : 'Measure card · for one plate / piece'),
      for (final p in portions) _portionRow(context, ref, p, te),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('askodoxYieldPortionAdd'),
          onPressed: () => _editPortion(context, ref, null, te),
          icon: const Icon(Icons.add_rounded),
          label: Text(te ? 'కొలత చేర్చు' : 'Add a measure'),
        ),
      ),
      if (sell > 0 || forms.any((f) => f.sellPaise > 0))
        OutlinedButton.icon(
          key: const Key('askodoxYieldShare'),
          onPressed: () => ref.read(askodoxShareTextProvider)(askodoxYieldBoardText('', item, sell, forms, te), subject: 'ASKODOX'),
          icon: const Icon(Icons.share_rounded),
          label: Text(te ? 'అమ్మే రేట్లు కస్టమర్లకు పంపు' : 'Send the selling rates to customers'),
        ),
    ]);
  }

  Widget _formRow(BuildContext context, WidgetRef ref, AskodoxYieldForm f, bool te) {
    final formCost = askodoxYieldFormCost(cost, f.yieldBp);
    final gain = formCost == null || f.sellPaise <= 0 ? null : askodoxYieldProfit(f.sellPaise, formCost);
    return ListTile(
      key: ValueKey('askodoxYieldForm-${f.name}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () => _editForm(context, ref, f, te),
      title: Text(f.name),
      subtitle: Text(
          formCost == null
              ? (te ? 'మీ యీల్డ్ రాయండి' : 'Enter your yield')
              : '${te ? 'ఖర్చు' : 'cost'} ${askodoxYieldRupees(formCost)}'
                  '${f.sellPaise > 0 ? ' · ${te ? 'అమ్మే' : 'sell'} ${askodoxYieldRupees(f.sellPaise)}' : ''}',
          key: ValueKey('askodoxYieldFormCost-${f.name}')),
      trailing: gain == null
          ? null
          : Text(askodoxYieldRupees(gain.profit),
              key: ValueKey('askodoxYieldFormProfit-${f.name}'),
              style: TextStyle(fontWeight: FontWeight.w800, color: gain.profit >= 0 ? AskodoxLook.good : AskodoxLook.accentText)),
    );
  }

  Widget _portionRow(BuildContext context, WidgetRef ref, AskodoxYieldPortion p, bool te) {
    final one = askodoxYieldPortionCost(p.grams, cost);
    return ListTile(
      key: ValueKey('askodoxYieldPortion-${p.name}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () => _editPortion(context, ref, p, te),
      title: Text('${p.name} · ${askodoxYieldGrams(p.grams)}'),
      subtitle: Text(
          '${askodoxYieldItemName(item, te)} ${te ? 'ఖర్చు' : 'cost'} ${askodoxYieldRupees(one)}'
          '${p.sellPaise > 0 ? ' · ${te ? 'అమ్మే' : 'sell'} ${askodoxYieldRupees(p.sellPaise)}' : ''}',
          key: ValueKey('askodoxYieldPortionCost-${p.name}')),
    );
  }

  InputDecoration _box(String label, String suffix) => InputDecoration(labelText: label, suffixText: suffix);

  String _plain(int value, int scale) =>
      value == 0 ? '' : (value / scale).toStringAsFixed(scale == 1000 ? 3 : 2).replaceFirst(RegExp(r'\.?0+$'), '');

  Future<void> _editForm(BuildContext context, WidgetRef ref, AskodoxYieldForm? old, bool te) async {
    final name = TextEditingController(text: old?.name ?? '');
    final yieldPct = TextEditingController(text: _plain(old?.yieldBp ?? 0, 100));
    final rate = TextEditingController(text: _plain(old?.sellPaise ?? 0, 100));
    final store = ref.read(askodoxYieldProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (sheet, setSheet) {
        final bp = askodoxYieldParsePercent(yieldPct.text);
        final formCost = bp > 10000 ? null : askodoxYieldFormCost(cost, bp);
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
                key: const Key('askodoxYieldFormName'),
                controller: name,
                maxLength: 30,
                enabled: old == null,
                decoration: InputDecoration(labelText: te ? 'రూపం పేరు' : 'Name of the form', counterText: '')),
            const SizedBox(height: 8),
            TextField(
                key: const Key('askodoxYieldFormYield'),
                controller: yieldPct,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setSheet(() {}),
                decoration: _box(te ? 'అమ్మే 1 కిలో నుంచి ఎంత వస్తుంది (మీ యీల్డ్)' : 'What 1 sellable kg gives (your yield)', '%')),
            const SizedBox(height: 8),
            TextField(
                key: const Key('askodoxYieldFormRate'),
                controller: rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _box(te ? 'మీ అమ్మే రేటు (కిలోకి)' : 'Your selling rate (a kg)', '₹')),
            const SizedBox(height: 8),
            Text(
                formCost == null
                    ? (te ? 'యీల్డ్ 1 నుంచి 100 లోపు రాయండి.' : 'Enter a yield from 1 to 100.')
                    : (te ? 'ఈ రూపం కిలో అసలు ఖర్చు: ${askodoxYieldRupees(formCost)}' : 'Real cost of a kg of this form: ${askodoxYieldRupees(formCost)}'),
                key: const Key('askodoxYieldFormPreview'),
                style: const TextStyle(color: AskodoxLook.muted)),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('askodoxYieldFormSave'),
              onPressed: () {
                final clean = name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
                if (clean.isEmpty || formCost == null) return;
                store.saveForm(
                    businessId, item, AskodoxYieldForm(name: clean, yieldBp: bp, sellPaise: askodoxYieldParsePaise(rate.text)));
                Navigator.of(sheet).pop();
              },
              child: Text(te ? 'సేవ్ చేయి' : 'Save'),
            ),
            if (old != null)
              TextButton(
                key: const Key('askodoxYieldFormRemove'),
                onPressed: () {
                  store.removeForm(businessId, item, old.name);
                  Navigator.of(sheet).pop();
                },
                child: Text(te ? 'తీసేయి' : 'Remove'),
              ),
          ]),
        );
      }),
    );
  }

  Future<void> _editPortion(BuildContext context, WidgetRef ref, AskodoxYieldPortion? old, bool te) async {
    final name = TextEditingController(text: old?.name ?? '');
    final grams = TextEditingController(text: old == null || old.grams == 0 ? '' : '${old.grams}');
    final rate = TextEditingController(text: _plain(old?.sellPaise ?? 0, 100));
    final batch = TextEditingController();
    final plates = TextEditingController();
    final store = ref.read(askodoxYieldProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (sheet, setSheet) {
        final g = int.tryParse(grams.text.trim()) ?? 0;
        final worked = askodoxYieldMeasure(askodoxYieldParseGrams(batch.text), int.tryParse(plates.text.trim()) ?? 0);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
                key: const Key('askodoxYieldPortionName'),
                controller: name,
                maxLength: 30,
                enabled: old == null,
                decoration: InputDecoration(labelText: te ? 'ప్లేట్ / పీస్ పేరు' : 'Name of the plate / piece', counterText: '')),
            const SizedBox(height: 8),
            TextField(
                key: const Key('askodoxYieldPortionGrams'),
                controller: grams,
                keyboardType: TextInputType.number,
                onChanged: (_) => setSheet(() {}),
                decoration: _box(te ? 'మీ కొలత (ఒక ప్లేట్‌కి)' : 'Your measure (for one plate)', 'g')),
            const SizedBox(height: 8),
            TextField(
                key: const Key('askodoxYieldPortionRate'),
                controller: rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _box(te ? 'ప్లేట్ అమ్మే ధర (ఐచ్ఛికం)' : 'Selling price of a plate (optional)', '₹')),
            const SizedBox(height: 8),
            Text(
                te
                    ? 'ప్లేట్‌లో ఈ సరుకు ఖర్చు: ${askodoxYieldRupees(askodoxYieldPortionCost(g, cost))} (మీ కొలత × కిలో అసలు ఖర్చు)'
                    : 'This item in one plate costs: ${askodoxYieldRupees(askodoxYieldPortionCost(g, cost))} (your measure × the cost of a kg)',
                key: const Key('askodoxYieldPortionPreview'),
                style: const TextStyle(color: AskodoxLook.muted)),
            const Divider(height: 24),
            Text(te ? 'కొలత తెలుసుకోవాలంటే: ఒక బ్యాచ్ తూకం, వచ్చిన ప్లేట్లు రాయండి' : 'To find your measure: one batch’s weight and the plates it gave',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                    key: const Key('askodoxYieldMeasureBatch'),
                    controller: batch,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setSheet(() {}),
                    decoration: _box(te ? 'బ్యాచ్‌లో వేసింది' : 'Went into the batch', 'kg')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    key: const Key('askodoxYieldMeasurePlates'),
                    controller: plates,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setSheet(() {}),
                    decoration: _box(te ? 'వచ్చిన ప్లేట్లు' : 'Plates it gave', '')),
              ),
            ]),
            worked == null
                ? const SizedBox(height: 8)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('askodoxYieldMeasureUse'),
                      onPressed: () => setSheet(() => grams.text = '$worked'),
                      child: Text(te ? 'మీ కొలత ≈ $worked g · ఇదే పెట్టు' : 'Your measure ≈ $worked g · use it'),
                    ),
                  ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('askodoxYieldPortionSave'),
              onPressed: () {
                final clean = name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
                if (clean.isEmpty || g <= 0 || g > 100000) return;
                store.savePortion(businessId, item,
                    AskodoxYieldPortion(name: clean, grams: g, sellPaise: askodoxYieldParsePaise(rate.text)));
                Navigator.of(sheet).pop();
              },
              child: Text(te ? 'సేవ్ చేయి' : 'Save'),
            ),
            if (old != null)
              TextButton(
                key: const Key('askodoxYieldPortionRemove'),
                onPressed: () {
                  store.removePortion(businessId, item, old.name);
                  Navigator.of(sheet).pop();
                },
                child: Text(te ? 'తీసేయి' : 'Remove'),
              ),
          ]),
        );
      }),
    );
  }
}
