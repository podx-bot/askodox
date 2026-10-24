import 'package:flutter/material.dart';

import '../domain/construction_calculators.dart';
import '../domain/load_planner.dart';
import 'smart_tool_widgets.dart';

class _ItemRow {
  final name = TextEditingController();
  final l = TextEditingController();
  final w = TextEditingController();
  final h = TextEditingController();
  final kg = TextEditingController();
  final qty = TextEditingController(text: '1');

  List<TextEditingController> get all => [name, l, w, h, kg, qty];
  void dispose() {
    for (final c in all) {
      c.dispose();
    }
  }
}

/// Load & space planner: boxes / bags vs a cargo space and the payload the
/// USER enters from the vehicle papers. Volume fit is necessary, not proof.
class AskodoxLoadPlannerScreen extends StatefulWidget {
  const AskodoxLoadPlannerScreen({super.key});

  @override
  State<AskodoxLoadPlannerScreen> createState() => _AskodoxLoadPlannerScreenState();
}

class _AskodoxLoadPlannerScreenState extends State<AskodoxLoadPlannerScreen> {
  final _cl = TextEditingController();
  final _cw = TextEditingController();
  final _ch = TextEditingController();
  final _payload = TextEditingController();
  final _rows = <_ItemRow>[_ItemRow()];

  @override
  void dispose() {
    for (final c in [_cl, _cw, _ch, _payload]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  (AskodoxLoadPlan?, String?) _plan(bool te) {
    final space = [_cl, _cw, _ch, _payload].map((c) => askodoxParseNumber(c.text)).toList();
    if (space.any((v) => v == null)) return (null, null);
    final items = <AskodoxLoadItem>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final dims = [r.l, r.w, r.h, r.kg].map((c) => askodoxParseNumber(c.text)).toList();
      if (dims.every((v) => v == null)) continue; // empty row
      if (dims.any((v) => v == null)) return (null, null);
      final name = r.name.text.trim().isEmpty ? (te ? 'వస్తువు ${i + 1}' : 'Item ${i + 1}') : r.name.text.trim();
      items.add(AskodoxLoadItem(
        name: name,
        lengthCm: dims[0]!,
        widthCm: dims[1]!,
        heightCm: dims[2]!,
        weightKg: dims[3]!,
        quantity: (askodoxParseNumber(r.qty.text) ?? 1).round(),
      ));
    }
    if (items.isEmpty) return (null, null);
    try {
      return (
        askodoxPlanLoad(items, AskodoxCargoSpace(lengthCm: space[0]!, widthCm: space[1]!, heightCm: space[2]!, payloadKg: space[3]!)),
        null
      );
    } on AskodoxCalcException catch (e) {
      return (null, e.message(te));
    }
  }

  Widget _small(TextEditingController c, String label, {bool number = true}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: number
              ? AskodoxNumberField(controller: c, label: label, onChanged: (_) => setState(() {}))
              : Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: c,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
                  ),
                ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final (plan, error) = _plan(te);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'లోడ్ & స్థలం ప్లానర్' : 'Load & space planner')),
      body: ListView(
        key: const ValueKey('askodoxCalc-load'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const AskodoxToolSafetyNote('load'),
          Text(te ? 'కార్గో స్థలం (సెం.మీ.) & బరువు పరిమితి (కేజీ, వాహన పత్రాల నుండి)'
              : 'Cargo space (cm) and payload limit (kg, from the vehicle papers)',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            _small(_cl, te ? 'పొడవు' : 'Length'),
            _small(_cw, te ? 'వెడల్పు' : 'Width'),
            _small(_ch, te ? 'ఎత్తు' : 'Height'),
          ]),
          AskodoxNumberField(
              key: const Key('askodoxLoadPayload'), controller: _payload,
              label: te ? 'గరిష్ట బరువు (payload)' : 'Payload limit', suffix: 'kg',
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 4),
          Text(te ? 'వస్తువులు (సెం.మీ., కేజీ)' : 'Items (cm, kg each)',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final r in _rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 4, 0),
                child: Column(children: [
                  Row(children: [
                    _small(r.name, te ? 'పేరు' : 'Name', number: false),
                    _small(r.qty, te ? 'సంఖ్య' : 'Qty'),
                  ]),
                  Row(children: [
                    _small(r.l, 'L'),
                    _small(r.w, 'W'),
                    _small(r.h, 'H'),
                    _small(r.kg, 'kg'),
                  ]),
                ]),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('askodoxLoadAddItem'),
              onPressed: _rows.length >= 20 ? null : () => setState(() => _rows.add(_ItemRow())),
              icon: const Icon(Icons.add_rounded),
              label: Text(te ? 'వస్తువు చేర్చు' : 'Add item'),
            ),
          ),
          if (error != null) AskodoxCalcResultCard(result: null, error: error),
          if (plan != null) _PlanCard(plan: plan, te: te),
          if (plan == null && error == null) const AskodoxCalcResultCard(result: null),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.te});
  final AskodoxLoadPlan plan;
  final bool te;

  String _verdict(AskodoxLoadVerdict v) => switch (v) {
        AskodoxLoadVerdict.fits => te ? 'సరిపోతుంది (ఘనపరిమాణం & బరువు).' : 'Fits by volume and weight.',
        AskodoxLoadVerdict.tight => te
            ? 'దాదాపు నిండిపోతుంది — ఆకారాలు/ఖాళీల వల్ల సరిపోకపోవచ్చు.'
            : 'Very tight — shapes and gaps may stop it fitting in practice.',
        AskodoxLoadVerdict.overWeight => te ? 'బరువు పరిమితి దాటింది.' : 'Over the payload limit.',
        AskodoxLoadVerdict.overVolume => te ? 'స్థలం సరిపోదు.' : 'Not enough space.',
        AskodoxLoadVerdict.itemTooLarge => te ? 'కొన్ని వస్తువులు స్థలం కంటే పెద్దవి.' : 'Some items are larger than the space.',
      };

  @override
  Widget build(BuildContext context) {
    final ok = plan.fits;
    return Card(
      key: const Key('askodoxToolResult'),
      color: ok ? null : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final v in plan.verdicts)
            Text(_verdict(v), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('${te ? 'ఘనపరిమాణం' : 'Volume'}: ${plan.totalVolumeM3.toStringAsFixed(2)} m³ '
              '(${plan.volumeUsedPercent.toStringAsFixed(0)}%)'),
          Text('${te ? 'బరువు' : 'Weight'}: ${plan.totalWeightKg.toStringAsFixed(0)} kg '
              '(${plan.weightUsedPercent.toStringAsFixed(0)}%)'),
          if (plan.oversizedItems.isNotEmpty)
            Text('${te ? 'పెద్దవి' : 'Too large'}: ${plan.oversizedItems.join(', ')}'),
          const SizedBox(height: 8),
          Text(te ? 'లోడ్ చేసే క్రమం (బరువైనవి కింద, ముందు వైపు):' : 'Loading order (heaviest at the bottom, toward the front):',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(plan.loadingOrder.join(' → ')),
          const SizedBox(height: 8),
          Text(te ? 'లోడ్‌ను తాళ్ళు/బెల్టులతో బిగించండి.' : 'Secure the load with straps before driving.',
              style: const TextStyle(fontSize: 12.5)),
        ]),
      ),
    );
  }
}
