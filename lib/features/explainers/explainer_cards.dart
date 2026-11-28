import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme/askodox_look.dart';
import '../../shared/widgets/estimate_note.dart';
import '../business_story/business_story.dart';
import '../home/application/conversation_archive.dart' show AskodoxChatRequest, askodoxChatRequestProvider;
import '../money_home/money_home_store.dart';

/// Problem -> solution cards (owner 2026-11-27, "explainer models" for the Business Kit): one card names a common
/// trouble, then shows the steps ASKODOX gives to solve it, each step opening the page that does it. One engine for
/// every business and for homes: a card is DATA (words + a page), never a rule per category, and it holds no figures --
/// the person's own numbers go into the pages it opens.
class AskodoxExplainerStep {
  const AskodoxExplainerStep(this.en, this.te, this.route);
  final String en, te;

  /// A page of the app; `:id` is replaced by the person's shop.
  final String route;
}

class AskodoxExplainer {
  const AskodoxExplainer({
    required this.id,
    required this.titleEn,
    required this.titleTe,
    required this.problemEn,
    required this.problemTe,
    required this.steps,
    required this.words,
  });
  final String id, titleEn, titleTe, problemEn, problemTe;
  final List<AskodoxExplainerStep> steps;

  /// Words (lower case, any language) that say a person has this trouble.
  final List<String> words;
}

const askodoxExplainers = <AskodoxExplainer>[
  AskodoxExplainer(
    id: 'stock_leak',
    titleEn: 'Stock does not add up',
    titleTe: 'స్టాక్ లెక్క సరిపోకపోతే',
    problemEn: 'Goods come in, goods go out, and the count at night is not what you expected. Where it went is unclear.',
    problemTe: 'సరుకు వస్తుంది, అమ్ముడవుతుంది, కానీ రాత్రి లెక్క అనుకున్నట్లు ఉండదు. ఎక్కడ పోయిందో తెలియదు.',
    steps: [
      AskodoxExplainerStep('Note what you bought, what came out after cleaning, and the rate.', 'ఏం కొన్నారో, శుభ్రం చేశాక ఎంత వచ్చిందో, రేటు ఎంతో నోట్ చేయండి.', '/pos/:id/yield'),
      AskodoxExplainerStep('At closing, weigh what is left and save the day end.', 'మూసేటప్పుడు మిగిలింది తూచి డే ఎండ్ సేవ్ చేయండి.', '/pos/:id/yield'),
      AskodoxExplainerStep('Read the weekly report: the gaps show by day.', 'వారం రిపోర్ట్ చూడండి: ఏ రోజు తేడా వచ్చిందో కనిపిస్తుంది.', '/weekly'),
    ],
    words: ['stock', 'leak', 'loss', 'shortage', 'లీక్', 'స్టాక్', 'లెక్క', 'పోతు', 'తేడా'],
  ),
  AskodoxExplainer(
    id: 'cost_unknown',
    titleEn: 'Cost of one plate or piece is unknown',
    titleTe: 'ఒక ప్లేట్ / పీస్ ఖర్చు తెలియకపోతే',
    problemEn: 'You sell by the plate or piece but buy by weight, so the real cost behind a price is a guess.',
    problemTe: 'అమ్మేది ప్లేట్ / పీస్ లెక్కన, కొనేది తూకం లెక్కన. అందుకే ధర వెనుక అసలు ఖర్చు ఊహే.',
    steps: [
      AskodoxExplainerStep('Enter your buying rate and what you get after cleaning.', 'కొనే రేటు, శుభ్రం చేశాక వచ్చేది నమోదు చేయండి.', '/pos/:id/yield'),
      AskodoxExplainerStep('Add your own measure for one plate or piece. Use your own number.', 'ఒక ప్లేట్ / పీస్‌కి మీ సొంత కొలత వేయండి. మీ సొంత లెక్కే వాడండి.', '/pos/:id/yield'),
      AskodoxExplainerStep('See the cost per portion and set your price.', 'ఒక్కో దానికి ఖర్చు చూసి మీ ధర నిర్ణయించండి.', '/pos/:id/yield'),
    ],
    words: ['cost', 'plate', 'portion', 'recipe', 'ఖర్చు', 'ప్లేట్', 'రెసిపీ', 'కొలత'],
  ),
  AskodoxExplainer(
    id: 'bills_mixed',
    titleEn: 'Some bills have GST, some are hand slips',
    titleTe: 'కొన్ని బిల్లుల్లో GST, కొన్ని చేతి చీటీలు',
    problemEn: 'Supplier papers come as GST bills, hand slips and photos, and they get lost or mixed up.',
    problemTe: 'సప్లయర్ కాగితాలు GST బిల్లులు, చేతి చీటీలు, ఫోటోలుగా వస్తాయి; పోతాయి, కలిసిపోతాయి.',
    steps: [
      AskodoxExplainerStep('Photograph each bill and choose GST bill or no GST.', 'ప్రతి బిల్లు ఫోటో తీసి GST బిల్ / చేతి చీటీ ఎంచుకోండి.', '/pos/:id/purchase/new'),
      AskodoxExplainerStep('Check the rows it read, then save and add the next bill.', 'చదివిన వరుసలు సరిచూసి సేవ్ చేసి తర్వాతి బిల్ వేయండి.', '/pos/:id/purchase/new'),
    ],
    words: ['bill', 'gst', 'slip', 'invoice', 'బిల్', 'చీటీ', 'జీఎస్టీ'],
  ),
  AskodoxExplainer(
    id: 'money_stuck',
    titleEn: 'Money is stuck with customers',
    titleTe: 'కస్టమర్ల దగ్గర డబ్బు ఆగిపోతే',
    problemEn: 'Customers owe you, and following up every one takes your time.',
    problemTe: 'కస్టమర్లు ఇవ్వాల్సిన బాకీ ఉంది, ప్రతి ఒక్కరినీ అడగడానికి మీ సమయం పోతుంది.',
    steps: [
      AskodoxExplainerStep('Open the dues list and set a pay-by day for each.', 'బాకీల జాబితా తెరిచి ప్రతి ఒక్కరికి చెల్లించే రోజు పెట్టండి.', '/pos/:id/dues'),
      AskodoxExplainerStep('Send the reminder yourself on WhatsApp in one tap.', 'రిమైండర్ WhatsApp లో ఒక్క టచ్‌తో మీరే పంపండి.', '/pos/:id/dues'),
    ],
    words: ['baaki', 'due', 'credit', 'pending', 'బాకీ', 'అప్పు', 'రావాల్సిన', 'వసూలు'],
  ),
  AskodoxExplainer(
    id: 'forgot_close',
    titleEn: 'Forgetting the day-end count',
    titleTe: 'రోజు చివర లెక్క మర్చిపోతే',
    problemEn: 'At closing you are tired, and the stock count and cash check get skipped.',
    problemTe: 'మూసేటప్పుడు అలసట, స్టాక్ లెక్క, క్యాష్ చెక్ మిస్ అవుతాయి.',
    steps: [
      AskodoxExplainerStep('Set your own closing time. It asks you once at that time.', 'మీ సొంత మూసే సమయం పెట్టండి. ఆ సమయానికి ఒక్కసారి గుర్తు చేస్తుంది.', '/pos/:id/yield'),
      AskodoxExplainerStep('Save the day end with a photo of the stock.', 'స్టాక్ ఫోటోతో డే ఎండ్ సేవ్ చేయండి.', '/pos/:id/yield'),
    ],
    words: ['close', 'closing', 'forget', 'night', 'మర్చిపో', 'మూసే', 'క్లోజ్', 'రాత్రి'],
  ),
  AskodoxExplainer(
    id: 'prices_change',
    titleEn: 'Rates change and prices are slow to follow',
    titleTe: 'రేట్లు మారుతాయి, ధరలు వెంటనే మారవు',
    problemEn: 'Your buying rate moves, and updating item prices one by one is slow.',
    problemTe: 'కొనే రేటు మారుతుంది, ఒక్కో వస్తువు ధర మార్చడం నెమ్మది.',
    steps: [
      AskodoxExplainerStep('Change many prices together and check the preview first.', 'చాలా ధరలు కలిపి మార్చండి, ముందు ప్రివ్యూ చూడండి.', '/pos/:id/prices'),
    ],
    words: ['price', 'rate', 'rates', 'ధర', 'రేటు', 'రేట్లు'],
  ),
  AskodoxExplainer(
    id: 'members_end',
    titleEn: 'Members forget to renew',
    titleTe: 'సభ్యులు రెన్యూ చేయడం మర్చిపోతే',
    problemEn: 'Monthly members, a gym, a class: ending dates pass and nobody follows up.',
    problemTe: 'నెలవారీ సభ్యులు, జిమ్, క్లాస్: ముగిసే తేదీలు దాటిపోతాయి, ఎవరూ అడగరు.',
    steps: [
      AskodoxExplainerStep('Add members with term and fee. The end day is worked out.', 'సభ్యులను కాలం, ఫీజుతో చేర్చండి. ముగిసే రోజు లెక్కవుతుంది.', '/biz/:id/members'),
      AskodoxExplainerStep('See who is ending soon and send the reminder yourself.', 'ఎవరు త్వరలో ముగుస్తున్నారో చూసి రిమైండర్ మీరే పంపండి.', '/biz/:id/members'),
    ],
    words: ['member', 'renew', 'gym', 'class', 'fee', 'సభ్య', 'రెన్యూ', 'జిమ్', 'ఫీజు'],
  ),
  AskodoxExplainer(
    id: 'home_papers',
    titleEn: 'Warranty papers get lost at home',
    titleTe: 'ఇంట్లో వారంటీ కాగితాలు పోతుంటే',
    problemEn: 'A mixer breaks and the bill is nowhere to be found, or the warranty ended last week.',
    problemTe: 'మిక్సీ చెడిపోతే బిల్ దొరకదు, లేదా వారంటీ గత వారమే ముగిసింది.',
    steps: [
      AskodoxExplainerStep('Photograph the bill. You check what it read before it is kept.', 'బిల్ ఫోటో తీయండి. ఉంచే ముందు చదివింది మీరు సరిచూస్తారు.', '/me/vault?photo=camera'),
      AskodoxExplainerStep('It tells you before a warranty ends.', 'వారంటీ ముగిసే ముందు చెబుతుంది.', '/me/home'),
    ],
    words: ['warranty', 'mixer', 'home', 'papers', 'వారంటీ', 'ఇల్లు', 'ఇంట్లో', 'కాగితా'],
  ),
];

/// The cards that fit what the person said, best first (a word counts once). None fit -> empty.
List<AskodoxExplainer> askodoxExplainersFor(String said) {
  final text = said.toLowerCase();
  final scored = <MapEntry<AskodoxExplainer, int>>[];
  for (final e in askodoxExplainers) {
    final hits = e.words.where(text.contains).length;
    if (hits > 0) scored.add(MapEntry(e, hits));
  }
  scored.sort((a, b) => b.value.compareTo(a.value));
  return [for (final s in scored) s.key];
}

/// A step's page for [shopId]; null when it needs a shop and none is known.
String? askodoxExplainerRoute(String route, String? shopId) {
  if (!route.contains(':id')) return route;
  if (shopId == null || shopId.isEmpty) return null;
  return route.replaceAll(':id', shopId);
}

const askodoxContactPrefKey = 'askodox.contactpref.v1';

/// How the person wants to be reached about a request that is noted: whatsapp / call / app ('' = not chosen). Phone only.
final askodoxContactPrefProvider = StateNotifierProvider<AskodoxContactPref, String>((ref) => AskodoxContactPref());

class AskodoxContactPref extends StateNotifier<String> {
  AskodoxContactPref() : super('') {
    _load();
  }

  Future<void> _load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(askodoxContactPrefKey) ?? '';
      if (mounted && const ['whatsapp', 'call', 'app'].contains(v)) state = v;
    } catch (_) {}
  }

  Future<void> choose(String v) async {
    if (!const ['whatsapp', 'call', 'app'].contains(v)) return;
    state = v;
    try {
      await (await SharedPreferences.getInstance()).setString(askodoxContactPrefKey, v);
    } catch (_) {}
  }
}

/// "Solutions for my trouble": the cards that fit what the person told about the business first, then all of them.
class AskodoxExplainersScreen extends ConsumerWidget {
  const AskodoxExplainersScreen({super.key, this.only = ''});

  /// A card id to open straight away.
  final String only;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final story = ref.watch(askodoxStoryProvider);
    final fit = askodoxExplainersFor('${story.chips['problem'] ?? ''} ${story.answers.join(' ')}');
    final rest = [for (final e in askodoxExplainers) if (!fit.contains(e)) e];
    final shops = ref.watch(askodoxMyShopsProvider).valueOrNull ?? const [];
    final picked = askodoxPickShop(shops, ref.watch(askodoxMoneyShopProvider));
    final shopId = picked == null ? null : '${picked['id']}';
    return Scaffold(
      key: const Key('askodoxExplainers'),
      appBar: AppBar(title: Text(te ? 'సమస్య → పరిష్కారం' : 'Problem → solution')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          if (fit.isNotEmpty) ...[
            Text(te ? 'మీరు చెప్పిన దానికి సరిపోయేవి' : 'Fits what you told us', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final e in fit) _card(context, ref, e, te, shopId, open: e.id == only || e == fit.first),
            const SizedBox(height: 10),
          ],
          Text(te ? 'అన్ని పరిష్కారాలు' : 'All solutions', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final e in rest) _card(context, ref, e, te, shopId, open: e.id == only),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('askodoxExplainersMine'),
            onPressed: () {
              ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(te
                  ? 'నా బిజినెస్‌లో వేరే సమస్య ఉంది. దానికి దారి చెప్పండి.'
                  : 'I have a different business problem. Please guide me.');
              context.go('/');
            },
            child: Text(te ? 'నా సమస్య వేరే. అడగండి' : 'My trouble is different. Ask'),
          ),
          const SizedBox(height: 6),
          Text(
              te
                  ? 'మీ అభ్యర్థన నోట్ చేసుకుంటాం, త్వరలోనే మిమ్మల్ని సంప్రదిస్తాం, అప్‌డేట్ చేసి ఇస్తాం.'
                  : 'We note your request, will get back to you soon and update the app for it.',
              style: const TextStyle(color: AskodoxLook.muted)),
          const SizedBox(height: 8),
          Text(te ? 'మిమ్మల్ని ఎలా సంప్రదించాలి?' : 'How should we reach you?', style: const TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            for (final c in [('whatsapp', 'WhatsApp', 'WhatsApp'), ('call', 'Phone call', 'ఫోన్ కాల్'), ('app', 'In the app', 'యాప్‌లో')])
              ChoiceChip(
                key: ValueKey('askodoxContact-${c.$1}'),
                label: Text(te ? c.$3 : c.$2),
                selected: ref.watch(askodoxContactPrefProvider) == c.$1,
                onSelected: (_) => ref.read(askodoxContactPrefProvider.notifier).choose(c.$1),
              ),
          ]),
          const SizedBox(height: 8),
          const AskodoxEstimateNote(),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, AskodoxExplainer e, bool te, String? shopId, {required bool open}) => Card(
        key: ValueKey('askodoxExplainer-${e.id}'),
        child: ExpansionTile(
          initiallyExpanded: open,
          title: Text(te ? e.titleTe : e.titleEn, style: const TextStyle(fontWeight: FontWeight.w800)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(te ? e.problemTe : e.problemEn, style: const TextStyle(color: AskodoxLook.muted)),
            const SizedBox(height: 8),
            for (var i = 0; i < e.steps.length; i++) _step(context, e, i, te, shopId),
          ],
        ),
      );

  Widget _step(BuildContext context, AskodoxExplainer e, int i, bool te, String? shopId) {
    final s = e.steps[i];
    final route = askodoxExplainerRoute(s.route, shopId);
    return ListTile(
      key: ValueKey('askodoxExplainerStep-${e.id}-$i'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(radius: 13, child: Text('${i + 1}')),
      title: Text(te ? s.te : s.en),
      trailing: route == null ? null : const Icon(Icons.chevron_right),
      subtitle: route == null ? Text(te ? 'ముందు మీ షాప్ సెటప్ చేయండి' : 'Set up your shop first') : null,
      onTap: route == null ? null : () => context.push(route),
    );
  }
}
