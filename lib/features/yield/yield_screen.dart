import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme/askodox_look.dart';
import '../../services/media_picker.dart';
import '../../shared/widgets/estimate_note.dart';
import '../vault/vault_store.dart';
import 'closing_alert.dart';
import 'yield_extras.dart';
import 'yield_math.dart';
import 'yield_store.dart';

/// Yield & rates (owner 2026-11-27, design canvas buy / dressing / rate board / day end): what a lot cost, what came
/// out of it, the real cost of a sellable kg, the profit at the owner's selling rate, and the day's stock against
/// the scale. Three steps: bought -> weighed after -> rate. Every number is the owner's own entry.
class AskodoxYieldScreen extends ConsumerStatefulWidget {
  const AskodoxYieldScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxYieldScreen> createState() => _AskodoxYieldScreenState();
}

class _AskodoxYieldScreenState extends ConsumerState<AskodoxYieldScreen> {
  final _own = TextEditingController();
  final _live = TextEditingController();
  final _count = TextEditingController();
  final _rate = TextEditingController();
  final _transport = TextEditingController();
  final _labour = TextEditingController();
  final _out = TextEditingController();
  final _by = TextEditingController();
  final _sell = TextEditingController();
  final _min = TextEditingController();
  final _opening = TextEditingController();
  final _sold = TextEditingController();
  final _actual = TextEditingController();
  final _other = TextEditingController();

  String _item = askodoxYieldItems.first.$1;
  int _step = 0; // 0 board · 1 bought · 2 weighed after · 3 rate · 9 day end
  String? _editing;
  String _reason = '';
  String _photoName = '';
  Uint8List? _photoBytes;

  List<TextEditingController> get _all =>
      [_own, _live, _count, _rate, _transport, _labour, _out, _by, _sell, _min, _opening, _sold, _actual, _other];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String get _today => askodoxYieldDayKey(ref.read(askodoxYieldClockProvider)());
  AskodoxYieldBook get _book => ref.read(askodoxYieldProvider).book(widget.businessId);

  String _plain(int value, int scale) {
    if (value == 0) return '';
    final text = (value / scale).toStringAsFixed(scale == 1000 ? 3 : 2);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  AskodoxYieldBatch _draft() {
    final now = ref.read(askodoxYieldClockProvider)();
    return AskodoxYieldBatch(
      id: _editing ?? 'lot_${now.microsecondsSinceEpoch}',
      item: _item,
      day: _editing == null ? _today : (_book.batches.where((b) => b.id == _editing).firstOrNull?.day ?? _today),
      liveGrams: askodoxYieldParseGrams(_live.text),
      count: int.tryParse(_count.text.trim()) ?? 0,
      ratePaise: askodoxYieldParsePaise(_rate.text),
      transportPaise: askodoxYieldParsePaise(_transport.text),
      labourPaise: askodoxYieldParsePaise(_labour.text),
      outGrams: askodoxYieldParseGrams(_out.text),
      byproductPaise: askodoxYieldParsePaise(_by.text),
      sellPaise: askodoxYieldParsePaise(_sell.text),
    );
  }

  void _newLot() {
    for (final c in [_live, _count, _rate, _transport, _labour, _out, _by]) {
      c.clear();
    }
    final last = _book.latest(_item);
    _sell.text = _plain(last?.sellPaise ?? 0, 100);
    _min.text = _plain(_book.minProfit[_item] ?? 0, 100);
    setState(() {
      _editing = null;
      _step = 1;
    });
  }

  void _open(AskodoxYieldBatch b, int step) {
    _live.text = _plain(b.liveGrams, 1000);
    _count.text = b.count > 0 ? '${b.count}' : '';
    _rate.text = _plain(b.ratePaise, 100);
    _transport.text = _plain(b.transportPaise, 100);
    _labour.text = _plain(b.labourPaise, 100);
    _out.text = _plain(b.outGrams, 1000);
    _by.text = _plain(b.byproductPaise, 100);
    _sell.text = _plain(b.sellPaise, 100);
    _min.text = _plain(_book.minProfit[_item] ?? 0, 100);
    setState(() {
      _editing = b.id;
      _step = step;
    });
  }

  Future<void> _save({required bool done}) async {
    final draft = _draft();
    if (draft.liveGrams <= 0 || draft.ratePaise <= 0) return;
    final store = ref.read(askodoxYieldProvider.notifier);
    await store.saveBatch(widget.businessId, draft);
    if (done) await store.setMinProfit(widget.businessId, _item, askodoxYieldParsePaise(_min.text));
    if (!mounted) return;
    setState(() {
      _editing = draft.id;
      if (done) _step = 0;
    });
  }

  void _openDay() {
    final book = _book;
    final saved = book.dayOf(_item, _today);
    _opening.text = _plain(saved?.openingGrams ?? book.openingFor(_item, _today), 1000);
    _sold.text = _plain(saved?.soldGrams ?? 0, 1000);
    _actual.text = _plain(saved?.actualGrams ?? 0, 1000);
    _other.text = _plain(saved?.otherPaise ?? 0, 100);
    setState(() {
      _reason = saved?.reason ?? '';
      _photoName = saved?.photo ?? '';
      _photoBytes = null;
      _step = 9;
    });
  }

  /// The stock as the owner sees it, kept on this phone beside the day end (never uploaded).
  Future<void> _takeStockPhoto() async {
    final picked = (await ref.read(askodoxMediaPickerProvider).pick('camera')).where((a) => a.isImage).toList();
    if (picked.isEmpty || !mounted) return;
    if (picked.first.bytes.length > 4400000) return;
    setState(() => _photoBytes = picked.first.bytes);
  }

  AskodoxYieldDay _dayDraft() {
    final book = _book;
    final last = book.latest(_item);
    return AskodoxYieldDay(
      item: _item,
      day: _today,
      openingGrams: askodoxYieldParseGrams(_opening.text),
      madeGrams: book.madeOn(_item, _today),
      soldGrams: askodoxYieldParseGrams(_sold.text),
      actualGrams: askodoxYieldParseGrams(_actual.text),
      otherPaise: askodoxYieldParsePaise(_other.text),
      costPaise: last?.cost ?? 0,
      sellPaise: last?.sellPaise ?? 0,
      reason: _reason,
      photo: _photoName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final state = ref.watch(askodoxYieldProvider);
    final book = state.book(widget.businessId);
    final title = switch (_step) {
      1 => te ? '1 / 3 · కొన్నది' : '1 / 3 · Bought',
      2 => te ? '2 / 3 · తర్వాత తూకం' : '2 / 3 · Weighed after',
      3 => te ? '3 / 3 · రేటు' : '3 / 3 · Rate',
      9 => te ? 'రోజు ముగింపు' : 'Day end',
      _ => te ? 'యీల్డ్ & రేట్లు' : 'Yield & rates',
    };
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step = _step == 9 || _step == 1 ? 0 : _step - 1);
      },
      child: Scaffold(
        key: const Key('askodoxYield'),
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: !state.loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                  ...switch (_step) {
                    1 => _bought(te),
                    2 => _after(te),
                    3 => _rateStep(te, book),
                    9 => _dayEnd(te),
                    _ => _board(te, book),
                  },
                  const SizedBox(height: 16),
                  const AskodoxEstimateNote(),
                ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------------------------------------ pieces
  Widget _field(String keyName, TextEditingController c, String label, {String suffix = ''}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: Key(keyName),
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, suffixText: suffix),
        ),
      );

  Widget _line(String label, String value, {String? keyName, bool strong = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: AskodoxLook.muted))),
          Text(value,
              key: keyName == null ? null : Key(keyName),
              style: TextStyle(
                  fontSize: strong ? 22 : 16, fontWeight: FontWeight.w800, color: color ?? AskodoxLook.text,
                  fontFeatures: AskodoxLook.figures)),
        ]),
      );

  Widget _next(String keyName, String label, VoidCallback? onPressed) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FilledButton(key: Key(keyName), onPressed: onPressed, child: Text(label)),
      );

  // ------------------------------------------------------------------------------------------------ board
  List<Widget> _board(bool te, AskodoxYieldBook book) {
    final names = {for (final row in askodoxYieldItems) row.$1, for (final b in book.batches) b.item};
    final last = book.latest(_item);
    final yields = book.yields(_item);
    final lots = book.of(_item).reversed.take(7).toList();
    return [
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final name in names)
          ChoiceChip(
            key: ValueKey('askodoxYieldItem-$name'),
            label: Text(askodoxYieldItemName(name, te)),
            selected: _item == name,
            onSelected: (_) => setState(() => _item = name),
          ),
      ]),
      Row(children: [
        Expanded(
          child: TextField(
            key: const Key('askodoxYieldOwnItem'),
            controller: _own,
            maxLength: 30,
            decoration: InputDecoration(labelText: te ? 'వేరే వస్తువు పేరు' : 'Another item', counterText: ''),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          key: const Key('askodoxYieldOwnAdd'),
          onPressed: () {
            final name = _own.text.trim().replaceAll(RegExp(r'\s+'), ' ');
            if (name.isEmpty) return;
            _own.clear();
            setState(() => _item = name);
          },
          child: Text(te ? 'ఎంచుకో' : 'Use'),
        ),
      ]),
      const SizedBox(height: 8),
      if (last == null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
                te
                    ? 'కొన్న బరువు, రేటు రాస్తే: అమ్మే ప్రతి కిలో అసలు ఖర్చు, లాభం వెంటనే కనిపిస్తాయి. సంఖ్యలన్నీ మీవే.'
                    : 'Enter what you bought and its rate: the real cost of each sellable kg and the profit show at once. '
                        'Every number is your own.',
                key: const Key('askodoxYieldEmpty')),
          ),
        )
      else
        _rateCard(te, book, last, onTap: () => _open(last, last.outGrams <= 0 ? 2 : 3)),
      if (last != null && last.cost != null)
        AskodoxYieldExtras(businessId: widget.businessId, item: _item, cost: last.cost!, sell: last.sellPaise),
      if (yields.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(te ? 'మీ గత యీల్డ్ % (మీ స్వంత రికార్డ్)' : 'Your last yields % (your own record)',
            style: const TextStyle(color: AskodoxLook.muted)),
        Wrap(spacing: 8, children: [
          for (final y in yields) Chip(label: Text(askodoxYieldPercent(y))),
        ]),
      ],
      _next('askodoxYieldNew', te ? 'కొత్త సరుకు వచ్చింది' : 'New lot came in', _newLot),
      const SizedBox(height: 8),
      OutlinedButton(
        key: const Key('askodoxYieldDayEnd'),
        onPressed: last == null ? null : _openDay,
        child: Text(te ? 'రోజు ముగింపు · స్టాక్ + లాభం' : 'Day end · stock + profit'),
      ),
      OutlinedButton.icon(
        key: const Key('askodoxYieldWeekly'),
        onPressed: () => context.push('/weekly'),
        icon: const Icon(Icons.bar_chart_rounded),
        label: Text(te ? 'ఈ వారం రిపోర్ట్' : 'This week'),
      ),
      OutlinedButton.icon(
        key: const Key('askodoxYieldTrend'),
        onPressed: () => context.push('/trend'),
        icon: const Icon(Icons.show_chart_rounded),
        label: Text(te ? 'రేటు ట్రెండ్' : 'Rate trend'),
      ),
      AskodoxClosingRow(businessId: widget.businessId),
      if (lots.length > 1) ...[
        const SizedBox(height: 12),
        Text(te ? 'రేటు ట్రెండ్ (గత సరుకులు)' : 'Rate trend (last lots)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        for (final b in lots)
          ListTile(
            key: ValueKey('askodoxYieldLot-${b.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            onTap: () => _open(b, b.outGrams <= 0 ? 2 : 3),
            title: Text('${b.day.substring(8)}-${b.day.substring(5, 7)} · ${te ? 'కొన్న' : 'buy'} ${askodoxYieldRupees(b.ratePaise)}'),
            subtitle: Text(b.cost == null
                ? (te ? 'తూకం వేయాలి' : 'To be weighed')
                : '${te ? 'ఖర్చు' : 'cost'} ${askodoxYieldRupees(b.cost!)} · ${te ? 'అమ్మే' : 'sell'} ${askodoxYieldRupees(b.sellPaise)}'),
            trailing: b.cost == null || b.sellPaise <= 0
                ? null
                : Text(askodoxYieldRupees(b.sellPaise - b.cost!),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: b.sellPaise >= b.cost! ? AskodoxLook.good : AskodoxLook.accentText)),
          ),
      ],
    ];
  }

  Widget _rateCard(bool te, AskodoxYieldBook book, AskodoxYieldBatch b, {VoidCallback? onTap}) {
    final cost = b.cost;
    final gain = cost == null || b.sellPaise <= 0 ? null : askodoxYieldProfit(b.sellPaise, cost);
    final min = book.minProfit[b.item] ?? 0;
    final low = gain != null && min > 0 && gain.profit < min;
    final rise = b.yieldBp == null ? null : askodoxYieldRiseEffect(200, b.yieldBp!);
    return Card(
      key: const Key('askodoxYieldBoard'),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${askodoxYieldItemName(b.item, te)} · ${te ? 'రేట్ బోర్డ్' : 'rate board'}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            _line(te ? 'కొన్న రేటు (కిలో)' : 'Bought at (a kg)', askodoxYieldRupees(b.ratePaise), keyName: 'askodoxYieldBoardBuy'),
            _line(te ? 'మొత్తం కొనుగోలు ఖర్చు' : 'Everything spent', askodoxYieldRupees(b.total), keyName: 'askodoxYieldBoardTotal'),
            if (b.yieldBp != null)
              _line(te ? 'యీల్డ్' : 'Yield', askodoxYieldPercent(b.yieldBp!), keyName: 'askodoxYieldBoardYield'),
            _line(te ? 'అమ్మే కిలో అసలు ఖర్చు' : 'Real cost of a sellable kg',
                cost == null ? (te ? 'తూకం వేయాలి' : 'To be weighed') : askodoxYieldRupees(cost),
                keyName: 'askodoxYieldBoardCost', strong: true),
            if (b.sellPaise > 0) _line(te ? 'అమ్మే రేటు' : 'Selling rate', askodoxYieldRupees(b.sellPaise)),
            if (gain != null)
              _line(te ? 'కిలోకి లాభం' : 'Profit a kg',
                  '${askodoxYieldRupees(gain.profit)}${gain.marginBp == null ? '' : ' · ${askodoxYieldPercent(gain.marginBp!)}'}',
                  keyName: 'askodoxYieldBoardProfit', strong: true, color: gain.profit >= 0 ? AskodoxLook.good : AskodoxLook.accentText),
            if (low)
              Text(
                  te
                      ? 'మీరు పెట్టుకున్న కనిష్ట లాభం ${askodoxYieldRupees(min)} కంటే తక్కువ వస్తోంది.'
                      : 'This is under the least profit you set (${askodoxYieldRupees(min)}).',
                  key: const Key('askodoxYieldBoardLow'),
                  style: const TextStyle(color: AskodoxLook.accentText, fontWeight: FontWeight.w700)),
            if (rise != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    te
                        ? 'కొన్న రేటు ₹2 పెరిగితే: అమ్మే కిలో ఖర్చు సుమారు ${askodoxYieldRupees(rise)} పెరుగుతుంది.'
                        : 'If the buying rate goes up ₹2: a sellable kg costs about ${askodoxYieldRupees(rise)} more.',
                    key: const Key('askodoxYieldBoardRise'),
                    style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted)),
              ),
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------------------------------------ 3 steps
  List<Widget> _bought(bool te) {
    final d = _draft();
    final ready = d.liveGrams > 0 && d.ratePaise > 0;
    return [
      Text('${askodoxYieldItemName(_item, te)} · ${te ? 'మీ సంఖ్యలు మీరే రాయండి' : 'enter your own numbers'}',
          style: const TextStyle(color: AskodoxLook.muted)),
      const SizedBox(height: 10),
      _field('askodoxYieldLive', _live, te ? 'కొన్న మొత్తం బరువు' : 'Weight bought', suffix: 'kg'),
      _field('askodoxYieldRate', _rate, te ? 'కొన్న రేటు (కిలోకి)' : 'Rate (a kg)', suffix: '₹'),
      _field('askodoxYieldCount', _count, te ? 'సంఖ్య (ఐచ్ఛికం)' : 'Count (optional)'),
      _field('askodoxYieldTransport', _transport, te ? 'రవాణా' : 'Transport', suffix: '₹'),
      _field('askodoxYieldLabour', _labour, te ? 'దించే కూలి' : 'Unloading', suffix: '₹'),
      _line(te ? 'మొత్తం కొనుగోలు ఖర్చు' : 'Everything spent', askodoxYieldRupees(d.total), keyName: 'askodoxYieldTotal', strong: true),
      _next('askodoxYieldNext1', te ? 'సేవ్ చేసి తూకానికి వెళ్ళు' : 'Save and go to weighing', !ready
          ? null
          : () async {
              await _save(done: false);
              if (mounted) setState(() => _step = 2);
            }),
    ];
  }

  List<Widget> _after(bool te) {
    final d = _draft();
    final y = d.yieldBp;
    return [
      _line(te ? 'కొన్నది' : 'Bought', '${askodoxYieldKg(d.liveGrams)} kg'),
      const SizedBox(height: 6),
      _field('askodoxYieldOut', _out, te ? 'అమ్మడానికి వచ్చింది (తూకం)' : 'Came out to sell (weighed)', suffix: 'kg'),
      // Fixed places (an empty box until there is a number): a row appearing must never move the boxes under it.
      y == null
          ? const SizedBox.shrink()
          : _line(te ? 'యీల్డ్' : 'Yield', askodoxYieldPercent(y), keyName: 'askodoxYieldPercent', strong: true),
      y == null
          ? const SizedBox.shrink()
          : _line(te ? 'తగ్గింది' : 'Went down by', '${askodoxYieldKg(d.liveGrams - d.outGrams)} kg', keyName: 'askodoxYieldLost'),
      _field('askodoxYieldBy', _by, te ? 'ఇతర భాగాలు అమ్మిన ఆదాయం (ఐచ్ఛికం)' : 'Income from by-products (optional)', suffix: '₹'),
      _line(te ? 'అమ్మే కిలో అసలు ఖర్చు' : 'Real cost of a sellable kg', d.cost == null ? '—' : askodoxYieldRupees(d.cost!),
          keyName: 'askodoxYieldCost', strong: true),
      _next('askodoxYieldNext2', te ? 'రేటుకి వెళ్ళు' : 'Go to the rate', d.cost == null
          ? null
          : () async {
              await _save(done: false);
              if (mounted) setState(() => _step = 3);
            }),
      TextButton(
        key: const Key('askodoxYieldLater'),
        onPressed: () async {
          _out.clear();
          await _save(done: true);
        },
        child: Text(te ? 'తూకం తర్వాత వేస్తా' : 'I will weigh later'),
      ),
    ];
  }

  List<Widget> _rateStep(bool te, AskodoxYieldBook book) {
    final d = _draft();
    final cost = d.cost;
    final gain = cost == null || d.sellPaise <= 0 ? null : askodoxYieldProfit(d.sellPaise, cost);
    final min = askodoxYieldParsePaise(_min.text);
    return [
      _line(te ? 'అమ్మే కిలో అసలు ఖర్చు' : 'Real cost of a sellable kg', cost == null ? '—' : askodoxYieldRupees(cost), strong: true),
      const SizedBox(height: 6),
      _field('askodoxYieldSell', _sell, te ? 'మీ అమ్మే రేటు (కిలోకి)' : 'Your selling rate (a kg)', suffix: '₹'),
      _field('askodoxYieldMin', _min, te ? 'మీ కనిష్ట లాభం (కిలోకి, మీరే పెట్టుకోండి)' : 'Your least profit (a kg, you set it)',
          suffix: '₹'),
      if (gain != null)
        _line(te ? 'కిలోకి లాభం' : 'Profit a kg',
            '${askodoxYieldRupees(gain.profit)}${gain.marginBp == null ? '' : ' · ${askodoxYieldPercent(gain.marginBp!)}'}',
            keyName: 'askodoxYieldProfit', strong: true, color: gain.profit >= 0 ? AskodoxLook.good : AskodoxLook.accentText),
      if (gain != null && min > 0 && gain.profit < min)
        Text(te ? 'మీరు పెట్టుకున్న కనిష్ట లాభం కంటే తక్కువ.' : 'Under the least profit you set.',
            key: const Key('askodoxYieldLow'), style: const TextStyle(color: AskodoxLook.accentText, fontWeight: FontWeight.w700)),
      _next('askodoxYieldSave', te ? 'సేవ్ చేయి' : 'Save', d.sellPaise <= 0 ? null : () => _save(done: true)),
    ];
  }

  // ------------------------------------------------------------------------------------------------ day end
  List<Widget> _dayEnd(bool te) {
    final d = _dayDraft();
    final value = askodoxYieldDiffValue(d.diff, d.costPaise);
    final money = askodoxYieldDayProfit(d.soldGrams, d.sellPaise, d.costPaise, d.otherPaise);
    final weighed = _actual.text.trim().isNotEmpty;
    const reasons = [('weight', 'Weight went down', 'తూకం తగ్గింది'), ('free', 'Given free', 'ఉచితంగా ఇచ్చాం'), ('unknown', 'To be found', 'తెలుసుకోవాలి')];
    return [
      Text('${askodoxYieldItemName(_item, te)} · ${te ? 'స్టాక్ లెక్క (kg)' : 'stock (kg)'}',
          style: const TextStyle(color: AskodoxLook.muted)),
      const SizedBox(height: 10),
      _field('askodoxYieldOpening', _opening, te ? 'ఉదయం స్టాక్' : 'Morning stock', suffix: 'kg'),
      _line(te ? '+ ఈ రోజు వచ్చింది' : '+ came today', askodoxYieldKg(d.madeGrams), keyName: 'askodoxYieldMade'),
      _field('askodoxYieldSold', _sold, te ? 'అమ్మింది' : 'Sold', suffix: 'kg'),
      _line(te ? '= ఉండాల్సింది' : '= should be there', askodoxYieldKg(d.expected), keyName: 'askodoxYieldExpected', strong: true),
      _field('askodoxYieldActual', _actual, te ? 'నిజంగా ఉంది (తూకం)' : 'Really there (weighed)', suffix: 'kg'),
      // Fixed places, as above: the boxes under these rows keep their place (and their keyboard) while typing.
      !weighed
          ? const SizedBox.shrink()
          : _line(te ? 'తేడా' : 'Difference', '${askodoxYieldKg(d.diff)} kg ≈ ${askodoxYieldRupees(value)}',
              keyName: 'askodoxYieldDiff', strong: true, color: d.diff == 0 ? AskodoxLook.good : AskodoxLook.accentText),
      !weighed || d.diff == 0
          ? const SizedBox.shrink()
          : Wrap(spacing: 8, children: [
              for (final r in reasons)
                ChoiceChip(
                  key: ValueKey('askodoxYieldReason-${r.$1}'),
                  label: Text(te ? r.$3 : r.$2),
                  selected: _reason == r.$1,
                  onSelected: (_) => setState(() => _reason = r.$1),
                ),
            ]),
      OutlinedButton.icon(
        key: const Key('askodoxYieldStockPhoto'),
        icon: Icon(_photoName.isNotEmpty || _photoBytes != null ? Icons.check_circle_outline : Icons.photo_camera_outlined),
        label: Text(_photoName.isNotEmpty || _photoBytes != null
            ? (te ? 'స్టాక్ ఫోటో సేవ్ అవుతుంది (ఫోన్‌లోనే)' : 'Stock photo will be kept (on this phone)')
            : (te ? 'స్టాక్ ఫోటో తీయండి' : 'Take a stock photo')),
        onPressed: _takeStockPhoto,
      ),
      const Divider(height: 28),
      _field('askodoxYieldOther', _other, te ? 'ఇతర ఖర్చులు (కరెంట్, కూలి…)' : 'Other costs (power, wages…)', suffix: '₹'),
      _line(te ? 'అమ్మకం' : 'Sales', askodoxYieldRupees(money.sales), keyName: 'askodoxYieldSales'),
      _line(te ? '− అసలు ఖర్చు' : '− cost of what was sold', askodoxYieldRupees(money.spent), keyName: 'askodoxYieldSpent'),
      _line(te ? 'ఈ రోజు లాభం (ఉజ్జాయింపు)' : 'Profit today (rough)', askodoxYieldRupees(money.profit),
          keyName: 'askodoxYieldDayProfit', strong: true, color: money.profit >= 0 ? AskodoxLook.good : AskodoxLook.accentText),
      _next('askodoxYieldDaySave', te ? 'సేవ్ చేయి' : 'Save', () async {
        var day = d;
        final bytes = _photoBytes;
        if (bytes != null) {
          final name = await ref.read(askodoxVaultFilesProvider).save('stock-${widget.businessId}-${d.item.hashCode.abs()}-${d.day}', bytes);
          if (name.isNotEmpty) {
            day = AskodoxYieldDay(
                item: d.item, day: d.day, openingGrams: d.openingGrams, madeGrams: d.madeGrams, soldGrams: d.soldGrams,
                actualGrams: d.actualGrams, otherPaise: d.otherPaise, costPaise: d.costPaise, sellPaise: d.sellPaise,
                reason: d.reason, photo: name);
          }
        }
        await ref.read(askodoxYieldProvider.notifier).saveDay(widget.businessId, day);
        if (mounted) setState(() => _step = 0);
      }),
    ];
  }
}
