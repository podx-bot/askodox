import 'package:flutter/material.dart';

import '../domain/construction_calculators.dart';
import 'smart_tool_widgets.dart';

/// One generic calculator screen driven by [AskodoxCalcSpec]: fields, an
/// optional choice (shape / mix / unit), a pure compute function. Results
/// recompute as the user types; nothing leaves the phone.
class AskodoxCalcField {
  const AskodoxCalcField(this.key, this.en, this.te,
      {this.suffix, this.initial = '', this.optional = false, this.length = false, this.showFor});
  final String key;
  final String en;
  final String te;
  final String? suffix;
  final String initial;
  final bool optional;

  /// Uses the metre / foot toggle.
  final bool length;

  /// Choice ids this field belongs to (null = always shown).
  final Set<String>? showFor;
}

class AskodoxCalcChoice {
  const AskodoxCalcChoice(this.id, this.en, this.te);
  final String id;
  final String en;
  final String te;
}

typedef AskodoxCalcCompute = AskodoxCalcResult Function(
    Map<String, double?> values, String choice, AskodoxLengthUnit unit);

class AskodoxCalcSpec {
  const AskodoxCalcSpec({
    required this.toolId,
    required this.titleEn,
    required this.titleTe,
    required this.fields,
    required this.compute,
    this.choices = const [],
    this.unitToggle = false,
  });
  final String toolId;
  final String titleEn;
  final String titleTe;
  final List<AskodoxCalcField> fields;
  final List<AskodoxCalcChoice> choices;
  final bool unitToggle;
  final AskodoxCalcCompute compute;
}

double _req(Map<String, double?> v, String key) => v[key] ?? double.nan;

AskodoxMasonryUnit _masonry(String id) =>
    askodoxMasonryUnits.firstWhere((u) => u.id == id, orElse: () => askodoxMasonryUnits.first);

final askodoxCalcSpecs = <String, AskodoxCalcSpec>{
  'area': AskodoxCalcSpec(
    toolId: 'area',
    titleEn: 'Area & perimeter',
    titleTe: 'వైశాల్యం & చుట్టుకొలత',
    unitToggle: true,
    choices: const [
      AskodoxCalcChoice('rectangle', 'Rectangle', 'దీర్ఘచతురస్రం'),
      AskodoxCalcChoice('triangle', 'Triangle', 'త్రిభుజం'),
      AskodoxCalcChoice('circle', 'Circle', 'వృత్తం'),
    ],
    fields: const [
      AskodoxCalcField('a', 'Length', 'పొడవు', length: true, showFor: {'rectangle'}),
      AskodoxCalcField('b', 'Width', 'వెడల్పు', length: true, showFor: {'rectangle'}),
      AskodoxCalcField('base', 'Base', 'బేస్', length: true, showFor: {'triangle'}),
      AskodoxCalcField('height', 'Height', 'ఎత్తు', length: true, showFor: {'triangle'}),
      AskodoxCalcField('d', 'Diameter', 'వ్యాసం', length: true, showFor: {'circle'}),
      AskodoxCalcField('openings', 'Doors / windows to subtract', 'తీసివేయాల్సిన తలుపులు/కిటికీలు',
          suffix: 'm²', optional: true),
    ],
    compute: (v, choice, unit) => switch (choice) {
      'triangle' => askodoxArea(shape: AskodoxShape.triangle, a: _req(v, 'base'), b: _req(v, 'height'), unit: unit,
          openingsSqm: v['openings'] ?? 0),
      'circle' => askodoxArea(shape: AskodoxShape.circle, a: _req(v, 'd'), unit: unit, openingsSqm: v['openings'] ?? 0),
      _ => askodoxArea(shape: AskodoxShape.rectangle, a: _req(v, 'a'), b: _req(v, 'b'), unit: unit,
          openingsSqm: v['openings'] ?? 0),
    },
  ),
  'volume': AskodoxCalcSpec(
    toolId: 'volume',
    titleEn: 'Volume',
    titleTe: 'ఘనపరిమాణం',
    unitToggle: true,
    choices: const [
      AskodoxCalcChoice('cuboid', 'Box / tank / room', 'పెట్టె / ట్యాంక్ / గది'),
      AskodoxCalcChoice('cylinder', 'Cylinder / drum', 'సిలిండర్ / డ్రమ్'),
    ],
    fields: const [
      AskodoxCalcField('a', 'Length', 'పొడవు', length: true, showFor: {'cuboid'}),
      AskodoxCalcField('b', 'Width', 'వెడల్పు', length: true, showFor: {'cuboid'}),
      AskodoxCalcField('d', 'Diameter', 'వ్యాసం', length: true, showFor: {'cylinder'}),
      AskodoxCalcField('h', 'Height', 'ఎత్తు', length: true),
    ],
    compute: (v, choice, unit) => choice == 'cylinder'
        ? askodoxVolume(solid: AskodoxSolid.cylinder, a: _req(v, 'd'), b: _req(v, 'h'), unit: unit)
        : askodoxVolume(solid: AskodoxSolid.cuboid, a: _req(v, 'a'), b: _req(v, 'b'), c: _req(v, 'h'), unit: unit),
  ),
  'brick': AskodoxCalcSpec(
    toolId: 'brick',
    titleEn: 'Brick / block calculator',
    titleTe: 'ఇటుకల లెక్క',
    unitToggle: true,
    choices: [for (final u in askodoxMasonryUnits) AskodoxCalcChoice(u.id, u.nameEn, u.nameTe)],
    fields: const [
      AskodoxCalcField('length', 'Wall length', 'గోడ పొడవు', length: true),
      AskodoxCalcField('height', 'Wall height', 'గోడ ఎత్తు', length: true),
      AskodoxCalcField('thickness', 'Wall thickness', 'గోడ మందం', suffix: 'mm', initial: '230'),
      AskodoxCalcField('openings', 'Doors / windows', 'తలుపులు/కిటికీలు', suffix: 'm²', optional: true),
      AskodoxCalcField('sand', 'Mortar 1 : sand parts', 'మోర్టార్ 1 : ఇసుక భాగాలు', initial: '6'),
      AskodoxCalcField('wastage', 'Wastage', 'వేస్టేజ్', suffix: '%', initial: '5'),
      AskodoxCalcField('rate', 'Your rate per brick / block (optional)', 'ఒక్కో ఇటుక మీ రేటు (ఐచ్ఛికం)',
          suffix: '₹', optional: true),
    ],
    compute: (v, choice, unit) => askodoxBricks(
      wallLength: _req(v, 'length'),
      wallHeight: _req(v, 'height'),
      wallThicknessMm: _req(v, 'thickness'),
      unit: _masonry(choice),
      lengthUnit: unit,
      openingsSqm: v['openings'] ?? 0,
      mortarSandParts: _req(v, 'sand'),
      wastagePercent: v['wastage'] ?? 0,
      ratePerUnit: v['rate'],
    ),
  ),
  'cement': AskodoxCalcSpec(
    toolId: 'cement',
    titleEn: 'Concrete & plaster',
    titleTe: 'కాంక్రీట్ & ప్లాస్టరింగ్',
    choices: const [
      AskodoxCalcChoice('concrete', 'Concrete (PCC / RCC volume)', 'కాంక్రీట్'),
      AskodoxCalcChoice('plaster', 'Plaster', 'ప్లాస్టరింగ్'),
    ],
    fields: const [
      AskodoxCalcField('volume', 'Concrete volume', 'కాంక్రీట్ ఘనపరిమాణం', suffix: 'm³', showFor: {'concrete'}),
      AskodoxCalcField('cp', 'Cement parts', 'సిమెంట్ భాగాలు', initial: '1', showFor: {'concrete'}),
      AskodoxCalcField('sp', 'Sand parts', 'ఇసుక భాగాలు', initial: '1.5', showFor: {'concrete'}),
      AskodoxCalcField('ap', 'Aggregate parts', 'కంకర భాగాలు', initial: '3', showFor: {'concrete'}),
      AskodoxCalcField('area', 'Plaster area', 'ప్లాస్టర్ వైశాల్యం', suffix: 'm²', showFor: {'plaster'}),
      AskodoxCalcField('thick', 'Thickness', 'మందం', suffix: 'mm', initial: '12', showFor: {'plaster'}),
      AskodoxCalcField('psand', 'Mortar 1 : sand parts', 'మోర్టార్ 1 : ఇసుక', initial: '4', showFor: {'plaster'}),
      AskodoxCalcField('wastage', 'Wastage', 'వేస్టేజ్', suffix: '%', initial: '5'),
    ],
    compute: (v, choice, unit) => choice == 'plaster'
        ? askodoxPlaster(areaSqm: _req(v, 'area'), thicknessMm: _req(v, 'thick'), sandParts: _req(v, 'psand'),
            wastagePercent: v['wastage'] ?? 0)
        : askodoxConcrete(wetVolumeM3: _req(v, 'volume'), cementParts: _req(v, 'cp'), sandParts: _req(v, 'sp'),
            aggregateParts: _req(v, 'ap'), wastagePercent: v['wastage'] ?? 0),
  ),
  'tile': AskodoxCalcSpec(
    toolId: 'tile',
    titleEn: 'Tile & flooring',
    titleTe: 'టైల్స్ & ఫ్లోరింగ్',
    fields: const [
      AskodoxCalcField('area', 'Floor / wall area', 'నేల / గోడ వైశాల్యం', suffix: 'm²'),
      AskodoxCalcField('tl', 'Tile length', 'టైల్ పొడవు', suffix: 'mm', initial: '600'),
      AskodoxCalcField('tw', 'Tile width', 'టైల్ వెడల్పు', suffix: 'mm', initial: '600'),
      AskodoxCalcField('wastage', 'Wastage', 'వేస్టేజ్', suffix: '%', initial: '8'),
      AskodoxCalcField('box', 'Tiles per box (optional)', 'బాక్స్‌కు టైల్స్ (ఐచ్ఛికం)', optional: true),
      AskodoxCalcField('rate', 'Your tile rate per sq ft (optional)', 'చ.అ.కు మీ టైల్ రేటు (ఐచ్ఛికం)',
          suffix: '₹', optional: true),
      AskodoxCalcField('labour', 'Your labour rate per sq ft (optional)', 'చ.అ.కు మీ కూలీ రేటు (ఐచ్ఛికం)',
          suffix: '₹', optional: true),
    ],
    compute: (v, choice, unit) => askodoxTiles(
      areaSqm: _req(v, 'area'),
      tileLengthMm: _req(v, 'tl'),
      tileWidthMm: _req(v, 'tw'),
      wastagePercent: v['wastage'] ?? 0,
      tilesPerBox: v['box']?.round(),
      ratePerSqft: v['rate'],
      labourPerSqft: v['labour'],
    ),
  ),
  'paint': AskodoxCalcSpec(
    toolId: 'paint',
    titleEn: 'Paint calculator',
    titleTe: 'పెయింట్ లెక్క',
    fields: const [
      AskodoxCalcField('area', 'Wall / ceiling area', 'గోడ / సీలింగ్ వైశాల్యం', suffix: 'm²'),
      AskodoxCalcField('coats', 'Coats', 'కోట్లు', initial: '2'),
      AskodoxCalcField('coverage', 'Coverage per litre per coat (see the can)', 'లీటరుకు కవరేజ్ (డబ్బాపై చూడండి)',
          suffix: 'm²', initial: '10'),
      AskodoxCalcField('wastage', 'Wastage', 'వేస్టేజ్', suffix: '%', initial: '5'),
      AskodoxCalcField('rate', 'Your paint rate per litre (optional)', 'లీటరుకు మీ రేటు (ఐచ్ఛికం)',
          suffix: '₹', optional: true),
    ],
    compute: (v, choice, unit) => askodoxPaint(
      areaSqm: _req(v, 'area'),
      coats: (v['coats'] ?? 0).round(),
      coverageSqmPerLitre: _req(v, 'coverage'),
      wastagePercent: v['wastage'] ?? 0,
      ratePerLitre: v['rate'],
    ),
  ),
};

class AskodoxCalculatorScreen extends StatefulWidget {
  const AskodoxCalculatorScreen({super.key, required this.spec});
  final AskodoxCalcSpec spec;

  @override
  State<AskodoxCalculatorScreen> createState() => _AskodoxCalculatorScreenState();
}

class _AskodoxCalculatorScreenState extends State<AskodoxCalculatorScreen> {
  late final Map<String, TextEditingController> _controllers = {
    for (final f in widget.spec.fields) f.key: TextEditingController(text: f.initial),
  };
  late String _choice = widget.spec.choices.isEmpty ? '' : widget.spec.choices.first.id;
  AskodoxLengthUnit _unit = AskodoxLengthUnit.metre;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _visible(AskodoxCalcField f) => f.showFor == null || f.showFor!.contains(_choice);

  (AskodoxCalcResult?, String?) _compute(bool te) {
    final values = <String, double?>{};
    for (final f in widget.spec.fields.where(_visible)) {
      final value = askodoxParseNumber(_controllers[f.key]!.text);
      if (value == null && !f.optional) return (null, null); // still typing
      values[f.key] = value;
    }
    try {
      return (widget.spec.compute(values, _choice, _unit), null);
    } on AskodoxCalcException catch (e) {
      return (null, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final spec = widget.spec;
    final (result, error) = _compute(te);
    final unitSuffix = _unit == AskodoxLengthUnit.metre ? 'm' : 'ft';
    return Scaffold(
      appBar: AppBar(title: Text(te ? spec.titleTe : spec.titleEn)),
      body: ListView(
        key: ValueKey('askodoxCalc-${spec.toolId}'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          AskodoxToolSafetyNote(spec.toolId),
          if (spec.choices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(spacing: 8, runSpacing: 6, children: [
                for (final c in spec.choices)
                  ChoiceChip(
                    key: ValueKey('askodoxCalcChoice-${c.id}'),
                    label: Text(te ? c.te : c.en),
                    selected: _choice == c.id,
                    onSelected: (_) => setState(() => _choice = c.id),
                  ),
              ]),
            ),
          if (spec.unitToggle)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SegmentedButton<AskodoxLengthUnit>(
                key: const Key('askodoxCalcUnit'),
                segments: [
                  ButtonSegment(value: AskodoxLengthUnit.metre, label: Text(te ? 'మీటర్లు' : 'Metres')),
                  ButtonSegment(value: AskodoxLengthUnit.foot, label: Text(te ? 'అడుగులు' : 'Feet')),
                ],
                selected: {_unit},
                onSelectionChanged: (s) => setState(() => _unit = s.first),
              ),
            ),
          for (final f in spec.fields.where(_visible))
            AskodoxNumberField(
              key: ValueKey('askodoxCalcField-${f.key}'),
              controller: _controllers[f.key]!,
              label: te ? f.te : f.en,
              suffix: f.length ? unitSuffix : f.suffix,
              onChanged: (_) => setState(() {}),
            ),
          AskodoxCalcResultCard(result: result, error: error),
        ],
      ),
    );
  }
}

/// Screen for a calculator id ('brick', 'tile', ...); unknown ids show a
/// plain notice instead of a broken page.
Widget askodoxCalculatorFor(String id) {
  final spec = askodoxCalcSpecs[id];
  if (spec == null) return const _UnknownTool();
  return AskodoxCalculatorScreen(spec: spec);
}

class _UnknownTool extends StatelessWidget {
  const _UnknownTool();
  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'స్మార్ట్ టూల్స్' : 'Smart Tools')),
      body: Center(child: Text(te ? 'ఈ టూల్ అందుబాటులో లేదు.' : 'This tool is not available.')),
    );
  }
}
