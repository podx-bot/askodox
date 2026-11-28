import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme/askodox_look.dart';
import '../../shared/widgets/estimate_note.dart';
import '../home/application/conversation_archive.dart' show AskodoxChatRequest, askodoxChatRequestProvider;
import '../home/presentation/question_mic.dart';
import '../pos/data/pos_repository.dart';

/// "Tell us about your business" (owner 2026-11-27, design "మీ బిజినెస్ గురించి చెప్పండి"): three questions answered by
/// voice or typing; the words are mapped onto five boxes (business, branches, supplier, bills, biggest headache) and
/// shown as chips the person can remove. Only the person's own words become chips -- nothing is guessed. Kept on this
/// phone only (`askodox.bizstory.v1`, account-scoped).
const askodoxBusinessStoryPrefsKey = 'askodox.bizstory.v1';

class AskodoxStoryQuestion {
  const AskodoxStoryQuestion(this.en, this.te);
  final String en, te;
}

const askodoxStoryQuestions = <AskodoxStoryQuestion>[
  AskodoxStoryQuestion('What is your business? What do you sell?', 'మీది ఏ బిజినెస్? ఏం అమ్ముతారు?'),
  AskodoxStoryQuestion('Where does your stock come from? Do you give GST bills?', 'సరుకు ఎక్కడి నుంచి తెస్తారు? GST బిల్ ఇస్తారా?'),
  AskodoxStoryQuestion('What is the biggest headache in your business?', 'మీ బిజినెస్‌లో పెద్ద తలనొప్పి ఏంటి?'),
];

/// The five boxes the words are mapped onto, in the order the chips show.
const askodoxStoryKeys = ['type', 'branches', 'supplier', 'bills', 'problem'];

/// The kinds of work the person can tap on the "who are you" page (design "మీ రకం ఎంచుకోండి"): id, English, Telugu.
/// More than one may be picked; a kind that is not here is told by voice and noted (never guessed).
const askodoxStoryKinds = <(String, String, String)>[
  ('home', 'Home / kitchen', 'ఇల్లు / వంటగది'),
  ('grocery', 'Grocery shop', 'కిరాణా షాప్'),
  ('hotel', 'Hotel / tiffin', 'హోటల్ / టిఫిన్'),
  ('meat', 'Chicken / mutton shop', 'చికెన్ / మటన్ షాప్'),
  ('cloth', 'Cloth shop', 'బట్టల షాప్'),
  ('salon', 'Salon / parlour', 'సెలూన్ / పార్లర్'),
  ('medical', 'Medical shop', 'మెడికల్ షాప్'),
  ('farm', 'Farmer / farm', 'రైతు / పొలం'),
  ('factory', 'Factory / making', 'ఫ్యాక్టరీ / తయారీ'),
  ('service', 'Service (mechanic etc.)', 'సర్వీస్ (మెకానిక్ మొ.)'),
  ('online', 'Online selling', 'ఆన్‌లైన్ అమ్మకం'),
  ('school', 'School / tuition', 'విద్య / ట్యూషన్'),
];

class AskodoxStory {
  const AskodoxStory({this.answers = const [], this.chips = const {}, this.picks = const []});
  final List<String> answers;
  final Map<String, String> chips;
  final List<String> picks;

  AskodoxStory copyWith({List<String>? answers, Map<String, String>? chips, List<String>? picks}) =>
      AskodoxStory(answers: answers ?? this.answers, chips: chips ?? this.chips, picks: picks ?? this.picks);

  /// The question being asked now; null when all are answered.
  AskodoxStoryQuestion? get next => answers.length < askodoxStoryQuestions.length ? askodoxStoryQuestions[answers.length] : null;

  String get words => answers.join('. ');
}

/// A chip's text: the person's own words, with a short lead for supplier / bills / headache.
String askodoxStoryChipText(String key, String value, bool te) => switch (key) {
      'supplier' => te ? 'సప్లయర్: $value' : 'Supplier: $value',
      'bills' => te ? 'బిల్స్: $value' : 'Bills: $value',
      'problem' => te ? 'సమస్య: $value' : 'Problem: $value',
      _ => value,
    };

String askodoxStoryEncode(AskodoxStory s) => jsonEncode({'a': s.answers, 'c': s.chips, 'p': s.picks});

AskodoxStory askodoxStoryDecode(String? raw) {
  if (raw == null || raw.isEmpty) return const AskodoxStory();
  try {
    final m = jsonDecode(raw);
    if (m is! Map) return const AskodoxStory();
    final answers = [for (final a in (m['a'] is List ? m['a'] as List : const [])) '$a'.trim()]
        .where((a) => a.isNotEmpty)
        .take(askodoxStoryQuestions.length)
        .toList();
    final chips = <String, String>{};
    if (m['c'] is Map) {
      for (final k in askodoxStoryKeys) {
        final v = '${(m['c'] as Map)[k] ?? ''}'.trim();
        if (v.isNotEmpty && v.length <= 80) chips[k] = v;
      }
    }
    final known = {for (final k in askodoxStoryKinds) k.$1};
    final picks = [for (final p in (m['p'] is List ? m['p'] as List : const [])) '$p'].where(known.contains).toSet().toList();
    return AskodoxStory(answers: answers, chips: chips, picks: picks);
  } catch (_) {
    return const AskodoxStory();
  }
}

class AskodoxStoryController extends StateNotifier<AskodoxStory> {
  AskodoxStoryController() : super(const AskodoxStory()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) state = askodoxStoryDecode(prefs.getString(askodoxBusinessStoryPrefsKey));
    } catch (_) {}
  }

  Future<void> _put(AskodoxStory s) async {
    state = s;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(askodoxBusinessStoryPrefsKey, askodoxStoryEncode(s));
    } catch (_) {}
  }

  Future<void> answer(String text) {
    final t = text.trim();
    if (t.isEmpty || state.next == null) return Future.value();
    return _put(state.copyWith(answers: [...state.answers, t.length > 400 ? t.substring(0, 400) : t]));
  }

  Future<void> setChips(Map<String, String> chips) => _put(state.copyWith(chips: chips));

  Future<void> dropChip(String key) => _put(state.copyWith(chips: {...state.chips}..remove(key)));

  /// Tap a kind: picked -> not picked and back.
  Future<void> togglePick(String id) {
    final has = state.picks.contains(id);
    return _put(state.copyWith(picks: has ? [for (final p in state.picks) if (p != id) p] : [...state.picks, id]));
  }

  Future<void> startOver() => _put(const AskodoxStory());
}

final askodoxStoryProvider =
    StateNotifierProvider<AskodoxStoryController, AskodoxStory>((ref) => AskodoxStoryController());

class AskodoxBusinessStoryScreen extends ConsumerStatefulWidget {
  const AskodoxBusinessStoryScreen({super.key});

  @override
  ConsumerState<AskodoxBusinessStoryScreen> createState() => _AskodoxBusinessStoryScreenState();
}

class _AskodoxBusinessStoryScreenState extends ConsumerState<AskodoxBusinessStoryScreen> {
  final _typed = TextEditingController();
  bool _working = false;
  String _status = '';

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _heard(String words, bool te) async {
    final text = words.trim();
    if (text.isEmpty) return;
    final c = ref.read(askodoxStoryProvider.notifier);
    await c.answer(text);
    _typed.clear();
    final story = ref.read(askodoxStoryProvider);
    setState(() {
      _working = true;
      _status = te ? 'అర్థం చేసుకుంటున్నాను…' : 'Understanding…';
    });
    try {
      final labels = {
        'type': te ? 'బిజినెస్ రకం' : 'kind of business',
        'branches': te ? 'బ్రాంచ్‌ల సంఖ్య' : 'number of branches',
        'supplier': te ? 'సరుకు ఎక్కడి నుంచి' : 'where the stock comes from',
        'bills': te ? 'GST బిల్ ఇస్తారా' : 'whether GST bills are given',
        'problem': te ? 'పెద్ద సమస్య' : 'biggest problem',
      };
      final out = await ref.read(askodoxPosRepositoryProvider).formFill([
        for (final k in askodoxStoryKeys) {'key': k, 'label': labels[k], 'kind': 'text', 'options': <String>[]}
      ], story.words, locale: te ? 'te' : 'en');
      final values = askodoxPosMap(out['values']);
      final chips = <String, String>{
        for (final k in askodoxStoryKeys)
          if (values[k] != null && '${values[k]}'.trim().isNotEmpty && '${values[k]}'.trim().length <= 80) k: '${values[k]}'.trim(),
      };
      await c.setChips(chips);
      if (mounted) setState(() => _status = '');
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _status = e.message(te));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final story = ref.watch(askodoxStoryProvider);
    final next = story.next;
    return Scaffold(
      key: const Key('askodoxBusinessStory'),
      appBar: AppBar(
        title: Text(te ? 'మీ బిజినెస్ గురించి చెప్పండి' : 'Tell us about your business'),
        actions: [
          if (story.answers.isNotEmpty)
            IconButton(
              key: const Key('askodoxStoryRestart'),
              tooltip: te ? 'మళ్ళీ మొదలు' : 'Start over',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => ref.read(askodoxStoryProvider.notifier).startOver(),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          Text(te ? 'మీరు ఎవరు? ఏం చేస్తారు? (ఒకటి కంటే ఎక్కువ ఎంచుకోవచ్చు)' : 'Who are you? What do you do? (pick more than one)',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in askodoxStoryKinds)
              FilterChip(
                key: ValueKey('askodoxStoryKind-${k.$1}'),
                label: Text(te ? k.$3 : k.$2),
                selected: story.picks.contains(k.$1),
                onSelected: (_) => ref.read(askodoxStoryProvider.notifier).togglePick(k.$1),
              ),
          ]),
          const SizedBox(height: 6),
          Text(te ? 'మీ రకం ఇక్కడ కనిపించకపోతే కింద చెప్పండి. మీ అభ్యర్థన నోట్ చేసుకుంటాం, త్వరలోనే సంప్రదిస్తాం.' : 'If your kind is not here, tell us below. We note your request and will contact you soon.',
              key: const Key('askodoxStoryKindsNote'), style: const TextStyle(color: AskodoxLook.muted)),
          const Divider(height: 24),
          Text(te ? 'మాట్లాడితే చాలు · తెలుగులో' : 'Just speak · in your language', style: const TextStyle(color: AskodoxLook.muted)),
          const SizedBox(height: 10),
          for (var i = 0; i < askodoxStoryQuestions.length; i++) ...[
            if (i <= story.answers.length) _bubble(te ? askodoxStoryQuestions[i].te : askodoxStoryQuestions[i].en, false, 'q$i'),
            if (i < story.answers.length) _bubble(story.answers[i], true, 'a$i'),
          ],
          if (story.chips.isNotEmpty || story.answers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(te ? 'మేం అర్థం చేసుకున్నవి' : 'What we understood', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (story.chips.isEmpty)
                    Text(te ? 'మీ మాటల నుంచి ఇంకా ఏదీ తీసుకోలేదు.' : 'Nothing taken from your words yet.',
                        key: const Key('askodoxStoryNoChips'), style: const TextStyle(color: AskodoxLook.muted)),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final k in askodoxStoryKeys)
                      if (story.chips[k] != null)
                        InputChip(
                          key: ValueKey('askodoxStoryChip-$k'),
                          label: Text(askodoxStoryChipText(k, story.chips[k]!, te), style: const TextStyle(fontWeight: FontWeight.w700)),
                          onDeleted: () => ref.read(askodoxStoryProvider.notifier).dropChip(k),
                        ),
                  ]),
                ]),
              ),
            ),
          ],
          if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status, key: const Key('askodoxStoryStatus'))),
          const SizedBox(height: 16),
          if (next != null) ...[
            Center(
              child: _working
                  ? const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 2))
                  : AskodoxQuestionMic(
                      key: const Key('askodoxStoryMic'), lang: te ? 'te' : 'en', followCentre: false, always: true, onText: (w) => _heard(w, te)),
            ),
            const SizedBox(height: 8),
            Center(child: Text(te ? 'లేదా టైప్ చేయండి' : 'Or type', style: const TextStyle(color: AskodoxLook.muted))),
            TextField(
              key: const Key('askodoxStoryField'),
              controller: _typed,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (w) => _heard(w, te),
              decoration: InputDecoration(
                hintText: te ? 'మీ సమాధానం' : 'Your answer',
                suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _working ? null : () => _heard(_typed.text, te)),
              ),
            ),
          ] else ...[
            OutlinedButton(
              key: const Key('askodoxStorySolutions'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => context.push('/me/solutions'),
              child: Text(te ? 'సరిపోయే పరిష్కారాలు చూడండి' : 'See solutions that fit'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('askodoxStoryAsk'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () {
                final problem = story.chips['problem'] ?? story.answers.last;
                ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(
                    te ? 'నా బిజినెస్‌లో సమస్య: $problem. ఎలా పరిష్కరించాలి?' : 'My business problem: $problem. How do I solve it?');
                context.go('/');
              },
              child: Text(te ? 'ఈ సమస్యకు పరిష్కారం అడగండి' : 'Ask how to solve this'),
            ),
          ],
          const SizedBox(height: 12),
          Text(te ? 'ఈ సమాధానాలు ఈ ఫోన్‌లోనే ఉంటాయి. చిప్ తప్పయితే ✕ నొక్కి తీసేయండి.' : 'These answers stay on this phone. Tap ✕ on a wrong chip to remove it.',
              key: const Key('askodoxStoryPrivacy'), style: const TextStyle(color: AskodoxLook.muted)),
          const SizedBox(height: 8),
          const AskodoxEstimateNote(),
        ]),
      ),
    );
  }

  Widget _bubble(String text, bool mine, String id) => Align(
        key: ValueKey('askodoxStoryBubble-$id'),
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: mine ? AskodoxLook.accent : AskodoxLook.sheet,
            border: mine ? null : Border.all(color: AskodoxLook.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: mine ? AskodoxLook.onAccent : null)),
        ),
      );
}
