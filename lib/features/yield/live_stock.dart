import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme/askodox_look.dart';
import '../../shared/widgets/estimate_note.dart';
import '../home/presentation/question_mic.dart';
import 'yield_math.dart';
import 'yield_store.dart';

/// Today's live stock (owner 2026-11-27, design "ఇవాళ లైవ్ స్టాక్"): the owner says what came this morning, then adds each
/// sale as it happens (typed or spoken); the stock that should be in the shop is worked out at once, and a line says when
/// it falls under the level HE set. Everything is his own entry, kept on this phone per shop and item; nothing is sent.
/// Not built: sales read from bills / UPI payments / a photo, and a push when the stock is low.
const askodoxLiveStockPrefsKey = 'askodox.livestock.v1';
const askodoxLiveStockKeep = 200;

class AskodoxLiveStockItem {
  const AskodoxLiveStockItem({this.day = '', this.morning = 0, this.sales = const [], this.minGrams = 0});
  final String day;
  final int morning, minGrams;
  final List<int> sales;

  int get sold => sales.fold(0, (a, b) => a + b);
  int get left => morning - sold;
  bool get low => minGrams > 0 && morning > 0 && left < minGrams;

  /// The same item as it stands on [today]: a new day starts with no morning stock and no sales, the level stays.
  AskodoxLiveStockItem on(String today) => day == today ? this : AskodoxLiveStockItem(day: today, minGrams: minGrams);

  AskodoxLiveStockItem copy({String? day, int? morning, List<int>? sales, int? minGrams}) => AskodoxLiveStockItem(
      day: day ?? this.day, morning: morning ?? this.morning, sales: sales ?? this.sales, minGrams: minGrams ?? this.minGrams);

  Map<String, Object?> toJson() => {'d': day, 'm': morning, 's': sales, 'n': minGrams};

  static AskodoxLiveStockItem fromJson(Object? j) {
    if (j is! Map) return const AskodoxLiveStockItem();
    int n(Object? v) => v is int && v >= 0 ? v : 0;
    return AskodoxLiveStockItem(
      day: '${j['d'] ?? ''}',
      morning: n(j['m']),
      sales: [if (j['s'] is List) for (final v in j['s'] as List) if (v is int && v > 0) v],
      minGrams: n(j['n']),
    );
  }
}

/// The first number in spoken or typed words, as grams of a kg amount ("అర" / "half" = 0.5 kg).
int askodoxLiveStockGrams(String words) {
  final w = words.toLowerCase();
  final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(w);
  if (m != null) return askodoxYieldParseGrams(m.group(0)!.replaceAll(',', '.'));
  if (w.contains('half') || w.contains('అర')) return 500;
  return 0;
}

class AskodoxLiveStockController extends StateNotifier<Map<String, Map<String, AskodoxLiveStockItem>>> {
  AskodoxLiveStockController() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(askodoxLiveStockPrefsKey);
      if (raw == null || !mounted) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      state = {
        for (final s in j.entries)
          if (s.value is Map) '${s.key}': {for (final i in (s.value as Map).entries) '${i.key}': AskodoxLiveStockItem.fromJson(i.value)}
      };
    } catch (_) {
      // Starts empty.
    }
  }

  AskodoxLiveStockItem of(String shop, String item, String today) => (state[shop]?[item] ?? const AskodoxLiveStockItem()).on(today);

  Future<void> _put(String shop, String item, AskodoxLiveStockItem v) async {
    state = {
      ...state,
      shop: {...?state[shop], item: v}
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          askodoxLiveStockPrefsKey, jsonEncode({for (final s in state.entries) s.key: {for (final i in s.value.entries) i.key: i.value.toJson()}}));
    } catch (_) {
      // Stays on screen; saved with the next change.
    }
  }

  Future<void> setMorning(String shop, String item, String today, int grams) async =>
      _put(shop, item, of(shop, item, today).copy(morning: grams < 0 ? 0 : grams));

  Future<void> addSale(String shop, String item, String today, int grams) async {
    if (grams <= 0) return;
    final cur = of(shop, item, today);
    final all = [...cur.sales, grams];
    await _put(shop, item, cur.copy(sales: all.length > askodoxLiveStockKeep ? all.sublist(all.length - askodoxLiveStockKeep) : all));
  }

  Future<void> undoSale(String shop, String item, String today) async {
    final cur = of(shop, item, today);
    if (cur.sales.isEmpty) return;
    await _put(shop, item, cur.copy(sales: cur.sales.sublist(0, cur.sales.length - 1)));
  }

  Future<void> setMin(String shop, String item, String today, int grams) async =>
      _put(shop, item, of(shop, item, today).copy(minGrams: grams < 0 ? 0 : grams));
}

final askodoxLiveStockProvider =
    StateNotifierProvider<AskodoxLiveStockController, Map<String, Map<String, AskodoxLiveStockItem>>>((ref) => AskodoxLiveStockController());

class AskodoxLiveStockScreen extends ConsumerStatefulWidget {
  const AskodoxLiveStockScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxLiveStockScreen> createState() => _AskodoxLiveStockScreenState();
}

class _AskodoxLiveStockScreenState extends ConsumerState<AskodoxLiveStockScreen> {
  String? _item;
  final _morning = TextEditingController();
  final _sale = TextEditingController();
  final _min = TextEditingController();
  String _shown = '';

  @override
  void dispose() {
    _morning.dispose();
    _sale.dispose();
    _min.dispose();
    super.dispose();
  }

  String _plain(int grams) => grams == 0 ? '' : askodoxYieldKg(grams);

  void _fill(String key, AskodoxLiveStockItem v) {
    if (_shown == key) return;
    _shown = key;
    _morning.text = _plain(v.morning);
    _min.text = _plain(v.minGrams);
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final yieldState = ref.watch(askodoxYieldProvider);
    final stock = ref.watch(askodoxLiveStockProvider);
    final today = askodoxYieldDayKey(ref.watch(askodoxYieldClockProvider)());
    final book = yieldState.book(widget.businessId);
    final items = <String>{
      for (final b in book.batches) b.item,
      for (final d in book.days) d.item,
      ...?stock[widget.businessId]?.keys,
    }.toList();
    final item = _item != null && items.contains(_item) ? _item! : (items.isEmpty ? '' : items.first);
    final ctl = ref.read(askodoxLiveStockProvider.notifier);
    final v = item.isEmpty ? const AskodoxLiveStockItem() : ctl.of(widget.businessId, item, today);
    _fill('$item|$today', v);
    return Scaffold(
      key: const Key('askodoxLiveStock'),
      appBar: AppBar(title: Text(te ? 'ఇవాళ లైవ్ స్టాక్' : "Today's live stock")),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          if (items.isEmpty)
            Text(
                te
                    ? 'యీల్డ్ & రేట్లు పేజీలో సరుకు రాస్తే, ఇక్కడ ఇవాళ స్టాక్ లెక్క కనిపిస్తుంది.'
                    : 'Once you enter a lot on the Yield & rates page, today\'s stock shows here.',
                key: const Key('askodoxLiveEmpty'))
          else ...[
            Wrap(spacing: 8, children: [
              for (final name in items)
                ChoiceChip(
                    key: ValueKey('askodoxLiveItem-$name'),
                    label: Text(askodoxYieldItemName(name, te)),
                    selected: item == name,
                    onSelected: (_) => setState(() {
                          _item = name;
                          _shown = '';
                        })),
            ]),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${te ? 'ఉదయం వచ్చింది' : 'Came this morning'}: ${askodoxYieldKg(v.morning)} kg   ·   ${te ? 'అమ్మింది' : 'Sold'}: ${askodoxYieldKg(v.sold)} kg',
                      key: const Key('askodoxLiveSummary'), style: const TextStyle(color: AskodoxLook.muted)),
                  const SizedBox(height: 6),
                  Text(te ? 'ఇప్పుడు షాప్‌లో ఉండాల్సింది' : 'Should be in the shop now'),
                  Text('${askodoxYieldKg(v.left)} kg',
                      key: const Key('askodoxLiveLeft'),
                      style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          fontFeatures: AskodoxLook.figures,
                          color: v.low || v.left < 0 ? AskodoxLook.accentText : AskodoxLook.good)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                      value: v.morning <= 0 ? 0 : (v.left / v.morning).clamp(0.0, 1.0), minHeight: 10, borderRadius: BorderRadius.circular(6)),
                  if (v.low)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(te ? 'మీరు పెట్టిన ${askodoxYieldKg(v.minGrams)} kg కంటే తక్కువ అయింది, ఆర్డర్ చేయండి.' : 'Under the ${askodoxYieldKg(v.minGrams)} kg you set: time to order.',
                          key: const Key('askodoxLiveLow'), style: const TextStyle(fontWeight: FontWeight.w800, color: AskodoxLook.accentText)),
                    ),
                ]),
              ),
            ),
            TextField(
              key: const Key('askodoxLiveMorning'),
              controller: _morning,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: te ? 'ఉదయం వచ్చిన సరుకు' : 'Came this morning', suffixText: 'kg'),
              onChanged: (t) => ctl.setMorning(widget.businessId, item, today, askodoxYieldParseGrams(t)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('askodoxLiveSale'),
                  controller: _sale,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: te ? 'ఇప్పుడు అమ్మింది' : 'Just sold', suffixText: 'kg'),
                ),
              ),
              AskodoxQuestionMic(
                  key: const Key('askodoxLiveMic'),
                  lang: te ? 'te' : 'en',
                  followCentre: false,
                  always: true,
                  onText: (w) {
                    final g = askodoxLiveStockGrams(w);
                    if (g > 0) ctl.addSale(widget.businessId, item, today, g);
                  }),
            ]),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('askodoxLiveAdd'),
              onPressed: () async {
                final g = askodoxYieldParseGrams(_sale.text);
                if (g <= 0) return;
                await ctl.addSale(widget.businessId, item, today, g);
                _sale.clear();
              },
              child: Text(te ? 'అమ్మకం రాయి' : 'Add the sale'),
            ),
            if (v.sales.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    key: const Key('askodoxLiveUndo'),
                    onPressed: () => ctl.undoSale(widget.businessId, item, today),
                    child: Text(te ? 'చివరిది తీసేయి (${askodoxYieldKg(v.sales.last)} kg)' : 'Undo last (${askodoxYieldKg(v.sales.last)} kg)')),
              ),
            for (var i = v.sales.length - 1; i >= 0 && i >= v.sales.length - 5; i--)
              ListTile(dense: true, title: Text('−${askodoxYieldKg(v.sales[i])} kg', key: ValueKey('askodoxLiveRow-$i'))),
            const SizedBox(height: 8),
            TextField(
              key: const Key('askodoxLiveMin'),
              controller: _min,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: te ? 'ఇంతకంటే తక్కువైతే చెప్పు' : 'Tell me when it falls under', suffixText: 'kg'),
              onChanged: (t) => ctl.setMin(widget.businessId, item, today, askodoxYieldParseGrams(t)),
            ),
          ],
          const SizedBox(height: 12),
          const AskodoxEstimateNote(),
        ]),
      ),
    );
  }
}
