import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme/askodox_look.dart';
import '../../shared/widgets/estimate_note.dart';
import '../home/presentation/question_mic.dart';
import 'closing_alert.dart';
import 'live_stock.dart';
import 'yield_math.dart';
import 'yield_store.dart';

/// Stock setup in 3 steps (owner 2026-11-28, design "చికెన్ స్టాక్ సెటప్"): 1 item + stock now (typed or spoken),
/// 2 how it is measured (per kg in a shop / by recipe in a hotel) + the selling rate, 3 closing time + who is told.
/// It only fills the pages that already exist (live stock, closing time); every number is the owner's own entry and
/// stays on this phone (`askodox.stocksetup.v1`, per shop). Not built: stock from a bill photo, alerts to staff / manager.
const askodoxStockSetupPrefsKey = 'askodox.stocksetup.v1';

class AskodoxStockSetup {
  const AskodoxStockSetup({this.item = 'chicken', this.recipe = false, this.sellPaise = 0, this.done = false});
  final String item;
  final bool recipe;
  final int sellPaise;
  final bool done;

  AskodoxStockSetup copy({String? item, bool? recipe, int? sellPaise, bool? done}) => AskodoxStockSetup(
      item: item ?? this.item, recipe: recipe ?? this.recipe, sellPaise: sellPaise ?? this.sellPaise, done: done ?? this.done);

  Map<String, Object> toJson() => {'i': item, 'r': recipe, 's': sellPaise, 'd': done};

  static AskodoxStockSetup fromJson(Object? j) {
    if (j is! Map) return const AskodoxStockSetup();
    final i = '${j['i'] ?? ''}'.trim();
    final s = j['s'];
    return AskodoxStockSetup(
        item: i.isEmpty || i.length > 40 ? 'chicken' : i, recipe: j['r'] == true, sellPaise: s is int && s > 0 ? s : 0, done: j['d'] == true);
  }
}

class AskodoxStockSetupController extends StateNotifier<Map<String, AskodoxStockSetup>> {
  AskodoxStockSetupController() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(askodoxStockSetupPrefsKey);
      if (raw == null || !mounted) return;
      final j = jsonDecode(raw);
      if (j is Map) state = {for (final e in j.entries) '${e.key}': AskodoxStockSetup.fromJson(e.value)};
    } catch (_) {}
  }

  AskodoxStockSetup of(String shop) => state[shop] ?? const AskodoxStockSetup();

  Future<void> put(String shop, AskodoxStockSetup v) async {
    state = {...state, shop: v};
    try {
      await (await SharedPreferences.getInstance())
          .setString(askodoxStockSetupPrefsKey, jsonEncode({for (final e in state.entries) e.key: e.value.toJson()}));
    } catch (_) {}
  }
}

final askodoxStockSetupProvider =
    StateNotifierProvider<AskodoxStockSetupController, Map<String, AskodoxStockSetup>>((ref) => AskodoxStockSetupController());

class AskodoxStockSetupScreen extends ConsumerStatefulWidget {
  const AskodoxStockSetupScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxStockSetupScreen> createState() => _AskodoxStockSetupScreenState();
}

class _AskodoxStockSetupScreenState extends ConsumerState<AskodoxStockSetupScreen> {
  int _step = 0;
  String _item = 'chicken';
  bool _recipe = false;
  final _stock = TextEditingController();
  final _rate = TextEditingController();
  final _other = TextEditingController();
  String _time = '22:30';

  @override
  void dispose() {
    _stock.dispose();
    _rate.dispose();
    _other.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final today = askodoxYieldDayKey(ref.read(askodoxYieldClockProvider)());
    final grams = askodoxYieldParseGrams(_stock.text.replaceAll(',', '.'));
    final rupees = double.tryParse(_rate.text.replaceAll(',', '.')) ?? 0;
    final item = _item.trim();
    if (item.isEmpty) return;
    await ref.read(askodoxStockSetupProvider.notifier).put(
        widget.businessId, AskodoxStockSetup(item: item, recipe: _recipe, sellPaise: (rupees * 100).round(), done: true));
    if (grams > 0) await ref.read(askodoxLiveStockProvider.notifier).setMorning(widget.businessId, item, today, grams);
    await ref.read(askodoxClosingProvider.notifier).set(widget.businessId, _time);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final titles = te ? ['ఐటమ్ + ఇప్పటి స్టాక్', 'కొలత', 'క్లోజింగ్ టైమ్ + అలర్ట్'] : ['Item + stock now', 'Measure', 'Closing time + alert'];
    final isOwn = !askodoxYieldItems.any((r) => r.$1 == _item);
    return Scaffold(
      key: const Key('askodoxStockSetup'),
      appBar: AppBar(title: Text(te ? 'స్టాక్ సెటప్' : 'Stock setup')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          Text(te ? '3 స్టెప్స్ · ${_step + 1}వ స్టెప్' : '3 steps · step ${_step + 1}', style: const TextStyle(color: AskodoxLook.muted)),
          const SizedBox(height: 4),
          Text(titles[_step], key: const Key('askodoxStockSetupTitle'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (_step == 0) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in askodoxYieldItems)
                ChoiceChip(
                    key: ValueKey('askodoxSetupItem-${r.$1}'),
                    label: Text(te ? r.$3 : r.$2),
                    selected: _item == r.$1,
                    onSelected: (_) => setState(() => _item = r.$1)),
              ChoiceChip(
                  key: const Key('askodoxSetupItemOther'),
                  label: Text(te ? '+ ఇతర' : '+ Other'),
                  selected: isOwn,
                  onSelected: (_) => setState(() => _item = _other.text.trim().isEmpty ? ' ' : _other.text.trim())),
            ]),
            if (isOwn)
              TextField(
                  key: const Key('askodoxSetupOtherName'),
                  controller: _other,
                  decoration: InputDecoration(labelText: te ? 'ఐటమ్ పేరు' : 'Item name'),
                  onChanged: (t) => setState(() => _item = t.trim().isEmpty ? ' ' : t.trim())),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                    key: const Key('askodoxSetupStock'),
                    controller: _stock,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: te ? 'ఇప్పుడు ఉంది' : 'In stock now', suffixText: 'kg')),
              ),
              AskodoxQuestionMic(
                  key: const Key('askodoxSetupStockMic'),
                  lang: te ? 'te' : 'en',
                  followCentre: false,
                  always: true,
                  onText: (w) {
                    final g = askodoxLiveStockGrams(w);
                    if (g > 0) setState(() => _stock.text = askodoxYieldKg(g));
                  }),
            ]),
          ] else if (_step == 1) ...[
            SegmentedButton<bool>(
              key: const Key('askodoxSetupMeasure'),
              segments: [
                ButtonSegment(value: false, label: Text(te ? 'కేజీ రేటు (షాప్)' : 'Per kg (shop)')),
                ButtonSegment(value: true, label: Text(te ? 'రెసిపీ (హోటల్)' : 'Recipe (hotel)')),
              ],
              selected: {_recipe},
              onSelectionChanged: (s) => setState(() => _recipe = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
                key: const Key('askodoxSetupRate'),
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: te ? 'అమ్మకం రేటు' : 'Selling rate', prefixText: '₹ ', suffixText: _recipe ? '' : '/ kg')),
            if (_recipe)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(te ? 'ప్లేట్ గ్రాములు యీల్డ్ పేజీలోని కొలత కార్డ్‌లో పెట్టండి.' : 'Put the plate grams on the measure card of the Yield page.',
                    key: const Key('askodoxSetupRecipeNote'), style: const TextStyle(color: AskodoxLook.muted)),
              ),
          ] else ...[
            ListTile(
              key: const Key('askodoxSetupTime'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alarm_outlined),
              title: Text(te ? 'క్లోజింగ్ టైమ్' : 'Closing time'),
              subtitle: Text(_time),
              onTap: () async {
                final cur = askodoxClosingParse(_time);
                final p = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur?.hour ?? 22, minute: cur?.minute ?? 30));
                if (p != null) setState(() => _time = askodoxClosingText(p.hour, p.minute));
              },
            ),
            Text(te ? 'ఆ టైమ్‌కి స్టాక్ ఫోటో అడుగుతాం.' : 'At that time we ask for a stock photo.', style: const TextStyle(color: AskodoxLook.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(te ? 'అలర్ట్ ఎవరికి:' : 'Alert to:'),
              FilterChip(key: const Key('askodoxSetupAlertOwner'), label: Text(te ? 'ఓనర్' : 'Owner'), selected: true, onSelected: (_) {}),
            ]),
            const SizedBox(height: 6),
            Text(
                te
                    ? 'స్టాఫ్ / మేనేజర్‌కి అలర్ట్: మీ అభ్యర్థన నోట్ చేసుకున్నాం, త్వరలోనే మిమ్మల్ని సంప్రదిస్తాం, అప్‌డేట్ చేసి మీకు ఇస్తాం.'
                    : 'Alert to staff / manager: we noted your request, will contact you soon and update the app for it.',
                key: const Key('askodoxSetupAlertNote'),
                style: const TextStyle(color: AskodoxLook.muted)),
          ],
          const SizedBox(height: 20),
          Row(children: [
            if (_step > 0)
              TextButton(key: const Key('askodoxSetupBack'), onPressed: () => setState(() => _step--), child: Text(te ? 'వెనక్కి' : 'Back')),
            const Spacer(),
            FilledButton(
              key: const Key('askodoxSetupNext'),
              onPressed: _step < 2 ? () => setState(() => _step++) : _finish,
              child: Text(_step < 2 ? (te ? 'తర్వాత' : 'Next') : (te ? 'సెటప్ పూర్తి చేయి' : 'Finish setup')),
            ),
          ]),
          const SizedBox(height: 6),
          Text(te ? 'తర్వాత ఎప్పుడైనా మార్చుకోవచ్చు' : 'You can change this any time', style: const TextStyle(color: AskodoxLook.muted)),
          const SizedBox(height: 8),
          const AskodoxEstimateNote(),
        ]),
      ),
    );
  }
}
