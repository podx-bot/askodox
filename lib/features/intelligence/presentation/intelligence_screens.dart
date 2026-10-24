import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../smart_tools/presentation/smart_tool_widgets.dart';
import '../data/intelligence_repository.dart';

String _lang(bool te) => te ? 'te' : 'en';

const askodoxIndianStates = <String>[
  'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa', 'Gujarat', 'Haryana',
  'Himachal Pradesh', 'Jharkhand', 'Karnataka', 'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya',
  'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura',
  'Uttar Pradesh', 'Uttarakhand', 'West Bengal', 'Andaman and Nicobar Islands', 'Chandigarh',
  'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',
];

class _Sources extends StatelessWidget {
  const _Sources({required this.sources, required this.te, this.verifiedOn, this.note});
  final List<Object?> sources;
  final bool te;
  final String? verifiedOn;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (sources.isNotEmpty)
            Text(te ? 'అధికారిక మూలాలు' : 'Official sources', style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final raw in sources)
            InkWell(
              onTap: () => launchUrl(Uri.parse(askodoxStr(askodoxMap(raw)['url'])), mode: LaunchMode.externalApplication),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(askodoxStr(askodoxMap(raw)['title']),
                    style: const TextStyle(color: Color(0xFF1769FF), decoration: TextDecoration.underline, fontSize: 12.5)),
              ),
            ),
          if ((verifiedOn ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(te ? 'ధృవీకరించిన తేదీ: $verifiedOn' : 'Checked against official sources on $verifiedOn',
                  style: const TextStyle(fontSize: 12)),
            ),
          if ((note ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(note!, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(text, key: const Key('askodoxIntelError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
}

Widget _row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label)),
        Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ]),
    );

// ---------------------------------------------------------------- income tax

class AskodoxIncomeTaxScreen extends ConsumerStatefulWidget {
  const AskodoxIncomeTaxScreen({super.key});

  @override
  ConsumerState<AskodoxIncomeTaxScreen> createState() => _AskodoxIncomeTaxScreenState();
}

class _AskodoxIncomeTaxScreenState extends ConsumerState<AskodoxIncomeTaxScreen> {
  final _salary = TextEditingController();
  final _other = TextEditingController();
  final _deductions = TextEditingController();
  String _year = '2026-27';
  String _age = 'below_60';
  bool _resident = true;
  bool _busy = false;
  Map<String, Object?>? _result;
  String? _error;

  @override
  void dispose() {
    for (final c in [_salary, _other, _deductions]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _calculate() async {
    final te = askodoxToolsTe(context);
    final salary = askodoxParseNumber(_salary.text) ?? 0;
    final other = askodoxParseNumber(_other.text) ?? 0;
    if (salary <= 0 && other <= 0) {
      setState(() => _error = te ? 'జీతం లేదా ఇతర ఆదాయం నమోదు చేయండి.' : 'Enter salary or other income.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await ref.read(askodoxIntelligenceRepositoryProvider).incomeTax(
            year: _year,
            regime: 'compare',
            salary: salary,
            other: other,
            deductions: askodoxParseNumber(_deductions.text) ?? 0,
            ageBand: _age,
            resident: _resident,
          );
      if (mounted) setState(() => _result = askodoxMap(data['comparison']));
    } on AskodoxIntelException catch (e) {
      if (mounted) setState(() => _error = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _regime(Map<String, Object?> r, String title, bool lower, bool te) => Expanded(
        child: Card(
          key: ValueKey('askodoxTaxRegime-${askodoxStr(r['regime'])}'),
          color: lower ? const Color(0xFFDCFCE7) : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(askodoxRupees(r['total_tax']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text('${te ? 'పన్ను విధించదగిన ఆదాయం' : 'Taxable'}: ${askodoxRupees(r['taxable_income'])}',
                  style: const TextStyle(fontSize: 12)),
              if (lower) Text(te ? 'తక్కువ పన్ను' : 'Lower tax', style: const TextStyle(color: Color(0xFF15803D))),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final result = _result;
    final newR = askodoxMap(result?['new']);
    final oldR = askodoxMap(result?['old']);
    final lower = askodoxStr(result?['lower_tax']);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఆదాయపు పన్ను అంచనా' : 'Income tax estimate')),
      body: ListView(
        key: const Key('askodoxIncomeTax'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(te
              ? 'కొత్త మరియు పాత విధానాలను పోల్చుతుంది. సాధారణ రేట్ల ఆదాయం మాత్రమే; క్యాపిటల్ గెయిన్స్ కలపలేదు.'
              : 'Compares the new and old regimes for income taxed at slab rates (capital gains not included).',
              style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            key: const Key('askodoxTaxYear'),
            segments: const [
              ButtonSegment(value: '2026-27', label: Text('2026-27')),
              ButtonSegment(value: '2025-26', label: Text('2025-26')),
            ],
            selected: {_year},
            onSelectionChanged: (s) => setState(() {
              _year = s.first;
              _result = null;
            }),
          ),
          const SizedBox(height: 10),
          AskodoxNumberField(
              key: const Key('askodoxTaxSalary'), controller: _salary,
              label: te ? 'వార్షిక జీతం (ఐచ్ఛికం)' : 'Annual salary (optional)', suffix: '₹'),
          AskodoxNumberField(
              key: const Key('askodoxTaxOther'), controller: _other,
              label: te ? 'ఇతర ఆదాయం — వ్యాపారం, వడ్డీ, అద్దె (ఐచ్ఛికం)' : 'Other income — business, interest, rent (optional)',
              suffix: '₹'),
          AskodoxNumberField(
              key: const Key('askodoxTaxDeductions'), controller: _deductions,
              label: te ? 'పాత విధానంలో డిడక్షన్లు (80C, 80D…)' : 'Old-regime deductions (80C, 80D…)', suffix: '₹'),
          Wrap(spacing: 6, children: [
            for (final (id, en, tel) in const [
              ('below_60', 'Below 60', '60 లోపు'),
              ('60_to_80', '60–80', '60–80'),
              ('80_plus', '80+', '80+'),
            ])
              ChoiceChip(label: Text(te ? tel : en), selected: _age == id, onSelected: (_) => setState(() => _age = id)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(te ? 'భారత నివాసి' : 'Resident in India'),
            value: _resident,
            onChanged: (v) => setState(() => _resident = v),
          ),
          FilledButton.icon(
            key: const Key('askodoxTaxCalculate'),
            onPressed: _busy ? null : _calculate,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.calculate_outlined),
            label: Text(te ? 'లెక్కించు' : 'Calculate'),
          ),
          if (_error != null) _ErrorText(_error!),
          if (result != null) ...[
            const SizedBox(height: 14),
            Text(askodoxStr(newR['year_label']), style: const TextStyle(fontWeight: FontWeight.w700)),
            Row(children: [
              _regime(newR, te ? 'కొత్త విధానం' : 'New regime', lower == 'new', te),
              _regime(oldR, te ? 'పాత విధానం' : 'Old regime', lower == 'old', te),
            ]),
            for (final r in [newR, oldR]) ...[
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('${askodoxStr(r['regime']) == 'new' ? (te ? 'కొత్త' : 'New') : (te ? 'పాత' : 'Old')} — '
                    '${te ? 'వివరాలు' : 'breakdown'}'),
                children: [
                  _row(te ? 'స్టాండర్డ్ డిడక్షన్' : 'Standard deduction', askodoxRupees(r['standard_deduction'])),
                  _row(te ? 'డిడక్షన్లు' : 'Deductions used', askodoxRupees(r['deductions_used'])),
                  _row(te ? 'శ్లాబ్ పన్ను' : 'Slab tax', askodoxRupees(r['slab_tax'])),
                  _row(te ? 'రిబేట్' : 'Rebate', askodoxRupees(r['rebate'])),
                  _row(te ? 'సర్‌చార్జ్' : 'Surcharge', askodoxRupees(r['surcharge'])),
                  _row(te ? 'సెస్ (4%)' : 'Cess (4%)', askodoxRupees(r['cess'])),
                  _row(te ? 'మొత్తం' : 'Total', askodoxRupees(r['total_tax']), bold: true),
                  for (final n in askodoxList(r['notes']))
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('• ${askodoxStr(n)}', style: const TextStyle(fontSize: 12))),
                ],
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(askodoxStr(result['switching_rule']), style: const TextStyle(fontSize: 12)),
            ),
            _Sources(
                sources: askodoxList(newR['sources']), te: te,
                verifiedOn: askodoxStr(newR['verified_on']), note: askodoxStr(newR['professional_note'])),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- GST

class AskodoxGstScreen extends ConsumerStatefulWidget {
  const AskodoxGstScreen({super.key});

  @override
  ConsumerState<AskodoxGstScreen> createState() => _AskodoxGstScreenState();
}

class _AskodoxGstScreenState extends ConsumerState<AskodoxGstScreen> {
  final _turnover = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController(text: '18');
  String _state = 'Andhra Pradesh';
  String _supply = 'goods';
  String _business = 'trader';
  bool _interstate = false;
  bool _ecommerce = false;
  bool _inclusive = false;
  bool _busy = false;
  Map<String, Object?>? _registration;
  Map<String, Object?>? _composition;
  Map<String, Object?>? _amountResult;
  String? _error;

  @override
  void dispose() {
    for (final c in [_turnover, _amount, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AskodoxIntelligenceRepository repo) body) async {
    final te = askodoxToolsTe(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body(ref.read(askodoxIntelligenceRepositoryProvider));
    } on AskodoxIntelException catch (e) {
      if (mounted) setState(() => _error = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _checkTurnover() {
    final te = askodoxToolsTe(context);
    final turnover = askodoxParseNumber(_turnover.text);
    if (turnover == null) {
      setState(() => _error = te ? 'వార్షిక టర్నోవర్ నమోదు చేయండి.' : 'Enter the annual turnover.');
      return;
    }
    _run((repo) async {
      final reg = await repo.gstRegistration(turnover: turnover, supply: _supply, state: _state);
      final comp = await repo.gstComposition(
          turnover: turnover, business: _business, state: _state, interstate: _interstate, ecommerce: _ecommerce);
      if (mounted) {
        setState(() {
          _registration = askodoxMap(reg['result']);
          _composition = askodoxMap(comp['result']);
        });
      }
    });
  }

  void _computeAmount() {
    final te = askodoxToolsTe(context);
    final amount = askodoxParseNumber(_amount.text);
    final rate = askodoxParseNumber(_rate.text);
    if (amount == null || rate == null) {
      setState(() => _error = te ? 'మొత్తం మరియు రేటు నమోదు చేయండి.' : 'Enter the amount and the rate.');
      return;
    }
    _run((repo) async {
      final data = await repo.gstAmount(amount: amount, rate: rate, inclusive: _inclusive, interstate: _interstate);
      if (mounted) setState(() => _amountResult = askodoxMap(data['result']));
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final reg = _registration;
    final comp = _composition;
    final amount = _amountResult;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'జీఎస్టీ టూల్' : 'GST tool')),
      body: ListView(
        key: const Key('askodoxGstTool'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          DropdownButtonFormField<String>(
            key: const Key('askodoxGstState'),
            initialValue: _state,
            decoration: InputDecoration(labelText: te ? 'రాష్ట్రం' : 'State', border: const OutlineInputBorder(), isDense: true),
            items: [for (final s in askodoxIndianStates) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: (v) => setState(() => _state = v ?? _state),
          ),
          const SizedBox(height: 12),
          Text(te ? 'రిజిస్ట్రేషన్ & కంపోజిషన్' : 'Registration & composition', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          AskodoxNumberField(
              key: const Key('askodoxGstTurnover'), controller: _turnover,
              label: te ? 'వార్షిక టర్నోవర్' : 'Annual turnover', suffix: '₹'),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final (id, en, tel) in const [('goods', 'Goods', 'వస్తువులు'), ('services', 'Services', 'సేవలు'), ('both', 'Both', 'రెండూ')])
              ChoiceChip(label: Text(te ? tel : en), selected: _supply == id, onSelected: (_) => setState(() => _supply = id)),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final (id, en, tel) in const [
              ('trader', 'Trader', 'వ్యాపారి'),
              ('manufacturer', 'Manufacturer', 'తయారీదారు'),
              ('restaurant', 'Restaurant', 'రెస్టారెంట్'),
              ('services', 'Service provider', 'సేవలు'),
            ])
              ChoiceChip(label: Text(te ? tel : en), selected: _business == id, onSelected: (_) => setState(() => _business = id)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(te ? 'ఇతర రాష్ట్రాలకు అమ్మకాలు' : 'Sales to other States'),
            value: _interstate,
            onChanged: (v) => setState(() => _interstate = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(te ? 'TCS వసూలు చేసే ఈ-కామర్స్ ద్వారా అమ్మకాలు' : 'Sales through e-commerce that collects TCS'),
            value: _ecommerce,
            onChanged: (v) => setState(() => _ecommerce = v),
          ),
          FilledButton(
            key: const Key('askodoxGstCheck'),
            onPressed: _busy ? null : _checkTurnover,
            child: Text(te ? 'చెక్ చేయి' : 'Check'),
          ),
          if (reg != null && reg.isNotEmpty)
            Card(
              key: const Key('askodoxGstRegistration'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    reg['registration_required_by_turnover'] == true
                        ? (te ? 'టర్నోవర్ ప్రకారం GST రిజిస్ట్రేషన్ అవసరం.' : 'GST registration is required by turnover.')
                        : (te ? 'టర్నోవర్ ప్రకారం రిజిస్ట్రేషన్ తప్పనిసరి కాదు.' : 'Turnover alone does not require registration.'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  _row(te ? 'పరిమితి' : 'Threshold', askodoxRupees(reg['threshold'])),
                  if (reg['approaching_threshold'] == true)
                    Text(te ? 'పరిమితికి దగ్గరగా ఉన్నారు.' : 'You are close to the threshold.'),
                  Text(askodoxStr(reg['always_required_cases']), style: const TextStyle(fontSize: 12)),
                  Text(askodoxStr(reg['no_invoice_note']), style: const TextStyle(fontSize: 12)),
                  Text(askodoxStr(reg['verify']), style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ),
          if (comp != null && comp.isNotEmpty)
            Card(
              key: const Key('askodoxGstComposition'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    comp['eligible'] == true
                        ? (te ? 'కంపోజిషన్ స్కీమ్‌కు అర్హులు.' : 'Eligible for the composition scheme.')
                        : (te ? 'కంపోజిషన్ స్కీమ్‌కు అర్హత లేదు.' : 'Not eligible for the composition scheme.'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  for (final b in askodoxList(comp['blockers'])) Text('• ${askodoxStr(b)}'),
                  _row(te ? 'టర్నోవర్‌పై రేటు' : 'Rate on turnover', '${askodoxStr(comp['rate_percent_of_turnover'])}%'),
                  for (final c in askodoxList(comp['conditions']))
                    Text('• ${askodoxStr(c)}', style: const TextStyle(fontSize: 12)),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(askodoxStr(comp['trade_off']), style: const TextStyle(fontSize: 12)),
                  ),
                  _Sources(sources: askodoxList(comp['sources']), te: te, verifiedOn: askodoxStr(comp['verified_on']),
                      note: askodoxStr(comp['professional_note'])),
                ]),
              ),
            ),
          const Divider(height: 28),
          Text(te ? 'GST మొత్తం లెక్క' : 'GST on an amount', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          AskodoxNumberField(key: const Key('askodoxGstAmount'), controller: _amount, label: te ? 'మొత్తం' : 'Amount', suffix: '₹'),
          AskodoxNumberField(key: const Key('askodoxGstRate'), controller: _rate, label: te ? 'GST రేటు' : 'GST rate', suffix: '%'),
          Text(te ? 'రేటు HSN / SAC కోడ్‌పై ఆధారపడి ఉంటుంది — ఉత్పత్తి పేరు నుండి ఊహించము.'
              : 'The rate depends on the HSN / SAC code — ASKODOX never guesses it from a product name.',
              style: const TextStyle(fontSize: 12)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(te ? 'మొత్తంలో GST కలిసి ఉంది' : 'Amount already includes GST'),
            value: _inclusive,
            onChanged: (v) => setState(() => _inclusive = v),
          ),
          OutlinedButton(
            key: const Key('askodoxGstAmountRun'),
            onPressed: _busy ? null : _computeAmount,
            child: Text(te ? 'లెక్కించు' : 'Calculate'),
          ),
          if (amount != null && amount.isNotEmpty)
            Card(
              key: const Key('askodoxGstAmountResult'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  _row(te ? 'పన్ను విధించదగిన విలువ' : 'Taxable value', askodoxRupees(amount['taxable_value'])),
                  for (final e in askodoxMap(amount['split']).entries) _row(e.key.toUpperCase(), '₹${askodoxStr(e.value)}'),
                  _row(te ? 'మొత్తం' : 'Total', askodoxRupees(amount['total']), bold: true),
                ]),
              ),
            ),
          if (_error != null) _ErrorText(_error!),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- fraud

class AskodoxFraudListScreen extends ConsumerStatefulWidget {
  const AskodoxFraudListScreen({super.key});

  @override
  ConsumerState<AskodoxFraudListScreen> createState() => _AskodoxFraudListScreenState();
}

class _AskodoxFraudListScreenState extends ConsumerState<AskodoxFraudListScreen> {
  Future<Map<String, Object?>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= ref.read(askodoxIntelligenceRepositoryProvider).fraudList(_lang(askodoxToolsTe(context)));
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'మోసాల చెక్‌లిస్టులు' : 'Scam checklists')),
      body: FutureBuilder<Map<String, Object?>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            final error = snap.error;
            return Center(child: _ErrorText(error is AskodoxIntelException ? error.message(te) : '$error'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final schemes = askodoxList(snap.data!['schemes']);
          return ListView(
            key: const Key('askodoxFraudList'),
            padding: const EdgeInsets.all(12),
            children: [
              Text(te ? 'డబ్బు పోయిన వెంటనే 1930 కి కాల్ చేయండి.' : 'Lost money to a scam? Call 1930 immediately.',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB45309))),
              for (final raw in schemes)
                Card(
                  child: ListTile(
                    key: ValueKey('askodoxFraud-${askodoxStr(askodoxMap(raw)['id'])}'),
                    title: Text(askodoxStr(askodoxMap(raw)['title'])),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/intel/fraud/${askodoxStr(askodoxMap(raw)['id'])}'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AskodoxFraudDetailScreen extends ConsumerStatefulWidget {
  const AskodoxFraudDetailScreen({super.key, required this.schemeId});
  final String schemeId;

  @override
  ConsumerState<AskodoxFraudDetailScreen> createState() => _AskodoxFraudDetailScreenState();
}

class _AskodoxFraudDetailScreenState extends ConsumerState<AskodoxFraudDetailScreen> {
  Future<Map<String, Object?>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= ref.read(askodoxIntelligenceRepositoryProvider).fraudScheme(widget.schemeId, _lang(askodoxToolsTe(context)));
  }

  Widget _section(String title, List<Object?> lines) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final l in lines) Padding(padding: const EdgeInsets.only(top: 3), child: Text('• ${askodoxStr(l)}')),
        ]),
      );

  void _open(Map<String, Object?> channel) {
    final contact = askodoxStr(channel['contact']);
    final url = askodoxStr(channel['url']);
    final uri = RegExp(r'^\d{3,5}$').hasMatch(contact) ? Uri.parse('tel:$contact') : (url.isEmpty ? null : Uri.parse(url));
    if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'మోసం చెక్‌లిస్ట్' : 'Scam checklist')),
      body: FutureBuilder<Map<String, Object?>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            final error = snap.error;
            return Center(child: _ErrorText(error is AskodoxIntelException ? error.message(te) : '$error'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final s = askodoxMap(snap.data!['scheme']);
          return ListView(
            key: const Key('askodoxFraudDetail'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(askodoxStr(s['title']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              _section(te ? 'ఇది సాధారణంగా ఎలా జరుగుతుంది' : 'How it usually works', [s['how_it_works']]),
              _section(te ? 'ఏది సాధారణ / చట్టబద్ధం' : 'What is normal / legitimate', [s['normal_practice']]),
              _section(te ? 'హెచ్చరిక సంకేతాలు' : 'Warning signs', askodoxList(s['warning_signs'])),
              _section(te ? 'ఎలా నిర్ధారించుకోవాలి' : 'How to verify', askodoxList(s['verify'])),
              _section(te ? 'ఏ ఆధారాలు దాచుకోవాలి' : 'Evidence to keep', askodoxList(s['evidence'])),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(te ? 'ఫిర్యాదు ఎక్కడ' : 'Where to report', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              for (final raw in askodoxList(s['report']))
                Card(
                  child: ListTile(
                    dense: true,
                    title: Text(askodoxStr(askodoxMap(raw)['name'])),
                    subtitle: Text(askodoxStr(askodoxMap(raw)['contact'])),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => _open(askodoxMap(raw)),
                  ),
                ),
              _section(te ? 'చట్టపరమైన పరిణామాలు' : 'Consequences', [s['consequence']]),
              _section(te ? 'సురక్షిత మార్గం' : 'Safer alternative', [s['safer_alternative']]),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(te ? 'ధృవీకరించిన తేదీ: ${askodoxStr(s['verified_on'])}'
                    : 'Reporting channels checked on ${askodoxStr(s['verified_on'])}', style: const TextStyle(fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- smart tricks

class _TrickField {
  const _TrickField(this.key, this.en, this.te, {this.suffix});
  final String key;
  final String en;
  final String te;
  final String? suffix;
}

const _trickFields = <String, List<_TrickField>>{
  'buy_vs_rent': [
    _TrickField('purchase_price', 'Purchase price', 'కొనే ధర', suffix: '₹'),
    _TrickField('resale_value', 'Resale value after use', 'తర్వాత అమ్మితే వచ్చే ధర', suffix: '₹'),
    _TrickField('yearly_upkeep', 'Yearly upkeep', 'సంవత్సర నిర్వహణ', suffix: '₹'),
    _TrickField('rent_per_month', 'Rent per month', 'నెల అద్దె', suffix: '₹'),
    _TrickField('months_needed', 'Months needed', 'ఎన్ని నెలలు కావాలి'),
  ],
  'repair_vs_replace': [
    _TrickField('repair_cost', 'Repair cost', 'రిపేర్ ఖర్చు', suffix: '₹'),
    _TrickField('replacement_price', 'New one price', 'కొత్తది ధర', suffix: '₹'),
    _TrickField('age_years', 'Age (years)', 'వయసు (సంవత్సరాలు)'),
    _TrickField('expected_life_years', 'Expected life (years)', 'అంచనా జీవితకాలం (సంవత్సరాలు)'),
  ],
  'bulk_buy': [
    _TrickField('unit_price_small', 'Price per unit (small pack)', 'చిన్న ప్యాక్ యూనిట్ ధర', suffix: '₹'),
    _TrickField('unit_price_bulk', 'Price per unit (bulk)', 'బల్క్ యూనిట్ ధర', suffix: '₹'),
    _TrickField('units_needed', 'Units you need', 'మీకు కావలసిన యూనిట్లు'),
    _TrickField('bulk_units', 'Units in the bulk pack', 'బల్క్ ప్యాక్‌లో యూనిట్లు'),
    _TrickField('monthly_use', 'Units used per month', 'నెలకు వాడే యూనిట్లు'),
    _TrickField('shelf_life_months', 'Shelf life (months)', 'నిల్వ కాలం (నెలలు)'),
  ],
};

const _trickNames = <String, (String, String)>{
  'unit_price': ('Which pack is cheaper', 'ఏ ప్యాక్ చౌక'),
  'buy_vs_rent': ('Buy or rent', 'కొనాలా అద్దెకా'),
  'repair_vs_replace': ('Repair or replace', 'రిపేర్ లేదా కొత్తది'),
  'bulk_buy': ('Bulk buy worth it?', 'బల్క్ కొనుగోలు లాభమా'),
  'total_cost': ('Total cost of ownership', 'మొత్తం యాజమాన్య ఖర్చు'),
};

class AskodoxSmartTricksScreen extends ConsumerStatefulWidget {
  const AskodoxSmartTricksScreen({super.key, this.initial});
  final String? initial;

  @override
  ConsumerState<AskodoxSmartTricksScreen> createState() => _AskodoxSmartTricksScreenState();
}

class _AskodoxSmartTricksScreenState extends ConsumerState<AskodoxSmartTricksScreen> {
  late String _calc = _trickNames.containsKey(widget.initial) ? widget.initial! : 'unit_price';
  final Map<String, TextEditingController> _fields = {};
  final List<List<TextEditingController>> _options = [];
  final _unit = TextEditingController(text: 'kg');
  final _years = TextEditingController(text: '5');
  bool _busy = false;
  Map<String, Object?>? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resetOptions();
  }

  void _resetOptions() {
    for (final row in _options) {
      for (final c in row) {
        c.dispose();
      }
    }
    _options
      ..clear()
      ..addAll([for (var i = 0; i < 2; i++) [for (var j = 0; j < 5; j++) TextEditingController()]]);
  }

  TextEditingController _field(String key) => _fields.putIfAbsent('$_calc.$key', TextEditingController.new);

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final row in _options) {
      for (final c in row) {
        c.dispose();
      }
    }
    _unit.dispose();
    _years.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final te = askodoxToolsTe(context);
    final repo = ref.read(askodoxIntelligenceRepositoryProvider);
    final values = <String, Object?>{};
    List<Map<String, Object?>>? options;
    if (_calc == 'unit_price' || _calc == 'total_cost') {
      options = [
        for (final row in _options)
          if (askodoxParseNumber(row[1].text) != null)
            _calc == 'unit_price'
                ? {
                    'name': row[0].text.trim().isEmpty ? 'option' : row[0].text.trim(),
                    'price': askodoxParseNumber(row[1].text),
                    'quantity': askodoxParseNumber(row[2].text) ?? 0,
                    'unit': _unit.text.trim(),
                  }
                : {
                    'name': row[0].text.trim().isEmpty ? 'option' : row[0].text.trim(),
                    'price': askodoxParseNumber(row[1].text),
                    'yearly_running': askodoxParseNumber(row[2].text) ?? 0,
                    'yearly_maintenance': askodoxParseNumber(row[3].text) ?? 0,
                    'resale_after': askodoxParseNumber(row[4].text) ?? 0,
                  },
      ];
      if (_calc == 'total_cost') values['years'] = askodoxParseNumber(_years.text);
    } else {
      for (final f in _trickFields[_calc]!) {
        values[f.key] = askodoxParseNumber(_field(f.key).text);
      }
      if (values.values.any((v) => v == null)) {
        setState(() => _error = te ? 'అన్ని విలువలు నమోదు చేయండి.' : 'Fill in every value.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await repo.trick(_calc, values: values, options: options);
      if (mounted) setState(() => _result = askodoxMap(data['result']));
    } on AskodoxIntelException catch (e) {
      if (mounted) setState(() => _error = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _optionRows(bool te) {
    final labels = _calc == 'unit_price'
        ? [(te ? 'పేరు' : 'Name'), (te ? 'ధర' : 'Price'), (te ? 'పరిమాణం' : 'Qty')]
        : [(te ? 'పేరు' : 'Name'), (te ? 'ధర' : 'Price'), (te ? 'సం. ఖర్చు' : 'Yearly running'),
           (te ? 'సం. సర్వీస్' : 'Yearly service'), (te ? 'రీసేల్' : 'Resale')];
    return [
      for (var i = 0; i < _options.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Column(children: [
              for (var j = 0; j < labels.length; j++)
                j == 0
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: _options[i][0],
                          decoration: InputDecoration(labelText: '${labels[0]} ${i + 1}', border: const OutlineInputBorder(), isDense: true),
                        ),
                      )
                    : AskodoxNumberField(controller: _options[i][j], label: labels[j]),
            ]),
          ),
        ),
      if (_options.length < 5)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _options.add([for (var j = 0; j < 5; j++) TextEditingController()])),
            icon: const Icon(Icons.add_rounded),
            label: Text(te ? 'మరో ఎంపిక' : 'Add option'),
          ),
        ),
    ];
  }

  Widget _resultView(Map<String, Object?> r, bool te) {
    final lines = <Widget>[];
    void add(String label, Object? v) {
      if (v == null) return;
      lines.add(_row(label, v is bool ? (v ? (te ? 'అవును' : 'Yes') : (te ? 'కాదు' : 'No')) : askodoxStr(v)));
    }

    switch (_calc) {
      case 'unit_price':
        add(te ? 'చౌకైనది' : 'Cheapest', r['cheapest']);
        for (final row in askodoxList(r['ranked'])) {
          final m = askodoxMap(row);
          add(askodoxStr(m['name']), '₹${askodoxStr(m['per_unit'])} / ${askodoxStr(r['unit'])}');
        }
        add(te ? 'ఆదా (%)' : 'Saving vs costliest (%)', r['saving_vs_costliest_percent']);
      case 'buy_vs_rent':
        add(te ? 'ఏది తక్కువ' : 'Cheaper', r['cheaper']);
        add(te ? 'కొంటే ఖర్చు' : 'Cost if you buy', askodoxRupees(r['own_cost']));
        add(te ? 'అద్దె ఖర్చు' : 'Cost if you rent', askodoxRupees(r['rent_cost']));
        add(te ? 'బ్రేక్-ఈవెన్ (నెలలు)' : 'Break-even (months)', r['breakeven_months']);
      case 'repair_vs_replace':
        add(te ? 'సూచన' : 'Suggestion', r['suggestion']);
        add(te ? 'రిపేర్ — సంవత్సరానికి' : 'Repaired, per remaining year', r['repair_cost_per_remaining_year']);
        add(te ? 'కొత్తది — సంవత్సరానికి' : 'New, per year', r['new_cost_per_year']);
        add(te ? 'మిగిలిన జీవితకాలం' : 'Remaining life (years)', r['remaining_life_years']);
      case 'bulk_buy':
        add(te ? 'లాభమా' : 'Worth it', r['worth_it']);
        add(te ? 'ఆదా' : 'Saving', askodoxRupees(r['saving']));
        add(te ? 'వృథా అయ్యే యూనిట్లు' : 'Units likely wasted', r['expected_waste_units']);
      case 'total_cost':
        add(te ? 'తక్కువ మొత్తం' : 'Lowest total', r['lowest_total']);
        for (final row in askodoxList(r['ranked'])) {
          final m = askodoxMap(row);
          add(askodoxStr(m['name']), '${askodoxRupees(m['total'])} (${askodoxRupees(m['per_year'])}/yr)');
        }
    }
    final notes = [...askodoxList(r['assumptions']), ...askodoxList(r['watch_out']), ...askodoxList(r['reasons'])];
    return Card(
      key: const Key('askodoxTrickResult'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ...lines,
          for (final n in notes) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• ${askodoxStr(n)}', style: const TextStyle(fontSize: 12))),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(askodoxStr(r['evidence_rule']), style: const TextStyle(fontSize: 11.5)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'స్మార్ట్ ట్రిక్స్' : 'Smart Tricks')),
      body: ListView(
        key: const Key('askodoxSmartTricks'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in _trickNames.entries)
              ChoiceChip(
                key: ValueKey('askodoxTrick-${e.key}'),
                label: Text(te ? e.value.$2 : e.value.$1),
                selected: _calc == e.key,
                onSelected: (_) => setState(() {
                  _calc = e.key;
                  _result = null;
                  _error = null;
                  _resetOptions();
                }),
              ),
          ]),
          const SizedBox(height: 12),
          if (_calc == 'unit_price')
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: const Key('askodoxTrickUnit'),
                controller: _unit,
                decoration: InputDecoration(
                    labelText: te ? 'యూనిట్ (kg / litre)' : 'Unit (kg / litre)', border: const OutlineInputBorder(), isDense: true),
              ),
            ),
          if (_calc == 'total_cost')
            AskodoxNumberField(controller: _years, label: te ? 'ఎన్ని సంవత్సరాలు' : 'Years of use'),
          if (_calc == 'unit_price' || _calc == 'total_cost') ..._optionRows(te),
          if (_trickFields[_calc] case final fields?)
            for (final f in fields)
              AskodoxNumberField(
                  key: ValueKey('askodoxTrickField-${f.key}'), controller: _field(f.key),
                  label: te ? f.te : f.en, suffix: f.suffix),
          FilledButton(
            key: const Key('askodoxTrickRun'),
            onPressed: _busy ? null : _run,
            child: Text(te ? 'లెక్కించు' : 'Work it out'),
          ),
          if (_error != null) _ErrorText(_error!),
          if (result != null) _resultView(result, te),
        ],
      ),
    );
  }
}
